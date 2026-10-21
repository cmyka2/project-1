--!strict
-- Equipping, upgrading and salvaging equipment. One item can be worn by one
-- monster at a time, one item per category per monster; compatibility and
-- level requirements are checked server-side.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Util = Shared:WaitForChild("Util")
local EquipmentConfig = require(Config:WaitForChild("EquipmentConfig"))
local MonsterConfig = require(Config:WaitForChild("MonsterConfig"))
local RegionConfig = require(Config:WaitForChild("RegionConfig"))
local EquipMath = require(Util:WaitForChild("EquipMath"))
local Modifiers = require(Util:WaitForChild("Modifiers"))
local Guard = require(Util:WaitForChild("Guard"))
local Types = require(Shared:WaitForChild("Types"))
local Modules = script.Parent.Parent:WaitForChild("Modules")
local NetServer = require(Modules:WaitForChild("NetServer"))
local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))
local EconomyService = require(script.Parent:WaitForChild("EconomyService"))
local InventoryService = require(script.Parent:WaitForChild("InventoryService"))
local TycoonService = require(script.Parent:WaitForChild("TycoonService"))

type Profile = Types.Profile

local EquipmentService = {}

function EquipmentService.upgradeCost(
	item: Types.EquipmentInstance,
	mods: Modifiers.Mods
): ({ EconomyService.Cost }, string?)
	local def = EquipmentConfig.Items[item.ItemId]
	if not def then
		return {}, "Unknown item"
	end
	if item.Level >= EquipMath.maxLevel(def) then
		return {}, "Already at max level."
	end
	local base = EquipmentConfig.UpgradeBaseCoins[def.Rarity] or 1000
	local coins =
		Modifiers.serviceCost(math.floor(base * EquipmentConfig.UpgradeCoinGrowth ^ item.Level), mods)
	local region = RegionConfig.Regions[def.Region]
	local costs: { EconomyService.Cost } = { { Kind = "Coins", Id = "Coins", Amount = coins } }
	if region then
		table.insert(costs, {
			Kind = "Material",
			Id = region.MaterialId,
			Amount = (item.Level + 1) * EquipmentConfig.UpgradeMaterialPerLevel,
		})
	end
	return costs, nil
end

function EquipmentService.equip(
	player: Player,
	equipId: string,
	monsterInstanceId: string
): (boolean, string?)
	local profile = PlayerDataService.get(player)
	if not profile then
		return false, "Not ready"
	end
	local item = profile.Inventory.Equipment[equipId]
	local monster = profile.Inventory.Monsters[monsterInstanceId]
	if not item or not monster then
		return false, "Invalid item or monster."
	end
	if InventoryService.transientLock(player, monsterInstanceId) == "Trade" then
		return false, "That monster is in a trade."
	end
	local def = EquipmentConfig.Items[item.ItemId]
	local monsterDef = MonsterConfig.Monsters[monster.MonsterId]
	if not def or not monsterDef then
		return false, "Invalid item."
	end
	local ok, reason = EquipMath.isCompatible(def, monsterDef.Element, monster.Level)
	if not ok then
		return false, reason
	end
	-- free the category slot on the target monster
	for _, other in profile.Inventory.Equipment do
		if other.EquippedTo == monsterInstanceId and other.Id ~= equipId then
			local otherDef = EquipmentConfig.Items[other.ItemId]
			if otherDef and otherDef.Category == def.Category then
				other.EquippedTo = nil
				PlayerDataService.equipmentChanged(player, other.Id)
			end
		end
	end
	item.EquippedTo = monsterInstanceId
	PlayerDataService.equipmentChanged(player, equipId)
	TycoonService.refreshIncome(player)
	return true, nil
end

function EquipmentService.init()
	NetServer.handle("EquipItem", { Rate = 6, Burst = 10 }, function(player, rawEquip, rawMonster)
		local equipId = Guard.string(rawEquip)
		local monsterId = Guard.string(rawMonster)
		if not equipId or not monsterId then
			return NetServer.invalid(player, "EquipItem")
		end
		local ok, err = EquipmentService.equip(player, equipId, monsterId)
		if not ok then
			return NetServer.fail(err or "Can't equip.")
		end
		return NetServer.ok()
	end)

	NetServer.handle("UnequipItem", { Rate = 6, Burst = 10 }, function(player, rawEquip)
		local profile = PlayerDataService.get(player)
		local equipId = Guard.string(rawEquip)
		local item = profile and equipId and profile.Inventory.Equipment[equipId]
		if not item then
			return NetServer.invalid(player, "UnequipItem")
		end
		if item.EquippedTo and InventoryService.transientLock(player, item.EquippedTo) == "Trade" then
			return NetServer.fail("That monster is in a trade.")
		end
		item.EquippedTo = nil
		PlayerDataService.equipmentChanged(player, item.Id)
		TycoonService.refreshIncome(player)
		return NetServer.ok()
	end)

	NetServer.handle("UpgradeEquipment", { Rate = 4, Burst = 8 }, function(player, rawEquip)
		local profile = PlayerDataService.get(player)
		local equipId = Guard.string(rawEquip)
		local item = profile and equipId and profile.Inventory.Equipment[equipId]
		if not item then
			return NetServer.invalid(player, "UpgradeEquipment")
		end
		local costs, err = EquipmentService.upgradeCost(item, PlayerDataService.mods(player))
		if err then
			return NetServer.fail(err)
		end
		local paid, payErr = EconomyService.pay(player, costs, "EquipmentUpgrade")
		if not paid then
			return NetServer.fail(payErr or "Can't afford that.")
		end
		item.Level += 1
		PlayerDataService.equipmentChanged(player, item.Id)
		TycoonService.refreshIncome(player)
		return NetServer.ok({ Level = item.Level })
	end)

	NetServer.handle("SalvageEquipment", { Rate = 3, Burst = 6 }, function(player, rawIds)
		local profile = PlayerDataService.get(player)
		local ids = Guard.stringArray(rawIds, 100)
		if not profile or not ids or #ids == 0 then
			return NetServer.invalid(player, "SalvageEquipment")
		end
		local gained: { [string]: number } = {}
		for _, id in ids do
			local item = profile.Inventory.Equipment[id]
			if not item then
				return NetServer.invalid(player, "SalvageEquipment")
			end
			if item.EquippedTo then
				return NetServer.fail("Unequip items before salvaging them.")
			end
			if item.Locked then
				return NetServer.fail("Unlock items before salvaging them.")
			end
		end
		for _, id in ids do
			local item = profile.Inventory.Equipment[id]
			local def = EquipmentConfig.Items[item.ItemId]
			local region = def and RegionConfig.Regions[def.Region]
			if def and region then
				local amount = (EquipmentConfig.SalvageMaterials[def.Rarity] or 1) * (1 + item.Level)
				gained[region.MaterialId] = (gained[region.MaterialId] or 0) + amount
			end
			InventoryService.removeEquipment(player, id)
		end
		for materialId, amount in gained do
			EconomyService.grantMaterial(player, materialId, amount)
		end
		return NetServer.ok({ Materials = gained })
	end)
end

return EquipmentService
