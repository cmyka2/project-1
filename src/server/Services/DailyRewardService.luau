--!strict
-- Daily login calendar (7-day cycle, UTC days). One claim per UTC day per
-- profile; missing a full day resets the streak when DailyResetOnMiss is set.
-- Duplicate claims are impossible: the day index is checked and written in
-- the same synchronous handler, the handler is exclusive per player, and the
-- profile itself is session-locked to one server.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local QuestConfig = require(Shared:WaitForChild("Config"):WaitForChild("QuestConfig"))
local TimeUtil = require(Shared:WaitForChild("Util"):WaitForChild("TimeUtil"))
local Types = require(Shared:WaitForChild("Types"))
local Modules = script.Parent.Parent:WaitForChild("Modules")
local NetServer = require(Modules:WaitForChild("NetServer"))
local GameEvents = require(Modules:WaitForChild("GameEvents"))
local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))
local EconomyService = require(script.Parent:WaitForChild("EconomyService"))

type Profile = Types.Profile

local DailyRewardService = {}

-- Returns (canClaim, streakAfterClaim, rewardIndex).
function DailyRewardService.status(profile: Profile, now: number): (boolean, number, number)
	local today = TimeUtil.dayIndex(now)
	local daily = profile.DailyRewards
	if daily.LastClaimDay == today then
		local index = ((math.max(1, daily.CurrentStreak) - 1) % #QuestConfig.DailyRewards) + 1
		return false, daily.CurrentStreak, index
	end
	local streak = if daily.LastClaimDay == today - 1 or not QuestConfig.DailyResetOnMiss
		then daily.CurrentStreak + 1
		else 1
	local index = ((streak - 1) % #QuestConfig.DailyRewards) + 1
	return true, streak, index
end

function DailyRewardService.claim(player: Player): ({ [string]: number }?, string?, number?)
	local profile = PlayerDataService.get(player)
	if not profile then
		return nil, "Not ready", nil
	end
	local now = os.time()
	local canClaim, streak, index = DailyRewardService.status(profile, now)
	if not canClaim then
		return nil, "Already claimed today. Come back tomorrow!", nil
	end
	local daily = profile.DailyRewards
	daily.LastClaimDay = TimeUtil.dayIndex(now)
	daily.CurrentStreak = streak
	daily.TotalClaims += 1
	PlayerDataService.changed(player, "DailyRewards")
	local summary = EconomyService.grantReward(player, QuestConfig.DailyRewards[index], "Daily")
	GameEvents.fire(player, "ClaimDaily", { Streak = streak })
	return summary, nil, streak
end

function DailyRewardService.init()
	NetServer.handle("ClaimDaily", { Rate = 1, Burst = 2 }, function(player)
		local summary, err, streak = DailyRewardService.claim(player)
		if not summary then
			return NetServer.fail(err or "Can't claim.")
		end
		return NetServer.ok({ Reward = summary, Streak = streak })
	end)
end

function DailyRewardService.onPlayerReady(player: Player, profile: Profile)
	local canClaim = DailyRewardService.status(profile, os.time())
	if canClaim then
		NetServer.push(player, "Popup", "DailyAvailable", {})
	end
end

return DailyRewardService
