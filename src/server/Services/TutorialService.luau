--!strict
-- Guided tutorial. Steps advance on matching server GameEvents (roll, place,
-- upgrade, battle...) or, for informational steps, when the player presses
-- Next. Progress is saved so players can leave and resume; it can be skipped,
-- and experienced players are never forced through it again.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("Config"):WaitForChild("GameConfig"))
local Types = require(Shared:WaitForChild("Types"))
local Modules = script.Parent.Parent:WaitForChild("Modules")
local NetServer = require(Modules:WaitForChild("NetServer"))
local GameEvents = require(Modules:WaitForChild("GameEvents"))
local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))
local EconomyService = require(script.Parent:WaitForChild("EconomyService"))

type Profile = Types.Profile

local STEPS = GameConfig.Tutorial.Steps

local TutorialService = {}

local function complete(player: Player, profile: Profile, skipped: boolean)
	if profile.Tutorial.Completed then
		return
	end
	profile.Tutorial.Completed = true
	profile.Tutorial.Skipped = skipped
	profile.Tutorial.Step = #STEPS + 1
	PlayerDataService.changed(player, "Tutorial")
	if not skipped then
		local reward = GameConfig.Tutorial.StarterReward
		EconomyService.grant(player, "Coins", reward.Coins, "Tutorial")
		EconomyService.grant(player, "Gems", reward.Gems, "Tutorial")
		NetServer.notify(
			player,
			"reward",
			"Tutorial complete! +" .. reward.Coins .. " Coins, +" .. reward.Gems .. " Gems"
		)
	end
end

local function advance(player: Player, profile: Profile)
	profile.Tutorial.Step += 1
	if profile.Tutorial.Step > #STEPS then
		complete(player, profile, false)
	else
		PlayerDataService.changed(player, "Tutorial")
	end
end

function TutorialService.onEvent(player: Player, eventType: string)
	local profile = PlayerDataService.get(player)
	if not profile or profile.Tutorial.Completed then
		return
	end
	local step = STEPS[profile.Tutorial.Step]
	if step and step.Advance == eventType then
		advance(player, profile)
	end
end

function TutorialService.init()
	GameEvents.Fired:Connect(function(player, eventType)
		TutorialService.onEvent(player, eventType)
	end)
	NetServer.handle("TutorialNext", { Rate = 4, Burst = 6 }, function(player)
		local profile = PlayerDataService.get(player)
		if not profile or profile.Tutorial.Completed then
			return NetServer.fail("No tutorial in progress.")
		end
		local step = STEPS[profile.Tutorial.Step]
		if not step or (step.Advance ~= "Info" and step.Advance ~= "OpenPanel") then
			return NetServer.fail("Complete the current step first.")
		end
		advance(player, profile)
		return NetServer.ok({ Step = profile.Tutorial.Step })
	end)
	NetServer.handle("TutorialSkip", { Rate = 1, Burst = 2 }, function(player)
		local profile = PlayerDataService.get(player)
		if not profile then
			return NetServer.fail("Not ready")
		end
		complete(player, profile, true)
		return NetServer.ok()
	end)
end

function TutorialService.onPlayerReady(player: Player, profile: Profile)
	-- Returning players who already played (e.g. before the tutorial existed) skip it.
	if
		not profile.Tutorial.Completed
		and profile.Tutorial.Step == 1
		and profile.Discovery.TotalRolls >= 25
	then
		complete(player, profile, true)
	end
end

return TutorialService
