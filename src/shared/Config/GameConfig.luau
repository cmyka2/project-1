--!strict
-- Global game settings: persistence, world layout, plots, social features,
-- tutorial, anti-exploit thresholds and QA tooling. Replicated to clients, so
-- nothing secret belongs here (the server re-checks every value it uses).

export type TutorialStep = {
	Id: string,
	Title: string,
	Text: string,
	-- "Info" steps advance when the player presses Next; the others advance
	-- when the matching server-side GameEvent fires.
	Advance: "Info"
		| "Roll"
		| "Inspect"
		| "PlaceMonster"
		| "UpgradeMonster"
		| "StartBattle"
		| "WinBattle"
		| "OpenPanel",
	Panel: string?, -- UI panel to highlight
}

local GameConfig = {
	GameName = "Monster Roll: Rise of the Mythics",
	Version = "1.0.0",

	Data = {
		StoreName = "MonsterRoll_PlayerData_v1",
		KeyPrefix = "Player_",
		SchemaVersion = 3,
		AutosaveInterval = 90, -- seconds; each player is staggered within the interval
		LockStaleSeconds = 1800, -- a lock older than this is considered abandoned
		LoadAttempts = 6,
		LockWaitSeconds = 5, -- wait between attempts when another server holds the lock
		SaveAttempts = 5,
		RetryBaseDelay = 1,
		RetryMaxDelay = 16,
		ShutdownTimeout = 25,
		-- When DataStores are unavailable in Studio (API access disabled), use an
		-- in-memory store so the game is testable. Never used in live servers.
		UseMockInStudio = true,
		MaxRareDiscoveries = 50, -- rolling history kept in the profile
		MaxReceiptHistory = 100,
	},

	World = {
		IslandSizeX = 640, -- east-west
		IslandSizeZ = 820, -- north-south
		IslandThickness = 30,
		OceanSize = 3200,
		OceanDepth = 40,
		-- Out-of-bounds recovery: players beyond these limits are returned to safety
		BoundsX = 560,
		BoundsZ = 680,
		MinY = -25,
		RegionIslandHeight = 900, -- region islands float high above the main island
		RegionIslandSpacing = 420,
		RegionIslandSize = 220,
	},

	Plots = {
		Count = 8, -- 4 on the north edge, 4 on the south edge
		PerRow = 4,
		Size = 120, -- studs, square footprint
		Gap = 22,
		EdgeInset = 14, -- distance between island edge and plot back wall
		FloorHeight = 22,
		SlotSpacing = 14,
		SlotColumns = 6,
		SlotPadSize = 9,
		MonsterDisplayHeight = 7, -- displayed models are scaled to this height
	},

	Travel = {
		CooldownSeconds = 8,
		MaxPromptDistance = 24,
	},

	Movement = {
		BaseWalkSpeed = 32, -- studs/s; 2x the Roblox default of 16. Mobility skills add % on top.
		BaseJumpPower = 50,
		SprintMultiplier = 1.5, -- sprint speed = walk speed (with skill bonuses) x this
		-- Keyboard keys are hold-to-sprint; the gamepad key and the touch button toggle.
		SprintKeys = { Enum.KeyCode.LeftShift, Enum.KeyCode.RightShift, Enum.KeyCode.ButtonL3 },
	},

	Social = {
		TradingEnabled = true,
		TradeRequestTimeout = 30,
		TradeConfirmCountdown = 3,
		TradeMaxMonsters = 8,
		TradeMinAccountAgeDays = 0,
		TradeSessionTimeout = 180,
		VisitEnabled = true,
		AnnounceRareRolls = true,
	},

	Leaderboards = {
		Enabled = true,
		RefreshSeconds = 90,
		UploadSeconds = 120,
		TopCount = 10,
		Boards = {
			{ Id = "Rebirths", DisplayName = "Most Rebirths", Stat = "RebirthCount", LogScale = false },
			{ Id = "Discoveries", DisplayName = "Codex Discoveries", Stat = "Discoveries", LogScale = false },
			{ Id = "LifetimeCoins", DisplayName = "Lifetime Coins", Stat = "LifetimeCoins", LogScale = true },
			{ Id = "BattleRating", DisplayName = "Arena Rating", Stat = "BattleRating", LogScale = false },
		},
	},

	AntiExploit = {
		-- Token-bucket defaults per remote (individual remotes override in Net)
		DefaultRate = 4,
		DefaultBurst = 8,
		StrikeLogThreshold = 25, -- log once a player trips this many rejections
		SpeedCheckInterval = 1,
		MaxSpeedStudsPerSecond = 140,
	},

	Cheats = {
		-- Gated server-side. Studio always allowed; live servers only for these UserIds.
		AllowedUserIds = {} :: { number },
	},

	Tutorial = {
		Steps = {
			{
				Id = "welcome",
				Title = "Welcome, Tamer!",
				Text = "Welcome to Monster Roll! Roll dice to discover monsters, place them in your base to earn coins, and battle your way across nine regions.",
				Advance = "Info",
			},
			{
				Id = "currency",
				Title = "Coins",
				Text = "Coins (top of the screen) pay for dice, upgrades and new regions. Your base earns them automatically.",
				Advance = "Info",
			},
			{
				Id = "roll",
				Title = "Your First Roll",
				Text = "Press the big ROLL button to roll the Grassland Dice.",
				Advance = "Roll",
				Panel = "Roll",
			},
			{
				Id = "inspect",
				Title = "Inspect Your Monster",
				Text = "Open your Inventory and tap a monster to see its stats.",
				Advance = "Inspect",
				Panel = "Inventory",
			},
			{
				Id = "place",
				Title = "Place It",
				Text = "Walk to a glowing pad in your base (or use Inventory > Place) to put your monster to work.",
				Advance = "PlaceMonster",
				Panel = "Inventory",
			},
			{
				Id = "income",
				Title = "Passive Income",
				Text = "Placed monsters earn coins every second, even a little while you are offline.",
				Advance = "Info",
			},
			{
				Id = "upgrade",
				Title = "Train Your Monster",
				Text = "Upgrade a placed monster from your Base panel to boost its income.",
				Advance = "UpgradeMonster",
				Panel = "Base",
			},
			{
				Id = "battle",
				Title = "First Battle",
				Text = "Open Battle, pick your team and start a Grassland Skirmish.",
				Advance = "StartBattle",
				Panel = "Battle",
			},
			{
				Id = "win",
				Title = "Win the Fight",
				Text = "Choose attacks and abilities each turn. Super-effective elements deal 50% more damage!",
				Advance = "WinBattle",
			},
			{
				Id = "dice",
				Title = "Better Dice",
				Text = "Defeat each region's boss and unlock the next region for stronger dice and monsters.",
				Advance = "Info",
			},
			{
				Id = "rebirth",
				Title = "Rebirth",
				Text = "Later, Rebirth resets coins and upgrades for permanent bonuses, Ascension Points and an extra base slot every time.",
				Advance = "Info",
			},
		} :: { TutorialStep },
		StarterReward = { Coins = 150, Gems = 10 },
	},

	Analytics = {
		Enabled = true,
	},
}

return table.freeze(GameConfig)
