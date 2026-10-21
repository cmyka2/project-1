--!strict
-- Optional Robux products. Every id is 0 until you create the product/pass on
-- the Creator Dashboard; entries with id 0 are hidden and never processed.
-- The game is fully playable without purchases. Gameplay-affecting passes are
-- described plainly in their Description so players know what they buy.

export type ProductDef = {
	Key: string,
	ProductId: number,
	DisplayName: string,
	Description: string,
	Grant: { Gems: number?, Consumables: { [string]: number }? },
}

export type PassDef = {
	Key: string,
	GamePassId: number,
	DisplayName: string,
	Description: string,
	Modifiers: { [string]: number }, -- merged into Util/Modifiers while owned
}

local Products: { ProductDef } = {
	{
		Key = "gems_small",
		ProductId = 0,
		DisplayName = "Pouch of Gems",
		Description = "100 Gems.",
		Grant = { Gems = 100 },
	},
	{
		Key = "gems_medium",
		ProductId = 0,
		DisplayName = "Chest of Gems",
		Description = "550 Gems.",
		Grant = { Gems = 550 },
	},
	{
		Key = "luck_bundle",
		ProductId = 0,
		DisplayName = "Luck Bundle",
		Description = "3 Super Luck Potions.",
		Grant = { Consumables = { super_luck_potion = 3 } },
	},
}

local Passes: { PassDef } = {
	{
		Key = "vip",
		GamePassId = 0,
		DisplayName = "VIP",
		Description = "+20% passive income and a VIP name tag.",
		Modifiers = { Income = 0.2 },
	},
	{
		Key = "lucky",
		GamePassId = 0,
		DisplayName = "Lucky Charm",
		Description = "+15% roll luck.",
		Modifiers = { Luck = 0.15 },
	},
	{
		Key = "storage",
		GamePassId = 0,
		DisplayName = "Bigger Storage",
		Description = "+100 monster storage.",
		Modifiers = { InventoryCapacity = 100 },
	},
}

local MonetizationConfig = {
	Products = Products,
	Passes = Passes,
	-- Gem-priced chests are paid random items (gems are purchasable). They are
	-- blocked for players whose PolicyService info restricts paid random items,
	-- and their odds are always shown in the chest UI.
	GemChestsArePaidRandom = true,
}

return table.freeze(MonetizationConfig)
