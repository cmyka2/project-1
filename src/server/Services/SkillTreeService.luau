--!strict
-- Skill tree purchases (Gems). The server validates node existence,
-- prerequisites, rebirth requirements, max level and cost; effect values
-- always come from SkillTreeConfig, never from the client.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local SkillTreeConfig = require(Shared:WaitForChild("Config"):WaitForChild("SkillTreeConfig"))
local Guard = require(Shared:WaitForChild("Util"):WaitForChild("Guard"))
local Types = require(Shared:WaitForChild("Types"))
local Modules = script.Parent.Parent:WaitForChild("Modules")
local NetServer = require(Modules:WaitForChild("NetServer"))
local GameEvents = require(Modules:WaitForChild("GameEvents"))
local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))
local EconomyService = require(script.Parent:WaitForChild("EconomyService"))
local TycoonService = require(script.Parent:WaitForChild("TycoonService"))

type Profile = Types.Profile

local SkillTreeService = {}

function SkillTreeService.canBuy(profile: Profile, nodeId: string): (boolean, string?, number)
	local node = SkillTreeConfig.Nodes[nodeId]
	if not node then
		return false, "Unknown skill.", 0
	end
	local level = profile.Skills.Nodes[nodeId] or 0
	if level >= node.MaxLevel then
		return false, "Already maxed.", 0
	end
	if profile.Progression.RebirthCount < node.RequiredRebirths then
		return false, "Requires " .. node.RequiredRebirths .. " rebirth(s).", 0
	end
	for _, pre in node.Prerequisites do
		if (profile.Skills.Nodes[pre] or 0) < 1 then
			local preNode = SkillTreeConfig.Nodes[pre]
			return false, "Requires " .. (if preNode then preNode.Name else pre) .. ".", 0
		end
	end
	local cost = SkillTreeConfig.costOf(node, level)
	if profile.Currencies.Gems < cost then
		return false, "Not enough Gems.", cost
	end
	return true, nil, cost
end

function SkillTreeService.buy(player: Player, nodeId: string): (boolean, string?)
	local profile = PlayerDataService.get(player)
	if not profile then
		return false, "Not ready"
	end
	local ok, reason, cost = SkillTreeService.canBuy(profile, nodeId)
	if not ok then
		return false, reason
	end
	if not EconomyService.spend(player, "Gems", cost, "Skill:" .. nodeId) then
		return false, "Not enough Gems."
	end
	profile.Skills.Nodes[nodeId] = (profile.Skills.Nodes[nodeId] or 0) + 1
	profile.Skills.GemsSpent += cost
	PlayerDataService.changed(player, "Skills")
	PlayerDataService.invalidateMods(player)
	TycoonService.refreshIncome(player)
	GameEvents.fire(player, "SkillsChanged", { Node = nodeId })
	return true, nil
end

function SkillTreeService.init()
	NetServer.handle("BuySkillNode", { Rate = 4, Burst = 8 }, function(player, rawId)
		local id = Guard.string(rawId)
		if not id or not SkillTreeConfig.Nodes[id] then
			return NetServer.invalid(player, "BuySkillNode")
		end
		local ok, err = SkillTreeService.buy(player, id)
		if not ok then
			return NetServer.fail(err or "Can't buy.")
		end
		return NetServer.ok({ Level = (PlayerDataService.get(player) :: Profile).Skills.Nodes[id] })
	end)

	-- Full respec: refunds every gem spent for a flat fee, on a cooldown.
	NetServer.handle("RespecSkills", { Rate = 1, Burst = 2 }, function(player)
		local profile = PlayerDataService.get(player)
		if not profile then
			return NetServer.fail("Not ready")
		end
		local now = os.time()
		if now - profile.Progression.LastRespec < SkillTreeConfig.RespecCooldownSeconds then
			return NetServer.fail("You can respec again later.")
		end
		if next(profile.Skills.Nodes) == nil then
			return NetServer.fail("You have no skills to reset.")
		end
		local refund = profile.Skills.GemsSpent
		if profile.Currencies.Gems + refund < SkillTreeConfig.RespecCostGems then
			return NetServer.fail("Not enough Gems for the respec fee.")
		end
		profile.Skills.Nodes = {}
		profile.Skills.GemsSpent = 0
		EconomyService.grant(player, "Gems", refund, "Respec")
		EconomyService.spend(player, "Gems", SkillTreeConfig.RespecCostGems, "RespecFee")
		profile.Progression.LastRespec = now
		PlayerDataService.changed(player, "Skills")
		PlayerDataService.changed(player, "Progression")
		PlayerDataService.invalidateMods(player)
		TycoonService.refreshIncome(player)
		GameEvents.fire(player, "SkillsChanged", {})
		return NetServer.ok({ Refunded = refund })
	end)
end

return SkillTreeService
