--!strict
-- Quests, achievements, daily login rewards and codex milestones.
-- Quest progress is driven only by server-side GameEvents (see QuestService).

local RegionConfig = require(script.Parent.RegionConfig)
local EnemyConfig = require(script.Parent.EnemyConfig)

export type Reward = {
	Coins: number?,
	CoinsScaled: number?, -- multiplied by the IncomeScale of the player's highest region
	Gems: number?,
	AscensionPoints: number?,
	EventTokens: number?,
	Materials: { [string]: number }?,
	Consumables: { [string]: number }?,
	Chests: { [string]: number }?,
}

-- Objective types emitted by gameplay services:
--   Roll{Dice?}, ObtainRarity{MinTier}, Discover, PlaceMonster, EarnCoins,
--   WinBattle{Region?}, DefeatBoss{Region?}, UpgradeMonster, Craft,
--   UnlockRegion{Region?}, Rebirth, OpenChest, Fuse, Evolve, SellMonster,
--   ClaimDaily, ArenaWin
export type Objective = {
	Type: string,
	Target: number,
	TargetScaled: boolean?, -- multiply Target by the highest region's IncomeScale (EarnCoins)
	Dice: string?,
	Region: string?,
	MinTier: number?,
}

export type QuestDef = {
	Id: string,
	Title: string,
	Description: string,
	Category: "Main" | "Daily" | "Weekly" | "Region" | "Event",
	Objective: Objective,
	Reward: Reward,
	RequiredRegion: string?, -- region quests: visible once unlocked
	EventId: string?,
}

export type AchievementDef = {
	Id: string,
	Title: string,
	Description: string,
	Stat: string, -- see AchievementService.stat()
	Value: number,
	Reward: Reward,
	Glyph: string,
}

local Quests: { [string]: QuestDef } = {}
local MainOrder: { string } = {}
local DailyPool: { string } = {}
local WeeklyPool: { string } = {}
local RegionQuests: { string } = {}
local EventQuests: { string } = {}

local function Q(def: QuestDef)
	assert(Quests[def.Id] == nil, "duplicate quest " .. def.Id)
	Quests[def.Id] = def
	if def.Category == "Main" then
		table.insert(MainOrder, def.Id)
	elseif def.Category == "Daily" then
		table.insert(DailyPool, def.Id)
	elseif def.Category == "Weekly" then
		table.insert(WeeklyPool, def.Id)
	elseif def.Category == "Region" then
		table.insert(RegionQuests, def.Id)
	else
		table.insert(EventQuests, def.Id)
	end
end

local function main(id: string, title: string, description: string, objective: Objective, reward: Reward)
	Q({
		Id = id,
		Title = title,
		Description = description,
		Category = "Main",
		Objective = objective,
		Reward = reward,
	})
end

-- Main story ------------------------------------------------------------------
main(
	"main_first_roll",
	"Your First Roll",
	"Roll any dice once.",
	{ Type = "Roll", Target = 1 },
	{ Coins = 50 }
)
main(
	"main_place",
	"Home Sweet Home",
	"Place a monster on a slot in your base.",
	{ Type = "PlaceMonster", Target = 1 },
	{ Coins = 100 }
)
main(
	"main_roll_10",
	"Getting the Hang of It",
	"Roll 10 times.",
	{ Type = "Roll", Target = 10 },
	{ Coins = 200, Gems = 5 }
)
main(
	"main_upgrade",
	"Training Day",
	"Upgrade a monster at your base.",
	{ Type = "UpgradeMonster", Target = 1 },
	{ Coins = 300 }
)
main("main_earn", "Money Maker", "Earn 1,000 coins.", { Type = "EarnCoins", Target = 1000 }, { Coins = 500 })
main(
	"main_battle",
	"First Blood",
	"Win a battle in the Grassland.",
	{ Type = "WinBattle", Target = 1, Region = "Grassland" },
	{ Gems = 5, Consumables = { battle_tonic = 2 } }
)
main(
	"main_place_5",
	"Full House",
	"Place monsters 5 times.",
	{ Type = "PlaceMonster", Target = 5 },
	{ Coins = 800 }
)

-- Then for every region: defeat its boss, unlock the next region.
for i, regionId in RegionConfig.Order do
	local region = RegionConfig.Regions[regionId]
	local boss = EnemyConfig.Encounters[region.BossEncounterId]
	main(
		"main_boss_" .. string.lower(regionId),
		"Boss: " .. boss.DisplayName,
		"Defeat " .. boss.DisplayName .. " in " .. region.DisplayName .. ".",
		{ Type = "DefeatBoss", Target = 1, Region = regionId },
		{ Gems = 10 + 5 * i, CoinsScaled = 600 }
	)
	if i == 2 then
		main(
			"main_craft",
			"Handy Crafter",
			"Craft any item at the Workshop.",
			{ Type = "Craft", Target = 1 },
			{ Gems = 8 }
		)
	elseif i == 3 then
		main(
			"main_rebirth",
			"Born Again",
			"Rebirth for the first time.",
			{ Type = "Rebirth", Target = 1 },
			{ Gems = 50 }
		)
	elseif i == 4 then
		main(
			"main_fuse",
			"Stronger Together",
			"Fuse monsters at the Fusion Lab.",
			{ Type = "Fuse", Target = 1 },
			{ Gems = 20 }
		)
	end
	local nextId = RegionConfig.Order[i + 1]
	if nextId then
		local nextRegion = RegionConfig.Regions[nextId]
		main(
			"main_unlock_" .. string.lower(nextId),
			"New Horizons: " .. nextRegion.DisplayName,
			"Unlock " .. nextRegion.DisplayName .. ".",
			{ Type = "UnlockRegion", Target = 1, Region = nextId },
			{ CoinsScaled = 900, Gems = 10 }
		)
		main(
			"main_roll_" .. string.lower(nextId),
			"Roll in " .. nextRegion.DisplayName,
			"Roll " .. nextRegion.DisplayName .. " dice 15 times.",
			{ Type = "Roll", Target = 15, Dice = nextRegion.DiceId },
			{ CoinsScaled = 500 }
		)
	end
end

-- Daily pool -------------------------------------------------------------------
Q({
	Id = "daily_roll",
	Title = "Daily Roller",
	Description = "Roll 50 times.",
	Category = "Daily",
	Objective = { Type = "Roll", Target = 50 },
	Reward = { Gems = 6, CoinsScaled = 300 },
})
Q({
	Id = "daily_battle",
	Title = "Daily Brawler",
	Description = "Win 5 battles.",
	Category = "Daily",
	Objective = { Type = "WinBattle", Target = 5 },
	Reward = { Gems = 6, CoinsScaled = 300 },
})
Q({
	Id = "daily_earn",
	Title = "Daily Earner",
	Description = "Earn coins from any source.",
	Category = "Daily",
	Objective = { Type = "EarnCoins", Target = 3000, TargetScaled = true },
	Reward = { Gems = 5 },
})
Q({
	Id = "daily_upgrade",
	Title = "Daily Trainer",
	Description = "Upgrade monsters 5 times.",
	Category = "Daily",
	Objective = { Type = "UpgradeMonster", Target = 5 },
	Reward = { Gems = 5, CoinsScaled = 200 },
})
Q({
	Id = "daily_chest",
	Title = "Treasure Hunter",
	Description = "Open 2 chests.",
	Category = "Daily",
	Objective = { Type = "OpenChest", Target = 2 },
	Reward = { Gems = 5 },
})
Q({
	Id = "daily_craft",
	Title = "Daily Crafter",
	Description = "Craft 2 items.",
	Category = "Daily",
	Objective = { Type = "Craft", Target = 2 },
	Reward = { Gems = 5, CoinsScaled = 200 },
})
Q({
	Id = "daily_sell",
	Title = "Spring Cleaning",
	Description = "Sell 10 monsters.",
	Category = "Daily",
	Objective = { Type = "SellMonster", Target = 10 },
	Reward = { Gems = 4, CoinsScaled = 200 },
})
Q({
	Id = "daily_arena",
	Title = "Arena Regular",
	Description = "Win 2 arena battles.",
	Category = "Daily",
	Objective = { Type = "ArenaWin", Target = 2 },
	Reward = { Gems = 8 },
})
Q({
	Id = "daily_rare",
	Title = "Rare Find",
	Description = "Roll a Rare or better monster 3 times.",
	Category = "Daily",
	Objective = { Type = "ObtainRarity", Target = 3, MinTier = 3 },
	Reward = { Gems = 6 },
})

-- Weekly pool -------------------------------------------------------------------
Q({
	Id = "weekly_roll",
	Title = "Weekly Roller",
	Description = "Roll 500 times.",
	Category = "Weekly",
	Objective = { Type = "Roll", Target = 500 },
	Reward = { Gems = 40, Chests = { rare_chest = 1 } },
})
Q({
	Id = "weekly_battle",
	Title = "Weekly Warrior",
	Description = "Win 40 battles.",
	Category = "Weekly",
	Objective = { Type = "WinBattle", Target = 40 },
	Reward = { Gems = 40, Chests = { region_chest = 2 } },
})
Q({
	Id = "weekly_boss",
	Title = "Boss Slayer",
	Description = "Defeat 3 bosses.",
	Category = "Weekly",
	Objective = { Type = "DefeatBoss", Target = 3 },
	Reward = { Gems = 50, Chests = { boss_chest = 1 } },
})
Q({
	Id = "weekly_craft",
	Title = "Master Crafter",
	Description = "Craft 15 items.",
	Category = "Weekly",
	Objective = { Type = "Craft", Target = 15 },
	Reward = { Gems = 30, Consumables = { luck_potion = 2 } },
})
Q({
	Id = "weekly_fuse",
	Title = "Fusion Fanatic",
	Description = "Fuse or evolve monsters 5 times.",
	Category = "Weekly",
	Objective = { Type = "Fuse", Target = 5 },
	Reward = { Gems = 35 },
})
Q({
	Id = "weekly_earn",
	Title = "Tycoon",
	Description = "Earn a fortune in coins.",
	Category = "Weekly",
	Objective = { Type = "EarnCoins", Target = 100000, TargetScaled = true },
	Reward = { Gems = 45, Consumables = { income_potion = 2 } },
})
Q({
	Id = "weekly_arena",
	Title = "Arena Champion",
	Description = "Win 10 arena battles.",
	Category = "Weekly",
	Objective = { Type = "ArenaWin", Target = 10 },
	Reward = { Gems = 50 },
})

-- Region quests ---------------------------------------------------------------
for _, regionId in RegionConfig.Order do
	local region = RegionConfig.Regions[regionId]
	local key = string.lower(regionId)
	Q({
		Id = "region_" .. key .. "_battles",
		Title = region.DisplayName .. " Patrol",
		Description = "Win 10 battles in " .. region.DisplayName .. ".",
		Category = "Region",
		Objective = { Type = "WinBattle", Target = 10, Region = regionId },
		Reward = { Gems = 8 + region.Index * 2, Materials = { [region.MaterialId] = 8 } },
		RequiredRegion = regionId,
	})
	Q({
		Id = "region_" .. key .. "_rolls",
		Title = region.DisplayName .. " Gambler",
		Description = "Roll " .. region.DisplayName .. " dice 50 times.",
		Category = "Region",
		Objective = { Type = "Roll", Target = 50, Dice = region.DiceId },
		Reward = { Gems = 6 + region.Index * 2, Materials = { [region.MaterialId] = 5 } },
		RequiredRegion = regionId,
	})
end

-- Event quests (only progress while their event is active) ---------------------
Q({
	Id = "event_spooky_rolls",
	Title = "Trick or Roll",
	Description = "Roll Spooky Dice 20 times.",
	Category = "Event",
	Objective = { Type = "Roll", Target = 20, Dice = "spooky_dice" },
	Reward = { EventTokens = 10 },
	EventId = "halloween_2026",
})
Q({
	Id = "event_spooky_battles",
	Title = "Monster Mash",
	Description = "Win 15 battles.",
	Category = "Event",
	Objective = { Type = "WinBattle", Target = 15 },
	Reward = { EventTokens = 8 },
	EventId = "halloween_2026",
})
Q({
	Id = "event_spooky_boss",
	Title = "Haunted Hunt",
	Description = "Defeat 2 bosses.",
	Category = "Event",
	Objective = { Type = "DefeatBoss", Target = 2 },
	Reward = { EventTokens = 12 },
	EventId = "halloween_2026",
})

-- Achievements ------------------------------------------------------------------
local Achievements: { [string]: AchievementDef } = {}
local AchievementOrder: { string } = {}

local function ACH(
	id: string,
	title: string,
	description: string,
	stat: string,
	value: number,
	reward: Reward,
	glyph: string
)
	assert(Achievements[id] == nil, "duplicate achievement " .. id)
	Achievements[id] = {
		Id = id,
		Title = title,
		Description = description,
		Stat = stat,
		Value = value,
		Reward = reward,
		Glyph = glyph,
	}
	table.insert(AchievementOrder, id)
end

ACH("first_roll", "First Roll", "Roll for the first time.", "TotalRolls", 1, { Gems = 5 }, "🎲")
ACH("rolls_100", "Dice Enthusiast", "Roll 100 times.", "TotalRolls", 100, { Gems = 15 }, "🎲")
ACH("rolls_1000", "Dice Addict", "Roll 1,000 times.", "TotalRolls", 1000, { Gems = 50 }, "🎲")
ACH(
	"rolls_10000",
	"Dice Legend",
	"Roll 10,000 times.",
	"TotalRolls",
	10000,
	{ Gems = 200, AscensionPoints = 2 },
	"🎲"
)
ACH("first_rare", "First Rare Monster", "Obtain a Rare monster.", "HighestRarityTier", 3, { Gems = 5 }, "★")
ACH(
	"first_epic",
	"First Epic Monster",
	"Obtain an Epic monster.",
	"HighestRarityTier",
	4,
	{ Gems = 10 },
	"✦"
)
ACH(
	"first_legendary",
	"First Legendary Monster",
	"Obtain a Legendary monster.",
	"HighestRarityTier",
	5,
	{ Gems = 25 },
	"✪"
)
ACH(
	"first_mythic",
	"First Mythic Monster",
	"Obtain a Mythic monster.",
	"HighestRarityTier",
	6,
	{ Gems = 50 },
	"❖"
)
ACH(
	"first_divine",
	"Divine Intervention",
	"Obtain a Divine monster.",
	"HighestRarityTier",
	7,
	{ Gems = 80 },
	"☀"
)
ACH(
	"first_celestial",
	"Written in the Stars",
	"Obtain a Celestial monster.",
	"HighestRarityTier",
	8,
	{ Gems = 120 },
	"☾"
)
ACH(
	"first_cosmic",
	"Cosmic Discovery",
	"Obtain a Cosmic monster.",
	"HighestRarityTier",
	9,
	{ Gems = 200, AscensionPoints = 1 },
	"✺"
)
ACH(
	"first_glitched",
	"ERROR: TOO LUCKY",
	"Obtain a Glitched monster.",
	"HighestRarityTier",
	10,
	{ Gems = 500, AscensionPoints = 3 },
	"▓"
)
ACH("first_rebirth", "First Rebirth", "Rebirth once.", "RebirthCount", 1, { Gems = 20 }, "♻")
ACH(
	"rebirth_6",
	"Second Story",
	"Rebirth 6 times to unlock floor 2.",
	"RebirthCount",
	6,
	{ Gems = 60 },
	"🏠"
)
ACH(
	"rebirth_10",
	"Ten Rebirths",
	"Rebirth 10 times.",
	"RebirthCount",
	10,
	{ Gems = 100, AscensionPoints = 2 },
	"♻"
)
ACH(
	"rebirth_12",
	"Penthouse",
	"Rebirth 12 times to unlock floor 3.",
	"RebirthCount",
	12,
	{ Gems = 120 },
	"🏙"
)
ACH("codex_25", "Curious Collector", "Discover 25% of the codex.", "CodexPercent", 25, { Gems = 20 }, "📖")
ACH(
	"codex_50",
	"Dedicated Collector",
	"Discover 50% of the codex.",
	"CodexPercent",
	50,
	{ Gems = 50 },
	"📖"
)
ACH(
	"codex_100",
	"Master Collector",
	"Discover every monster.",
	"CodexPercent",
	100,
	{ Gems = 400, AscensionPoints = 5 },
	"📚"
)
ACH("battles_10", "Brawler", "Win 10 battles.", "BattlesWon", 10, { Gems = 10 }, "⚔")
ACH("battles_100", "Veteran", "Win 100 battles.", "BattlesWon", 100, { Gems = 40 }, "⚔")
ACH("battles_1000", "Warlord", "Win 1,000 battles.", "BattlesWon", 1000, { Gems = 150 }, "⚔")
ACH(
	"bosses_all",
	"Champion of the Isles",
	"Defeat every region boss.",
	"BossesDefeatedUnique",
	#RegionConfig.Order,
	{ Gems = 300, AscensionPoints = 3 },
	"🏆"
)
ACH("coins_1m", "Millionaire", "Earn 1 million coins in total.", "LifetimeCoins", 1e6, { Gems = 20 }, "💰")
ACH("coins_1b", "Billionaire", "Earn 1 billion coins in total.", "LifetimeCoins", 1e9, { Gems = 80 }, "💰")
ACH(
	"coins_1t",
	"Trillionaire",
	"Earn 1 trillion coins in total.",
	"LifetimeCoins",
	1e12,
	{ Gems = 250 },
	"💰"
)
ACH("arena_10", "Gladiator", "Win 10 arena battles.", "ArenaWins", 10, { Gems = 30 }, "🏟")
ACH(
	"collect_mythics",
	"Mythic Collector",
	"Discover every rollable Mythic monster.",
	"TierComplete:Mythic",
	1,
	{ Gems = 150 },
	"❖"
)
for _, regionId in RegionConfig.Order do
	local region = RegionConfig.Regions[regionId]
	ACH(
		"complete_" .. string.lower(regionId),
		"Complete " .. region.DisplayName,
		"Discover every rollable monster from " .. region.DisplayName .. ".",
		"RegionComplete:" .. regionId,
		1,
		{ Gems = 15 + region.Index * 10, Materials = { [region.MaterialId] = 10 } },
		"🗺"
	)
end

-- Daily login calendar (7-day cycle). Missing a full UTC day resets the streak.
local DailyRewards: { Reward } = {
	{ CoinsScaled = 400 },
	{ Gems = 5 },
	{ Consumables = { luck_potion = 1 } },
	{ Gems = 10, CoinsScaled = 600 },
	{ Chests = { rare_chest = 1 } },
	{ Consumables = { income_potion = 1 }, Gems = 10 },
	{ Gems = 40, Consumables = { super_luck_potion = 1 } },
}

-- Codex milestones (percent of all codex entries discovered)
local DiscoveryMilestones = {
	{ Id = "codex_m10", Percent = 10, Reward = { Gems = 10 } :: Reward },
	{ Id = "codex_m25", Percent = 25, Reward = { Gems = 25, CoinsScaled = 1000 } :: Reward },
	{ Id = "codex_m50", Percent = 50, Reward = { Gems = 60, AscensionPoints = 1 } :: Reward },
	{ Id = "codex_m75", Percent = 75, Reward = { Gems = 120, AscensionPoints = 2 } :: Reward },
	{ Id = "codex_m100", Percent = 100, Reward = { Gems = 300, AscensionPoints = 4 } :: Reward },
}

local QuestConfig = {
	Quests = Quests,
	MainOrder = MainOrder,
	DailyPool = DailyPool,
	WeeklyPool = WeeklyPool,
	RegionQuests = RegionQuests,
	EventQuests = EventQuests,
	DailyQuestCount = 3,
	WeeklyQuestCount = 3,
	Achievements = Achievements,
	AchievementOrder = AchievementOrder,
	DailyRewards = DailyRewards,
	DailyResetOnMiss = true,
	DiscoveryMilestones = DiscoveryMilestones,
	-- Day/week boundaries are UTC: day index = floor(unix / 86400),
	-- week index = floor((unix / 86400 + 3) / 7) (weeks start Monday 00:00 UTC).
}

return table.freeze(QuestConfig)
