--!strict
-- All currency, material and reward mutations go through here so balances
-- stay finite, non-negative, capped, tracked (lifetime coins) and replicated.
-- Costs are always validated in full before anything is deducted.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local EconomyConfig = require(Config:WaitForChild("EconomyConfig"))
local CraftingConfig = require(Config:WaitForChild("CraftingConfig"))
local RegionConfig = require(Config:WaitForChild("RegionConfig"))
local QuestConfig = require(Config:WaitForChild("QuestConfig"))
local ChestConfig = require(Config:WaitForChild("ChestConfig"))
local Types = require(Shared:WaitForChild("Types"))
local Modules = script.Parent.Parent:WaitForChild("Modules")
local GameEvents = require(Modules:WaitForChild("GameEvents"))
local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))
local AnalyticsService = require(script.Parent:WaitForChild("AnalyticsService"))

type Profile = Types.Profile

export type Currency = "Coins" | "Gems" | "AscensionPoints" | "EventTokens"
export type Cost = { Kind: string, Id: string, Amount: number }

local EconomyService = {}

local VALID: { [string]: boolean } = { Coins = true, Gems = true, AscensionPoints = true, EventTokens = true }

local function valid(amount: number): boolean
	return amount == amount and amount >= 0 and amount < math.huge
end

function EconomyService.balance(profile: Profile, currency: string): number
	return (profile.Currencies :: any)[currency] or 0
end

function EconomyService.canAfford(profile: Profile, currency: string, amount: number): boolean
	return VALID[currency] == true and valid(amount) and EconomyService.balance(profile, currency) >= amount
end

-- Deducts if affordable. Returns false (and changes nothing) otherwise.
function EconomyService.spend(player: Player, currency: string, amount: number, reason: string): boolean
	local profile = PlayerDataService.get(player)
	if not profile or not EconomyService.canAfford(profile, currency, amount) then
		return false
	end
	if amount == 0 then
		return true
	end
	local c = profile.Currencies :: any
	c[currency] -= amount
	PlayerDataService.changed(player, "Currencies")
	AnalyticsService.economy(player, "Sink", currency, amount, c[currency], reason)
	return true
end

-- Adds currency. Coins count toward lifetime earnings and EarnCoins quests.
function EconomyService.grant(player: Player, currency: string, amount: number, source: string)
	local profile = PlayerDataService.get(player)
	if not profile or not VALID[currency] or not valid(amount) or amount <= 0 then
		return
	end
	local c = profile.Currencies :: any
	local before = c[currency]
	c[currency] = math.min(EconomyConfig.MaxCurrency, before + amount)
	local added = c[currency] - before
	if currency == "Coins" and added > 0 then
		profile.Statistics.LifetimeCoinsEarned =
			math.min(EconomyConfig.MaxCurrency, profile.Statistics.LifetimeCoinsEarned + added)
		PlayerDataService.changed(player, "Statistics")
		GameEvents.fire(player, "EarnCoins", { Amount = added, Source = source })
	end
	PlayerDataService.changed(player, "Currencies")
	if source ~= "Income" then
		AnalyticsService.economy(player, "Source", currency, added, c[currency], source)
	end
end

function EconomyService.material(profile: Profile, materialId: string): number
	return profile.Currencies.Materials[materialId] or 0
end

function EconomyService.grantMaterial(player: Player, materialId: string, amount: number)
	local profile = PlayerDataService.get(player)
	if not profile or not CraftingConfig.Materials[materialId] or not valid(amount) or amount <= 0 then
		return
	end
	local mats = profile.Currencies.Materials
	mats[materialId] = math.min(1e12, (mats[materialId] or 0) + math.floor(amount))
	PlayerDataService.changed(player, "Currencies")
end

-- Checks every cost first; deducts all or nothing.
-- Supported kinds: Coins/Gems/AscensionPoints/EventTokens (Id ignored), Material, Consumable.
function EconomyService.canPay(profile: Profile, costs: { Cost }): (boolean, string?)
	local needed: { [string]: number } = {}
	for _, cost in costs do
		if not valid(cost.Amount) then
			return false, "Invalid cost"
		end
		local key = cost.Kind .. ":" .. cost.Id
		needed[key] = (needed[key] or 0) + cost.Amount
	end
	for key, amount in needed do
		local kind, id = string.match(key, "^([^:]+):(.+)$")
		local have = 0
		if kind == "Material" and id then
			have = profile.Currencies.Materials[id] or 0
		elseif kind == "Consumable" and id then
			have = profile.Inventory.Consumables[id] or 0
		elseif kind and VALID[kind] then
			have = EconomyService.balance(profile, kind)
		else
			return false, "Invalid cost"
		end
		if have < amount then
			local label = id or kind or "?"
			local mat = if kind == "Material" and id then CraftingConfig.Materials[id] else nil
			if mat then
				label = mat.DisplayName
			elseif kind and EconomyConfig.Currencies[kind] then
				label = EconomyConfig.Currencies[kind].DisplayName
			end
			return false, "Not enough " .. label
		end
	end
	return true, nil
end

function EconomyService.pay(player: Player, costs: { Cost }, reason: string): (boolean, string?)
	local profile = PlayerDataService.get(player)
	if not profile then
		return false, "Not ready"
	end
	local ok, err = EconomyService.canPay(profile, costs)
	if not ok then
		return false, err
	end
	for _, cost in costs do
		if cost.Amount > 0 then
			if cost.Kind == "Material" then
				local mats = profile.Currencies.Materials
				mats[cost.Id] = (mats[cost.Id] or 0) - cost.Amount
				if mats[cost.Id] <= 0 then
					mats[cost.Id] = nil
				end
			elseif cost.Kind == "Consumable" then
				local c = profile.Inventory.Consumables
				c[cost.Id] = (c[cost.Id] or 0) - cost.Amount
				if c[cost.Id] <= 0 then
					c[cost.Id] = nil
				end
				PlayerDataService.changed(player, "Inventory")
			else
				local cur = profile.Currencies :: any
				cur[cost.Kind] -= cost.Amount
				AnalyticsService.economy(player, "Sink", cost.Kind, cost.Amount, cur[cost.Kind], reason)
			end
		end
	end
	PlayerDataService.changed(player, "Currencies")
	return true, nil
end

-- Income scale of the player's highest unlocked region (for scaled rewards/costs).
function EconomyService.regionScale(profile: Profile): number
	local region = RegionConfig.Regions[profile.Progression.HighestRegion]
	return if region then region.IncomeScale else 1
end

function EconomyService.regionMaterial(profile: Profile): string
	local region = RegionConfig.Regions[profile.Progression.HighestRegion]
	return if region then region.MaterialId else "grassland_essence"
end

export type RewardSummary = { [string]: number }

-- Grants a configured Reward. `bonus` multiplies currency and material amounts
-- (e.g. QuestRewards modifier). Returns a summary for the UI.
function EconomyService.grantReward(
	player: Player,
	reward: QuestConfig.Reward,
	source: string,
	bonus: number?
): RewardSummary
	local profile = PlayerDataService.get(player)
	local summary: RewardSummary = {}
	if not profile then
		return summary
	end
	local m = bonus or 1
	local coins = (reward.Coins or 0) + (reward.CoinsScaled or 0) * EconomyService.regionScale(profile)
	if coins > 0 then
		local amount = math.floor(coins * m)
		EconomyService.grant(player, "Coins", amount, source)
		summary.Coins = amount
	end
	for _, currency in { "Gems", "AscensionPoints", "EventTokens" } do
		local value = (reward :: any)[currency]
		if typeof(value) == "number" and value > 0 then
			local amount = if currency == "AscensionPoints" then value else math.floor(value * m)
			EconomyService.grant(player, currency, amount, source)
			summary[currency] = amount
		end
	end
	if reward.Materials then
		for id, amount in reward.Materials do
			local n = math.floor(amount * m)
			EconomyService.grantMaterial(player, id, n)
			summary["Material:" .. id] = n
		end
	end
	if reward.Consumables then
		for id, amount in reward.Consumables do
			if CraftingConfig.Consumables[id] then
				profile.Inventory.Consumables[id] = (profile.Inventory.Consumables[id] or 0) + amount
				summary["Consumable:" .. id] = amount
			end
		end
		PlayerDataService.changed(player, "Inventory")
	end
	if reward.Chests then
		for id, amount in reward.Chests do
			if ChestConfig.Chests[id] then
				profile.Inventory.Chests[id] = (profile.Inventory.Chests[id] or 0) + amount
				summary["Chest:" .. id] = amount
			end
		end
		PlayerDataService.changed(player, "Inventory")
	end
	return summary
end

function EconomyService.init() end

return EconomyService
