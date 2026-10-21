--!strict
-- Sprinting. The server sets the character's walk speed (base x skill bonuses)
-- and replicates WalkSpeed and SprintSpeed in Derived; this controller only
-- switches the local Humanoid between the two (characters are client-owned, so
-- the server's speed telemetry already allows for sprinting). Keyboard sprint
-- keys are held; the gamepad key and the on-screen touch button toggle.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("Config"):WaitForChild("GameConfig"))
local UI = script.Parent.Parent:WaitForChild("UI")
local Theme = require(UI:WaitForChild("Theme"))
local StateController = require(script.Parent:WaitForChild("StateController"))

local C = Theme.Colors

local MovementController = {}

local ACTION = "Sprint"
local player = Players.LocalPlayer
local held = false -- a keyboard sprint key is down
local toggled = false -- the touch button or gamepad key toggled sprint on
local humanoidConn: RBXScriptConnection? = nil

function MovementController.isSprinting(): boolean
	return held or toggled
end

local function humanoid(): Humanoid?
	local character = player.Character
	return if character then character:FindFirstChildOfClass("Humanoid") else nil
end

local function apply()
	local derived = StateController.Derived
	local h = humanoid()
	if derived and h then
		local speed = if MovementController.isSprinting() then derived.SprintSpeed else derived.WalkSpeed
		if h.WalkSpeed ~= speed then
			h.WalkSpeed = speed
		end
	end
	local button = ContextActionService:GetButton(ACTION)
	if button then
		button.ImageColor3 = if toggled then C.Good else Color3.new(1, 1, 1)
	end
end

local function onAction(
	_name: string,
	state: Enum.UserInputState,
	input: InputObject
): Enum.ContextActionResult
	if input.UserInputType == Enum.UserInputType.Keyboard then
		held = state == Enum.UserInputState.Begin
	elseif state == Enum.UserInputState.Begin then
		toggled = not toggled
	end
	apply()
	-- Sink so Shift does not also toggle Roblox's shift lock (disabled in StarterPlayer).
	return Enum.ContextActionResult.Sink
end

local function watchCharacter(character: Model)
	if humanoidConn then
		humanoidConn:Disconnect()
		humanoidConn = nil
	end
	toggled = false
	local h = character:WaitForChild("Humanoid", 10)
	if h and h:IsA("Humanoid") then
		-- the server re-applies walk speed on spawn and when skills change
		humanoidConn = h:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
			if MovementController.isSprinting() then
				apply()
			end
		end)
	end
	apply()
end

function MovementController.init()
	ContextActionService:BindActionAtPriority(
		ACTION,
		onAction,
		true,
		Enum.ContextActionPriority.High.Value,
		table.unpack(GameConfig.Movement.SprintKeys)
	)
	ContextActionService:SetTitle(ACTION, "Sprint")
	UserInputService.WindowFocusReleased:Connect(function()
		held = false
		apply()
	end)
	StateController.Changed:Connect(function(key)
		if key == "*" or key == "Derived" then
			apply()
		end
	end)
end

function MovementController.start()
	player.CharacterAdded:Connect(watchCharacter)
	local character = player.Character
	if character then
		watchCharacter(character)
	end
end

return MovementController
