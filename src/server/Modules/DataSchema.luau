--!strict
-- Player profile schema (pure, unit-tested): defaults for new players,
-- versioned migrations, and sanitization that repairs invalid or tampered
-- values without discarding valid progress.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local GameConfig = require(Config:WaitForChild("GameConfig"))
local EconomyConfig = require(Config:WaitForChild("EconomyConfig"))
local MonsterConfig = require(Config:WaitForChild("MonsterConfig"))
local RegionConfig = require(Config:WaitForChild("RegionConfig"))
local EquipmentConfig = require(Config:WaitForChild("EquipmentConfig"))
local SkillTreeConfig = require(Config:WaitForChild("SkillTreeConfig"))
local RebirthConfig = require(Config:WaitForChild("RebirthConfig"))
local CraftingConfig = require(Config:WaitForChild("CraftingConfig"))
local ChestConfig = require(Config:WaitForChild("ChestConfig"))
local QuestConfig = require(Config:WaitForChild("QuestConfig"))
local RarityConfig = require(Config:WaitForChild("RarityConfig"))
local CombatConfig = require(Config:WaitForChild("CombatConfig"))
local BaseLayout = require(Shared:WaitForChild("Util"):WaitForChild("BaseLayout"))
local TimeUtil = require(Shared:WaitForChild("Util"):WaitForChild("TimeUtil"))
local Types = require(Shared:WaitForChild("Types"))

type Profile = Types.Profile

local DataSchema = {}

DataSchema.CURRENT_VERSION = GameConfig.Data.SchemaVersion

function DataSchema.default(now: number): Profile
	return {
		SchemaVersion = DataSchema.CURRENT_VERSION,
		Currencies = {
			Coins = EconomyConfig.StartingCoins,
			Gems = EconomyConfig.StartingGems,
			AscensionPoints = 0,
			EventTokens = 0,
			Materials = {},
		},
		Progression = {
			RebirthCount = 0,
			AscensionUpgrades = {},
			UnlockedRegions = { [RegionConfig.StartingRegion] = true },
			HighestRegion = RegionConfig.StartingRegion,
			BossesDefeated = {},
			EncounterClears = {},
			EncounterCooldowns = {},
			LastRespec = 0,
		},
		Inventory = {
			Monsters = {},
			Equipment = {},
			Consumables = {},
			Chests = {},
			NextId = 1,
		},
		Base = {
			PlacedMonsters = {},
			UnlockedFloors = 1,
			CosmeticUpgrades = {},
			EquippedCosmetics = {},
			PlotPreferences = { ShowIncomeLabels = true },
		},
		Skills = { Nodes = {}, GemsSpent = 0 },
		Battle = {
			Team = {},
			Loadouts = {},
			BattleRating = CombatConfig.ArenaStartingRating,
			ArenaWins = 0,
			ArenaLosses = 0,
		},
		Discovery = {
			DiscoveredMonsters = {},
			TotalRolls = 0,
			RareDiscoveries = {},
			HighestRarityTier = 0,
			ClaimedMilestones = {},
			RollCounts = {},
		},
		Quests = {
			MainIndex = 1,
			MainProgress = 0,
			DailyKey = -1,
			Daily = {},
			WeeklyKey = -1,
			Weekly = {},
			Region = {},
			Event = {},
			Completed = {},
		},
		Achievements = { Completed = {}, Claimed = {} },
		DailyRewards = { LastClaimDay = -1, CurrentStreak = 0, TotalClaims = 0 },
		Statistics = {
			LifetimeCoinsEarned = 0,
			BattlesWon = 0,
			BattlesLost = 0,
			MonstersSold = 0,
			BossesDefeated = 0,
			MonstersFused = 0,
			ItemsCrafted = 0,
			ChestsOpened = 0,
			PlayTimeSeconds = 0,
			HighestMonsterLevel = 1,
		},
		Timestamps = { FirstJoin = now, LastSeen = now, LastSaved = 0, LastFreeRoll = 0 },
		Boosts = {},
		Crafting = { Queue = {}, NextJob = 1 },
		Tutorial = { Step = 1, Completed = false, Skipped = false },
		Settings = {
			MusicVolume = 0.5,
			SfxVolume = 0.7,
			SkipRollAnimation = false,
			AutoSell = {},
			ShowIncomeLabels = true,
			ReducedEffects = false,
		},
		Exploration = { CacheClaims = {} },
		Purchases = { Receipts = {}, GamePasses = {} },
	}
end

-- Migrations ------------------------------------------------------------------
-- Each step upgrades data from version N to N+1. Never edit a released step.
local MIGRATIONS: { [number]: (any) -> any } = {
	-- v1 (original spec layout) -> v2: daily reward timestamps become UTC day
	-- indices; quest bookkeeping moves to the category layout.
	[1] = function(data: any): any
		local daily = data.DailyRewards
		if typeof(daily) == "table" then
			local ts = daily.LastClaimTimestamp
			daily.LastClaimDay = if typeof(ts) == "number" and ts > 0 then TimeUtil.dayIndex(ts) else -1
			daily.LastClaimTimestamp = nil
		end
		local quests = data.Quests
		if typeof(quests) == "table" then
			local completed = {}
			if typeof(quests.Completed) == "table" then
				for k, v in quests.Completed do
					if typeof(k) == "string" and v then
						completed[k] = true
					elseif typeof(v) == "string" then
						completed[v] = true
					end
				end
			end
			data.Quests = { Completed = completed }
		end
		return data
	end,
	-- v2 -> v3: achievements become { Completed, Claimed }; dice roll counters added.
	[2] = function(data: any): any
		local ach = data.Achievements
		if typeof(ach) == "table" and ach.Completed == nil then
			local completed, claimed = {}, {}
			for id, value in ach do
				if typeof(id) == "string" and value then
					completed[id] = if typeof(value) == "number" then value else 0
					claimed[id] = true -- old achievements were auto-claimed
				end
			end
			data.Achievements = { Completed = completed, Claimed = claimed }
		end
		if typeof(data.Discovery) == "table" and data.Discovery.RollCounts == nil then
			data.Discovery.RollCounts = {}
		end
		return data
	end,
}

function DataSchema.migrate(data: any): any
	local version = if typeof(data.SchemaVersion) == "number" then data.SchemaVersion else 1
	if version > DataSchema.CURRENT_VERSION then
		error(
			string.format(
				"profile schema v%d is newer than this server (v%d)",
				version,
				DataSchema.CURRENT_VERSION
			)
		)
	end
	while version < DataSchema.CURRENT_VERSION do
		local step = MIGRATIONS[version]
		if not step then
			error("missing migration from v" .. version)
		end
		data = step(data)
		version += 1
		data.SchemaVersion = version
	end
	return data
end

-- Sanitization -------------------------------------------------------------------

local function num(value: any, default: number, min: number?, max: number?): number
	if typeof(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return default
	end
	local v = value :: number
	if min and v < min then
		v = min
	end
	if max and v > max then
		v = max
	end
	return v
end

local function int(value: any, default: number, min: number?, max: number?): number
	return math.floor(num(value, default, min, max))
end

local function bool(value: any, default: boolean): boolean
	if typeof(value) == "boolean" then
		return value
	end
	return default
end

local function str(value: any, default: string): string
	if typeof(value) == "string" and #value <= 200 then
		return value
	end
	return default
end

local function tbl(value: any): { [any]: any }
	if typeof(value) == "table" then
		return value
	end
	return {}
end

-- Fills missing fields from defaults (recursively for plain records) without
-- touching existing valid values.
local function reconcile(target: { [any]: any }, defaults: { [any]: any })
	for key, defaultValue in defaults do
		local current = target[key]
		if typeof(defaultValue) == "table" and current ~= nil and typeof(current) ~= "table" then
			-- a section of the wrong type (corruption/tampering) is reset to defaults
			current = nil
		end
		if current == nil then
			if typeof(defaultValue) == "table" then
				target[key] = table.clone(defaultValue)
				reconcile(target[key], defaultValue)
			else
				target[key] = defaultValue
			end
		elseif
			typeof(defaultValue) == "table"
			and typeof(current) == "table"
			and next(defaultValue) ~= nil
		then
			-- only recurse into fixed-shape records, not dictionaries keyed by ids
			local isRecord = true
			for k in defaultValue do
				if typeof(k) ~= "string" then
					isRecord = false
				end
			end
			if isRecord then
				reconcile(current, defaultValue)
			end
		end
	end
end

local function numberMap(
	value: any,
	validKey: (string) -> boolean,
	min: number,
	max: number,
	integer: boolean,
	keepZero: boolean?
): { [string]: number }
	local out: { [string]: number } = {}
	for k, v in tbl(value) do
		if typeof(k) == "string" and validKey(k) then
			local n = if integer then int(v, 0, min, max) else num(v, 0, min, max)
			if n ~= 0 or keepZero then
				out[k] = n
			end
		end
	end
	return out
end

local function boolMap(value: any, validKey: (string) -> boolean): { [string]: boolean }
	local out: { [string]: boolean } = {}
	for k, v in tbl(value) do
		if typeof(k) == "string" and validKey(k) and v == true then
			out[k] = true
		end
	end
	return out
end

local function anyKey(_: string): boolean
	return true
end

local function questList(value: any): { Types.QuestProgress }
	local out: { Types.QuestProgress } = {}
	for _, q in tbl(value) do
		if typeof(q) == "table" and typeof(q.Id) == "string" and QuestConfig.Quests[q.Id] then
			table.insert(out, {
				Id = q.Id,
				Progress = num(q.Progress, 0, 0, 1e30),
				Completed = bool(q.Completed, false),
				Claimed = bool(q.Claimed, false),
			})
		end
	end
	return out
end

local function questMap(value: any): { [string]: Types.QuestProgress }
	local out: { [string]: Types.QuestProgress } = {}
	for k, q in tbl(value) do
		if typeof(k) == "string" and QuestConfig.Quests[k] and typeof(q) == "table" then
			out[k] = {
				Id = k,
				Progress = num(q.Progress, 0, 0, 1e30),
				Completed = bool(q.Completed, false),
				Claimed = bool(q.Claimed, false),
			}
		end
	end
	return out
end

-- Returns (profile, issues). `issues` lists every repair made, for logging.
function DataSchema.sanitize(raw: any, now: number): (Profile, { string })
	local issues: { string } = {}
	local function issue(text: string)
		if #issues < 50 then
			table.insert(issues, text)
		end
	end
	local d: any = if typeof(raw) == "table" then raw else {}
	local defaults = DataSchema.default(now)
	reconcile(d, defaults :: any)

	local maxCurrency = EconomyConfig.MaxCurrency
	local c = d.Currencies
	c.Coins = num(c.Coins, 0, 0, maxCurrency)
	c.Gems = int(c.Gems, 0, 0, maxCurrency)
	c.AscensionPoints = int(c.AscensionPoints, 0, 0, 1e9)
	c.EventTokens = int(c.EventTokens, 0, 0, 1e9)
	c.Materials = numberMap(c.Materials, function(k)
		return CraftingConfig.Materials[k] ~= nil
	end, 0, 1e12, true)

	local p = d.Progression
	p.RebirthCount = int(p.RebirthCount, 0, 0, RebirthConfig.MaxRebirths)
	p.AscensionUpgrades = numberMap(p.AscensionUpgrades, function(k)
		return RebirthConfig.AscensionNodes[k] ~= nil
	end, 0, 100, true)
	for id, level in p.AscensionUpgrades do
		local node = RebirthConfig.AscensionNodes[id]
		if level > node.MaxLevel then
			issue("ascension level clamped " .. id)
			p.AscensionUpgrades[id] = node.MaxLevel
		end
	end
	p.UnlockedRegions = boolMap(p.UnlockedRegions, function(k)
		return RegionConfig.Regions[k] ~= nil
	end)
	p.UnlockedRegions[RegionConfig.StartingRegion] = true
	local highest = RegionConfig.StartingRegion
	for regionId in p.UnlockedRegions do
		if RegionConfig.indexOf(regionId) > RegionConfig.indexOf(highest) then
			highest = regionId
		end
	end
	p.HighestRegion = highest
	p.BossesDefeated = numberMap(p.BossesDefeated, function(k)
		return RegionConfig.Regions[k] ~= nil
	end, 0, 1e9, true)
	p.EncounterClears = numberMap(p.EncounterClears, anyKey, 0, 1e9, true)
	p.EncounterCooldowns = numberMap(p.EncounterCooldowns, anyKey, 0, now + 86400, false)
	p.LastRespec = num(p.LastRespec, 0, 0, now)

	-- Inventory: monsters
	local inv = d.Inventory
	local monsters: { [string]: Types.MonsterInstance } = {}
	local maxNumericId = 0
	for key, m in tbl(inv.Monsters) do
		if typeof(key) == "string" and typeof(m) == "table" and typeof(m.MonsterId) == "string" then
			local def = MonsterConfig.Monsters[m.MonsterId]
			if not def then
				issue("unknown monster dropped " .. tostring(m.MonsterId))
			else
				local rarity = RarityConfig.Rarities[def.Rarity]
				monsters[key] = {
					Id = key,
					MonsterId = m.MonsterId,
					Level = int(m.Level, 1, 1, CombatConfig.MaxMonsterLevel),
					Xp = num(m.Xp, 0, 0, 1e15),
					Upgrade = int(m.Upgrade, 0, 0, rarity.MaxUpgradeLevel),
					Stars = int(m.Stars, 0, 0, EconomyConfig.MaxStars),
					Locked = bool(m.Locked, false),
					Favorite = bool(m.Favorite, false),
					Source = str(m.Source, "Unknown"),
					Acquired = num(m.Acquired, now, 0, now + 60),
					Variant = if typeof(m.Variant) == "string" then m.Variant else nil,
					EvolvedFrom = if typeof(m.EvolvedFrom) == "string" then m.EvolvedFrom else nil,
				}
				local n = tonumber(string.match(key, "^m(%d+)$"))
				if n and n > maxNumericId then
					maxNumericId = n
				end
			end
		end
	end
	inv.Monsters = monsters

	local equipment: { [string]: Types.EquipmentInstance } = {}
	for key, e in tbl(inv.Equipment) do
		if typeof(key) == "string" and typeof(e) == "table" and typeof(e.ItemId) == "string" then
			local def = EquipmentConfig.Items[e.ItemId]
			if def then
				local maxLevel = EquipmentConfig.MaxLevelBase + RarityConfig.tierOf(def.Rarity)
				local equippedTo = if typeof(e.EquippedTo) == "string" and monsters[e.EquippedTo]
					then e.EquippedTo
					else nil
				equipment[key] = {
					Id = key,
					ItemId = e.ItemId,
					Level = int(e.Level, 0, 0, maxLevel),
					EquippedTo = equippedTo,
					Locked = bool(e.Locked, false),
				}
				local n = tonumber(string.match(key, "^e(%d+)$"))
				if n and n > maxNumericId then
					maxNumericId = n
				end
			else
				issue("unknown equipment dropped " .. tostring(e.ItemId))
			end
		end
	end
	-- one item per category per monster
	local slotTaken: { [string]: boolean } = {}
	local equipmentKeys: { string } = {}
	for k in equipment do
		table.insert(equipmentKeys, k)
	end
	table.sort(equipmentKeys)
	for _, key in equipmentKeys do
		local item = equipment[key]
		if item.EquippedTo then
			local category = EquipmentConfig.Items[item.ItemId].Category
			local slotKey = item.EquippedTo .. ":" .. category
			if slotTaken[slotKey] then
				issue("duplicate equipped slot fixed " .. key)
				item.EquippedTo = nil
			else
				slotTaken[slotKey] = true
			end
		end
	end
	inv.Equipment = equipment
	inv.Consumables = numberMap(inv.Consumables, function(k)
		return CraftingConfig.Consumables[k] ~= nil
	end, 0, 1e6, true)
	inv.Chests = numberMap(inv.Chests, function(k)
		return ChestConfig.Chests[k] ~= nil
	end, 0, 1e6, true)
	inv.NextId = math.max(int(inv.NextId, 1, 1, 1e12), maxNumericId + 1)

	-- Base placements: valid slot, existing monster, no monster placed twice
	local base = d.Base
	local placed: { [string]: string } = {}
	local used: { [string]: boolean } = {}
	for slotKey, instanceId in tbl(base.PlacedMonsters) do
		local slotId = tonumber(slotKey)
		if
			slotId
			and BaseLayout.isValidSlot(slotId, p.RebirthCount)
			and typeof(instanceId) == "string"
			and monsters[instanceId]
			and not used[instanceId]
		then
			placed[tostring(math.floor(slotId))] = instanceId
			used[instanceId] = true
		else
			issue("invalid placement removed " .. tostring(slotKey))
		end
	end
	base.PlacedMonsters = placed
	base.UnlockedFloors = BaseLayout.floorCount(p.RebirthCount)
	base.CosmeticUpgrades = boolMap(base.CosmeticUpgrades, function(k)
		return EconomyConfig.BaseCosmetics[k] ~= nil
	end)
	local equippedCosmetics: { [string]: string } = {}
	for category, cosmeticId in tbl(base.EquippedCosmetics) do
		if
			typeof(category) == "string"
			and typeof(cosmeticId) == "string"
			and base.CosmeticUpgrades[cosmeticId]
		then
			local def = EconomyConfig.BaseCosmetics[cosmeticId]
			if def and def.Category == category then
				equippedCosmetics[category] = cosmeticId
			end
		end
	end
	base.EquippedCosmetics = equippedCosmetics
	base.PlotPreferences = { ShowIncomeLabels = bool(tbl(base.PlotPreferences).ShowIncomeLabels, true) }

	-- Skills
	local skills = d.Skills
	skills.Nodes = numberMap(skills.Nodes, function(k)
		return SkillTreeConfig.Nodes[k] ~= nil
	end, 0, 100, true)
	for id, level in skills.Nodes do
		local node = SkillTreeConfig.Nodes[id]
		if level > node.MaxLevel then
			skills.Nodes[id] = node.MaxLevel
			issue("skill level clamped " .. id)
		end
	end
	skills.GemsSpent = int(skills.GemsSpent, 0, 0, 1e15)

	-- Battle team / loadouts reference existing monsters only
	local battle = d.Battle
	local function cleanTeam(list: any): { string }
		local out: { string } = {}
		local seen: { [string]: boolean } = {}
		for _, id in tbl(list) do
			if typeof(id) == "string" and monsters[id] and not seen[id] and #out < CombatConfig.TeamSize then
				seen[id] = true
				table.insert(out, id)
			end
		end
		return out
	end
	battle.Team = cleanTeam(battle.Team)
	local loadouts: { { string } } = {}
	for i, loadout in tbl(battle.Loadouts) do
		if typeof(i) == "number" and i <= 10 then
			loadouts[#loadouts + 1] = cleanTeam(loadout)
		end
	end
	battle.Loadouts = loadouts
	battle.BattleRating =
		int(battle.BattleRating, CombatConfig.ArenaStartingRating, CombatConfig.ArenaMinRating, 100000)
	battle.ArenaWins = int(battle.ArenaWins, 0, 0, 1e9)
	battle.ArenaLosses = int(battle.ArenaLosses, 0, 0, 1e9)

	-- Discovery
	local disc = d.Discovery
	disc.DiscoveredMonsters = numberMap(disc.DiscoveredMonsters, function(k)
		return MonsterConfig.Monsters[k] ~= nil
	end, 0, now + 60, false, true)
	disc.TotalRolls = int(disc.TotalRolls, 0, 0, 1e12)
	local rare: { Types.RareRecord } = {}
	for _, r in tbl(disc.RareDiscoveries) do
		if
			typeof(r) == "table"
			and typeof(r.MonsterId) == "string"
			and MonsterConfig.Monsters[r.MonsterId]
		then
			table.insert(rare, {
				MonsterId = r.MonsterId,
				Rarity = str(r.Rarity, "Common"),
				Time = num(r.Time, 0, 0, now + 60),
				Source = str(r.Source, "Roll"),
			})
		end
	end
	while #rare > GameConfig.Data.MaxRareDiscoveries do
		table.remove(rare, 1)
	end
	disc.RareDiscoveries = rare
	disc.HighestRarityTier = int(disc.HighestRarityTier, 0, 0, #RarityConfig.Order)
	disc.ClaimedMilestones = boolMap(disc.ClaimedMilestones, anyKey)
	disc.RollCounts = numberMap(disc.RollCounts, anyKey, 0, 1e12, true)

	-- Quests
	local q = d.Quests
	q.MainIndex = int(q.MainIndex, 1, 1, #QuestConfig.MainOrder + 1)
	q.MainProgress = num(q.MainProgress, 0, 0, 1e30)
	q.DailyKey = int(q.DailyKey, -1, -1, 1e9)
	q.Daily = questList(q.Daily)
	q.WeeklyKey = int(q.WeeklyKey, -1, -1, 1e9)
	q.Weekly = questList(q.Weekly)
	q.Region = questMap(q.Region)
	q.Event = questMap(q.Event)
	q.Completed = boolMap(q.Completed, anyKey)

	local ach = d.Achievements
	ach.Completed = numberMap(ach.Completed, function(k)
		return QuestConfig.Achievements[k] ~= nil
	end, 0, now + 60, false, true)
	ach.Claimed = boolMap(ach.Claimed, function(k)
		return ach.Completed[k] ~= nil
	end)

	local daily = d.DailyRewards
	local today = TimeUtil.dayIndex(now)
	daily.LastClaimDay = int(daily.LastClaimDay, -1, -1, today)
	daily.CurrentStreak = int(daily.CurrentStreak, 0, 0, 1e6)
	daily.TotalClaims = int(daily.TotalClaims, 0, 0, 1e7)

	local stats = d.Statistics
	for key, value in stats do
		stats[key] = num(value, 0, 0, 1e30)
	end
	stats.HighestMonsterLevel = int(stats.HighestMonsterLevel, 1, 1, CombatConfig.MaxMonsterLevel)

	local ts = d.Timestamps
	ts.FirstJoin = num(ts.FirstJoin, now, 0, now)
	ts.LastSeen = num(ts.LastSeen, now, 0, now) -- future timestamps are clamped: no negative offline time
	ts.LastSaved = num(ts.LastSaved, 0, 0, now)
	ts.LastFreeRoll = num(ts.LastFreeRoll, 0, 0, now)

	d.Boosts = numberMap(d.Boosts, function(k)
		local def = CraftingConfig.Consumables[k]
		return def ~= nil and def.Boost ~= nil
	end, 0, now + 86400, false)
	for k, expiresAt in d.Boosts do
		if expiresAt <= now then
			d.Boosts[k] = nil
		end
	end

	local crafting = d.Crafting
	local queue: { Types.CraftJob } = {}
	for _, job in tbl(crafting.Queue) do
		if
			typeof(job) == "table"
			and typeof(job.RecipeId) == "string"
			and CraftingConfig.Recipes[job.RecipeId]
			and typeof(job.JobId) == "string"
		then
			table.insert(queue, {
				JobId = job.JobId,
				RecipeId = job.RecipeId,
				Count = int(job.Count, 1, 1, CraftingConfig.MaxCraftCount),
				StartedAt = num(job.StartedAt, now, 0, now),
				ReadyAt = num(job.ReadyAt, now, 0, now + 86400),
			})
		end
	end
	crafting.Queue = queue
	crafting.NextJob = int(crafting.NextJob, 1, 1, 1e12)

	local tut = d.Tutorial
	tut.Step = int(tut.Step, 1, 1, #GameConfig.Tutorial.Steps + 1)
	tut.Completed = bool(tut.Completed, false)
	tut.Skipped = bool(tut.Skipped, false)

	local settings = d.Settings
	settings.MusicVolume = num(settings.MusicVolume, 0.5, 0, 1)
	settings.SfxVolume = num(settings.SfxVolume, 0.7, 0, 1)
	settings.SkipRollAnimation = bool(settings.SkipRollAnimation, false)
	settings.AutoSell = boolMap(settings.AutoSell, function(k)
		local r = RarityConfig.Rarities[k]
		return r ~= nil and r.Tier <= 4 -- only Common..Epic may be auto-sold
	end)
	settings.ShowIncomeLabels = bool(settings.ShowIncomeLabels, true)
	settings.ReducedEffects = bool(settings.ReducedEffects, false)

	d.Exploration = { CacheClaims = numberMap(tbl(d.Exploration).CacheClaims, anyKey, 0, today, true) }

	local purchases = d.Purchases
	local receipts: { string } = {}
	for _, r in tbl(purchases.Receipts) do
		if typeof(r) == "string" then
			table.insert(receipts, r)
		end
	end
	while #receipts > GameConfig.Data.MaxReceiptHistory do
		table.remove(receipts, 1)
	end
	purchases.Receipts = receipts
	purchases.GamePasses = boolMap(purchases.GamePasses, anyKey)

	-- drop unknown top-level keys so stale fields cannot accumulate
	for key in d do
		if (defaults :: any)[key] == nil then
			d[key] = nil
			issue("unknown top-level key removed " .. tostring(key))
		end
	end
	d.SchemaVersion = DataSchema.CURRENT_VERSION
	return d :: Profile, issues
end

return DataSchema
