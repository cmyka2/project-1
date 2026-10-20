-- Data-driven progression extras: collection milestones, quests, the 7-day daily cycle, timed events, cosmetics.
-- Everything here is granted by the server only (ProgressService); clients read it for display.
local C = Color3.fromRGB
local P = {}

-- MILESTONES (each awarded once). unique = distinct monster+variant discoveries; set = every monster of a rarity.
-- effects stack through Game.stat like skill nodes.
P.Milestones = {
	{ id = "unique10", name = "10 unique discoveries", unique = 10, cash = 25000 },
	{ id = "unique25", name = "25 unique discoveries", unique = 25, effects = { storage = 25 } },
	{ id = "unique50", name = "50 unique discoveries", unique = 50, effects = { luck = 0.02 } },
	{ id = "unique100", name = "100 unique discoveries", unique = 100, cosmetic = "title_collector" },
	{ id = "set_common", name = "Complete the Commons", set = "Common", cosmetic = "aura_meadow" },
	{ id = "set_mythic", name = "Complete the Mythics", set = "Mythic", cosmetic = "aura_solar" },
	{ id = "set_glitched", name = "Complete the Glitched", set = "Glitched", cosmetic = "aura_glitch" },
}

-- QUESTS: a chain; the first 3 not yet completed are active and auto-complete from server counters.
-- stat: rolls | discoveries | placed | earned | upgrades | chests | wins | bosses | fusions | rebirths
-- reward: cash, gems, gear (rarity), mats
local function q(id, text, stat, target, reward) return { id = id, text = text, stat = stat, target = target, reward = reward } end
P.Quests = {
	q("roll10", "Roll 10 times", "rolls", 10, { cash = 500 }),
	q("discover5", "Discover 5 monsters", "discoveries", 5, { cash = 1000 }),
	q("place3", "Place 3 monsters on your base", "placed", 3, { cash = 1500 }),
	q("upgrade1", "Upgrade a monster", "upgrades", 1, { gems = 5, cash = 2000 }),
	q("earn10k", "Earn $10k in total", "earned", 10e3, { cash = 2500 }),
	q("chest1", "Open a chest", "chests", 1, { gems = 5, mats = { forest_essence = 3 } }),
	q("win1", "Win a battle", "wins", 1, { gems = 10, gear = "Uncommon" }),
	q("roll100", "Roll 100 times", "rolls", 100, { cash = 20000 }),
	q("boss1", "Defeat a boss", "bosses", 1, { gems = 15, gear = "Rare" }),
	q("fuse1", "Fuse a duplicate", "fusions", 1, { gems = 10, cash = 50000 }),
	q("rebirth1", "Perform a rebirth", "rebirths", 1, { gems = 20, gear = "Epic" }),
	q("discover25", "Discover 25 monsters", "discoveries", 25, { mats = { desert_relic = 5 } }),
	q("earn10m", "Earn $10m in total", "earned", 10e6, { cash = 1e6 }),
	q("win25", "Win 25 battles", "wins", 25, { gems = 30, gear = "Legendary" }),
	q("rebirth6", "Reach your second floor (6 rebirths)", "rebirths", 6, { gems = 50, gear = "Mythic" }),
}

-- DAILY: 7-day cycle on UTC days; missing a day restarts at day 1. cashSecs = seconds of current income (min cash).
P.Daily = {
	{ text = "Cash + 5 Gems", cashSecs = 600, cash = 2000, gems = 5 },
	{ text = "Chest + 5 Gems", chest = true, gems = 5 },
	{ text = "Materials + 10 Gems", mats = { forest_essence = 5, desert_relic = 2 }, gems = 10 },
	{ text = "2x Luck (15 min) + 10 Lucky Rolls", boost = { effect = "luck", mult = 2, secs = 900 }, luckyRolls = 10 },
	{ text = "Rare Gear + 15 Gems", gear = "Rare", gems = 15 },
	{ text = "Epic Gear + 15 Gems", gear = "Epic", gems = 15 },
	{ text = "Weekly title + Legendary Gear + 50 Gems", gear = "Legendary", cosmetic = "title_weekly", gems = 50 },
}

-- EVENTS: active by date window (UTC unix) or by weekday (os.date("!*t").wday: 1 = Sunday, 7 = Saturday),
-- optionally limited to some UTC hours.
-- effects multiply income/luck in the temporary bracket (never applied to offline earnings).
P.Events = {
	{ id = "weekend_income", name = "Weekend Double Income", weekdays = { 1, 7 }, effects = { income = 2 } },
	-- a weekly scheduled luck hour (the genre's "admin abuse" slot): Saturdays 18:00-19:00 UTC
	{ id = "lucky_hour", name = "Lucky Hour: 3x Luck", weekdays = { 7 }, hours = { 18 }, effects = { luck = 3 } },
	{ id = "halloween_hunt", name = "Halloween Hunt: 1.5x Luck", from = 1792800000, to = 1793577600, effects = { luck = 1.5 } }, -- 2026-10-24 .. 2026-11-02
}
P.EventById = {}
for _, e in P.Events do P.EventById[e.id] = e end
function P.activeEvents(now: number, forced: { [string]: number }?)
	local t = os.date("!*t", now)
	local out, wday = {}, t.wday
	for _, e in P.Events do
		local on = (e.from and now >= e.from and now < e.to)
			or (e.weekdays and table.find(e.weekdays, wday) ~= nil and (not e.hours or table.find(e.hours, t.hour) ~= nil))
		if on or (forced and forced[e.id] and forced[e.id] > now) then table.insert(out, e) end
	end
	return out
end
function P.eventMult(events, effect: string): number
	local m = 1
	for _, e in events do m *= e.effects[effect] or 1 end
	return m
end

-- BIOMES: server-wide weather (Sol's RNG / Grow a Garden style). Every BIOME_EVERY seconds there's a BIOME_CHANCE
-- one starts for secs; monsters of its element get mult x roll weight (still normalized, shown in the Index).
-- weight = how often it is picked relative to the others.
P.BIOME_EVERY, P.BIOME_CHANCE = 420, 0.6
P.Biomes = {
	{ id = "rainy", name = "Rainy", icon = "🌧️", element = "Water", mult = 3, secs = 180, weight = 1, tint = C(160, 190, 255) },
	{ id = "heatwave", name = "Heatwave", icon = "🔥", element = "Fire", mult = 3, secs = 180, weight = 1, tint = C(255, 190, 150) },
	{ id = "thunderstorm", name = "Thunderstorm", icon = "⛈️", element = "Lightning", mult = 3, secs = 150, weight = 1, tint = C(175, 175, 225) },
	{ id = "bloom", name = "Bloom", icon = "🌸", element = "Nature", mult = 3, secs = 180, weight = 1, tint = C(210, 255, 200) },
	{ id = "sandstorm", name = "Sandstorm", icon = "🌪️", element = "Earth", mult = 3, secs = 150, weight = 1, tint = C(240, 215, 160) },
	{ id = "aurora", name = "Aurora", icon = "🌌", element = "Light", mult = 4, secs = 120, weight = 0.5, tint = C(205, 255, 240) },
	{ id = "blood_moon", name = "Blood Moon", icon = "🌑", element = "Shadow", mult = 5, secs = 120, weight = 0.3, tint = C(255, 130, 130) },
	{ id = "starfall", name = "Starfall", icon = "🌠", element = "Cosmic", mult = 5, secs = 120, weight = 0.3, tint = C(195, 175, 255) },
}
P.BiomeById = {}
for _, b in P.Biomes do P.BiomeById[b.id] = b end

-- CODES: each redeemable once per player, case-insensitive. expires = unix time (nil = never).
-- reward keys: cash, gems, luckyRolls, boost { effect, mult, secs }, mats, gear
P.Codes = {
	{ code = "RELEASE", reward = { luckyRolls = 10, cash = 1000, gems = 20 } },
	{ code = "LUCKY", reward = { luckyRolls = 25 } },
	{ code = "SPOOKY", reward = { boost = { effect = "luck", mult = 2, secs = 900 } }, expires = 1793577600 },
}
P.CodeByName = {}
for _, c in P.Codes do P.CodeByName[c.code:upper()] = c end

-- COSMETICS: titles (above your head) and auras (particles). Never affect gameplay.
-- cash = buy price; paid = sold for Robux via gamepass / product id (nil id = not on sale yet). Paid items are
-- fixed, never randomized. Earned ones (milestones, daily) have neither.
P.Cosmetics = {
	{ id = "title_rookie", kind = "title", name = "Rookie Roller", cash = 10e3, color = C(200, 200, 200) },
	{ id = "title_tamer", kind = "title", name = "Monster Tamer", cash = 1e6, color = C(90, 220, 90) },
	{ id = "title_mythic", kind = "title", name = "Mythic Hunter", cash = 1e9, color = C(255, 60, 90) },
	{ id = "title_collector", kind = "title", name = "Master Collector", color = C(255, 200, 60) },
	{ id = "title_weekly", kind = "title", name = "Weekly Champion", color = C(120, 230, 255) },
	{ id = "title_vip", kind = "title", name = "VIP", color = C(255, 215, 0) }, -- comes with the VIP gamepass
	{ id = "aura_ember", kind = "aura", name = "Ember Aura", cash = 100e6, color = C(255, 120, 40) },
	{ id = "aura_meadow", kind = "aura", name = "Meadow Aura", color = C(90, 220, 90) },
	{ id = "aura_solar", kind = "aura", name = "Solar Aura", color = C(255, 230, 120) },
	{ id = "aura_glitch", kind = "aura", name = "Glitch Aura", color = C(0, 255, 120) },
	{ id = "aura_supporter", kind = "aura", name = "Supporter Aura", paid = true, product = nil, color = C(255, 120, 255) },
}
P.CosmeticById = {}
for _, c in P.Cosmetics do P.CosmeticById[c.id] = c end

-- the UTC day number used for daily rewards
function P.day(now: number): number return now // 86400 end
-- next daily state if claimed now, or nil if already claimed today
function P.nextDaily(daily, now: number)
	local today = P.day(now)
	if daily.last == today then return nil end
	local day = (daily.last == today - 1 and daily.day % #P.Daily or 0) + 1
	return { day = day, last = today }
end
return P
