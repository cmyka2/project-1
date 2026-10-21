--!strict
-- Live events. Activity is always computed from server time (Util/EventSchedule),
-- so expired events stop applying the moment they end. This service announces
-- start/end transitions, refreshes everyone's derived state and updates the
-- plaza event board.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EventConfig = require(Shared:WaitForChild("Config"):WaitForChild("EventConfig"))
local EventSchedule = require(Shared:WaitForChild("Util"):WaitForChild("EventSchedule"))
local Format = require(Shared:WaitForChild("Util"):WaitForChild("Format"))
local Modules = script.Parent.Parent:WaitForChild("Modules")
local NetServer = require(Modules:WaitForChild("NetServer"))
local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))

local EventService = {}

local active: { [string]: boolean } = {}

function EventService.isActive(eventId: string): boolean
	return EventSchedule.isEventActive(eventId, os.time())
end

function EventService.activeIds(): { string }
	return EventSchedule.activeIds(os.time())
end

local function updateBoards()
	local now = os.time()
	local lines = {}
	for _, id in EventSchedule.activeIds(now) do
		local event = EventConfig.Events[id]
		table.insert(
			lines,
			event.Glyph
				.. " "
				.. event.DisplayName
				.. " ("
				.. Format.duration(EventSchedule.secondsRemaining(id, now))
				.. ")"
		)
	end
	local text = if #lines > 0 then table.concat(lines, "\n") else "No live events right now"
	for _, board in CollectionService:GetTagged("EventBoard") do
		local gui = board:FindFirstChild("Label")
		local label = gui and gui:FindFirstChild("Text")
		if label and label:IsA("TextLabel") then
			label.Text = "🎉 Live Events\n" .. text
		end
	end
end

function EventService.check()
	local now = os.time()
	local current: { [string]: boolean } = {}
	for _, id in EventSchedule.activeIds(now) do
		current[id] = true
	end
	local changed = false
	for id in current do
		if not active[id] then
			changed = true
			local event = EventConfig.Events[id]
			NetServer.pushAll(
				"Announce",
				event.Glyph .. " " .. event.DisplayName .. " has started!",
				event.Color,
				true
			)
		end
	end
	for id in active do
		if not current[id] then
			changed = true
			local event = EventConfig.Events[id]
			if event then
				NetServer.pushAll(
					"Announce",
					event.DisplayName .. " has ended. Thanks for playing!",
					event.Color,
					false
				)
			end
		end
	end
	active = current
	if changed then
		for _, player in PlayerDataService.players() do
			PlayerDataService.invalidateMods(player)
			PlayerDataService.changed(player, "__Derived")
		end
	end
	updateBoards()
end

function EventService.init()
	for _, id in EventSchedule.activeIds(os.time()) do
		active[id] = true
	end
end

function EventService.start()
	updateBoards()
	while true do
		task.wait(30)
		EventService.check()
	end
end

return EventService
