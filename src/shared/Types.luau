--!strict
-- Types shared by server and client. The Profile type is the persisted
-- player data schema (see server/Modules/DataSchema for defaults,
-- migrations and sanitization).

export type MonsterInstance = {
	Id: string,
	MonsterId: string,
	Level: number,
	Xp: number,
	Upgrade: number,
	Stars: number,
	Locked: boolean,
	Favorite: boolean,
	Source: string,
	Acquired: number,
	Variant: string?,
	EvolvedFrom: string?,
}

export type EquipmentInstance = {
	Id: string,
	ItemId: string,
	Level: number,
	EquippedTo: string?, -- monster instance id
	Locked: boolean,
}

export type CraftJob = {
	JobId: string,
	RecipeId: string,
	Count: number,
	StartedAt: number,
	ReadyAt: number,
}

export type QuestProgress = {
	Id: string,
	Progress: number,
	Completed: boolean,
	Claimed: boolean,
}

export type RareRecord = {
	MonsterId: string,
	Rarity: string,
	Time: number,
	Source: string,
}

export type Profile = {
	SchemaVersion: number,
	Currencies: {
		Coins: number,
		Gems: number,
		AscensionPoints: number,
		EventTokens: number,
		Materials: { [string]: number },
	},
	Progression: {
		RebirthCount: number,
		AscensionUpgrades: { [string]: number },
		UnlockedRegions: { [string]: boolean },
		HighestRegion: string,
		BossesDefeated: { [string]: number }, -- region -> times defeated
		EncounterClears: { [string]: number },
		EncounterCooldowns: { [string]: number }, -- encounter -> unix time when available
		LastRespec: number,
	},
	Inventory: {
		Monsters: { [string]: MonsterInstance },
		Equipment: { [string]: EquipmentInstance },
		Consumables: { [string]: number },
		Chests: { [string]: number },
		NextId: number,
	},
	Base: {
		PlacedMonsters: { [string]: string }, -- slotId (string) -> monster instance id
		UnlockedFloors: number,
		CosmeticUpgrades: { [string]: boolean },
		EquippedCosmetics: { [string]: string }, -- category -> cosmetic id
		PlotPreferences: { ShowIncomeLabels: boolean },
	},
	Skills: {
		Nodes: { [string]: number },
		GemsSpent: number,
	},
	Battle: {
		Team: { string },
		Loadouts: { { string } },
		BattleRating: number,
		ArenaWins: number,
		ArenaLosses: number,
	},
	Discovery: {
		DiscoveredMonsters: { [string]: number }, -- monster id -> first discovery unix time
		TotalRolls: number,
		RareDiscoveries: { RareRecord },
		HighestRarityTier: number,
		ClaimedMilestones: { [string]: boolean },
		RollCounts: { [string]: number }, -- dice id -> rolls
	},
	Quests: {
		MainIndex: number,
		MainProgress: number,
		DailyKey: number,
		Daily: { QuestProgress },
		WeeklyKey: number,
		Weekly: { QuestProgress },
		Region: { [string]: QuestProgress },
		Event: { [string]: QuestProgress },
		Completed: { [string]: boolean },
	},
	Achievements: {
		Completed: { [string]: number }, -- id -> unix time completed
		Claimed: { [string]: boolean },
	},
	DailyRewards: {
		LastClaimDay: number,
		CurrentStreak: number,
		TotalClaims: number,
	},
	Statistics: {
		LifetimeCoinsEarned: number,
		BattlesWon: number,
		BattlesLost: number,
		MonstersSold: number,
		BossesDefeated: number,
		MonstersFused: number,
		ItemsCrafted: number,
		ChestsOpened: number,
		PlayTimeSeconds: number,
		HighestMonsterLevel: number,
	},
	Timestamps: {
		FirstJoin: number,
		LastSeen: number,
		LastSaved: number,
		LastFreeRoll: number,
	},
	Boosts: { [string]: number }, -- consumable id -> unix expiry
	Crafting: {
		Queue: { CraftJob },
		NextJob: number,
	},
	Tutorial: {
		Step: number,
		Completed: boolean,
		Skipped: boolean,
	},
	Settings: {
		MusicVolume: number,
		SfxVolume: number,
		SkipRollAnimation: boolean,
		AutoSell: { [string]: boolean }, -- rarity -> auto-sell newly rolled duplicates
		ShowIncomeLabels: boolean,
		ReducedEffects: boolean,
	},
	Exploration: {
		CacheClaims: { [string]: number }, -- cache id -> day index claimed
	},
	Purchases: {
		Receipts: { string },
		GamePasses: { [string]: boolean },
	},
}

-- Server-computed values replicated alongside the profile so the UI displays
-- exactly what the server uses.
export type DiceOdds = { Rarity: string, Chance: number }

export type DerivedState = {
	PlotIndex: number?,
	TotalIncome: number,
	MonsterIncome: { [string]: number }, -- placed monster instance id -> coins/sec
	IncomeMultiplier: number,
	TotalSlots: number,
	Floors: number,
	MonsterCapacity: number,
	EquipmentCapacity: number,
	Luck: { [string]: number }, -- dice id -> effective luck
	Odds: { [string]: { DiceOdds } }, -- dice id -> final rarity odds
	RollCosts: { [string]: number }, -- dice id -> cost after reductions
	UnlockedDice: { [string]: boolean },
	MultiRollOptions: { number },
	AutoRollUnlocked: boolean,
	ActiveEvents: { string },
	RebirthCost: number,
	RebirthRegion: string,
	CanRebirth: boolean,
	Modifiers: { [string]: number },
	WalkSpeed: number,
	SprintSpeed: number,
	JumpPower: number,
	CraftQueueSize: number,
	LoadoutSlots: number,
	FreeRollReadyAt: number,
	ServerTime: number,
	CodexPercent: number,
	AutoRolling: boolean,
	AutoRollDice: string?,
}

export type RemoteResult = {
	ok: boolean,
	err: string?,
	data: any,
}

return nil
