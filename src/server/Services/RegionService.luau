--!strict
-- Region unlocks, travel and daily exploration caches. Unlocks require the
-- previous region's boss, a rebirth count and coins; all checked here.
-- Travel is server-performed; gameplay inside regions (dice, battles,
-- caches) independently re-checks the unlock, so moving there by other
-- means grants nothing.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Util = Shared:WaitForChild("Util")
local RegionConfig = require(Config:WaitForChild("RegionConfig"))
local Modifiers = require(Util:WaitForChild("Modifiers"))
local TimeUtil = require(Util:WaitForChild("TimeUtil"))
local Guard = require(Util:WaitForChild("Guard"))
local Types = require(Shared:WaitForChild("Types"))
local Modules = script.Parent.Parent:WaitForChild("Modules")
local NetServer = require(Modules:WaitForChild("NetServer"))
local GameEvents = require(Modules:WaitForChild("GameEvents"))
local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))
local EconomyService = require(script.Parent:WaitForChild("EconomyService"))
local WorldService = require(script.Parent:WaitForChild("WorldService"))
local PlotService = require(script.Parent:WaitForChild("PlotService"))
local AntiExploitService = require(script.Parent:WaitForChild("AntiExploitService"))

type Profile = Types.Profile

local RegionService = {}

local lastTravel: { [Player]: number } = {}

-- Returns (canUnlock, reason) without changing anything.
function RegionService.unlockStatus(profile: Profile, regionId: string): (boolean, string?)
	local region = RegionConfig.Regions[regionId]
	if not region then
		return false, "Unknown region."
	end
	local progression = profile.Progression
	if progression.UnlockedRegions[regionId] then
		return false, "Already unlocked."
	end
	local previousId = RegionConfig.Order[region.Index - 1]
	if previousId and not progression.UnlockedRegions[previousId] then
		return false, "Unlock " .. RegionConfig.Regions[previousId].DisplayName .. " first."
	end
	if region.RequiresBossOf and (progression.BossesDefeated[region.RequiresBossOf] or 0) < 1 then
		local bossRegion = RegionConfig.Regions[region.RequiresBossOf]
		return false,
			"Defeat the "
				.. (if bossRegion then bossRegion.DisplayName else region.RequiresBossOf)
				.. " boss first."
	end
	if progression.RebirthCount < region.RequiredRebirths then
		return false, "Requires " .. region.RequiredRebirths .. " rebirth(s)."
	end
	if profile.Currencies.Coins < region.UnlockCost then
		return false, "Not enough Coins."
	end
	return true, nil
end

function RegionService.unlock(player: Player, regionId: string): (boolean, string?)
	local profile = PlayerDataService.get(player)
	if not profile then
		return false, "Not ready"
	end
	local ok, reason = RegionService.unlockStatus(profile, regionId)
	if not ok then
		return false, reason
	end
	local region = RegionConfig.Regions[regionId]
	if not EconomyService.spend(player, "Coins", region.UnlockCost, "RegionUnlock:" .. regionId) then
		return false, "Not enough Coins."
	end
	profile.Progression.UnlockedRegions[regionId] = true
	if region.Index > RegionConfig.indexOf(profile.Progression.HighestRegion) then
		profile.Progression.HighestRegion = regionId
	end
	PlayerDataService.changed(player, "Progression")
	GameEvents.fire(player, "UnlockRegion", { Region = regionId })
	return true, nil
end

local function travelReady(player: Player): (boolean, string?)
	local cooldown = Modifiers.travelCooldown(PlayerDataService.mods(player))
	local last = lastTravel[player] or -math.huge
	local remaining = cooldown - (os.clock() - last)
	if remaining > 0 then
		return false, string.format("Travel is recharging (%ds).", math.ceil(remaining))
	end
	return true, nil
end

function RegionService.travel(player: Player, regionId: string): (boolean, string?)
	local profile = PlayerDataService.get(player)
	if not profile then
		return false, "Not ready"
	end
	if not RegionConfig.Regions[regionId] then
		return false, "Unknown region."
	end
	if not profile.Progression.UnlockedRegions[regionId] then
		return false, "That region is locked."
	end
	local ready, reason = travelReady(player)
	if not ready then
		return false, reason
	end
	local arrival = WorldService.info().RegionArrivals[regionId]
	if not arrival then
		return false, "That region isn't built yet."
	end
	AntiExploitService.allowTeleport(player)
	if not WorldService.teleport(player, arrival) then
		return false, "Can't travel right now."
	end
	lastTravel[player] = os.clock()
	player:SetAttribute("CurrentRegion", regionId)
	return true, nil
end

function RegionService.currentRegion(player: Player): string?
	local root = WorldService.rootPart(player)
	return if root then WorldService.regionAt(root.Position) else nil
end

function RegionService.init()
	NetServer.handle("UnlockRegion", { Rate = 2, Burst = 4 }, function(player, rawId)
		local id = Guard.string(rawId)
		if not id or not RegionConfig.Regions[id] then
			return NetServer.invalid(player, "UnlockRegion")
		end
		local ok, err = RegionService.unlock(player, id)
		if not ok then
			return NetServer.fail(err or "Can't unlock.")
		end
		return NetServer.ok()
	end)

	NetServer.handle("TravelToRegion", { Rate = 1, Burst = 3 }, function(player, rawId)
		local id = Guard.string(rawId)
		if not id or not RegionConfig.Regions[id] then
			return NetServer.invalid(player, "TravelToRegion")
		end
		local ok, err = RegionService.travel(player, id)
		if not ok then
			return NetServer.fail(err or "Can't travel.")
		end
		return NetServer.ok()
	end)

	NetServer.handle("TravelToHub", { Rate = 1, Burst = 3 }, function(player, rawHome)
		local home = Guard.boolean(rawHome) == true
		AntiExploitService.allowTeleport(player)
		local ok = if home
			then PlotService.teleportHome(player)
			else WorldService.teleport(player, WorldService.info().HubSpawn)
		if not ok then
			return NetServer.fail("Can't travel right now.")
		end
		player:SetAttribute("CurrentRegion", nil)
		return NetServer.ok()
	end)

	NetServer.handle("ClaimCache", { Rate = 2, Burst = 4 }, function(player, rawId)
		local profile = PlayerDataService.get(player)
		local id = Guard.string(rawId)
		local cache = id and WorldService.info().Caches[id]
		if not profile or not id or not cache then
			return NetServer.invalid(player, "ClaimCache")
		end
		if not profile.Progression.UnlockedRegions[cache.Region] then
			return NetServer.fail("That region is locked.")
		end
		local root = WorldService.rootPart(player)
		if not root or (root.Position - cache.Position).Magnitude > 20 then
			return NetServer.fail("Get closer to the cache.")
		end
		local today = TimeUtil.dayIndex(os.time())
		if profile.Exploration.CacheClaims[id] == today then
			return NetServer.fail("Already looted today. Come back tomorrow!")
		end
		profile.Exploration.CacheClaims[id] = today
		PlayerDataService.changed(player, "Exploration")
		local region = RegionConfig.Regions[cache.Region]
		local summary = EconomyService.grantReward(player, {
			Coins = region.CacheRewardCoins,
			Materials = { [region.MaterialId] = 2 },
		}, "Cache")
		return NetServer.ok(summary)
	end)
end

function RegionService.onPlayerRemoving(player: Player, _profile: Profile)
	lastTravel[player] = nil
end

function RegionService.start()
	Players.PlayerRemoving:Connect(function(player)
		lastTravel[player] = nil
	end)
end

return RegionService
