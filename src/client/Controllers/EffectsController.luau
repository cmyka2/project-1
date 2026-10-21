--!strict
-- Client-only visual effects: screen flashes, camera shake, floating text,
-- and per-region atmosphere (lighting tweens when the player stands on a
-- region island). Effects never influence gameplay.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RegionConfig = require(Shared:WaitForChild("Config"):WaitForChild("RegionConfig"))
local GameConfig = require(Shared:WaitForChild("Config"):WaitForChild("GameConfig"))
local UI = script.Parent.Parent:WaitForChild("UI")
local Kit = require(UI:WaitForChild("Kit"))
local Theme = require(UI:WaitForChild("Theme"))
local StateController = require(script.Parent:WaitForChild("StateController"))
local UIController = require(script.Parent:WaitForChild("UIController"))

local EffectsController = {}

local player = Players.LocalPlayer
local shakeUntil = 0
local shakeStrength = 0
local currentRegion: string? = "none"
local defaults = {
	Ambient = Lighting.Ambient,
	FogColor = Lighting.FogColor,
	FogEnd = Lighting.FogEnd,
}

local function reduced(): boolean
	local profile = StateController.Profile
	return profile ~= nil and profile.Settings.ReducedEffects
end

function EffectsController.flash(color: Color3, strength: number?)
	if reduced() then
		return
	end
	local f = Kit.frame({
		BackgroundColor3 = color,
		BackgroundTransparency = 1 - (strength or 0.4),
		Size = UDim2.fromScale(1, 1),
		ZIndex = 300,
		Parent = UIController.overlay(),
	})
	Kit.tween(f, Theme.Tween.Slow, { BackgroundTransparency = 1 })
	task.delay(0.7, function()
		f:Destroy()
	end)
end

function EffectsController.shake(seconds: number, strength: number?)
	if reduced() then
		return
	end
	shakeUntil = os.clock() + seconds
	shakeStrength = strength or 0.35
end

-- Floating text that rises and fades (e.g. "+125 coins").
function EffectsController.floatText(parent: GuiObject, text: string, color: Color3)
	local t = Kit.text({
		Text = text,
		Font = Theme.Fonts.Title,
		TextColor3 = color,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.4),
		Size = UDim2.fromScale(1.4, 0.4),
		ZIndex = 60,
		MaxTextSize = 30,
		Parent = parent,
	})
	Kit.textStroke(t, Color3.new(0, 0, 0), 2)
	Kit.tween(
		t,
		TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Position = UDim2.fromScale(0.5, -0.2), TextTransparency = 1 }
	)
	task.delay(1, function()
		t:Destroy()
	end)
end

local function regionAt(position: Vector3): string?
	local half = GameConfig.World.RegionIslandSize / 2 + 30
	for _, id in RegionConfig.Order do
		local region = RegionConfig.Regions[id]
		local spacing = GameConfig.World.RegionIslandSpacing
		local col = (region.Index - 1) % 3 - 1
		local row = math.floor((region.Index - 1) / 3) - 1
		local center = Vector3.new(col * spacing, GameConfig.World.RegionIslandHeight, row * spacing)
		local d = position - center
		if math.abs(d.X) <= half and math.abs(d.Z) <= half and d.Y > -60 and d.Y < 220 then
			return id
		end
	end
	return nil
end

local function applyAtmosphere(regionId: string?)
	local info = TweenInfo.new(1.5, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
	if regionId then
		local theme = RegionConfig.Regions[regionId].Theme
		TweenService:Create(Lighting, info, {
			Ambient = theme.Sky:Lerp(Color3.new(0, 0, 0), 0.4),
			FogColor = theme.Fog,
			FogEnd = 900,
		}):Play()
		UIController.toast("info", "Entered " .. RegionConfig.Regions[regionId].DisplayName)
	else
		TweenService:Create(Lighting, info, defaults):Play()
	end
end

function EffectsController.init() end

function EffectsController.start()
	RunService.RenderStepped:Connect(function()
		local camera = Workspace.CurrentCamera
		if camera and os.clock() < shakeUntil then
			local s = shakeStrength
			camera.CFrame *= CFrame.new((math.random() - 0.5) * s, (math.random() - 0.5) * s, 0)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") then
				local region = regionAt(root.Position)
				if region ~= currentRegion then
					currentRegion = region
					applyAtmosphere(region)
				end
			end
		end
	end)
end

return EffectsController
