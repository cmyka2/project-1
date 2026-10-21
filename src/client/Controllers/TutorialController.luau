--!strict
-- Tutorial guide card. Shows the current step from the replicated profile,
-- highlights the relevant HUD button, and lets the player advance info steps
-- or skip. Step completion itself is decided by the server.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("Config"):WaitForChild("GameConfig"))
local UI = script.Parent.Parent:WaitForChild("UI")
local Kit = require(UI:WaitForChild("Kit"))
local Theme = require(UI:WaitForChild("Theme"))
local StateController = require(script.Parent:WaitForChild("StateController"))
local UIController = require(script.Parent:WaitForChild("UIController"))

local C = Theme.Colors
local STEPS = GameConfig.Tutorial.Steps

local TutorialController = {}

local card: Frame? = nil

local function render()
	local profile = StateController.Profile
	local frame = card
	if not profile or not frame then
		return
	end
	local tut = profile.Tutorial
	local step = STEPS[tut.Step]
	if tut.Completed or not step then
		frame.Visible = false
		UIController.highlight(nil)
		return
	end
	frame.Visible = true
	Kit.clear(frame)
	local title = Kit.text({
		Text = string.format("📘 %s  (%d/%d)", step.Title, tut.Step, #STEPS),
		Font = Theme.Fonts.Title,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = C.Gold,
		Size = UDim2.new(1, -16, 0, 26),
		Position = UDim2.fromOffset(10, 6),
		MaxTextSize = 20,
		Parent = frame,
	})
	Kit.textStroke(title)
	Kit.text({
		Text = step.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Size = UDim2.new(1, -20, 0, 40),
		Position = UDim2.fromOffset(10, 34),
		MaxTextSize = 15,
		Parent = frame,
	})
	if step.Advance == "Info" or step.Advance == "OpenPanel" then
		Kit.button("Next ▶", "Good", function()
			UIController.call("TutorialNext")
		end, { Size = UDim2.fromOffset(110, 32), Position = UDim2.new(1, -230, 1, -38), Parent = frame })
	end
	Kit.button("Skip", "Ghost", function()
		if
			UIController.confirm("Skip tutorial?", "You can still find every feature from the menu.", "Skip")
		then
			UIController.call("TutorialSkip")
		end
	end, { Size = UDim2.fromOffset(100, 32), Position = UDim2.new(1, -110, 1, -38), Parent = frame })
	UIController.highlight(step.Panel)
end

function TutorialController.init() end

function TutorialController.start()
	card = Kit.frame({
		Name = "Tutorial",
		BackgroundColor3 = C.PanelDark,
		BackgroundTransparency = 0.05,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		Parent = UIController.slot("TopCenter"),
	})
	Kit.corner(card :: Frame)
	Kit.stroke(card :: Frame, C.Gold, 2)
	StateController.waitForReady()
	render()
	StateController.Changed:Connect(function(key)
		if key == "Tutorial" or key == "*" then
			render()
		end
	end)
	UIController.on("PanelOpened", function(id)
		local profile = StateController.Profile
		local step = profile and STEPS[profile.Tutorial.Step]
		if step and step.Advance == "OpenPanel" and step.Panel == id then
			UIController.call("TutorialNext")
		end
	end)
end

return TutorialController
