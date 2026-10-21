--!strict
-- Battle UI. The prep panel manages the team, loadouts, region encounters
-- and the arena. The battle screen renders server snapshots, replays the
-- server's event log as animations (damage numbers, statuses, phases), and
-- sends the player's chosen action. Nothing here computes combat results.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Util = Shared:WaitForChild("Util")
local AbilityConfig = require(Config:WaitForChild("AbilityConfig"))
local CombatConfig = require(Config:WaitForChild("CombatConfig"))
local EnemyConfig = require(Config:WaitForChild("EnemyConfig"))
local RegionConfig = require(Config:WaitForChild("RegionConfig"))
local CraftingConfig = require(Config:WaitForChild("CraftingConfig"))
local StatMath = require(Util:WaitForChild("StatMath"))
local Format = require(Util:WaitForChild("Format"))
local Net = require(Shared:WaitForChild("Net"))
local Types = require(Shared:WaitForChild("Types"))
local UI = script.Parent.Parent:WaitForChild("UI")
local Kit = require(UI:WaitForChild("Kit"))
local Theme = require(UI:WaitForChild("Theme"))
local Icons = require(UI:WaitForChild("Icons"))
local Cards = require(UI:WaitForChild("Cards"))
local StateController = require(script.Parent:WaitForChild("StateController"))
local UIController = require(script.Parent:WaitForChild("UIController"))
local InventoryController = require(script.Parent:WaitForChild("InventoryController"))
local AudioController = require(script.Parent:WaitForChild("AudioController"))
local EffectsController = require(script.Parent:WaitForChild("EffectsController"))

local C = Theme.Colors

local CombatController = {}

local selectedRegion = RegionConfig.StartingRegion
local renderPrep: (() -> ())? = nil

-- Battle screen state
local screen: Frame? = nil
local snapshot: any = nil
local unitCards: { [string]: Frame } = {}
local pendingAbility: string? = nil
local playing = false
local queue: { { any } } = {}
local logLines: { string } = {}

-- Prep panel ----------------------------------------------------------------------------

local function teamPower(): number
	local profile = StateController.Profile
	if not profile then
		return 0
	end
	local total = 0
	for _, id in profile.Battle.Team do
		local inst = profile.Inventory.Monsters[id]
		if inst then
			total += InventoryController.powerOf(inst)
		end
	end
	return total
end

local function editTeam()
	local profile = StateController.Profile
	if not profile then
		return
	end
	local list = StateController.monsters()
	table.sort(list, function(a, b)
		return InventoryController.powerOf(a) > InventoryController.powerOf(b)
	end)
	Cards.picker({
		Title = "Choose up to " .. CombatConfig.TeamSize .. " monsters",
		Candidates = list,
		Max = CombatConfig.TeamSize,
		Min = 1,
		Preselected = profile.Battle.Team,
		Subtitle = function(inst: Types.MonsterInstance): string
			return "💪 " .. Format.number(InventoryController.powerOf(inst))
		end,
		ConfirmText = "Save Team",
		Overlay = UIController.overlay(),
		OnConfirm = function(ids)
			UIController.call("SetTeam", ids)
		end,
	})
end

local function startEncounter(encounterId: string)
	local result = UIController.call("StartBattle", encounterId)
	if result.ok then
		UIController.close()
	end
end

local function buildPrep(body: Frame)
	local left =
		Kit.frame({ BackgroundColor3 = C.PanelDark, Size = UDim2.new(0.36, -6, 1, 0), Parent = body })
	Kit.corner(left)
	Kit.padding(left, 10)
	Kit.list(left, Enum.FillDirection.Vertical, 8)
	Kit.header("⚔ Your Team", { LayoutOrder = 1, Parent = left })
	local teamGrid = Kit.frame({
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 130),
		LayoutOrder = 2,
		Parent = left,
	})
	Kit.grid(teamGrid, UDim2.new(1 / 3, -6, 1, 0), 6)
	local powerLabel = Kit.text({
		Text = "",
		Font = Theme.Fonts.Bold,
		Size = UDim2.new(1, 0, 0, 24),
		LayoutOrder = 3,
		MaxTextSize = 18,
		Parent = left,
	})
	Kit.button(
		"Edit Team",
		"Primary",
		editTeam,
		{ Size = UDim2.new(1, 0, 0, 44), LayoutOrder = 4, Parent = left }
	)
	local loadoutRow = Kit.frame({
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 92),
		LayoutOrder = 5,
		Parent = left,
	})
	Kit.grid(loadoutRow, UDim2.new(0.5, -4, 0, 42), 6)
	Kit.header("🏟 Arena", { LayoutOrder = 6, Parent = left })
	local arenaLabel = Kit.text({
		Text = "",
		TextColor3 = C.Muted,
		Size = UDim2.new(1, 0, 0, 40),
		LayoutOrder = 7,
		MaxTextSize = 16,
		Parent = left,
	})
	Kit.button("Fight in the Arena", "Bad", function()
		local result = UIController.call("StartArena")
		if result.ok then
			UIController.close()
		end
	end, { Size = UDim2.new(1, 0, 0, 46), LayoutOrder = 8, Parent = left })

	local right = Kit.frame({
		BackgroundTransparency = 1,
		Size = UDim2.new(0.64, -6, 1, 0),
		Position = UDim2.new(0.36, 6, 0, 0),
		Parent = body,
	})
	local regionBar = Kit.scroll({
		Size = UDim2.new(1, 0, 0, 46),
		ScrollingDirection = Enum.ScrollingDirection.X,
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		Parent = right,
	})
	Kit.list(regionBar, Enum.FillDirection.Horizontal, 6)
	local encounters =
		Kit.scroll({ Size = UDim2.new(1, 0, 1, -52), Position = UDim2.fromOffset(0, 52), Parent = right })
	Kit.list(encounters, Enum.FillDirection.Vertical, 8)

	local function doRender()
		local profile = StateController.Profile
		if not profile then
			return
		end
		Kit.clear(teamGrid)
		for i = 1, CombatConfig.TeamSize do
			local id = profile.Battle.Team[i]
			local inst = id and profile.Inventory.Monsters[id]
			if inst then
				Cards.monster(teamGrid, inst, { LayoutOrder = i, OnClick = editTeam })
			else
				local empty = Kit.card({ LayoutOrder = i, Parent = teamGrid })
				Kit.text({
					Text = "+",
					Font = Theme.Fonts.Title,
					TextColor3 = C.Muted,
					MaxTextSize = 40,
					Parent = empty,
				})
			end
		end
		local power = teamPower()
		powerLabel.Text = "💪 Team power: " .. Format.number(power)
		Kit.clear(loadoutRow)
		local slotsCount = if StateController.Derived then StateController.Derived.LoadoutSlots else 1
		for i = 1, slotsCount do
			Kit.button("Save " .. i, "Dark", function()
				UIController.call("SaveLoadout", i)
				UIController.toast("success", "Loadout " .. i .. " saved.")
			end, { LayoutOrder = i * 2 - 1, Parent = loadoutRow })
			local load = Kit.button("Load " .. i, "Ghost", function()
				UIController.call("LoadLoadout", i)
			end, { LayoutOrder = i * 2, Parent = loadoutRow })
			Kit.setEnabled(load, profile.Battle.Loadouts[i] ~= nil and #profile.Battle.Loadouts[i] > 0)
		end
		arenaLabel.Text = string.format(
			"Rating %d · %dW / %dL",
			profile.Battle.BattleRating,
			profile.Battle.ArenaWins,
			profile.Battle.ArenaLosses
		)

		Kit.clear(regionBar)
		for i, regionId in RegionConfig.Order do
			if profile.Progression.UnlockedRegions[regionId] then
				local region = RegionConfig.Regions[regionId]
				local b = Kit.button(region.DisplayName, "Dark", function()
					selectedRegion = regionId
					if renderPrep then
						renderPrep()
					end
				end, { Size = UDim2.fromOffset(160, 40), LayoutOrder = i, Parent = regionBar })
				if regionId == selectedRegion then
					b.BackgroundColor3 = C.Accent
				end
			end
		end
		Kit.clear(encounters)
		for i, encounter in EnemyConfig.encountersForRegion(selectedRegion) do
			local card = Kit.card({ Size = UDim2.new(1, -8, 0, 108), LayoutOrder = i, Parent = encounters })
			Kit.stroke(card, if encounter.IsBoss then C.Bad else C.Stroke, if encounter.IsBoss then 3 else 1)
			local recommended = StatMath.encounterPower(encounter)
			local color = if power >= recommended * 1.15
				then C.Good
				elseif power >= recommended * 0.85 then C.Warn
				else C.Bad
			local enemyNames = {}
			for _, entry in encounter.Enemies do
				local enemy = EnemyConfig.Enemies[entry.Enemy]
				table.insert(
					enemyNames,
					(if enemy then enemy.DisplayName else entry.Enemy) .. " Lv" .. entry.Level
				)
			end
			Kit.text({
				Text = (if encounter.IsBoss then "💀 " else "⚔ ") .. encounter.DisplayName,
				Font = Theme.Fonts.Title,
				TextXAlignment = Enum.TextXAlignment.Left,
				Size = UDim2.new(1, -170, 0, 28),
				Position = UDim2.fromOffset(10, 6),
				MaxTextSize = 20,
				Parent = card,
			})
			Kit.text({
				Text = table.concat(enemyNames, ", "),
				TextColor3 = C.Muted,
				TextXAlignment = Enum.TextXAlignment.Left,
				Size = UDim2.new(1, -170, 0, 22),
				Position = UDim2.fromOffset(10, 34),
				MaxTextSize = 14,
				Parent = card,
			})
			local clears = profile.Progression.EncounterClears[encounter.Id] or 0
			local rewardText = string.format(
				"💰 %s · ✨ %d XP%s%s",
				Format.number(encounter.RewardCoins),
				encounter.RewardXp,
				if encounter.RewardGems > 0 then " · 💎 " .. encounter.RewardGems else "",
				if clears == 0 then " · First clear: 💎" .. encounter.FirstClearGems else ""
			)
			Kit.text({
				Text = rewardText,
				TextColor3 = C.Gold,
				TextXAlignment = Enum.TextXAlignment.Left,
				Size = UDim2.new(1, -170, 0, 22),
				Position = UDim2.fromOffset(10, 56),
				MaxTextSize = 14,
				Parent = card,
			})
			Kit.text({
				Text = string.format(
					'Recommended 💪 <font color="#%s">%s</font> · cleared %d×',
					color:ToHex(),
					Format.number(recommended),
					clears
				),
				TextXAlignment = Enum.TextXAlignment.Left,
				Size = UDim2.new(1, -170, 0, 22),
				Position = UDim2.fromOffset(10, 80),
				MaxTextSize = 14,
				Parent = card,
			})
			local cooldown = profile.Progression.EncounterCooldowns[encounter.Id]
			local remaining = if cooldown then cooldown - StateController.serverTime() else 0
			local fight = Kit.button(
				if remaining > 0 then "⏱ " .. Format.duration(remaining) else "Fight!",
				if encounter.IsBoss then "Bad" else "Good",
				function()
					startEncounter(encounter.Id)
				end,
				{ Size = UDim2.fromOffset(150, 52), Position = UDim2.new(1, -160, 0.5, -26), Parent = card }
			)
			Kit.setEnabled(fight, remaining <= 0 and #profile.Battle.Team > 0)
		end
	end
	renderPrep = doRender
	doRender()
end

-- Battle screen ------------------------------------------------------------------------------

local function unitById(id: string): any
	if not snapshot then
		return nil
	end
	for _, u in snapshot.Units do
		if u.Id == id then
			return u
		end
	end
	return nil
end

local function addLog(text: string)
	table.insert(logLines, text)
	while #logLines > 40 do
		table.remove(logLines, 1)
	end
	local s = screen
	local logBox = s and s:FindFirstChild("Log", true)
	if logBox and logBox:IsA("TextLabel") then
		logBox.Text = table.concat(logLines, "\n")
	end
end

local function sendAction(kind: string, abilityId: string?, targetId: string?, itemId: string?)
	if not snapshot then
		return
	end
	pendingAbility = nil
	local result = Net.request("BattleAction", snapshot.Id, kind, abilityId, targetId, itemId)
	if not result.ok and result.err then
		UIController.toast("error", result.err)
	end
end

local function needsTarget(abilityId: string): string?
	local ability = AbilityConfig.Abilities[abilityId]
	if not ability then
		return nil
	end
	if ability.Target == "SingleEnemy" then
		return "Enemy"
	elseif ability.Target == "SingleAlly" then
		return "Player"
	end
	return nil
end

local renderBattle: () -> ()

local function unitCard(parent: Instance, unit: any, order: number): Frame
	local isActive = snapshot.Active == unit.Id
	local targetingSide = pendingAbility and needsTarget(pendingAbility)
	local targetable = targetingSide ~= nil and unit.Side == targetingSide and unit.Alive
	local element = CombatConfig.Elements[unit.Element]
	local card = Kit.card({
		BackgroundColor3 = if unit.Alive then C.PanelDark else Color3.fromRGB(30, 30, 36),
		LayoutOrder = order,
		Parent = parent,
	})
	Kit.stroke(
		card,
		if isActive
			then C.Gold
			elseif targetable then C.Good
			elseif unit.IsBoss then C.Bad
			else (if element then element.Color else C.Stroke),
		if isActive or targetable then 4 else 2
	)
	local holder = Kit.frame({
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(0.36, 0.56),
		Position = UDim2.fromScale(0.03, 0.06),
		Parent = card,
	})
	Kit.aspect(holder, 1)
	if unit.MonsterId then
		Icons.monster(unit.MonsterId, holder)
	else
		local tile = Kit.frame({
			BackgroundColor3 = if element then element.Color:Lerp(Color3.new(0, 0, 0), 0.3) else C.Disabled,
			Size = UDim2.fromScale(1, 1),
			Parent = holder,
		})
		Kit.corner(tile, 8)
		Kit.text({
			Text = (if unit.IsBoss then "👑" else "") .. (if element then element.Glyph else "?"),
			MaxTextSize = 36,
			Parent = tile,
		})
	end
	local name = Kit.text({
		Text = unit.Name .. "  Lv" .. unit.Level,
		Font = Theme.Fonts.Title,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(0.6, 0, 0.2, 0),
		Position = UDim2.fromScale(0.4, 0.04),
		MaxTextSize = 17,
		Parent = card,
	})
	Kit.textStroke(name)
	local _, setHp = Kit.progress(
		card,
		if unit.Hp / unit.MaxHp > 0.5 then C.Good elseif unit.Hp / unit.MaxHp > 0.25 then C.Warn else C.Bad,
		{ Size = UDim2.new(0.57, 0, 0.16, 0), Position = UDim2.fromScale(0.4, 0.28) }
	)
	setHp(unit.Hp / unit.MaxHp, Format.number(unit.Hp) .. " / " .. Format.number(unit.MaxHp))
	local _, setEnergy = Kit.progress(
		card,
		C.Gem,
		{ Size = UDim2.new(0.57, 0, 0.1, 0), Position = UDim2.fromScale(0.4, 0.47) }
	)
	setEnergy(
		unit.Energy / CombatConfig.MaxEnergy,
		if unit.Energy >= CombatConfig.MaxEnergy then "ULT READY" else ""
	)
	local statusTexts = {}
	for _, s in unit.Statuses do
		local def = CombatConfig.StatusEffects[s.Id]
		if def then
			table.insert(
				statusTexts,
				def.Glyph .. s.Duration .. (if s.Stacks > 1 then "×" .. s.Stacks else "")
			)
		end
	end
	Kit.text({
		Text = table.concat(statusTexts, " "),
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(0.94, 0, 0.18, 0),
		Position = UDim2.fromScale(0.04, 0.64),
		MaxTextSize = 15,
		Parent = card,
	})
	if unit.Charging then
		local ability = AbilityConfig.Abilities[unit.Charging]
		Kit.text({
			Text = "⚠ Charging " .. (if ability then ability.Name else "") .. "! Defend!",
			TextColor3 = C.Bad,
			Font = Theme.Fonts.Bold,
			Size = UDim2.new(0.94, 0, 0.16, 0),
			Position = UDim2.fromScale(0.04, 0.82),
			MaxTextSize = 14,
			Parent = card,
		})
	elseif not unit.Alive then
		Kit.text({
			Text = "💀 Defeated",
			TextColor3 = C.Muted,
			Font = Theme.Fonts.Bold,
			Size = UDim2.new(0.94, 0, 0.16, 0),
			Position = UDim2.fromScale(0.04, 0.82),
			MaxTextSize = 14,
			Parent = card,
		})
	end
	if targetable then
		local hit = Instance.new("TextButton")
		hit.Text = ""
		hit.BackgroundTransparency = 1
		hit.Size = UDim2.fromScale(1, 1)
		hit.ZIndex = 10
		hit.Parent = card
		hit.Activated:Connect(function()
			if pendingAbility then
				sendAction("Ability", pendingAbility, unit.Id, nil)
			end
		end)
	end
	unitCards[unit.Id] = card
	return card
end

local function showResult(s: any)
	local frame = screen
	if not frame then
		return
	end
	local victory = s.State == "Victory"
	local rewards = s.Rewards or {}
	AudioController.play(if victory then "Victory" else "Defeat")
	local box = Kit.frame({
		Name = "Result",
		BackgroundColor3 = C.Panel,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(460, 360),
		ZIndex = 40,
		Parent = frame,
	})
	Kit.corner(box)
	Kit.stroke(box, if victory then C.Gold else C.Bad, 4)
	Kit.padding(box, 14)
	Kit.list(box, Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Center)
	local title = Kit.text({
		Text = if victory then "🏆 VICTORY!" else "💀 Defeat",
		Font = Theme.Fonts.Title,
		TextColor3 = if victory then C.Gold else C.Bad,
		Size = UDim2.new(1, 0, 0, 50),
		ZIndex = 41,
		MaxTextSize = 44,
		Parent = box,
	})
	Kit.textStroke(title, Color3.new(0, 0, 0), 2)
	local lines = {}
	if s.EndReason and not victory then
		table.insert(lines, s.EndReason)
	end
	if rewards.Coins then
		table.insert(lines, "💰 +" .. Format.number(rewards.Coins))
	end
	if rewards.Gems then
		table.insert(
			lines,
			"💎 +" .. rewards.Gems .. (if rewards.FirstClear then " (first clear bonus!)" else "")
		)
	end
	if rewards.RatingChange then
		table.insert(
			lines,
			string.format(
				"🏟 Rating %s%d → %d",
				if rewards.RatingChange >= 0 then "+" else "",
				rewards.RatingChange,
				rewards.Rating or 0
			)
		)
	end
	if rewards.Drops then
		for key, amount in rewards.Drops do
			table.insert(lines, Icons.rewardLabel(key, amount, Format.number))
		end
	end
	local leveled = 0
	for _, entry in rewards.Xp or {} do
		leveled += entry.Levels or 0
	end
	if leveled > 0 then
		table.insert(lines, "⬆ " .. leveled .. " level-up(s)!")
	end
	for i, line in lines do
		Kit.text({
			Text = line,
			Size = UDim2.new(1, 0, 0, 24),
			LayoutOrder = i + 1,
			ZIndex = 41,
			MaxTextSize = 18,
			Parent = box,
		})
	end
	local continue = Kit.button("Continue", "Good", function()
		CombatController.closeScreen()
	end, { Size = UDim2.new(0.6, 0, 0, 46), LayoutOrder = 99, Parent = box })
	for _, d in continue:GetDescendants() do
		if d:IsA("GuiObject") then
			d.ZIndex = 42
		end
	end
	continue.ZIndex = 41
	if victory then
		EffectsController.flash(C.Gold, 0.25)
	end
end

renderBattle = function()
	local frame = screen
	local s = snapshot
	if not frame or not s then
		return
	end
	local enemies = frame:FindFirstChild("Enemies", true) :: Frame
	local players = frame:FindFirstChild("Players", true) :: Frame
	local actions = frame:FindFirstChild("Actions", true) :: Frame
	local header = frame:FindFirstChild("HeaderText", true) :: TextLabel
	local order = frame:FindFirstChild("Order", true) :: TextLabel
	Kit.clear(enemies)
	Kit.clear(players)
	unitCards = {}
	local ei, pi = 0, 0
	for _, unit in s.Units do
		if unit.Side == "Enemy" then
			ei += 1
			unitCard(enemies, unit, ei)
		else
			pi += 1
			unitCard(players, unit, pi)
		end
	end
	header.Text = string.format(
		"%s  ·  Round %d",
		s.OpponentName
			or (
				if s.EncounterId and EnemyConfig.Encounters[s.EncounterId]
					then EnemyConfig.Encounters[s.EncounterId].DisplayName
					else "Battle"
			),
		s.Round
	)
	local queueNames = {}
	for _, id in s.Queue do
		local u = unitById(id)
		if u then
			table.insert(queueNames, (if u.Side == "Player" then "🟦" else "🟥") .. u.Name)
		end
	end
	order.Text = "Next: " .. table.concat(queueNames, " → ")
	Kit.clear(actions)
	local active = s.Active and unitById(s.Active)
	if s.State == "PlayerTurn" and active and not playing then
		if pendingAbility then
			local ability = AbilityConfig.Abilities[pendingAbility]
			Kit.text({
				Text = "🎯 Choose a target for " .. (if ability then ability.Name else "?"),
				Font = Theme.Fonts.Bold,
				TextColor3 = C.Good,
				Size = UDim2.new(0.7, 0, 1, 0),
				MaxTextSize = 20,
				Parent = actions,
			})
			Kit.button(
				"Cancel",
				"Dark",
				function()
					pendingAbility = nil
					renderBattle()
				end,
				{ Size = UDim2.new(0.25, 0, 0.8, 0), Position = UDim2.fromScale(0.74, 0.1), Parent = actions }
			)
			return
		end
		Kit.list(actions, Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Center)
		for i, entry in active.Abilities do
			local ability = AbilityConfig.Abilities[entry.Id]
			if ability then
				local element = CombatConfig.Elements[ability.Element or active.Element]
				local label = (if element then element.Glyph .. " " else "") .. ability.Name
				if not entry.Ready then
					label ..= if ability.Kind == "Ultimate" then " (energy)" else " ⏱" .. entry.Cooldown
				end
				local b = Kit.button(
					label,
					if ability.Kind == "Ultimate"
						then "Gold"
						elseif ability.Kind == "Special" then "Primary"
						else "Dark",
					function()
						if needsTarget(entry.Id) then
							pendingAbility = entry.Id
							renderBattle()
						else
							sendAction("Ability", entry.Id, nil, nil)
						end
					end,
					{ Size = UDim2.new(0, 150, 1, 0), LayoutOrder = i, Parent = actions }
				)
				Kit.setEnabled(b, entry.Ready)
			end
		end
		Kit.button("✋ Defend", "Ghost", function()
			sendAction("Defend", nil, nil, nil)
		end, { Size = UDim2.new(0, 110, 1, 0), LayoutOrder = 10, Parent = actions })
		local profile = StateController.Profile
		for _, itemId in { "battle_tonic", "grand_elixir" } do
			local count = profile and profile.Inventory.Consumables[itemId] or 0
			local def = CraftingConfig.Consumables[itemId]
			if count > 0 and def and s.ItemsUsed < s.MaxItems then
				Kit.button(def.Glyph .. " x" .. count, "Good", function()
					if def.HealAll then
						sendAction("Item", nil, nil, itemId)
					else
						-- heal the most injured living ally
						local best, bestFrac = nil, 2
						for _, u in s.Units do
							if u.Side == "Player" and u.Alive and u.Hp / u.MaxHp < bestFrac then
								best, bestFrac = u, u.Hp / u.MaxHp
							end
						end
						if best then
							sendAction("Item", nil, best.Id, itemId)
						end
					end
				end, { Size = UDim2.new(0, 90, 1, 0), LayoutOrder = 11, Parent = actions })
			end
		end
	elseif s.State == "Running" or s.State == "PlayerTurn" then
		Kit.text({ Text = "⏳ Enemy turn…", TextColor3 = C.Muted, MaxTextSize = 20, Parent = actions })
	end
	if
		(s.State == "Victory" or s.State == "Defeat")
		and not playing
		and not frame:FindFirstChild("Result")
	then
		showResult(s)
	end
end

local function describe(e: any): string?
	local function nameOf(id: string?): string
		local u = id and unitById(id)
		return if u then u.Name else "?"
	end
	if e.Type == "Damage" then
		local text =
			string.format("%s hits %s for %s", nameOf(e.Source), nameOf(e.Target), Format.number(e.Amount))
		if e.Crit then
			text ..= " (CRIT!)"
		end
		if e.Effectiveness and e.Effectiveness > 1 then
			text ..= " Super effective!"
		elseif e.Effectiveness and e.Effectiveness < 1 and e.Effectiveness > 0 then
			text ..= " Resisted."
		elseif e.Effectiveness == 0 then
			text ..= " Immune!"
		end
		return text
	elseif e.Type == "Tick" then
		return string.format("%s takes %s from %s", nameOf(e.Target), Format.number(e.Amount), e.Status)
	elseif e.Type == "Heal" then
		return if e.Amount > 0
			then string.format("%s heals %s", nameOf(e.Target), Format.number(e.Amount))
			else nil
	elseif e.Type == "Miss" then
		return nameOf(e.Source) .. " missed!"
	elseif e.Type == "Status" then
		return nameOf(e.Target) .. " gains " .. e.Status
	elseif e.Type == "Resist" then
		return nameOf(e.Target) .. " resisted " .. e.Status
	elseif e.Type == "Defeated" then
		return "💀 " .. nameOf(e.Unit) .. " was defeated!"
	elseif e.Type == "Skip" then
		return nameOf(e.Unit) .. " can't move (" .. e.Status .. ")"
	elseif e.Type == "Phase" then
		return "⚠ " .. e.Message
	elseif e.Type == "Summon" then
		return "⚠ " .. (e.Name or "A minion") .. " joins the fight!"
	elseif e.Type == "Charging" then
		local ability = AbilityConfig.Abilities[e.Ability]
		return "⚠ "
			.. nameOf(e.Unit)
			.. " is charging "
			.. (if ability then ability.Name else "something big")
			.. "!"
	elseif e.Type == "Ability" then
		local ability = AbilityConfig.Abilities[e.Ability]
		return nameOf(e.Source) .. " uses " .. (if ability then ability.Name else e.Ability)
	elseif e.Type == "Defend" then
		return nameOf(e.Source) .. " is guarding"
	elseif e.Type == "Item" then
		return nameOf(e.Source) .. " used an item"
	elseif e.Type == "Round" then
		return "— Round " .. e.Round .. " —"
	end
	return nil
end

local function animateEvent(e: any)
	local card = e.Target and unitCards[e.Target]
	if e.Type == "Damage" or e.Type == "Tick" then
		if card then
			local color = if e.Crit
				then C.Gold
				elseif e.Effectiveness and e.Effectiveness > 1 then Color3.fromRGB(255, 140, 60)
				else C.Bad
			EffectsController.floatText(
				card,
				"-" .. Format.number(e.Amount) .. (if e.Crit then "!" else ""),
				color
			)
			Kit.pop(card, if e.Crit then 0.08 else 0.04)
		end
		AudioController.play(if e.Crit then "Critical" else "HitBasic")
		if e.Crit then
			EffectsController.shake(0.15, 0.2)
		end
	elseif e.Type == "Heal" and card and e.Amount > 0 then
		EffectsController.floatText(card, "+" .. Format.number(e.Amount), C.Good)
		AudioController.play("Heal")
	elseif e.Type == "Miss" and card then
		EffectsController.floatText(card, "MISS", C.Muted)
	elseif e.Type == "Phase" then
		UIController.announce(e.Message, C.Bad, true)
		AudioController.play("Roar")
	elseif e.Type == "Charging" then
		AudioController.play("BossUltimate")
	end
end

-- Plays queued updates one after another so animations never overlap.
local function pump()
	if playing then
		return
	end
	playing = true
	while #queue > 0 do
		local item = table.remove(queue, 1) :: { any }
		local newSnapshot, events = item[1], item[2]
		local reduced = StateController.Profile ~= nil and StateController.Profile.Settings.ReducedEffects
		for _, e in events or {} do
			local line = describe(e)
			if line then
				addLog(line)
			end
			if snapshot and screen then
				animateEvent(e)
				if
					e.Type == "Damage"
					or e.Type == "Tick"
					or e.Type == "Heal"
					or e.Type == "Phase"
					or e.Type == "Defeated"
				then
					task.wait(if reduced then 0.08 else 0.32)
				end
			end
		end
		snapshot = newSnapshot
		if #queue == 0 then
			playing = false
		end
		renderBattle()
	end
	playing = false
	renderBattle()
end

function CombatController.openScreen()
	if screen then
		return
	end
	logLines = {}
	local frame = Kit.frame({
		Name = "BattleScreen",
		BackgroundColor3 = C.Backdrop,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 20,
		Parent = UIController.overlay(),
	})
	Kit.gradient(frame, Color3.fromRGB(40, 36, 80), Color3.fromRGB(10, 12, 24), 90)
	Kit.padding(frame, 14)
	local top = Kit.frame({ BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 44), Parent = frame })
	local headerText = Kit.text({
		Name = "HeaderText",
		Text = "",
		Font = Theme.Fonts.Title,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(0.7, 0, 1, 0),
		MaxTextSize = 28,
		Parent = top,
	})
	Kit.textStroke(headerText, Color3.new(0, 0, 0), 2)
	Kit.button("🏳 Flee", "Bad", function()
		if
			UIController.confirm(
				"Flee battle?",
				"You will lose this battle and get no rewards.",
				"Flee",
				true
			)
		then
			Net.request("ForfeitBattle")
		end
	end, { Size = UDim2.fromOffset(120, 40), Position = UDim2.new(1, -120, 0, 2), Parent = top })
	local main = Kit.frame({
		BackgroundTransparency = 1,
		Size = UDim2.new(0.74, 0, 1, -170),
		Position = UDim2.fromOffset(0, 52),
		Parent = frame,
	})
	local enemies = Kit.frame({
		Name = "Enemies",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0.46, 0),
		Parent = main,
	})
	Kit.grid(enemies, UDim2.new(0.25, -8, 1, 0), 8).HorizontalAlignment = Enum.HorizontalAlignment.Center
	local players = Kit.frame({
		Name = "Players",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0.46, 0),
		Position = UDim2.fromScale(0, 0.54),
		Parent = main,
	})
	Kit.grid(players, UDim2.new(1 / 3, -8, 1, 0), 8).HorizontalAlignment = Enum.HorizontalAlignment.Center
	local logPanel = Kit.frame({
		BackgroundColor3 = C.PanelDark,
		BackgroundTransparency = 0.2,
		Size = UDim2.new(0.25, 0, 1, -170),
		Position = UDim2.new(0.75, 0, 0, 52),
		Parent = frame,
	})
	Kit.corner(logPanel)
	Kit.padding(logPanel, 8)
	local logScroll = Kit.scroll({ Parent = logPanel })
	Kit.text({
		Name = "Log",
		Text = "",
		TextScaled = false,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Bottom,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, -8, 0, 0),
		TextColor3 = C.Muted,
		Parent = logScroll,
	})
	Kit.text({
		Name = "Order",
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = C.Muted,
		Size = UDim2.new(1, 0, 0, 24),
		Position = UDim2.new(0, 0, 1, -112),
		MaxTextSize = 15,
		Parent = frame,
	})
	local actions = Kit.frame({
		Name = "Actions",
		BackgroundColor3 = C.PanelDark,
		BackgroundTransparency = 0.15,
		Size = UDim2.new(1, 0, 0, 80),
		Position = UDim2.new(0, 0, 1, -80),
		Parent = frame,
	})
	Kit.corner(actions)
	Kit.padding(actions, 10)
	screen = frame
end

function CombatController.closeScreen()
	if screen then
		screen:Destroy()
		screen = nil
	end
	snapshot = nil
	pendingAbility = nil
	queue = {}
	playing = false
	if renderPrep then
		renderPrep()
	end
end

function CombatController.onUpdate(newSnapshot: any, events: { any })
	if not screen then
		CombatController.openScreen()
		UIController.close()
	end
	if not snapshot then
		snapshot = newSnapshot
	end
	table.insert(queue, { newSnapshot, events })
	task.spawn(pump)
end

function CombatController.init()
	UIController.registerPanel({
		Id = "Battle",
		Title = "Battle",
		Glyph = "⚔",
		Wide = true,
		Build = buildPrep,
		OnOpen = function(args)
			if typeof(args) == "table" and args.Region then
				selectedRegion = args.Region
			end
			if renderPrep then
				renderPrep()
			end
		end,
	})
	Net.on("BattleUpdate", CombatController.onUpdate)
end

function CombatController.start()
	StateController.Changed:Connect(function(key)
		if
			UIController.openId() == "Battle"
			and renderPrep
			and (key == "Battle" or key == "Monsters" or key == "Progression" or key == "*")
		then
			renderPrep()
		end
	end)
end

return CombatController
