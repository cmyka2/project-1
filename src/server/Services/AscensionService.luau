--!strict
-- Permanent Ascension tree bought with Ascension Points (earned by rebirths
-- and milestones). Purchases survive rebirths.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RebirthConfig = require(Shared:WaitForChild("Config"):WaitForChild("RebirthConfig"))
local Guard = require(Shared:WaitForChild("Util"):WaitForChild("Guard"))
local Types = require(Shared:WaitForChild("Types"))
local Modules = script.Parent.Parent:WaitForChild("Modules")
local NetServer = require(Modules:WaitForChild("NetServer"))
local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))
local EconomyService = require(script.Parent:WaitForChild("EconomyService"))
local TycoonService = require(script.Parent:WaitForChild("TycoonService"))

type Profile = Types.Profile

local AscensionService = {}

function AscensionService.canBuy(profile: Profile, nodeId: string): (boolean, string?, number)
	local node = RebirthConfig.AscensionNodes[nodeId]
	if not node then
		return false, "Unknown upgrade.", 0
	end
	local level = profile.Progression.AscensionUpgrades[nodeId] or 0
	if level >= node.MaxLevel then
		return false, "Already maxed.", 0
	end
	for _, pre in node.Prerequisites do
		if (profile.Progression.AscensionUpgrades[pre] or 0) < 1 then
			local preNode = RebirthConfig.AscensionNodes[pre]
			return false, "Requires " .. (if preNode then preNode.Name else pre) .. ".", 0
		end
	end
	local cost = RebirthConfig.ascensionCost(node, level)
	if profile.Currencies.AscensionPoints < cost then
		return false, "Not enough Ascension Points.", cost
	end
	return true, nil, cost
end

function AscensionService.init()
	NetServer.handle("BuyAscensionNode", { Rate = 4, Burst = 8 }, function(player, rawId)
		local profile = PlayerDataService.get(player)
		local id = Guard.string(rawId)
		if not profile or not id or not RebirthConfig.AscensionNodes[id] then
			return NetServer.invalid(player, "BuyAscensionNode")
		end
		local ok, reason, cost = AscensionService.canBuy(profile, id)
		if not ok then
			return NetServer.fail(reason or "Can't buy.")
		end
		if not EconomyService.spend(player, "AscensionPoints", cost, "Ascension:" .. id) then
			return NetServer.fail("Not enough Ascension Points.")
		end
		profile.Progression.AscensionUpgrades[id] = (profile.Progression.AscensionUpgrades[id] or 0) + 1
		PlayerDataService.changed(player, "Progression")
		TycoonService.refreshIncome(player)
		return NetServer.ok({ Level = profile.Progression.AscensionUpgrades[id] })
	end)
end

return AscensionService
