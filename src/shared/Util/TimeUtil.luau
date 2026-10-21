--!strict
-- UTC day/week boundaries used by daily rewards, quests and caches.

local TimeUtil = {}

local DAY = 86400

function TimeUtil.dayIndex(unix: number): number
	return math.floor(unix / DAY)
end

-- Weeks start Monday 00:00 UTC (unix day 0 was a Thursday).
function TimeUtil.weekIndex(unix: number): number
	return math.floor((math.floor(unix / DAY) + 3) / 7)
end

-- 1 = Monday ... 7 = Sunday
function TimeUtil.weekDay(unix: number): number
	return ((math.floor(unix / DAY) + 3) % 7) + 1
end

function TimeUtil.secondsUntilNextDay(unix: number): number
	return DAY - (unix % DAY)
end

function TimeUtil.secondsUntilNextWeek(unix: number): number
	local nextWeekStartDay = (TimeUtil.weekIndex(unix) + 1) * 7 - 3
	return nextWeekStartDay * DAY - unix
end

return TimeUtil
