--!strict
-- Live events. The server decides which events are active from server time;
-- clients only display what the server replicates. Expired events stop
-- applying modifiers automatically because activity is evaluated per check.

export type EventSchedule = {
	Kind: "Fixed" | "Weekly",
	StartUtc: number?, -- Fixed: unix seconds
	EndUtc: number?,
	WeekDays: { number }?, -- Weekly: 1 = Monday ... 7 = Sunday (UTC)
}

export type EventDef = {
	Id: string,
	DisplayName: string,
	Description: string,
	Schedule: EventSchedule,
	-- Multipliers applied while active (online only; never during offline income)
	LuckMultiplier: number,
	IncomeMultiplier: number,
	BattleCoinMultiplier: number,
	DiceId: string?, -- limited-time dice
	ChestId: string?, -- event chest
	QuestIds: { string },
	Color: Color3,
	Glyph: string,
}

local Events: { [string]: EventDef } = {
	weekend_luck = {
		Id = "weekend_luck",
		DisplayName = "Weekend Luck Festival",
		Description = "Every Saturday and Sunday (UTC): x1.25 roll luck for everyone.",
		Schedule = { Kind = "Weekly", WeekDays = { 6, 7 } },
		LuckMultiplier = 1.25,
		IncomeMultiplier = 1,
		BattleCoinMultiplier = 1,
		QuestIds = {},
		Color = Color3.fromRGB(110, 230, 140),
		Glyph = "🍀",
	},
	halloween_2026 = {
		Id = "halloween_2026",
		DisplayName = "Glitchy Halloween",
		Description = "Spooky Dice, event quests, Event Tokens and the Spooky Chest. x1.5 income!",
		-- 2026-10-17 00:00 UTC to 2026-11-03 00:00 UTC
		Schedule = { Kind = "Fixed", StartUtc = 1792195200, EndUtc = 1793664000 },
		LuckMultiplier = 1,
		IncomeMultiplier = 1.5,
		BattleCoinMultiplier = 1.25,
		DiceId = "spooky_dice",
		ChestId = "event_chest",
		QuestIds = { "event_spooky_rolls", "event_spooky_battles", "event_spooky_boss" },
		Color = Color3.fromRGB(255, 140, 30),
		Glyph = "🎃",
	},
}

local EventConfig = {
	Events = Events,
	Order = { "halloween_2026", "weekend_luck" },
}

return table.freeze(EventConfig)
