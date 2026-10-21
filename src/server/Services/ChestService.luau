--!strict
-- Chests: bought (coins/gems/event tokens) or earned (region/boss drops).
-- Rewards are drawn server-side from the configured weighted pool before the
-- client plays any opening animation. Gem chests are paid random items, so
-- they are blocked for players whose policy restricts paid random items.

local Players = game:GetService("Players")
local PolicyService = game:GetService("PolicyService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Util = Shared:WaitForChild("Util")
local ChestConfig = require(Config:WaitForChild("ChestConfig"))
local EquipmentConfig = require(Config:WaitForChild("EquipmentConfig"))
local RegionConfig = require(Config:WaitForChild("RegionConfig"))
local MonetizationConfig = require(Config:WaitForChild("MonetizationConfig"))
local RollMath = require(Util:WaitForChild("RollMath"))
local StatMath = require(Util:WaitForChild("StatMath"))
local EventSchedule = require(Util:WaitForChild("EventSchedule"))
local Guard = require(Util:WaitForChild("Guard"))
local Types = require(Shared:WaitForChild("Types"))
local Modules = script.Parent.Parent:WaitForChild("Modules")
local NetServer = require(Modules:WaitForChild("NetServer"))
local GameEvents = require(Modules:WaitForChild("GameEvents"))
local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))
local EconomyService = require(script.Parent:WaitForChild("EconomyService"))
local InventoryService = require(script.Parent:WaitForChild("InventoryService"))

type Profile = Types.Profile

export type ChestReward = { Kind: string, Id: string, Amount: number, Note: string? }

local ChestService = {}

local rng = Random.new()
local paidRandomRestricted: { [Player]: boolean } = {}

function ChestService.setRng(seeded: Random)
	rng = seeded
end

function ChestService.cost(profile: Profile, chest: ChestConfig.ChestDef): number?
	if not chest.Cost then
		return nil
	end
	local cost = chest.Cost
	if chest.ScaleCost then
		cost *= EconomyService.regionScale(profile)
	end
	return math.floor(cost)
end

-- Exact probability of each reward entry (for the odds display).
function ChestService.odds(chest: ChestConfig.ChestDef): { { Kind: string, Id: string, Chance: number } }
	local total = 0
	for _, r in chest.Rewards do
		total += r.Weight
	end
	local out = {}
	for _, r in chest.Rewards do
		table.insert(
			out,
			{ Kind = r.Kind :: string, Id = r.Id, Chance = if total > 0 then r.Weight / total else 0 }
		)
	end
	return out
end

local function drawOne(player: Player, profile: Profile, chest: ChestConfig.ChestDef): ChestReward?
	local entries: { RollMath.WeightedEntry<ChestConfig.ChestReward> } = {}
	for _, r in chest.Rewards do
		table.insert(entries, { Value = r, Weight = r.Weight })
	end
	local reward = RollMath.pickWeighted(entries, function()
		return rng:NextNumber()
	end)
	if not reward then
		return nil
	end
	local amount = rng:NextInteger(reward.Min, reward.Max)
	if reward.Scaled then
		amount = math.floor(amount * EconomyService.regionScale(profile))
	end
	local id = if reward.Id == "@region" then EconomyService.regionMaterial(profile) else reward.Id
	if reward.Kind == "Coins" then
		EconomyService.grant(player, "Coins", amount, "Chest")
	elseif reward.Kind == "Gems" then
		EconomyService.grant(player, "Gems", amount, "Chest")
	elseif reward.Kind == "Material" then
		EconomyService.grantMaterial(player, id, amount)
	elseif reward.Kind == "Consumable" then
		InventoryService.addConsumable(player, id, amount)
	elseif reward.Kind == "Equipment" then
		local item = InventoryService.addEquipment(player, id, 0)
		if not item then
			-- storage full: convert to salvage materials so nothing is lost
			local def = EquipmentConfig.Items[id]
			local region = def and RegionConfig.Regions[def.Region]
			if def and region then
				local mats = EquipmentConfig.SalvageMaterials[def.Rarity] or 1
				EconomyService.grantMaterial(player, region.MaterialId, mats)
				return {
					Kind = "Material",
					Id = region.MaterialId,
					Amount = mats,
					Note = "Equipment storage full: salvaged",
				}
			end
		end
	elseif reward.Kind == "Monster" then
		local inst = InventoryService.addMonster(player, id, "Chest:" .. chest.Id)
		if not inst then
			local temp: Types.MonsterInstance = {
				Id = "",
				MonsterId = id,
				Level = 1,
				Xp = 0,
				Upgrade = 0,
				Stars = 0,
				Locked = false,
				Favorite = false,
				Source = "Chest",
				Acquired = os.time(),
			}
			local value = StatMath.sellValue(temp, PlayerDataService.mods(player))
			EconomyService.grant(player, "Coins", value, "ChestOverflow")
			return { Kind = "Coins", Id = "Coins", Amount = value, Note = "Monster storage full: sold" }
		end
	end
	return { Kind = reward.Kind :: string, Id = id, Amount = amount }
end

function ChestService.open(
	player: Player,
	chestId: string,
	count: number,
	fromInventory: boolean
): ({ ChestReward }?, string?)
	local profile = PlayerDataService.get(player)
	local chest = ChestConfig.Chests[chestId]
	if not profile or not chest then
		return nil, "Unknown chest."
	end
	if chest.EventId and not fromInventory and not EventSchedule.isEventActive(chest.EventId, os.time()) then
		return nil, "That chest is only sold during its event."
	end
	if fromInventory then
		if (profile.Inventory.Chests[chestId] or 0) < count then
			return nil, "You don't have enough of those chests."
		end
	else
		local cost = ChestService.cost(profile, chest)
		local currency = chest.CostCurrency
		if not cost or not currency then
			return nil, "That chest can't be bought."
		end
		if
			currency == "Gems"
			and MonetizationConfig.GemChestsArePaidRandom
			and paidRandomRestricted[player]
		then
			return nil, "Gem chests aren't available in your region."
		end
		if not EconomyService.canAfford(profile, currency, cost * count) then
			return nil, "Not enough " .. currency .. "."
		end
	end
	-- pay / consume only after every check passed
	if fromInventory then
		InventoryService.takeChest(player, chestId, count)
	else
		local cost = ChestService.cost(profile, chest)
		local currency = chest.CostCurrency
		if
			not cost
			or not currency
			or not EconomyService.spend(player, currency, cost * count, "Chest:" .. chestId)
		then
			return nil, "Purchase failed."
		end
	end
	local mods = PlayerDataService.mods(player)
	local rewards: { ChestReward } = {}
	for _ = 1, count do
		local draws = chest.Rolls
		if rng:NextNumber() < (mods.ChestBonusRollChance or 0) then
			draws += 1
		end
		for _ = 1, draws do
			local reward = drawOne(player, profile, chest)
			if reward then
				table.insert(rewards, reward)
			end
		end
	end
	profile.Statistics.ChestsOpened += count
	PlayerDataService.changed(player, "Statistics")
	GameEvents.fire(player, "OpenChest", { Count = count, ChestId = chestId })
	return rewards, nil
end

local function checkPolicy(player: Player)
	task.spawn(function()
		local ok, info = pcall(function()
			return PolicyService:GetPolicyInfoForPlayerAsync(player)
		end)
		-- if the policy check fails, err on the side of caution
		paidRandomRestricted[player] = if ok and info then info.ArePaidRandomItemsRestricted == true else true
	end)
end

function ChestService.init()
	NetServer.handle(
		"OpenChest",
		{ Rate = 3, Burst = 6 },
		function(player, rawChest, rawCount, rawFromInventory)
			local chestId = Guard.string(rawChest)
			local count = Guard.integer(rawCount, 1, ChestConfig.MaxOpenPerRequest)
			local fromInventory = Guard.boolean(rawFromInventory) == true
			if not chestId or not count or not ChestConfig.Chests[chestId] then
				return NetServer.invalid(player, "OpenChest")
			end
			local rewards, err = ChestService.open(player, chestId, count, fromInventory)
			if not rewards then
				return NetServer.fail(err or "Can't open.")
			end
			return NetServer.ok({ Rewards = rewards })
		end
	)
end

function ChestService.onPlayerReady(player: Player, _profile: Profile)
	checkPolicy(player)
end

function ChestService.start()
	Players.PlayerRemoving:Connect(function(player)
		paidRandomRestricted[player] = nil
	end)
end

return ChestService
