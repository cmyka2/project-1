--!strict
-- Quests (story, daily, weekly, region, event), achievements, the daily
-- login calendar, live events and the HUD quest tracker.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Util = Shared:WaitForChild("Util")
local QuestConfig = require(Config:WaitForChild("QuestConfig"))
local EventConfig = require(Config:WaitForChild("EventConfig"))
local RegionConfig = require(Config:WaitForChild("RegionConfig"))
local Format = require(Util:WaitForChild("Format"))
local TimeUtil = require(Util:WaitForChild("TimeUtil"))
local EventSchedule = require(Util:WaitForChild("EventSchedule"))
local Types = require(Shared:WaitForChild("Types"))
local UI = script.Parent.Parent:WaitForChild("UI")
local Kit = require(UI:WaitForChild("Kit"))
local Theme = require(UI:WaitForChild("Theme"))
local Icons = require(UI:WaitForChild("Icons"))
local StateController = require(script.Parent:WaitForChild("StateController"))
local UIController = require(script.Parent:WaitForChild("UIController"))
local AudioController = require(script.Parent:WaitForChild("AudioController"))

local C = Theme.Colors

local QuestController = {}

local renderers: { [string]: () -> () } = {}
local questTab = 1
local tracker: Frame? = nil

local function regionScale(profile: Types.Profile): number
	local region = RegionConfig.Regions[profile.Progression.HighestRegion]
	return if region then region.IncomeScale else 1
end

local function rewardText(reward: QuestConfig.Reward, profile: Types.Profile): string
	local parts = {}
	local coins = (reward.Coins or 0) + (reward.CoinsScaled or 0) * regionScale(profile)
	if coins > 0 then
		table.insert(parts, "💰" .. Format.number(coins))
	end
	if reward.Gems then
		table.insert(parts, "💎" .. reward.Gems)
	end
	if reward.AscensionPoints then
		table.insert(parts, "🌟" .. reward.AscensionPoints)
	end
	if reward.EventTokens then
		table.insert(parts, "🎟" .. reward.EventTokens)
	end
	local materials: { [string]: number } = reward.Materials or {}
	for id, n in materials do
		table.insert(parts, Icons.rewardLabel("Material:" .. id, n, Format.number))
	end
	local consumables: { [string]: number } = reward.Consumables or {}
	for id, n in consumables do
		table.insert(parts, Icons.rewardLabel("Consumable:" .. id, n, Format.number))
	end
	local chests: { [string]: number } = reward.Chests or {}
	for id, n in chests do
		table.insert(parts, Icons.rewardLabel("Chest:" .. id, n, Format.number))
	end
	return table.concat(parts, "  ")
end

local function target(def: QuestConfig.QuestDef, profile: Types.Profile): number
	local t = def.Objective.Target
	if def.Objective.TargetScaled then
		t *= regionScale(profile)
	end
	return t
end

local function claim(questId: string)
	local result = UIController.call("ClaimQuest", questId)
	if result.ok then
		AudioController.play("Achievement")
		UIController.toast("reward", "Reward claimed!")
	end
end

local function questRow(
	parent: Instance,
	def: QuestConfig.QuestDef,
	progress: number,
	completed: boolean,
	claimed: boolean,
	order: number,
	profile: Types.Profile
)
	local row = Kit.card({ Size = UDim2.new(1, -8, 0, 84), LayoutOrder = order, Parent = parent })
	Kit.stroke(
		row,
		if claimed then C.Disabled elseif completed then C.Gold else C.Stroke,
		if completed and not claimed then 3 else 1
	)
	Kit.text({
		Text = def.Title,
		Font = Theme.Fonts.Title,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -170, 0, 24),
		Position = UDim2.fromOffset(10, 4),
		MaxTextSize = 18,
		Parent = row,
	})
	Kit.text({
		Text = def.Description,
		TextColor3 = C.Muted,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -170, 0, 18),
		Position = UDim2.fromOffset(10, 28),
		MaxTextSize = 14,
		Parent = row,
	})
	local t = target(def, profile)
	local _, set = Kit.progress(
		row,
		if completed then C.Gold else C.Accent,
		{ Size = UDim2.new(1, -180, 0, 16), Position = UDim2.fromOffset(10, 50) }
	)
	set(progress / math.max(t, 1), Format.number(math.min(progress, t)) .. " / " .. Format.number(t))
	Kit.text({
		Text = rewardText(def.Reward, profile),
		TextColor3 = C.Gold,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -180, 0, 14),
		Position = UDim2.fromOffset(10, 68),
		MaxTextSize = 13,
		Parent = row,
	})
	local b = Kit.button(
		if claimed then "Claimed ✓" elseif completed then "Claim!" else "In progress",
		if completed and not claimed then "Gold" else "Dark",
		function()
			claim(def.Id)
		end,
		{ Size = UDim2.fromOffset(150, 48), Position = UDim2.new(1, -158, 0.5, -24), Parent = row }
	)
	Kit.setEnabled(b, completed and not claimed)
end

local TABS = { "📖 Story", "☀ Daily", "📅 Weekly", "🗺 Region", "🎉 Event" }

local function buildQuests(body: Frame)
	local content =
		Kit.scroll({ Size = UDim2.new(1, 0, 1, -46), Position = UDim2.fromOffset(0, 46), Parent = body })
	Kit.list(content, Enum.FillDirection.Vertical, 6)
	local render: () -> ()
	local _, selectTab = Kit.tabs(body, TABS, function(index)
		questTab = index
		render()
	end)
	render = function()
		local profile = StateController.Profile
		if not profile then
			return
		end
		Kit.clear(content)
		local q = profile.Quests
		local now = StateController.serverTime()
		if questTab == 1 then
			local id = QuestConfig.MainOrder[q.MainIndex]
			if id then
				local def = QuestConfig.Quests[id]
				questRow(
					content,
					def,
					q.MainProgress,
					q.MainProgress >= target(def, profile),
					false,
					1,
					profile
				)
				Kit.text({
					Text = string.format(
						"Story progress: chapter %d of %d",
						q.MainIndex,
						#QuestConfig.MainOrder
					),
					TextColor3 = C.Muted,
					Size = UDim2.new(1, -8, 0, 24),
					LayoutOrder = 2,
					MaxTextSize = 15,
					Parent = content,
				})
				for offset = 1, 3 do
					local nextId = QuestConfig.MainOrder[q.MainIndex + offset]
					if nextId then
						local nextDef = QuestConfig.Quests[nextId]
						Kit.text({
							Text = "🔒 Next: " .. nextDef.Title .. " — " .. nextDef.Description,
							TextColor3 = C.Muted,
							TextXAlignment = Enum.TextXAlignment.Left,
							Size = UDim2.new(1, -8, 0, 22),
							LayoutOrder = 2 + offset,
							MaxTextSize = 14,
							Parent = content,
						})
					end
				end
			else
				Kit.text({
					Text = "🏆 You've completed the whole story. Legendary!",
					Size = UDim2.new(1, -8, 0, 40),
					Parent = content,
				})
			end
		elseif questTab == 2 or questTab == 3 then
			local list: { Types.QuestProgress } = if questTab == 2 then q.Daily else q.Weekly
			local resetIn = if questTab == 2
				then TimeUtil.secondsUntilNextDay(now)
				else TimeUtil.secondsUntilNextWeek(now)
			Kit.text({
				Text = "New quests in " .. Format.duration(resetIn),
				TextColor3 = C.Muted,
				Size = UDim2.new(1, -8, 0, 22),
				LayoutOrder = 0,
				MaxTextSize = 15,
				Parent = content,
			})
			for i, entry in list do
				local def = QuestConfig.Quests[entry.Id]
				if def then
					questRow(content, def, entry.Progress, entry.Completed, entry.Claimed, i, profile)
				end
			end
		elseif questTab == 4 then
			local i = 0
			for _, id in QuestConfig.RegionQuests do
				local entry = q.Region[id]
				local def = QuestConfig.Quests[id]
				if entry and def then
					i += 1
					questRow(content, def, entry.Progress, entry.Completed, entry.Claimed, i, profile)
				end
			end
			if i == 0 then
				Kit.text({
					Text = "Unlock regions to receive region quests.",
					TextColor3 = C.Muted,
					Size = UDim2.new(1, -8, 0, 30),
					Parent = content,
				})
			end
		else
			local i = 0
			for _, id in QuestConfig.EventQuests do
				local entry = q.Event[id]
				local def = QuestConfig.Quests[id]
				if entry and def and def.EventId and EventSchedule.isEventActive(def.EventId, now) then
					i += 1
					questRow(content, def, entry.Progress, entry.Completed, entry.Claimed, i, profile)
				end
			end
			if i == 0 then
				Kit.text({
					Text = "No event quests right now. Check the Events board!",
					TextColor3 = C.Muted,
					Size = UDim2.new(1, -8, 0, 30),
					Parent = content,
				})
			end
		end
	end
	renderers.Quests = render
	selectTab(questTab)
end

local function buildAchievements(body: Frame)
	local grid = Kit.scroll({ Parent = body })
	Kit.grid(grid, UDim2.new(0.5, -6, 0, 78), 8)
	renderers.Achievements = function()
		local profile = StateController.Profile
		if not profile then
			return
		end
		Kit.clear(grid)
		for i, id in QuestConfig.AchievementOrder do
			local def = QuestConfig.Achievements[id]
			local done = profile.Achievements.Completed[id] ~= nil
			local claimed = profile.Achievements.Claimed[id] == true
			local card =
				Kit.card({ LayoutOrder = if done and not claimed then i - 1000 else i, Parent = grid })
			Kit.stroke(
				card,
				if claimed then C.Disabled elseif done then C.Gold else C.Stroke,
				if done and not claimed then 3 else 1
			)
			Kit.text({
				Text = def.Glyph,
				Size = UDim2.fromOffset(50, 60),
				Position = UDim2.fromOffset(6, 8),
				TextTransparency = if done then 0 else 0.6,
				MaxTextSize = 36,
				Parent = card,
			})
			Kit.text({
				Text = def.Title,
				Font = Theme.Fonts.Title,
				TextXAlignment = Enum.TextXAlignment.Left,
				Size = UDim2.new(1, -190, 0, 24),
				Position = UDim2.fromOffset(60, 6),
				MaxTextSize = 17,
				Parent = card,
			})
			Kit.text({
				Text = def.Description .. "\n" .. rewardText(def.Reward, profile),
				TextColor3 = C.Muted,
				TextXAlignment = Enum.TextXAlignment.Left,
				Size = UDim2.new(1, -190, 0, 40),
				Position = UDim2.fromOffset(60, 32),
				MaxTextSize = 13,
				Parent = card,
			})
			local b = Kit.button(
				if claimed then "✓" elseif done then "Claim" else "🔒",
				if done and not claimed then "Gold" else "Dark",
				function()
					local r = UIController.call("ClaimAchievement", id)
					if r.ok then
						AudioController.play("Achievement")
					end
				end,
				{ Size = UDim2.fromOffset(110, 44), Position = UDim2.new(1, -116, 0.5, -22), Parent = card }
			)
			Kit.setEnabled(b, done and not claimed)
		end
	end
	renderers.Achievements()
end

local function buildDaily(body: Frame)
	local info = Kit.text({
		Text = "",
		Font = Theme.Fonts.Title,
		Size = UDim2.new(1, 0, 0, 34),
		MaxTextSize = 22,
		Parent = body,
	})
	local grid = Kit.frame({
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, -110),
		Position = UDim2.fromOffset(0, 42),
		Parent = body,
	})
	Kit.grid(grid, UDim2.new(1 / 4, -8, 0.48, 0), 8)
	local claimButton = Kit.button("Claim today's reward", "Gold", function()
		local r = UIController.call("ClaimDaily")
		if r.ok then
			AudioController.play("Achievement")
			UIController.toast("reward", "Day " .. tostring(r.data.Streak) .. " reward claimed!")
		end
	end, { Size = UDim2.new(1, 0, 0, 56), Position = UDim2.new(0, 0, 1, -56), Parent = body })
	renderers.Daily = function()
		local profile = StateController.Profile
		if not profile then
			return
		end
		local now = StateController.serverTime()
		local today = TimeUtil.dayIndex(now)
		local daily = profile.DailyRewards
		local claimedToday = daily.LastClaimDay == today
		local streak = if claimedToday
			then daily.CurrentStreak
			elseif
				daily.LastClaimDay == today - 1 or not QuestConfig.DailyResetOnMiss
			then daily.CurrentStreak + 1
			else 1
		local index = ((math.max(1, streak) - 1) % #QuestConfig.DailyRewards) + 1
		info.Text = if claimedToday
			then "✓ Claimed today · streak " .. daily.CurrentStreak .. " · next in " .. Format.duration(
				TimeUtil.secondsUntilNextDay(now)
			)
			else "🎁 Day " .. streak .. " reward is ready!"
		Kit.clear(grid)
		for day, reward in QuestConfig.DailyRewards do
			local isToday = day == index
			local past = day < index or (claimedToday and isToday)
			local card = Kit.card({
				LayoutOrder = day,
				BackgroundColor3 = if isToday and not claimedToday
					then C.Gold:Lerp(C.PanelDark, 0.6)
					else C.PanelLight,
				Parent = grid,
			})
			Kit.stroke(card, if isToday then C.Gold else C.Stroke, if isToday then 3 else 1)
			Kit.text({
				Text = "Day " .. day .. (if past then " ✓" else ""),
				Font = Theme.Fonts.Title,
				Size = UDim2.new(1, 0, 0.3, 0),
				MaxTextSize = 20,
				Parent = card,
			})
			Kit.text({
				Text = rewardText(reward, profile),
				Size = UDim2.new(1, -10, 0.62, 0),
				Position = UDim2.new(0, 5, 0.34, 0),
				MaxTextSize = 15,
				Parent = card,
			})
		end
		Kit.setEnabled(claimButton, not claimedToday)
	end
	renderers.Daily()
end

local function buildEvents(body: Frame)
	local list = Kit.scroll({ Parent = body })
	Kit.list(list, Enum.FillDirection.Vertical, 8)
	renderers.Events = function()
		Kit.clear(list)
		local now = StateController.serverTime()
		for i, id in EventConfig.Order do
			local event = EventConfig.Events[id]
			local active = EventSchedule.isActive(event, now)
			local card = Kit.card({
				Size = UDim2.new(1, -8, 0, 110),
				LayoutOrder = if active then i else i + 100,
				Parent = list,
			})
			Kit.stroke(card, if active then event.Color else C.Disabled, if active then 3 else 1)
			Kit.text({
				Text = event.Glyph .. " " .. event.DisplayName .. (if active
					then "  · LIVE · ends in " .. Format.duration(EventSchedule.secondsRemaining(id, now))
					else "  · not active"),
				Font = Theme.Fonts.Title,
				TextXAlignment = Enum.TextXAlignment.Left,
				Size = UDim2.new(1, -20, 0, 28),
				Position = UDim2.fromOffset(10, 6),
				MaxTextSize = 20,
				Parent = card,
			})
			local mods = {}
			if event.LuckMultiplier ~= 1 then
				table.insert(mods, "🍀 x" .. event.LuckMultiplier .. " luck")
			end
			if event.IncomeMultiplier ~= 1 then
				table.insert(mods, "💰 x" .. event.IncomeMultiplier .. " income (online)")
			end
			if event.BattleCoinMultiplier ~= 1 then
				table.insert(mods, "⚔ x" .. event.BattleCoinMultiplier .. " battle coins")
			end
			Kit.text({
				Text = event.Description .. "\n" .. table.concat(mods, " · "),
				TextColor3 = C.Muted,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top,
				Size = UDim2.new(1, -200, 0, 60),
				Position = UDim2.fromOffset(10, 38),
				MaxTextSize = 14,
				Parent = card,
			})
			if active and event.DiceId then
				Kit.button(
					"🎲 Event Dice",
					"Gold",
					function()
						UIController.open("Roll", { DiceId = event.DiceId })
					end,
					{ Size = UDim2.fromOffset(170, 40), Position = UDim2.new(1, -180, 0, 40), Parent = card }
				)
			end
		end
	end
	renderers.Events()
end

-- HUD tracker -------------------------------------------------------------------------------

local function renderTracker()
	local frame = tracker
	local profile = StateController.Profile
	if not frame or not profile then
		return
	end
	Kit.clear(frame)
	local q = profile.Quests
	local id = QuestConfig.MainOrder[q.MainIndex]
	local def = id and QuestConfig.Quests[id]
	local order = 0
	local function line(title: string, progress: number, total: number, questId: string?, done: boolean)
		order += 1
		local card = Kit.card({
			BackgroundColor3 = C.PanelDark,
			BackgroundTransparency = 0.15,
			Size = UDim2.new(1, 0, 0, 58),
			LayoutOrder = order,
			Parent = frame,
		})
		Kit.stroke(card, if done then C.Gold else C.Stroke, if done then 2 else 1)
		Kit.text({
			Text = title,
			Font = Theme.Fonts.Bold,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(1, -16, 0, 22),
			Position = UDim2.fromOffset(8, 4),
			MaxTextSize = 15,
			Parent = card,
		})
		if done and questId then
			Kit.button("Claim reward!", "Gold", function()
				claim(questId)
			end, { Size = UDim2.new(1, -16, 0, 26), Position = UDim2.fromOffset(8, 28), Parent = card })
		else
			local _, set = Kit.progress(
				card,
				C.Accent,
				{ Size = UDim2.new(1, -16, 0, 16), Position = UDim2.fromOffset(8, 32) }
			)
			set(
				progress / math.max(1, total),
				Format.number(math.min(progress, total)) .. " / " .. Format.number(total)
			)
		end
	end
	if def then
		local t = target(def, profile)
		line("📖 " .. def.Title, q.MainProgress, t, def.Id, q.MainProgress >= t)
	end
	for _, entry in q.Daily do
		if entry.Completed and not entry.Claimed then
			local d = QuestConfig.Quests[entry.Id]
			if d then
				line("☀ " .. d.Title, entry.Progress, target(d, profile), d.Id, true)
			end
		end
	end
end

function QuestController.init()
	UIController.registerPanel({
		Id = "Quests",
		Title = "Quests",
		Glyph = "📜",
		Build = buildQuests,
		OnOpen = function()
			if renderers.Quests then
				renderers.Quests()
			end
		end,
	})
	UIController.registerPanel({
		Id = "Achievements",
		Title = "Achievements",
		Glyph = "🏆",
		Wide = true,
		Build = buildAchievements,
		OnOpen = function()
			if renderers.Achievements then
				renderers.Achievements()
			end
		end,
	})
	UIController.registerPanel({
		Id = "Daily",
		Title = "Daily Rewards",
		Glyph = "🗓",
		Build = buildDaily,
		OnOpen = function()
			if renderers.Daily then
				renderers.Daily()
			end
		end,
	})
	UIController.registerPanel({
		Id = "Events",
		Title = "Live Events",
		Glyph = "🎉",
		Build = buildEvents,
		OnOpen = function()
			if renderers.Events then
				renderers.Events()
			end
		end,
	})
end

function QuestController.start()
	tracker = Kit.frame({
		Name = "QuestTracker",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 200),
		LayoutOrder = 1,
		Parent = UIController.slot("Right"),
	})
	Kit.list(tracker :: Frame, Enum.FillDirection.Vertical, 6)
	StateController.waitForReady()
	renderTracker()
	StateController.Changed:Connect(function(key)
		if key == "Quests" or key == "*" then
			renderTracker()
		end
		local open = UIController.openId()
		if
			open
			and renderers[open]
			and (key == "Quests" or key == "Achievements" or key == "DailyRewards" or key == "*")
		then
			renderers[open]()
		end
	end)
end

return QuestController
