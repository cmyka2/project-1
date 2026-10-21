--!strict
-- Plays sounds by SoundKey (AssetConfig.Sounds). Missing ids are silent, so
-- the game works before audio is imported. Volume follows player settings.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AssetRegistry = require(Shared:WaitForChild("AssetRegistry"))
local StateController = require(script.Parent:WaitForChild("StateController"))

local AudioController = {}

local pool: { [string]: Sound } = {}
local music: Sound? = nil

local function volume(isMusic: boolean): number
	local profile = StateController.Profile
	if not profile then
		return if isMusic then 0.5 else 0.7
	end
	return if isMusic then profile.Settings.MusicVolume else profile.Settings.SfxVolume
end

function AudioController.play(key: string, pitchVariance: number?)
	local id = AssetRegistry.sound(key)
	if not id then
		return
	end
	local sound = pool[key]
	if not sound then
		local created = Instance.new("Sound")
		created.Name = key
		created.SoundId = id
		created.Parent = SoundService
		pool[key] = created
		sound = created
	end
	local s = sound :: Sound
	s.Volume = volume(false)
	s.PlaybackSpeed = 1 + (math.random() - 0.5) * (pitchVariance or 0.08)
	s:Play()
end

function AudioController.refreshVolume()
	if music then
		music.Volume = volume(true) * 0.6
	end
end

function AudioController.init()
	local id = AssetRegistry.sound("Music")
	if id then
		local m = Instance.new("Sound")
		m.Name = "Music"
		m.SoundId = id
		m.Looped = true
		m.Parent = SoundService
		music = m
	end
end

function AudioController.start()
	StateController.waitForReady()
	AudioController.refreshVolume()
	if music then
		music:Play()
	end
	StateController.Changed:Connect(function(key)
		if key == "Settings" or key == "*" then
			AudioController.refreshVolume()
		end
	end)
end

return AudioController
