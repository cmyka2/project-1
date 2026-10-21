--!strict
-- Server-only gameplay event bus. Services fire validated, server-witnessed
-- events here; quests, achievements, the tutorial and analytics listen.
-- Clients can never fire these.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Signal"))

export type EventData = { [string]: any }

local GameEvents = {}

GameEvents.Fired = Signal.new() :: Signal.Signal<Player, string, EventData>

function GameEvents.fire(player: Player, eventType: string, data: EventData?)
	GameEvents.Fired:Fire(player, eventType, data or {})
end

return GameEvents
