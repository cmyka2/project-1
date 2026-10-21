--!strict
-- Achievements (stat thresholds, granted once) and codex discovery
-- milestones. Completion is evaluated server-side after relevant events;
-- rewards are claimed explicitly and can only be claimed once.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Util = Shared:WaitForChild("Util")
local QuestConfig = require(Config:WaitForChild("QuestConfig"))
local RegionConfig = require(Config:WaitForChild("RegionConfig"))
local Codex = require(Util:WaitForChild("Codex"))
local Guard = require(Util:WaitForChild("Guard"))
local Types = require(Shared:WaitForChild("Types"))
local Modules = script.Parent.Parent:WaitForChild("Modules")
local NetServer = require(Modules:WaitForChild("NetServer"))
local GameEvents = require(Modules:WaitForChild("GameEvents"))
local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))
local EconomyService = require(script.Parent:WaitForChild("EconomyService"))

type Profile = Types.Profile

local AchievementService = {}

local dirty: { [Player]: boolean } = {}

function AchievementService.stat(profile: Profile, stat: string): number
	if stat == "TotalRolls" then
		return profile.Discovery.TotalRolls
	elseif stat == "HighestRarityTier" then
		return profile.Discovery.HighestRarityTier
	elseif stat == "RebirthCount" then
		return profile.Progression.RebirthCount
	elseif stat == "CodexPercent" then
		return Codex.percent(profile)
	elseif stat == "BattlesWon" then
		return profile.Statistics.BattlesWon
	elseif stat == "BossesDefeatedUnique" then
		local n = 0
		for _, regionId in RegionConfig.Order do
			if (profile.Progression.BossesDefeated[regionId] or 0) > 0 then
				n += 1
			end
		end
		return n
	elseif stat == "LifetimeCoins" then
		return profile.Statistics.LifetimeCoinsEarned
	elseif stat == "ArenaWins" then
		return profile.Battle.ArenaWins
	end
	local tier = string.match(stat, "^TierComplete:(.+)$")
	if tier then
		return if Codex.tierComplete(profile, tier) then 1 else 0
	end
	local region = string.match(stat, "^RegionComplete:(.+)$")
	if region then
		return if Codex.regionComplete(profile, region) then 1 else 0
	end
	return 0
end

function AchievementService.evaluate(player: Player)
	local profile = PlayerDataService.get(player)
	if not profile then
		return
	end
	local changed = false
	for _, id in QuestConfig.AchievementOrder do
		if not profile.Achievements.Completed[id] then
			local def = QuestConfig.Achievements[id]
			if AchievementService.stat(profile, def.Stat) >= def.Value then
				profile.Achievements.Completed[id] = os.time()
				changed = true
				NetServer.notify(player, "reward", def.Glyph .. " Achievement unlocked: " .. def.Title)
			end
		end
	end
	if changed then
		PlayerDataService.changed(player, "Achievements")
	end
end

function AchievementService.claim(player: Player, id: string): ({ [string]: number }?, string?)
	local profile = PlayerDataService.get(player)
	local def = QuestConfig.Achievements[id]
	if not profile or not def then
		return nil, "invalid"
	end
	if not profile.Achievements.Completed[id] then
		return nil, "Not unlocked yet."
	end
	if profile.Achievements.Claimed[id] then
		return nil, "Already claimed."
	end
	profile.Achievements.Claimed[id] = true
	PlayerDataService.changed(player, "Achievements")
	return EconomyService.grantReward(player, def.Reward, "Achievement"), nil
end

function AchievementService.claimMilestone(
	player: Player,
	milestoneId: string
): ({ [string]: number }?, string?)
	local profile = PlayerDataService.get(player)
	if not profile then
		return nil, "Not ready"
	end
	for _, milestone in QuestConfig.DiscoveryMilestones do
		if milestone.Id == milestoneId then
			if profile.Discovery.ClaimedMilestones[milestoneId] then
				return nil, "Already claimed."
			end
			if Codex.percent(profile) < milestone.Percent then
				return nil, "Discover more monsters first."
			end
			profile.Discovery.ClaimedMilestones[milestoneId] = true
			PlayerDataService.changed(player, "Discovery")
			local bonus = 1 + (PlayerDataService.mods(player).DiscoveryRewardBonus or 0)
			return EconomyService.grantReward(player, milestone.Reward, "Codex", bonus), nil
		end
	end
	return nil, "invalid"
end

local RELEVANT: { [string]: boolean } = {
	Roll = true,
	Discover = true,
	ObtainRarity = true,
	Rebirth = true,
	WinBattle = true,
	DefeatBoss = true,
	ArenaWin = true,
	EarnCoins = true,
	Evolve = true,
	Fuse = true,
}

function AchievementService.init()
	GameEvents.Fired:Connect(function(player, eventType)
		if RELEVANT[eventType] then
			dirty[player] = true
		end
	end)
	NetServer.handle("ClaimAchievement", { Rate = 4, Burst = 8 }, function(player, rawId)
		local id = Guard.string(rawId)
		if not id then
			return NetServer.invalid(player, "ClaimAchievement")
		end
		AchievementService.evaluate(player)
		local summary, err = AchievementService.claim(player, id)
		if not summary then
			if err == "invalid" then
				return NetServer.invalid(player, "ClaimAchievement")
			end
			return NetServer.fail(err or "Can't claim.")
		end
		return NetServer.ok(summary)
	end)
	NetServer.handle("ClaimMilestone", { Rate = 4, Burst = 8 }, function(player, rawId)
		local id = Guard.string(rawId)
		if not id then
			return NetServer.invalid(player, "ClaimMilestone")
		end
		local summary, err = AchievementService.claimMilestone(player, id)
		if not summary then
			if err == "invalid" then
				return NetServer.invalid(player, "ClaimMilestone")
			end
			return NetServer.fail(err or "Can't claim.")
		end
		return NetServer.ok(summary)
	end)
end

function AchievementService.onPlayerReady(player: Player, _profile: Profile)
	AchievementService.evaluate(player)
end

function AchievementService.start()
	Players.PlayerRemoving:Connect(function(player)
		dirty[player] = nil
	end)
	while true do
		task.wait(1)
		for player in dirty do
			dirty[player] = nil
			AchievementService.evaluate(player)
		end
	end
end

return AchievementService
