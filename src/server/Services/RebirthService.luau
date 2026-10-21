--!strict
-- Rebirth: pay the coin requirement, reset short-term progress (per
-- RebirthConfig.Reset) and gain permanent bonuses, Ascension Points, gems and
-- one more base slot. Requests carry the rebirth count the client expects to
-- leave, so a repeated or replayed request can never rebirth twice.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Util = Shared:WaitForChild("Util")
local RebirthConfig = require(Config:WaitForChild("RebirthConfig"))
local RegionConfig = require(Config:WaitForChild("RegionConfig"))
local BaseLayout = require(Util:WaitForChild("BaseLayout"))
local Guard = require(Util:WaitForChild("Guard"))
local Types = require(Shared:WaitForChild("Types"))
local Modules = script.Parent.Parent:WaitForChild("Modules")
local NetServer = require(Modules:WaitForChild("NetServer"))
local GameEvents = require(Modules:WaitForChild("GameEvents"))
local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))
local EconomyService = require(script.Parent:WaitForChild("EconomyService"))
local PlotService = require(script.Parent:WaitForChild("PlotService"))
local TycoonService = require(script.Parent:WaitForChild("TycoonService"))
local AnalyticsService = require(script.Parent:WaitForChild("AnalyticsService"))

type Profile = Types.Profile

export type RebirthSummary = {
	NewCount: number,
	AscensionPoints: number,
	Gems: number,
	KeptCoins: number,
	TotalSlots: number,
	Floors: number,
	FloorUnlocked: boolean,
}

local RebirthService = {}

function RebirthService.status(profile: Profile): (boolean, string?)
	local count = profile.Progression.RebirthCount
	if count >= RebirthConfig.MaxRebirths then
		return false, "You have reached the maximum number of rebirths."
	end
	local regionId = RebirthConfig.requiredRegion(count)
	if not profile.Progression.UnlockedRegions[regionId] then
		local region = RegionConfig.Regions[regionId]
		return false, "Unlock " .. (if region then region.DisplayName else regionId) .. " first."
	end
	if profile.Currencies.Coins < RebirthConfig.cost(count) then
		return false, "Not enough Coins."
	end
	return true, nil
end

function RebirthService.rebirth(player: Player, expectedCount: number): (RebirthSummary?, string?)
	local profile = PlayerDataService.get(player)
	if not profile then
		return nil, "Not ready"
	end
	local count = profile.Progression.RebirthCount
	if expectedCount ~= count then
		return nil, "Your rebirth was already processed."
	end
	local ok, reason = RebirthService.status(profile)
	if not ok then
		return nil, reason
	end
	local cost = RebirthConfig.cost(count)
	if not EconomyService.spend(player, "Coins", cost, "Rebirth") then
		return nil, "Not enough Coins."
	end
	local mods = PlayerDataService.mods(player)
	local reset = RebirthConfig.Reset
	local kept = 0
	if reset.Coins then
		kept = math.floor(profile.Currencies.Coins * (mods.RebirthKeepCoins or 0))
		profile.Currencies.Coins = kept
	end
	if reset.MonsterUpgrades then
		for id, inst in profile.Inventory.Monsters do
			if inst.Upgrade > 0 then
				inst.Upgrade = 0
				PlayerDataService.monsterChanged(player, id)
			end
		end
	end
	if reset.Skills then
		profile.Skills.Nodes = {}
		profile.Skills.GemsSpent = 0
		PlayerDataService.changed(player, "Skills")
	end
	if reset.Boosts then
		profile.Boosts = {}
		PlayerDataService.changed(player, "Boosts")
	end
	local newCount = count + 1
	local floorsBefore = BaseLayout.floorCount(count)
	profile.Progression.RebirthCount = newCount
	profile.Base.UnlockedFloors = BaseLayout.floorCount(newCount)
	local points = RebirthConfig.AscensionPointsPerRebirth
	if newCount % RebirthConfig.AscensionMilestoneEvery == 0 then
		points += RebirthConfig.AscensionMilestoneBonus
	end
	EconomyService.grant(player, "AscensionPoints", points, "Rebirth")
	local gems = RebirthConfig.GemsPerRebirth * newCount
	EconomyService.grant(player, "Gems", gems, "Rebirth")
	PlayerDataService.changed(player, "Progression")
	PlayerDataService.changed(player, "Currencies")
	PlayerDataService.changed(player, "Base")
	PlayerDataService.invalidateMods(player)
	-- the layout changed: rebuild slot pads; displays follow via LayoutChanged
	PlotService.buildSlots(player)
	TycoonService.refreshIncome(player)
	GameEvents.fire(player, "Rebirth", { Count = newCount })
	AnalyticsService.event(player, "Rebirth", newCount)
	local summary: RebirthSummary = {
		NewCount = newCount,
		AscensionPoints = points,
		Gems = gems,
		KeptCoins = kept,
		TotalSlots = BaseLayout.totalSlots(newCount),
		Floors = BaseLayout.floorCount(newCount),
		FloorUnlocked = BaseLayout.floorCount(newCount) > floorsBefore,
	}
	return summary, nil
end

function RebirthService.init()
	NetServer.handle("Rebirth", { Rate = 1, Burst = 2 }, function(player, rawExpected)
		local expected = Guard.integer(rawExpected, 0, RebirthConfig.MaxRebirths)
		if expected == nil then
			return NetServer.invalid(player, "Rebirth")
		end
		local summary, err = RebirthService.rebirth(player, expected)
		if not summary then
			return NetServer.fail(err or "Can't rebirth.")
		end
		NetServer.push(player, "Popup", "Rebirth", summary)
		return NetServer.ok(summary)
	end)
end

return RebirthService
