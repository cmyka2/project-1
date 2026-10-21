--!strict
-- Determines which live events are active at a given unix time (pure).

local EventConfig = require(script.Parent.Parent.Config.EventConfig)
local TimeUtil = require(script.Parent.TimeUtil)

local EventSchedule = {}

function EventSchedule.isActive(event: EventConfig.EventDef, now: number): boolean
	local schedule = event.Schedule
	if schedule.Kind == "Fixed" then
		local startUtc = schedule.StartUtc or 0
		local endUtc = schedule.EndUtc or 0
		return now >= startUtc and now < endUtc
	elseif schedule.Kind == "Weekly" then
		local days = schedule.WeekDays
		if not days then
			return false
		end
		return table.find(days, TimeUtil.weekDay(now)) ~= nil
	end
	return false
end

function EventSchedule.activeIds(now: number): { string }
	local out = {}
	for _, id in EventConfig.Order do
		local event = EventConfig.Events[id]
		if event and EventSchedule.isActive(event, now) then
			table.insert(out, id)
		end
	end
	return out
end

function EventSchedule.isEventActive(eventId: string, now: number): boolean
	local event = EventConfig.Events[eventId]
	return event ~= nil and EventSchedule.isActive(event, now)
end

-- Seconds until the event ends (Fixed) or until the current active day ends (Weekly).
function EventSchedule.secondsRemaining(eventId: string, now: number): number
	local event = EventConfig.Events[eventId]
	if not event or not EventSchedule.isActive(event, now) then
		return 0
	end
	if event.Schedule.Kind == "Fixed" then
		return (event.Schedule.EndUtc or now) - now
	end
	return TimeUtil.secondsUntilNextDay(now)
end

return EventSchedule
