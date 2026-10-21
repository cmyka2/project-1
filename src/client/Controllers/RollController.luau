--!strict
-- Rolling UI: quick-roll bar, dice panel with exact odds, multi-roll and
-- auto-roll controls, and the reveal animation. The server picks every
-- result before this code animates anything; animations are cosmetic and
-- skippable.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Util = Shared:WaitForChild("Util")
local DiceConfig = require(Config:WaitForChild("DiceConfig"))
local MonsterConfig = require(Config:WaitForChild("MonsterConfig"))
local RarityConfig = require(Config:WaitForChild("RarityConfig"))
local RegionConfig = require(Config:WaitForChild("RegionConfig"))
local Format = require(Util:WaitForChild("Format"))
local Net = require(Shared:WaitForChild("Net"))
local UI = script.Parent.Parent:WaitForChild("UI")
local Kit = require(UI:WaitForChild("Kit"))
local Theme = require(UI:WaitForChild("Theme"))
local Icons = require(UI:WaitForChild("Icons"))
local StateController = require(script.Parent:WaitForChild("StateController"))
local UIController = require(script.Parent:WaitForChild("UIController"))
local AudioController = require(script.Parent:WaitForChild("AudioController"))
local EffectsController = require(script.Parent:WaitForChild("EffectsController"))

local C = Theme.Colors

local RollController = {}

local selectedDice = DiceConfig.StartingDice
local rolling = false
local quick: {
	name: TextLabel?,
	roll: TextButton?,
	multi: { [number]: TextButton },
	auto: TextButton?,
	free: TextButton?,
	autoStrip: Frame?,
} =
	{ multi = {} }
local panelRefresh: (() -> ())? = nil

local function derived()
	return StateController.Derived
end

local function unlockedDiceList(): { string }
	local d = derived()
	local out = {}
	for _, id in DiceConfig.Order do
		if d and d.UnlockedDice[id] then
			table.insert(out, id)
		end
	end
	return out
end

function RollController.select(diceId: string)
	if DiceConfig.Dice[diceId] then
		selectedDice = diceId
		RollController.refresh()
	end
end

function RollController.selected(): string
	return selectedDice
end

-- Reveal animation -----------------------------------------------------------------------

type Result = {
	MonsterId: string,
	Rarity: string,
	InstanceId: string?,
	AutoSold: boolean,
	SoldFor: number,
	New: boolean,
}

local function resultCard(parent: Instance, result: Result, order: number): Frame
	local def = MonsterConfig.Monsters[result.MonsterId]
	local rarity = RarityConfig.Rarities[result.Rarity]
	local card = Kit.card({ BackgroundColor3 = C.PanelDark, LayoutOrder = order, Parent = parent })
	Kit.stroke(card, rarity.Color, 3)
	local iconHolder = Kit.frame({
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(0.8, 0.55),
		Position = UDim2.fromScale(0.1, 0.05),
		Parent = card,
	})
	Kit.aspect(iconHolder, 1)
	Icons.monster(result.MonsterId, iconHolder)
	local name = Kit.text({
		Text = if def then def.DisplayName else result.MonsterId,
		Font = Theme.Fonts.Title,
		Size = UDim2.fromScale(0.94, 0.18),
		Position = UDim2.fromScale(0.03, 0.6),
		MaxTextSize = 18,
		Parent = card,
	})
	Kit.textStroke(name)
	local tag = rarity.DisplayName
	if result.AutoSold then
		tag ..= " · sold 💰" .. Format.number(result.SoldFor)
	end
	Kit.text({
		Text = tag,
		TextColor3 = rarity.Color,
		Font = Theme.Fonts.Bold,
		Size = UDim2.fromScale(0.94, 0.14),
		Position = UDim2.fromScale(0.03, 0.8),
		MaxTextSize = 15,
		Parent = card,
	})
	if result.New then
		local badge = Kit.text({
			Text = "NEW!",
			Font = Theme.Fonts.Title,
			TextColor3 = C.Gold,
			Size = UDim2.fromScale(0.5, 0.14),
			Position = UDim2.fromScale(0.5, 0),
			MaxTextSize = 16,
			Rotation = 12,
			Parent = card,
		})
		Kit.textStroke(badge, Color3.new(0, 0, 0), 2)
	end
	return card
end

local function playReveal(outcome: any)
	local results: { Result } = outcome.Results
	local profile = StateController.Profile
	local skipAll = profile ~= nil and profile.Settings.SkipRollAnimation
	local reduced = profile ~= nil and profile.Settings.ReducedEffects
	local overlay = UIController.overlay()
	local shade = Instance.new("TextButton")
	shade.Text = ""
	shade.AutoButtonColor = false
	shade.BackgroundColor3 = C.Backdrop
	shade.BackgroundTransparency = 0.25
	shade.Size = UDim2.fromScale(1, 1)
	shade.Parent = overlay
	local skipped = skipAll
	local closed = false
	local stage = Kit.frame({
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.46),
		Size = UDim2.fromScale(0.8, 0.62),
		Parent = shade,
	})
	local buttons = Kit.frame({
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -24),
		Size = UDim2.fromOffset(460, 50),
		Parent = shade,
	})
	Kit.list(buttons, Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Center)
	local skipButton = Kit.button("Skip ⏩", "Dark", function()
		skipped = true
	end, { Size = UDim2.fromOffset(140, 46), Parent = buttons })

	local highestTier = 0
	for _, r in results do
		highestTier = math.max(highestTier, RarityConfig.tierOf(r.Rarity))
	end
	local dice = DiceConfig.Dice[selectedDice]
	local pool = if dice then dice.Pool else {}

	if #results == 1 then
		local r = results[1]
		local rarity = RarityConfig.Rarities[r.Rarity]
		local holder = Kit.frame({
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.45),
			Size = UDim2.fromScale(0.3, 0.75),
			Parent = stage,
		})
		Kit.aspect(holder, 0.8)
		-- anticipation: cycle silhouettes, slowing down
		if not skipped and #pool > 0 then
			AudioController.play(if dice then dice.SoundKey else "RollBasic")
			local duration = rarity.RevealDuration
			local elapsed = 0
			local delay = 0.05
			while elapsed < duration and not skipped do
				Kit.clear(holder)
				local fakeId = pool[math.random(1, #pool)]
				local fakeDef = MonsterConfig.Monsters[fakeId]
				local fakeRarity = RarityConfig.Rarities[fakeDef.Rarity]
				local card = Kit.card({
					BackgroundColor3 = C.PanelDark,
					Size = UDim2.fromScale(1, 1),
					Parent = holder,
				})
				Kit.stroke(card, fakeRarity.Color, 4)
				Kit.text({
					Text = "?",
					Font = Theme.Fonts.Title,
					TextColor3 = fakeRarity.Color,
					MaxTextSize = 120,
					Parent = card,
				})
				task.wait(delay)
				elapsed += delay
				delay = math.min(0.22, delay * 1.12)
			end
		end
		Kit.clear(holder)
		local card = resultCard(holder, r, 1)
		card.Size = UDim2.fromScale(1, 1)
		Kit.pop(card, 0.25)
		AudioController.play(
			if rarity.Tier >= 6
				then "RevealMythic"
				elseif rarity.Tier >= 5 then "RevealLegendary"
				elseif rarity.Tier >= 3 then "RevealRare"
				else "RevealCommon"
		)
		if rarity.Tier >= 5 and not reduced then
			EffectsController.flash(rarity.Color, if rarity.Tier >= 7 then 0.6 else 0.35)
			EffectsController.shake(if rarity.Tier >= 8 then 0.5 else 0.25)
		end
		if rarity.Tier >= 6 then
			local big = Kit.text({
				Text = string.upper(rarity.DisplayName) .. "!",
				Font = Theme.Fonts.Title,
				TextColor3 = rarity.Color,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.02),
				Size = UDim2.fromScale(0.9, 0.2),
				MaxTextSize = 80,
				Parent = stage,
			})
			Kit.textStroke(big, Color3.new(0, 0, 0), 3)
			Kit.pop(big, 0.4)
		end
	else
		local grid = Kit.frame({ BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = stage })
		local columns = if #results <= 3 then #results elseif #results <= 6 then 3 else 5
		Kit.grid(grid, UDim2.new(1 / columns, -10, 0.46, 0), 10).HorizontalAlignment =
			Enum.HorizontalAlignment.Center
		AudioController.play(if dice then dice.SoundKey else "RollBasic")
		for i, r in results do
			if not skipped then
				task.wait(0.18)
			end
			local card = resultCard(grid, r, i)
			Kit.pop(card, 0.15)
		end
		if highestTier >= 5 and not reduced then
			local best = RarityConfig.Rarities[RarityConfig.Order[highestTier]]
			EffectsController.flash(best.Color, 0.35)
		end
	end
	skipButton:Destroy()
	if outcome.StoppedReason then
		UIController.toast("info", outcome.StoppedReason)
	end
	Kit.button("Roll Again", "Good", function()
		closed = true
		shade:Destroy()
		RollController.roll(#results, false)
	end, { Size = UDim2.fromOffset(170, 46), Parent = buttons })
	Kit.button("Close", "Dark", function()
		closed = true
		shade:Destroy()
	end, { Size = UDim2.fromOffset(140, 46), Parent = buttons })
	shade.Activated:Connect(function()
		if not closed then
			closed = true
			shade:Destroy()
		end
	end)
end

function RollController.roll(count: number, free: boolean)
	if rolling then
		return
	end
	local d = derived()
	if d and d.AutoRolling then
		UIController.toast("info", "Stop auto-roll first.")
		return
	end
	rolling = true
	local result = UIController.call("Roll", selectedDice, count, free)
	rolling = false
	if result.ok and result.data then
		playReveal(result.data)
	end
end

function RollController.toggleAuto(count: number?)
	local d = derived()
	if not d then
		return
	end
	if d.AutoRolling then
		UIController.call("SetAutoRoll", false)
	else
		local best = 1
		for _, option in d.MultiRollOptions do
			best = math.max(best, option)
		end
		local result = UIController.call("SetAutoRoll", true, selectedDice, count or best)
		if result.ok then
			UIController.toast("success", "Auto-roll started.")
		end
	end
end

-- Quick roll bar ------------------------------------------------------------------------

local function buildQuickBar()
	local slot = UIController.slot("BottomCenter")
	local bar = Kit.frame({
		BackgroundColor3 = C.PanelDark,
		BackgroundTransparency = 0.1,
		Size = UDim2.fromScale(1, 1),
		Parent = slot,
	})
	Kit.corner(bar, 18)
	Kit.stroke(bar, C.Stroke, 2)
	Kit.padding(bar, 8)
	Kit.button("◀", "Dark", function()
		local list = unlockedDiceList()
		local i = table.find(list, selectedDice) or 1
		RollController.select(list[((i - 2) % #list) + 1] or selectedDice)
	end, { Size = UDim2.new(0, 36, 0.5, -2), Position = UDim2.fromScale(0, 0), Parent = bar })
	Kit.button("▶", "Dark", function()
		local list = unlockedDiceList()
		local i = table.find(list, selectedDice) or 1
		RollController.select(list[(i % #list) + 1] or selectedDice)
	end, { Size = UDim2.new(0, 36, 0.5, -2), Position = UDim2.new(0, 154, 0, 0), Parent = bar })
	quick.name = Kit.text({
		Text = "",
		Font = Theme.Fonts.Title,
		Size = UDim2.new(0, 112, 0.5, -2),
		Position = UDim2.fromOffset(40, 0),
		MaxTextSize = 16,
		Parent = bar,
	})
	quick.free = Kit.button("🎁 Free Roll", "Gold", function()
		RollController.roll(1, true)
	end, { Size = UDim2.new(0, 190, 0.5, -4), Position = UDim2.new(0, 0, 0.5, 4), Parent = bar })
	quick.roll = Kit.button("ROLL", "Good", function()
		RollController.roll(1, false)
	end, { Size = UDim2.new(0, 150, 1, 0), Position = UDim2.fromOffset(198, 0), Parent = bar })
	local multiFrame = Kit.frame({
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -356, 0.5, -4),
		Position = UDim2.fromOffset(356, 0),
		Parent = bar,
	})
	Kit.list(multiFrame, Enum.FillDirection.Horizontal, 4)
	for _, count in { 3, 5, 10 } do
		quick.multi[count] = Kit.button("x" .. count, "Primary", function()
			RollController.roll(count, false)
		end, { Size = UDim2.new(1 / 3, -3, 1, 0), Parent = multiFrame })
	end
	quick.auto = Kit.button("AUTO", "Dark", function()
		RollController.toggleAuto(nil)
	end, { Size = UDim2.new(1, -356, 0.5, -4), Position = UDim2.new(0, 356, 0.5, 4), Parent = bar })
	quick.autoStrip = Kit.frame({
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0, -6),
		Size = UDim2.new(1, 0, 0, 40),
		Parent = slot,
	})
	Kit.list(quick.autoStrip :: Frame, Enum.FillDirection.Horizontal, 4, Enum.HorizontalAlignment.Center)
end

function RollController.refresh()
	local d = derived()
	local profile = StateController.Profile
	if not d or not profile then
		return
	end
	if not d.UnlockedDice[selectedDice] then
		selectedDice = DiceConfig.StartingDice
	end
	local dice = DiceConfig.Dice[selectedDice]
	if quick.name then
		quick.name.Text = dice.DisplayName
	end
	if quick.roll then
		local cost = d.RollCosts[selectedDice] or dice.Cost
		Kit.setText(
			quick.roll,
			"ROLL\n" .. (if dice.CostCurrency == "Coins" then "💰" else "🎟") .. Format.number(cost)
		)
		Kit.setEnabled(quick.roll, not d.AutoRolling)
	end
	for count, button in quick.multi do
		local allowed = table.find(d.MultiRollOptions, count) ~= nil
		Kit.setEnabled(button, allowed and not d.AutoRolling)
	end
	if quick.auto then
		Kit.setText(
			quick.auto,
			if d.AutoRolling then "■ STOP AUTO" elseif d.AutoRollUnlocked then "▶ AUTO" else "🔒 AUTO"
		)
		Kit.setEnabled(quick.auto, d.AutoRollUnlocked)
	end
	if quick.free then
		local ready = StateController.serverTime() >= d.FreeRollReadyAt
		Kit.setText(
			quick.free,
			if ready
				then "🎁 Free Roll!"
				else "🎁 " .. Format.duration(d.FreeRollReadyAt - StateController.serverTime())
		)
		Kit.setEnabled(quick.free, ready and not d.AutoRolling)
	end
	if panelRefresh then
		panelRefresh()
	end
end

-- Dice panel -----------------------------------------------------------------------------

local function buildPanel(body: Frame)
	local left = Kit.scroll({ Size = UDim2.new(0.42, -6, 1, 0), Parent = body })
	Kit.list(left, Enum.FillDirection.Vertical, 6)
	Kit.padding(left, 4)
	local right = Kit.frame({
		BackgroundColor3 = C.PanelDark,
		Size = UDim2.new(0.58, -6, 1, 0),
		Position = UDim2.new(0.42, 6, 0, 0),
		Parent = body,
	})
	Kit.corner(right)
	Kit.padding(right, 10)
	local title = Kit.header("", { Parent = right })
	local info = Kit.text({
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = C.Muted,
		Size = UDim2.new(1, 0, 0, 40),
		Position = UDim2.fromOffset(0, 30),
		MaxTextSize = 16,
		Parent = right,
	})
	local oddsList =
		Kit.scroll({ Size = UDim2.new(1, 0, 1, -190), Position = UDim2.fromOffset(0, 76), Parent = right })
	Kit.list(oddsList, Enum.FillDirection.Vertical, 4)
	local actions = Kit.frame({
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 104),
		Position = UDim2.new(0, 0, 1, -104),
		Parent = right,
	})
	Kit.grid(actions, UDim2.new(0.25, -6, 0, 46), 6)
	local buttons: { [number]: TextButton } = {}
	for i, count in { 1, 3, 5, 10 } do
		buttons[count] = Kit.button("Roll x" .. count, "Good", function()
			RollController.roll(count, false)
		end, { LayoutOrder = i, Parent = actions })
	end
	local autoButton = Kit.button("Auto", "Dark", function()
		RollController.toggleAuto(nil)
	end, { LayoutOrder = 5, Parent = actions })
	local skipToggle = Kit.button("Skip anim: OFF", "Dark", function()
		local profile = StateController.Profile
		if profile then
			UIController.call(
				"UpdateSettings",
				{ SkipRollAnimation = not profile.Settings.SkipRollAnimation }
			)
		end
	end, { LayoutOrder = 6, Parent = actions })
	Kit.button("Auto-sell ⚙", "Dark", function()
		UIController.open("Settings")
	end, { LayoutOrder = 7, Parent = actions })
	Kit.button("Odds ⓘ", "Ghost", function()
		UIController.popup("How odds work", {
			"Each roll first picks a rarity, then a monster of it.",
			"Luck multiplies rare weights: weight × luck ^ exponent.",
			"Percentages shown are exact, including your luck.",
		}, C.Accent)
	end, { LayoutOrder = 8, Parent = actions })

	local diceCards: { [string]: Frame } = {}
	for i, diceId in DiceConfig.Order do
		local dice = DiceConfig.Dice[diceId]
		local card = Kit.card({ Size = UDim2.new(1, -8, 0, 64), LayoutOrder = i, Parent = left })
		Kit.stroke(card, dice.Color, 2)
		Kit.text({ Text = dice.Glyph, Size = UDim2.new(0, 50, 1, 0), MaxTextSize = 34, Parent = card })
		Kit.text({
			Name = "Title",
			Text = dice.DisplayName,
			Font = Theme.Fonts.Title,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(1, -60, 0.5, 0),
			Position = UDim2.fromOffset(54, 4),
			MaxTextSize = 20,
			Parent = card,
		})
		Kit.text({
			Name = "Sub",
			Text = "",
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = C.Muted,
			Size = UDim2.new(1, -60, 0.4, 0),
			Position = UDim2.new(0, 54, 0.5, 0),
			MaxTextSize = 15,
			Parent = card,
		})
		local hit = Instance.new("TextButton")
		hit.Text = ""
		hit.BackgroundTransparency = 1
		hit.Size = UDim2.fromScale(1, 1)
		hit.Parent = card
		hit.Activated:Connect(function()
			RollController.select(diceId)
		end)
		diceCards[diceId] = card
	end

	local function refreshPanel()
		local d = derived()
		local profile = StateController.Profile
		if not d or not profile then
			return
		end
		for diceId, card in diceCards do
			local dice = DiceConfig.Dice[diceId]
			local unlocked = d.UnlockedDice[diceId]
			local isEvent = dice.EventId ~= nil
			card.Visible = not isEvent or unlocked
			card.BackgroundColor3 = if diceId == selectedDice
				then C.Accent:Lerp(C.PanelLight, 0.5)
				else C.PanelLight
			local sub = card:FindFirstChild("Sub")
			if sub and sub:IsA("TextLabel") then
				if unlocked then
					sub.Text = string.format(
						"💰 %s · 🍀 x%.2f luck",
						Format.number(d.RollCosts[diceId] or dice.Cost),
						d.Luck[diceId] or 1
					)
				else
					local region = RegionConfig.Regions[dice.RequiredRegion]
					local needs = {}
					if not profile.Progression.UnlockedRegions[dice.RequiredRegion] then
						table.insert(
							needs,
							"unlock " .. (if region then region.DisplayName else dice.RequiredRegion)
						)
					end
					if profile.Progression.RebirthCount < dice.RequiredRebirths then
						table.insert(needs, dice.RequiredRebirths .. " rebirths")
					end
					sub.Text = "🔒 Requires " .. table.concat(needs, " + ")
				end
			end
		end
		local dice = DiceConfig.Dice[selectedDice]
		title.Text = dice.Glyph .. " " .. dice.DisplayName
		info.Text = string.format(
			"Cost 💰 %s per roll · Luck x%.2f (base %.2f)",
			Format.number(d.RollCosts[selectedDice] or dice.Cost),
			d.Luck[selectedDice] or 1,
			dice.BaseLuck
		)
		Kit.clear(oddsList)
		local oddsRows: { any } = d.Odds[selectedDice] or {}
		for i, odds in oddsRows do
			local rarity = RarityConfig.Rarities[odds.Rarity]
			local row = Kit.card({ Size = UDim2.new(1, -8, 0, 30), LayoutOrder = i, Parent = oddsList })
			Kit.stroke(row, rarity.Color, 1)
			Kit.text({
				Text = rarity.Glyph .. " " .. rarity.DisplayName,
				TextColor3 = rarity.Color,
				Font = Theme.Fonts.Bold,
				TextXAlignment = Enum.TextXAlignment.Left,
				Size = UDim2.new(0.45, 0, 1, -6),
				Position = UDim2.fromOffset(8, 3),
				MaxTextSize = 16,
				Parent = row,
			})
			Kit.text({
				Text = Format.percent(odds.Chance, 3) .. "   (" .. Format.oneIn(odds.Chance) .. ")",
				TextXAlignment = Enum.TextXAlignment.Right,
				Size = UDim2.new(0.55, -10, 1, -6),
				Position = UDim2.new(0.45, 0, 0, 3),
				MaxTextSize = 15,
				Parent = row,
			})
		end
		local unlocked = d.UnlockedDice[selectedDice]
		for count, button in buttons do
			Kit.setEnabled(
				button,
				unlocked and table.find(d.MultiRollOptions, count) ~= nil and not d.AutoRolling
			)
		end
		Kit.setText(
			autoButton,
			if d.AutoRolling then "Stop Auto" elseif d.AutoRollUnlocked then "Auto Roll" else "🔒 Auto"
		)
		Kit.setEnabled(autoButton, d.AutoRollUnlocked and unlocked)
		Kit.setText(skipToggle, "Skip anim: " .. (if profile.Settings.SkipRollAnimation then "ON" else "OFF"))
	end
	panelRefresh = refreshPanel
	refreshPanel()
end

function RollController.init()
	UIController.registerPanel({
		Id = "Roll",
		Title = "Dice Altar",
		Glyph = "🎲",
		Build = buildPanel,
		OnOpen = function(args)
			if typeof(args) == "table" and args.DiceId then
				RollController.select(args.DiceId)
			end
			RollController.refresh()
		end,
	})
	Net.on("AutoRollResult", function(outcome: any)
		local strip = quick.autoStrip
		if not strip or typeof(outcome) ~= "table" then
			return
		end
		Kit.clear(strip)
		for i, r in outcome.Results do
			local holder = Kit.frame({
				BackgroundTransparency = 1,
				Size = UDim2.fromOffset(38, 38),
				LayoutOrder = i,
				Parent = strip,
			})
			Icons.monster(r.MonsterId, holder)
			if RarityConfig.tierOf(r.Rarity) >= 5 then
				local def = MonsterConfig.Monsters[r.MonsterId]
				UIController.toast(
					"reward",
					"Auto-roll: " .. r.Rarity .. " " .. (if def then def.DisplayName else r.MonsterId) .. "!"
				)
			end
		end
	end)
end

function RollController.start()
	buildQuickBar()
	StateController.waitForReady()
	-- default to the best unlocked regional dice
	local list = unlockedDiceList()
	for _, id in list do
		if not DiceConfig.Dice[id].EventId then
			selectedDice = id
		end
	end
	RollController.refresh()
	StateController.Changed:Connect(function(key)
		if key == "Derived" or key == "*" or key == "Settings" or key == "Discovery" then
			RollController.refresh()
		end
	end)
	while true do
		task.wait(1)
		local d = derived()
		if d and quick.free then
			local ready = StateController.serverTime() >= d.FreeRollReadyAt
			Kit.setText(
				quick.free,
				if ready
					then "🎁 Free Roll!"
					else "🎁 " .. Format.duration(d.FreeRollReadyAt - StateController.serverTime())
			)
			Kit.setEnabled(quick.free, ready and not d.AutoRolling)
		end
	end
end

return RollController
