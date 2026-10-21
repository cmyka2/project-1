--!strict
-- QA panel. Only appears when the server says this player is authorized
-- (Studio, or an allowlisted UserId); the server re-checks every command.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local UI = script.Parent.Parent:WaitForChild("UI")
local Kit = require(UI:WaitForChild("Kit"))
local UIController = require(script.Parent:WaitForChild("UIController"))

local CheatController = {}

local commands: { string } = {}

local function buildPanel(body: Frame)
	local arg = Kit.textbox({
		PlaceholderText = "Argument (number or id), optional",
		Size = UDim2.new(1, 0, 0, 40),
		Parent = body,
	})
	local grid =
		Kit.scroll({ Size = UDim2.new(1, 0, 1, -50), Position = UDim2.fromOffset(0, 50), Parent = body })
	Kit.grid(grid, UDim2.new(1 / 3, -8, 0, 44), 8)
	for i, name in commands do
		Kit.button(name, "Dark", function()
			local text = arg.Text
			local value: any = tonumber(text) or (if text ~= "" then text else nil)
			local r = UIController.call("Cheat", name, value)
			if r.ok and r.data then
				UIController.toast("success", "[QA] " .. tostring(r.data.Message))
			end
		end, { LayoutOrder = i, Parent = grid })
	end
end

function CheatController.init()
	Net.on("CheatAccess", function(allowed: boolean, list: { string }?)
		if not allowed then
			return
		end
		commands = list or {}
		UIController.registerPanel({ Id = "Cheats", Title = "QA Tools", Glyph = "🛠", Build = buildPanel })
		Kit.button("🛠 QA", "Bad", function()
			UIController.toggle("Cheats")
		end, { Size = UDim2.fromOffset(80, 34), Parent = UIController.slot("TopLeft") })
	end)
end

return CheatController
