--!strict
-- World interactions. ProximityPrompts carry an Action attribute (set by the
-- server's WorldBuilder); this controller turns them into UI or requests.
-- It also personalizes prompts locally: slot pads on other players' plots
-- become "Inspect", and region gates show their lock state.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local RegionConfig = require(Config:WaitForChild("RegionConfig"))
local MonsterConfig = require(Config:WaitForChild("MonsterConfig"))
local EnemyConfig = require(Config:WaitForChild("EnemyConfig"))
local StateController = require(script.Parent:WaitForChild("StateController"))
local UIController = require(script.Parent:WaitForChild("UIController"))
local TycoonController = require(script.Parent:WaitForChild("TycoonController"))

local player = Players.LocalPlayer

local InteractionController = {}

local function myPlot(): number?
	local d = StateController.Derived
	return d and d.PlotIndex
end

local function plotModel(index: number): Model?
	local world = Workspace:FindFirstChild("World")
	local plots = world and world:FindFirstChild("PlayerBasePlots")
	local m = plots and plots:FindFirstChild("Plot" .. index)
	return if m and m:IsA("Model") then m else nil
end

-- Client-side movement between floors of a plot (movement is client-owned in Roblox anyway;
-- nothing gameplay-relevant depends on being on a floor).
local function useElevator(plotIndex: number, floor: number)
	local model = plotModel(plotIndex)
	local character = player.Character
	if not model or not character then
		return
	end
	local unlocked = tonumber(model:GetAttribute("UnlockedFloors")) or 1
	local target = floor + 1
	if target > unlocked then
		target = 1
	end
	if target == floor then
		if unlocked <= 1 then
			UIController.toast("info", "Floor 2 unlocks at Rebirth 6.")
		end
		return
	end
	local pad = model:FindFirstChild("Elevator" .. target)
	if pad and pad:IsA("BasePart") then
		character:PivotTo(pad.CFrame * CFrame.new(0, 4, 4))
	end
end

local function onPrompt(prompt: ProximityPrompt)
	local action = prompt:GetAttribute("Action")
	if action == "Panel" then
		local panel = prompt:GetAttribute("Panel")
		if typeof(panel) == "string" then
			UIController.open(panel)
		end
	elseif action == "Dice" then
		local diceId = prompt:GetAttribute("DiceId")
		UIController.open("Roll", { DiceId = diceId })
	elseif action == "Slot" then
		local plotIndex = prompt:GetAttribute("PlotIndex")
		local slotId = prompt:GetAttribute("SlotId")
		if typeof(slotId) ~= "number" then
			return
		end
		if plotIndex == myPlot() then
			TycoonController.manageSlot(slotId)
		else
			local monsterId = nil
			local model = if typeof(plotIndex) == "number" then plotModel(plotIndex) else nil
			local displays = model and model:FindFirstChild("Displays")
			local display = displays and displays:FindFirstChild("Slot_" .. slotId)
			if display then
				monsterId = display:GetAttribute("MonsterId")
			end
			local def = if typeof(monsterId) == "string" then MonsterConfig.Monsters[monsterId] else nil
			local owner = model and model:GetAttribute("OwnerName")
			UIController.toast(
				"info",
				if def
					then string.format(
						"%s's %s (%s)",
						tostring(owner or "Someone"),
						def.DisplayName,
						def.Rarity
					)
					else "An empty slot."
			)
		end
	elseif action == "Portal" then
		local regionId = prompt:GetAttribute("RegionId")
		local profile = StateController.Profile
		if typeof(regionId) == "string" and profile then
			if profile.Progression.UnlockedRegions[regionId] then
				UIController.call("TravelToRegion", regionId)
			else
				UIController.open("Regions")
			end
		end
	elseif action == "Hub" then
		UIController.call("TravelToHub", false)
	elseif action == "Cache" then
		local cacheId = prompt:GetAttribute("CacheId")
		if typeof(cacheId) == "string" then
			local r = UIController.call("ClaimCache", cacheId)
			if r.ok then
				UIController.toast(
					"reward",
					"Treasure! " .. tostring(r.data and r.data.Coins and ("💰 " .. r.data.Coins) or "")
				)
			end
		end
	elseif action == "Encounter" then
		local encounterId = prompt:GetAttribute("EncounterId")
		local encounter = if typeof(encounterId) == "string" then EnemyConfig.Encounters[encounterId] else nil
		if encounter then
			if
				UIController.confirm(
					"Battle: " .. encounter.DisplayName,
					"Fight with your current team?",
					"Fight!"
				)
			then
				UIController.call("StartBattle", encounter.Id)
			end
		end
	elseif action == "Elevator" then
		local plotIndex = prompt:GetAttribute("PlotIndex")
		local floor = prompt:GetAttribute("Floor")
		if typeof(plotIndex) == "number" and typeof(floor) == "number" then
			useElevator(plotIndex, floor)
		end
	end
end

-- Local prompt text: other players' slot pads become "Inspect".
local function personalize(prompt: ProximityPrompt)
	if prompt:GetAttribute("Action") == "Slot" then
		local plotIndex = prompt:GetAttribute("PlotIndex")
		if plotIndex ~= myPlot() then
			prompt.ActionText = "Inspect"
		end
	end
end

local function refreshGates()
	local profile = StateController.Profile
	local world = Workspace:FindFirstChild("World")
	local gates = world and world:FindFirstChild("RegionGates")
	if not profile or not gates then
		return
	end
	for _, gate in gates:GetChildren() do
		local regionId = gate:GetAttribute("RegionId")
		local region = if typeof(regionId) == "string" then RegionConfig.Regions[regionId] else nil
		if region then
			local unlocked = profile.Progression.UnlockedRegions[region.Id] == true
			local lintel = gate:FindFirstChild("Lintel")
			local billboard = lintel and lintel:FindFirstChild("LockLabel")
			local text = billboard and billboard:FindFirstChild("Text")
			if text and text:IsA("TextLabel") then
				text.Text = if unlocked
					then "✓ Unlocked"
					else "🔒 " .. (if region.UnlockCost > 0 then "💰" .. region.UnlockCost else "")
			end
			local portal = gate:FindFirstChild("Portal")
			local prompt = portal and portal:FindFirstChildOfClass("ProximityPrompt")
			if prompt then
				prompt.ActionText = if unlocked then "Travel" else "View requirements"
			end
		end
	end
end

function InteractionController.init()
	ProximityPromptService.PromptTriggered:Connect(onPrompt)
	ProximityPromptService.PromptShown:Connect(function(prompt)
		personalize(prompt)
	end)
end

function InteractionController.start()
	StateController.waitForReady()
	refreshGates()
	StateController.Changed:Connect(function(key)
		if key == "Progression" or key == "*" then
			refreshGates()
		end
	end)
end

return InteractionController
