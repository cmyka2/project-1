--!strict
-- Quests: main story chain, daily and weekly rotations (UTC), region quests
-- and event quests. Progress comes only from server-side GameEvents; claims
-- are validated (complete, unclaimed, event still active) and idempotent.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Util = Shared:WaitForChild("Util")
local QuestConfig = require(Config:WaitForChild("QuestConfig"))
local EventConfig = require(Config:WaitForChild("EventConfig"))
local TimeUtil = require(Util:WaitForChild("TimeUtil"))
local EventSchedule = require(Util:WaitForChild("EventSchedule"))
local Guard = require(Util:WaitForChild("Guard"))
local Types = require(Shared:WaitForChild("Types"))
local Modules = script.Parent.Parent:WaitForChild("Modules")
local NetServer = require(Modules:WaitForChild("NetServer"))
local GameEvents = require(Modules:WaitForChild("GameEvents"))
local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))
local EconomyService = require(script.Parent:WaitForChild("EconomyService"))

type Profile = Types.Profile
type QuestProgress = Types.QuestProgress

local QuestService = {}

local function pick(pool: { string }, count: number, seed: number): { QuestProgress }
	local shuffled = table.clone(pool)
	local r = Random.new(seed)
	for i = #shuffled, 2, -1 do
		local j = r:NextInteger(1, i)
		shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
	end
	local out: { QuestProgress } = {}
	for i = 1, math.min(count, #shuffled) do
		table.insert(out, { Id = shuffled[i], Progress = 0, Completed = false, Claimed = false })
	end
	return out
end

-- Makes sure rotations and region/event quest entries are current.
function QuestService.ensure(player: Player, profile: Profile): boolean
	local q = profile.Quests
	local now = os.time()
	local changed = false
	local day = TimeUtil.dayIndex(now)
	if q.DailyKey ~= day then
		q.DailyKey = day
		q.Daily = pick(QuestConfig.DailyPool, QuestConfig.DailyQuestCount, player.UserId * 31 + day)
		changed = true
	end
	local week = TimeUtil.weekIndex(now)
	if q.WeeklyKey ~= week then
		q.WeeklyKey = week
		q.Weekly = pick(QuestConfig.WeeklyPool, QuestConfig.WeeklyQuestCount, player.UserId * 17 + week)
		changed = true
	end
	for _, id in QuestConfig.RegionQuests do
		local def = QuestConfig.Quests[id]
		if
			def.RequiredRegion
			and profile.Progression.UnlockedRegions[def.RequiredRegion]
			and not q.Region[id]
		then
			q.Region[id] = { Id = id, Progress = 0, Completed = false, Claimed = false }
			changed = true
		end
	end
	for _, eventId in EventSchedule.activeIds(now) do
		local event = EventConfig.Events[eventId]
		for _, id in event.QuestIds do
			if QuestConfig.Quests[id] and not q.Event[id] then
				q.Event[id] = { Id = id, Progress = 0, Completed = false, Claimed = false }
				changed = true
			end
		end
	end
	if changed then
		PlayerDataService.changed(player, "Quests")
	end
	return changed
end

function QuestService.target(profile: Profile, def: QuestConfig.QuestDef): number
	local t = def.Objective.Target
	if def.Objective.TargetScaled then
		t *= EconomyService.regionScale(profile)
	end
	return t
end

-- How much an event advances an objective (0 = not relevant).
function QuestService.amountFor(
	objective: QuestConfig.Objective,
	eventType: string,
	data: GameEvents.EventData
): number
	if objective.Type ~= eventType then
		return 0
	end
	if objective.Dice and data.Dice ~= objective.Dice then
		return 0
	end
	if objective.Region and data.Region ~= objective.Region then
		return 0
	end
	if eventType == "ObtainRarity" then
		return if (data.Tier or 0) >= (objective.MinTier or 1) then 1 else 0
	elseif eventType == "EarnCoins" then
		return data.Amount or 0
	elseif
		eventType == "Roll"
		or eventType == "Craft"
		or eventType == "OpenChest"
		or eventType == "SellMonster"
		or eventType == "Fuse"
	then
		return data.Count or 1
	end
	return 1
end

local function progress(
	player: Player,
	profile: Profile,
	entry: QuestProgress,
	eventType: string,
	data: GameEvents.EventData
): boolean
	if entry.Completed then
		return false
	end
	local def = QuestConfig.Quests[entry.Id]
	if not def then
		return false
	end
	local amount = QuestService.amountFor(def.Objective, eventType, data)
	if amount <= 0 then
		return false
	end
	entry.Progress += amount
	local target = QuestService.target(profile, def)
	if entry.Progress >= target then
		entry.Progress = target
		entry.Completed = true
		NetServer.notify(player, "success", "Quest complete: " .. def.Title .. "!")
	end
	return true
end

function QuestService.onEvent(player: Player, eventType: string, data: GameEvents.EventData)
	local profile = PlayerDataService.get(player)
	if not profile then
		return
	end
	local q = profile.Quests
	local changed = false
	-- main quest
	local mainId = QuestConfig.MainOrder[q.MainIndex]
	if mainId then
		local def = QuestConfig.Quests[mainId]
		local target = QuestService.target(profile, def)
		if q.MainProgress < target then
			local amount = QuestService.amountFor(def.Objective, eventType, data)
			if amount > 0 then
				q.MainProgress = math.min(target, q.MainProgress + amount)
				changed = true
				if q.MainProgress >= target then
					NetServer.notify(
						player,
						"success",
						"Story quest complete: " .. def.Title .. "! Claim your reward."
					)
				end
			end
		end
	end
	for _, entry in q.Daily do
		changed = progress(player, profile, entry, eventType, data) or changed
	end
	for _, entry in q.Weekly do
		changed = progress(player, profile, entry, eventType, data) or changed
	end
	for _, entry in q.Region do
		changed = progress(player, profile, entry, eventType, data) or changed
	end
	local now = os.time()
	for id, entry in q.Event do
		local def = QuestConfig.Quests[id]
		if def and def.EventId and EventSchedule.isEventActive(def.EventId, now) then
			changed = progress(player, profile, entry, eventType, data) or changed
		end
	end
	if eventType == "UnlockRegion" then
		changed = QuestService.ensure(player, profile) or changed
	end
	if changed then
		PlayerDataService.changed(player, "Quests")
	end
end

function QuestService.claim(player: Player, questId: string): ({ [string]: number }?, string?)
	local profile = PlayerDataService.get(player)
	local def = QuestConfig.Quests[questId]
	if not profile or not def then
		return nil, "invalid"
	end
	local q = profile.Quests
	local bonus = 1 + (PlayerDataService.mods(player).QuestRewards or 0)
	if def.Category == "Main" then
		if QuestConfig.MainOrder[q.MainIndex] ~= questId then
			return nil, "That isn't your current story quest."
		end
		if q.MainProgress < QuestService.target(profile, def) then
			return nil, "Not complete yet."
		end
		q.MainIndex += 1
		q.MainProgress = 0
		q.Completed[questId] = true
		PlayerDataService.changed(player, "Quests")
		return EconomyService.grantReward(player, def.Reward, "Quest", bonus), nil
	end
	local entry: QuestProgress? = nil
	if def.Category == "Daily" then
		for _, e in q.Daily do
			if e.Id == questId then
				entry = e
			end
		end
	elseif def.Category == "Weekly" then
		for _, e in q.Weekly do
			if e.Id == questId then
				entry = e
			end
		end
	elseif def.Category == "Region" then
		entry = q.Region[questId]
	elseif def.Category == "Event" then
		entry = q.Event[questId]
		if def.EventId and not EventSchedule.isEventActive(def.EventId, os.time()) then
			return nil, "That event has ended."
		end
	end
	if not entry then
		return nil, "That quest isn't active."
	end
	if not entry.Completed then
		return nil, "Not complete yet."
	end
	if entry.Claimed then
		return nil, "Already claimed."
	end
	entry.Claimed = true
	q.Completed[questId] = true
	PlayerDataService.changed(player, "Quests")
	return EconomyService.grantReward(player, def.Reward, "Quest", bonus), nil
end

function QuestService.init()
	GameEvents.Fired:Connect(function(player, eventType, data)
		QuestService.onEvent(player, eventType, data)
	end)
	NetServer.handle("ClaimQuest", { Rate = 4, Burst = 8 }, function(player, rawId)
		local id = Guard.string(rawId)
		if not id then
			return NetServer.invalid(player, "ClaimQuest")
		end
		local summary, err = QuestService.claim(player, id)
		if not summary then
			if err == "invalid" then
				return NetServer.invalid(player, "ClaimQuest")
			end
			return NetServer.fail(err or "Can't claim.")
		end
		return NetServer.ok(summary)
	end)
end

function QuestService.onPlayerReady(player: Player, profile: Profile)
	QuestService.ensure(player, profile)
end

function QuestService.start()
	-- daily/weekly rollover for players who stay online across midnight UTC
	while true do
		task.wait(60)
		for _, player in PlayerDataService.players() do
			local profile = PlayerDataService.get(player)
			if profile then
				QuestService.ensure(player, profile)
			end
		end
	end
end

return QuestService
