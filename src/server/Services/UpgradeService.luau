--!strict
-- Monster upgrades (coins -> upgrade rank: income and combat stats) and base
-- cosmetics (purely visual; they never change gameplay values).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Util = Shared:WaitForChild("Util")
local EconomyConfig = require(Config:WaitForChild("EconomyConfig"))
local StatMath = require(Util:WaitForChild("StatMath"))
local Guard = require(Util:WaitForChild("Guard"))
local Modules = script.Parent.Parent:WaitForChild("Modules")
local NetServer = require(Modules:WaitForChild("NetServer"))
local GameEvents = require(Modules:WaitForChild("GameEvents"))
local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))
local EconomyService = require(script.Parent:WaitForChild("EconomyService"))
local TycoonService = require(script.Parent:WaitForChild("TycoonService"))
local PlotService = require(script.Parent:WaitForChild("PlotService"))

local UpgradeService = {}

-- Upgrades a monster up to `times` ranks while affordable. Returns ranks gained and coins spent.
function UpgradeService.upgrade(player: Player, instanceId: string, times: number): (number, number, string?)
	local profile = PlayerDataService.get(player)
	if not profile then
		return 0, 0, "Not ready"
	end
	local inst = profile.Inventory.Monsters[instanceId]
	if not inst then
		return 0, 0, "You don't own that monster."
	end
	local maxRank = StatMath.maxUpgrade(inst)
	local mods = PlayerDataService.mods(player)
	local gained, spent = 0, 0
	for _ = 1, times do
		if inst.Upgrade >= maxRank then
			break
		end
		local cost = StatMath.upgradeCost(inst, mods)
		if not EconomyService.spend(player, "Coins", cost, "MonsterUpgrade") then
			break
		end
		inst.Upgrade += 1
		gained += 1
		spent += cost
	end
	if gained == 0 then
		if inst.Upgrade >= maxRank then
			return 0, 0, "Already at max upgrade."
		end
		return 0, 0, "Not enough Coins."
	end
	PlayerDataService.monsterChanged(player, instanceId)
	TycoonService.refreshIncome(player)
	GameEvents.fire(player, "UpgradeMonster", { InstanceId = instanceId, Ranks = gained })
	return gained, spent, nil
end

function UpgradeService.init()
	NetServer.handle("UpgradeMonster", { Rate = 6, Burst = 10 }, function(player, rawId, rawTimes)
		local id = Guard.string(rawId)
		local times = if rawTimes == nil then 1 else Guard.integer(rawTimes, 1, 100)
		if not id or not times then
			return NetServer.invalid(player, "UpgradeMonster")
		end
		local gained, spent, err = UpgradeService.upgrade(player, id, times)
		if gained == 0 then
			return NetServer.fail(err or "Can't upgrade.")
		end
		return NetServer.ok({ Ranks = gained, Spent = spent })
	end)

	NetServer.handle("BuyCosmetic", { Rate = 2, Burst = 4 }, function(player, rawId)
		local profile = PlayerDataService.get(player)
		local id = Guard.string(rawId)
		local def = id and EconomyConfig.BaseCosmetics[id]
		if not profile or not id or not def then
			return NetServer.invalid(player, "BuyCosmetic")
		end
		if profile.Base.CosmeticUpgrades[id] then
			return NetServer.fail("You already own that.")
		end
		if profile.Progression.RebirthCount < def.RequiredRebirths then
			return NetServer.fail("Requires " .. def.RequiredRebirths .. " rebirth(s).")
		end
		if not EconomyService.spend(player, def.CostCurrency, def.Cost, "Cosmetic:" .. id) then
			return NetServer.fail("Not enough " .. def.CostCurrency .. ".")
		end
		profile.Base.CosmeticUpgrades[id] = true
		profile.Base.EquippedCosmetics[def.Category] = id
		PlayerDataService.changed(player, "Base")
		local index = PlotService.plotIndex(player)
		if index then
			PlotService.buildSlots(player)
		end
		return NetServer.ok()
	end)

	NetServer.handle("EquipCosmetic", { Rate = 3, Burst = 6 }, function(player, rawCategory, rawId)
		local profile = PlayerDataService.get(player)
		local category = Guard.string(rawCategory)
		if
			not profile
			or not category
			or not ({ Floor = true, Platform = true, Lighting = true, Sign = true, Decoration = true })[category]
		then
			return NetServer.invalid(player, "EquipCosmetic")
		end
		if rawId == nil then
			profile.Base.EquippedCosmetics[category] = nil
		else
			local id = Guard.string(rawId)
			local def = id and EconomyConfig.BaseCosmetics[id]
			if not id or not def or def.Category ~= category or not profile.Base.CosmeticUpgrades[id] then
				return NetServer.invalid(player, "EquipCosmetic")
			end
			profile.Base.EquippedCosmetics[category] = id
		end
		PlayerDataService.changed(player, "Base")
		if PlotService.plotIndex(player) then
			PlotService.buildSlots(player)
		end
		return NetServer.ok()
	end)
end

return UpgradeService
