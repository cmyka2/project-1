--!strict
-- The single client entry point. Controllers are initialized in order
-- (init: register panels and remote listeners, no yielding) and then started.

local Players = game:GetService("Players")

local Client = script.Parent
local Controllers = Client:WaitForChild("Controllers")

local ORDER = {
	"StateController",
	"UIController",
	"AudioController",
	"EffectsController",
	"RollController",
	"InventoryController",
	"TycoonController",
	"CombatController",
	"ProgressionController",
	"ShopController",
	"QuestController",
	"SocialController",
	"SettingsController",
	"TutorialController",
	"InteractionController",
	"MovementController",
	"CheatController",
}

type Controller = { init: (() -> ...any)?, start: (() -> ...any)? }

local loaded: { { name: string, controller: Controller } } = {}
for _, name in ORDER do
	local module = Controllers:FindFirstChild(name)
	if module and module:IsA("ModuleScript") then
		local ok, result = pcall(require, module)
		if ok then
			table.insert(loaded, { name = name, controller = result :: Controller })
		else
			warn("[Client] failed to load " .. name .. ": " .. tostring(result))
		end
	end
end

for _, entry in loaded do
	local init = entry.controller.init
	if init then
		local ok, err = pcall(init)
		if not ok then
			warn("[Client] " .. entry.name .. ".init failed: " .. tostring(err))
		end
	end
end

for _, entry in loaded do
	local start = entry.controller.start
	if start then
		task.spawn(function()
			local ok, err = pcall(start)
			if not ok then
				warn("[Client] " .. entry.name .. ".start failed: " .. tostring(err))
			end
		end)
	end
end

print("[MonsterRoll] client started for " .. Players.LocalPlayer.Name)
