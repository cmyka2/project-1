--!strict
-- Player settings (audio, roll animation, auto-sell, labels, effects) and
-- applying movement modifiers to the character. Settings are validated
-- field-by-field; unknown fields are rejected.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RarityConfig = require(Shared:WaitForChild("Config"):WaitForChild("RarityConfig"))
local Modifiers = require(Shared:WaitForChild("Util"):WaitForChild("Modifiers"))
local Guard = require(Shared:WaitForChild("Util"):WaitForChild("Guard"))
local Types = require(Shared:WaitForChild("Types"))
local Modules = script.Parent.Parent:WaitForChild("Modules")
local NetServer = require(Modules:WaitForChild("NetServer"))
local GameEvents = require(Modules:WaitForChild("GameEvents"))
local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))
local TycoonService = require(script.Parent:WaitForChild("TycoonService"))

type Profile = Types.Profile

local SettingsService = {}

local connections: { [Player]: RBXScriptConnection } = {}

function SettingsService.applyMovement(player: Player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local mods = PlayerDataService.mods(player)
	humanoid.WalkSpeed = Modifiers.walkSpeed(mods)
	humanoid.UseJumpPower = true
	humanoid.JumpPower = Modifiers.jumpPower(mods)
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and (mods.MovementTrail or 0) >= 1 and not root:FindFirstChild("StardustTrail") then
		local a0 = Instance.new("Attachment")
		a0.Name = "TrailTop"
		a0.Position = Vector3.new(0, 1, 0)
		a0.Parent = root
		local a1 = Instance.new("Attachment")
		a1.Name = "TrailBottom"
		a1.Position = Vector3.new(0, -1, 0)
		a1.Parent = root
		local trail = Instance.new("Trail")
		trail.Name = "StardustTrail"
		trail.Attachment0 = a0
		trail.Attachment1 = a1
		trail.Lifetime = 0.5
		trail.Color = ColorSequence.new(Color3.fromRGB(255, 240, 160), Color3.fromRGB(160, 120, 255))
		trail.LightEmission = 0.8
		trail.Parent = root
	end
end

local SETTERS: { [string]: (Profile, unknown) -> boolean } = {
	MusicVolume = function(profile, v)
		local n = Guard.number(v, 0, 1)
		if n == nil then
			return false
		end
		profile.Settings.MusicVolume = n
		return true
	end,
	SfxVolume = function(profile, v)
		local n = Guard.number(v, 0, 1)
		if n == nil then
			return false
		end
		profile.Settings.SfxVolume = n
		return true
	end,
	SkipRollAnimation = function(profile, v)
		local b = Guard.boolean(v)
		if b == nil then
			return false
		end
		profile.Settings.SkipRollAnimation = b
		return true
	end,
	ShowIncomeLabels = function(profile, v)
		local b = Guard.boolean(v)
		if b == nil then
			return false
		end
		profile.Settings.ShowIncomeLabels = b
		return true
	end,
	ReducedEffects = function(profile, v)
		local b = Guard.boolean(v)
		if b == nil then
			return false
		end
		profile.Settings.ReducedEffects = b
		return true
	end,
	AutoSell = function(profile, v)
		local map = Guard.record(v, Guard.boolean, 10)
		if not map then
			return false
		end
		local out: { [string]: boolean } = {}
		for rarity, enabled in map do
			local def = RarityConfig.Rarities[rarity]
			if not def or def.Tier > 4 then
				return false
			end
			if enabled then
				out[rarity] = true
			end
		end
		profile.Settings.AutoSell = out
		return true
	end,
}

function SettingsService.init()
	NetServer.handle("UpdateSettings", { Rate = 4, Burst = 8 }, function(player, rawSettings)
		local profile = PlayerDataService.get(player)
		if not profile or typeof(rawSettings) ~= "table" then
			return NetServer.invalid(player, "UpdateSettings")
		end
		local count = 0
		for key, value in rawSettings :: { [any]: any } do
			count += 1
			local setter = if typeof(key) == "string" then SETTERS[key] else nil
			if count > 10 or not setter or not setter(profile, value) then
				return NetServer.invalid(player, "UpdateSettings")
			end
		end
		PlayerDataService.changed(player, "Settings")
		if rawSettings.ShowIncomeLabels ~= nil then
			TycoonService.rebuildDisplays(player)
		end
		return NetServer.ok()
	end)
	-- re-apply movement whenever skills change
	GameEvents.Fired:Connect(function(player, eventType)
		if eventType == "SkillsChanged" then
			SettingsService.applyMovement(player)
		end
	end)
end

function SettingsService.onPlayerReady(player: Player, _profile: Profile)
	connections[player] = player.CharacterAdded:Connect(function()
		task.wait(0.1)
		SettingsService.applyMovement(player)
	end)
	SettingsService.applyMovement(player)
end

function SettingsService.onPlayerRemoving(player: Player, _profile: Profile)
	local conn = connections[player]
	if conn then
		conn:Disconnect()
		connections[player] = nil
	end
end

return SettingsService
