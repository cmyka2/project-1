--!strict
-- Skill tree and Ascension tree (pannable/zoomable canvas with connection
-- lines), the Rebirth panel (exact costs, rewards, reset/keep lists) and the
-- region map (requirements, unlock, travel).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Util = Shared:WaitForChild("Util")
local SkillTreeConfig = require(Config:WaitForChild("SkillTreeConfig"))
local RebirthConfig = require(Config:WaitForChild("RebirthConfig"))
local RegionConfig = require(Config:WaitForChild("RegionConfig"))
local BaseLayout = require(Util:WaitForChild("BaseLayout"))
local Format = require(Util:WaitForChild("Format"))
local UI = script.Parent.Parent:WaitForChild("UI")
local Kit = require(UI:WaitForChild("Kit"))
local Theme = require(UI:WaitForChild("Theme"))
local StateController = require(script.Parent:WaitForChild("StateController"))
local UIController = require(script.Parent:WaitForChild("UIController"))
local AudioController = require(script.Parent:WaitForChild("AudioController"))

local C = Theme.Colors

local ProgressionController = {}

local renderers: { [string]: () -> () } = {}

-- Generic tree canvas -------------------------------------------------------------------

type TreeNode = {
	Id: string,
	Name: string,
	Description: string,
	Icon: string,
	Position: Vector2,
	MaxLevel: number,
	Prerequisites: { string },
	Effects: { { Key: string, PerLevel: number } },
	Color: Color3,
	Requirement: string?,
}

type TreeSpec = {
	Nodes: { TreeNode },
	Level: (string) -> number,
	Cost: (TreeNode, number) -> number,
	CurrencyGlyph: string,
	Balance: () -> number,
	Buy: (string) -> (),
	Locked: (TreeNode) -> string?, -- reason or nil
}

local CELL = 112

local function formatEffect(effect: { Key: string, PerLevel: number }, level: number): string
	local total = effect.PerLevel * level
	if math.abs(effect.PerLevel) < 1 then
		return Format.percent(total, 1)
	end
	return tostring(math.floor(total))
end

local function buildTree(container: Frame, spec: TreeSpec): () -> ()
	local canvasHolder = Kit.scroll({
		Size = UDim2.new(0.68, -6, 1, -44),
		Position = UDim2.fromOffset(0, 44),
		ScrollingDirection = Enum.ScrollingDirection.XY,
		AutomaticCanvasSize = Enum.AutomaticSize.None,
		ElasticBehavior = Enum.ElasticBehavior.Always,
		Parent = container,
	})
	canvasHolder.BackgroundTransparency = 0
	canvasHolder.BackgroundColor3 = C.PanelDark
	Kit.corner(canvasHolder)
	local canvas = Kit.frame({
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(CELL * 13, CELL * 6.5),
		Parent = canvasHolder,
	})
	local zoom = Kit.scale(canvas)
	local function applyZoom()
		canvasHolder.CanvasSize = UDim2.fromOffset(CELL * 13 * zoom.Scale, CELL * 6.5 * zoom.Scale)
	end
	applyZoom()
	local zoomBar =
		Kit.frame({ BackgroundTransparency = 1, Size = UDim2.new(0.68, -6, 0, 38), Parent = container })
	Kit.list(zoomBar, Enum.FillDirection.Horizontal, 6)
	Kit.button("➖", "Dark", function()
		zoom.Scale = math.max(0.5, zoom.Scale - 0.15)
		applyZoom()
	end, { Size = UDim2.fromOffset(44, 36), Parent = zoomBar })
	Kit.button("➕", "Dark", function()
		zoom.Scale = math.min(1.6, zoom.Scale + 0.15)
		applyZoom()
	end, { Size = UDim2.fromOffset(44, 36), Parent = zoomBar })
	local balance = Kit.text({
		Text = "",
		Font = Theme.Fonts.Title,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(0, 260, 1, 0),
		MaxTextSize = 20,
		Parent = zoomBar,
	})
	local info = Kit.frame({
		BackgroundColor3 = C.PanelDark,
		Size = UDim2.new(0.32, -6, 1, 0),
		Position = UDim2.new(0.68, 6, 0, 0),
		Parent = container,
	})
	Kit.corner(info)
	Kit.padding(info, 10)
	local selected: string? = nil
	local nodesById: { [string]: TreeNode } = {}
	for _, node in spec.Nodes do
		nodesById[node.Id] = node
	end

	local function center(node: TreeNode): Vector2
		return Vector2.new(node.Position.X * CELL + CELL * 0.5, node.Position.Y * CELL)
	end

	local render: () -> ()
	local function renderInfo()
		Kit.clear(info)
		local node = selected and nodesById[selected]
		if not node then
			Kit.text({
				Text = "Tap a node to see what it does.\nDrag to pan, ➕/➖ to zoom.",
				TextColor3 = C.Muted,
				Size = UDim2.new(1, 0, 0, 60),
				Parent = info,
			})
			return
		end
		Kit.list(info, Enum.FillDirection.Vertical, 6)
		local level = spec.Level(node.Id)
		Kit.header(node.Icon .. " " .. node.Name, { LayoutOrder = 1, Parent = info })
		local nowText = string.gsub(
			node.Description,
			"{v}",
			if node.Effects[1] then formatEffect(node.Effects[1], level) else ""
		)
		local nextText = string.gsub(
			node.Description,
			"{v}",
			if node.Effects[1] then formatEffect(node.Effects[1], math.min(node.MaxLevel, level + 1)) else ""
		)
		Kit.text({
			Text = string.format(
				"Level %d / %d\nNow: %s\nNext: %s",
				level,
				node.MaxLevel,
				if level > 0 then nowText else "—",
				if level < node.MaxLevel then nextText else "MAXED"
			),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			Size = UDim2.new(1, 0, 0, 90),
			LayoutOrder = 2,
			MaxTextSize = 16,
			Parent = info,
		})
		if #node.Prerequisites > 0 then
			local names = {}
			for _, pre in node.Prerequisites do
				local p = nodesById[pre]
				local done = spec.Level(pre) > 0
				table.insert(names, (if done then "✓ " else "✗ ") .. (if p then p.Name else pre))
			end
			Kit.text({
				Text = "Requires:\n" .. table.concat(names, "\n"),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top,
				TextColor3 = C.Muted,
				Size = UDim2.new(1, 0, 0, 22 * (#names + 1)),
				LayoutOrder = 3,
				MaxTextSize = 14,
				Parent = info,
			})
		end
		if node.Requirement then
			Kit.text({
				Text = node.Requirement,
				TextColor3 = C.Warn,
				Size = UDim2.new(1, 0, 0, 22),
				LayoutOrder = 4,
				MaxTextSize = 14,
				Parent = info,
			})
		end
		if level < node.MaxLevel then
			local cost = spec.Cost(node, level)
			local reason = spec.Locked(node)
			local buy = Kit.button(
				string.format("Buy %s %s", spec.CurrencyGlyph, Format.number(cost)),
				"Good",
				function()
					spec.Buy(node.Id)
				end,
				{ Size = UDim2.new(1, 0, 0, 46), LayoutOrder = 5, Parent = info }
			)
			Kit.setEnabled(buy, reason == nil and spec.Balance() >= cost)
			if reason then
				Kit.text({
					Text = reason,
					TextColor3 = C.Bad,
					Size = UDim2.new(1, 0, 0, 22),
					LayoutOrder = 6,
					MaxTextSize = 14,
					Parent = info,
				})
			end
		end
	end

	render = function()
		Kit.clear(canvas)
		balance.Text = spec.CurrencyGlyph .. " " .. Format.number(spec.Balance())
		-- connection lines
		for _, node in spec.Nodes do
			for _, pre in node.Prerequisites do
				local p = nodesById[pre]
				if p then
					local a, b = center(p), center(node)
					local mid = (a + b) / 2
					local delta = b - a
					Kit.frame({
						BackgroundColor3 = if spec.Level(pre) > 0 then node.Color else C.Disabled,
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.fromOffset(mid.X, mid.Y),
						Size = UDim2.fromOffset(delta.Magnitude, 4),
						Rotation = math.deg(math.atan2(delta.Y, delta.X)),
						ZIndex = 1,
						Parent = canvas,
					})
				end
			end
		end
		-- nodes
		for _, node in spec.Nodes do
			local level = spec.Level(node.Id)
			local locked = spec.Locked(node) ~= nil
			local maxed = level >= node.MaxLevel
			local color = if maxed
				then C.Gold
				elseif level > 0 then node.Color
				elseif locked then C.Disabled
				else node.Color:Lerp(C.PanelDark, 0.45)
			local c = center(node)
			local b = Instance.new("TextButton")
			b.Text = ""
			b.AutoButtonColor = false
			b.AnchorPoint = Vector2.new(0.5, 0.5)
			b.Position = UDim2.fromOffset(c.X, c.Y)
			b.Size = UDim2.fromOffset(70, 70)
			b.BackgroundColor3 = color
			b.ZIndex = 3
			b.Parent = canvas
			Kit.corner(b, 35)
			Kit.stroke(
				b,
				if selected == node.Id then C.Text else color:Lerp(Color3.new(0, 0, 0), 0.4),
				if selected == node.Id then 4 else 3
			)
			Kit.text({
				Text = node.Icon,
				Size = UDim2.fromScale(1, 0.62),
				ZIndex = 4,
				MaxTextSize = 30,
				Parent = b,
			})
			local lv = Kit.text({
				Text = level .. "/" .. node.MaxLevel,
				Font = Theme.Fonts.Title,
				Size = UDim2.fromScale(1, 0.34),
				Position = UDim2.fromScale(0, 0.62),
				ZIndex = 4,
				MaxTextSize = 15,
				Parent = b,
			})
			Kit.textStroke(lv)
			b.Activated:Connect(function()
				selected = node.Id
				render()
			end)
		end
		renderInfo()
	end
	return render
end

local function skillSpec(): TreeSpec
	local nodes: { TreeNode } = {}
	for _, id in SkillTreeConfig.NodeOrder do
		local def = SkillTreeConfig.Nodes[id]
		table.insert(nodes, {
			Id = def.Id,
			Name = def.Name,
			Description = def.Description,
			Icon = def.Icon,
			Position = def.Position,
			MaxLevel = def.MaxLevel,
			Prerequisites = def.Prerequisites,
			Effects = def.Effects,
			Color = SkillTreeConfig.Branches[def.Branch].Color,
			Requirement = if def.RequiredRebirths > 0
				then "Requires " .. def.RequiredRebirths .. " rebirth(s)"
				else nil,
		})
	end
	return {
		Nodes = nodes,
		Level = function(id)
			local profile = StateController.Profile
			return if profile then profile.Skills.Nodes[id] or 0 else 0
		end,
		Cost = function(node, level)
			return SkillTreeConfig.costOf(SkillTreeConfig.Nodes[node.Id], level)
		end,
		CurrencyGlyph = "💎",
		Balance = function()
			local profile = StateController.Profile
			return if profile then profile.Currencies.Gems else 0
		end,
		Buy = function(id)
			local result = UIController.call("BuySkillNode", id)
			if result.ok then
				AudioController.play("Upgrade")
			end
		end,
		Locked = function(node)
			local profile = StateController.Profile
			if not profile then
				return "Loading"
			end
			local def = SkillTreeConfig.Nodes[node.Id]
			if profile.Progression.RebirthCount < def.RequiredRebirths then
				return "Requires " .. def.RequiredRebirths .. " rebirth(s)"
			end
			for _, pre in def.Prerequisites do
				if (profile.Skills.Nodes[pre] or 0) < 1 then
					return "Unlock the connected skills first"
				end
			end
			return nil
		end,
	}
end

local function ascensionSpec(): TreeSpec
	local nodes: { TreeNode } = {}
	for _, id in RebirthConfig.AscensionOrder do
		local def = RebirthConfig.AscensionNodes[id]
		table.insert(nodes, {
			Id = def.Id,
			Name = def.Name,
			Description = def.Description,
			Icon = def.Icon,
			Position = Vector2.new(def.Position.X * 1.3, def.Position.Y * 1.2),
			MaxLevel = def.MaxLevel,
			Prerequisites = def.Prerequisites,
			Effects = def.Effects,
			Color = C.Ascension,
			Requirement = nil,
		})
	end
	return {
		Nodes = nodes,
		Level = function(id)
			local profile = StateController.Profile
			return if profile then profile.Progression.AscensionUpgrades[id] or 0 else 0
		end,
		Cost = function(node, level)
			return RebirthConfig.ascensionCost(RebirthConfig.AscensionNodes[node.Id], level)
		end,
		CurrencyGlyph = "🌟",
		Balance = function()
			local profile = StateController.Profile
			return if profile then profile.Currencies.AscensionPoints else 0
		end,
		Buy = function(id)
			local result = UIController.call("BuyAscensionNode", id)
			if result.ok then
				AudioController.play("Upgrade")
			end
		end,
		Locked = function(node)
			local profile = StateController.Profile
			if not profile then
				return "Loading"
			end
			for _, pre in RebirthConfig.AscensionNodes[node.Id].Prerequisites do
				if (profile.Progression.AscensionUpgrades[pre] or 0) < 1 then
					return "Unlock the connected upgrades first"
				end
			end
			return nil
		end,
	}
end

local function buildSkills(body: Frame)
	local holder = Kit.frame({
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, -44),
		Position = UDim2.fromOffset(0, 0),
		Parent = body,
	})
	local render = buildTree(holder, skillSpec())
	Kit.button(
		"♻ Respec (refund all gems, fee 💎" .. SkillTreeConfig.RespecCostGems .. ")",
		"Dark",
		function()
			if
				UIController.confirm(
					"Reset skills?",
					"All gems spent on skills are refunded, minus the respec fee.",
					"Respec",
					true
				)
			then
				UIController.call("RespecSkills")
			end
		end,
		{ Size = UDim2.new(0.68, -6, 0, 38), Position = UDim2.new(0, 0, 1, -38), Parent = body }
	)
	renderers.Skills = render
	render()
end

local function buildAscension(body: Frame)
	local render = buildTree(body, ascensionSpec())
	renderers.Ascension = render
	render()
end

-- Rebirth ----------------------------------------------------------------------------------

local function buildRebirth(body: Frame)
	local scroll = Kit.scroll({ Parent = body })
	Kit.list(scroll, Enum.FillDirection.Vertical, 8)
	local render = function()
		local profile = StateController.Profile
		local derived = StateController.Derived
		if not profile or not derived then
			return
		end
		Kit.clear(scroll)
		local count = profile.Progression.RebirthCount
		local nextCount = count + 1
		Kit.header(
			string.format("♻ Rebirths: %d / %d", count, RebirthConfig.MaxRebirths),
			{ LayoutOrder = 1, Parent = scroll }
		)
		local cost = derived.RebirthCost
		local _, setProgress =
			Kit.progress(scroll, C.Gold, { LayoutOrder = 2, Size = UDim2.new(1, -8, 0, 26) })
		setProgress(
			profile.Currencies.Coins / math.max(1, cost),
			"💰 " .. Format.number(profile.Currencies.Coins) .. " / " .. Format.number(cost)
		)
		local region = RegionConfig.Regions[derived.RebirthRegion]
		local hasRegion = profile.Progression.UnlockedRegions[derived.RebirthRegion] == true
		Kit.text({
			Text = (if hasRegion then "✓ " else "✗ ") .. "Requires " .. (if region
				then region.DisplayName
				else derived.RebirthRegion) .. " unlocked",
			TextColor3 = if hasRegion then C.Good else C.Bad,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(1, -8, 0, 22),
			LayoutOrder = 3,
			MaxTextSize = 16,
			Parent = scroll,
		})
		local floorsNow = BaseLayout.floorCount(count)
		local floorsNext = BaseLayout.floorCount(nextCount)
		local points = RebirthConfig.AscensionPointsPerRebirth
			+ (
				if nextCount % RebirthConfig.AscensionMilestoneEvery == 0
					then RebirthConfig.AscensionMilestoneBonus
					else 0
			)
		local gains = {
			string.format(
				"🏠 +1 base slot (%d → %d)%s",
				BaseLayout.totalSlots(count),
				BaseLayout.totalSlots(nextCount),
				if floorsNext > floorsNow then "  ·  🏢 unlocks Floor " .. floorsNext .. "!" else ""
			),
			string.format(
				"💰 Permanent income +%s (total +%s)",
				Format.percent(RebirthConfig.IncomeBonusPerRebirth, 0),
				Format.percent(RebirthConfig.IncomeBonusPerRebirth * nextCount, 0)
			),
			string.format(
				"🍀 Permanent luck +%s (cap %s)",
				Format.percent(RebirthConfig.LuckBonusPerRebirth, 0),
				Format.percent(RebirthConfig.LuckBonusCap, 0)
			),
			string.format(
				"🌟 +%d Ascension Point(s)   💎 +%d Gems",
				points,
				RebirthConfig.GemsPerRebirth * nextCount
			),
		}
		Kit.header("You gain", { LayoutOrder = 4, Parent = scroll })
		Kit.text({
			Text = table.concat(gains, "\n"),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			Size = UDim2.new(1, -8, 0, 100),
			LayoutOrder = 5,
			MaxTextSize = 17,
			Parent = scroll,
		})
		local resets = {}
		local reset = RebirthConfig.Reset :: any
		if reset.Coins then
			local keep = derived.Modifiers.RebirthKeepCoins or 0
			table.insert(
				resets,
				"💰 Coins" .. (if keep > 0 then " (you keep " .. Format.percent(keep, 0) .. ")" else "")
			)
		end
		if reset.MonsterUpgrades then
			table.insert(resets, "⬆ Monster upgrade ranks (levels, stars and equipment are kept)")
		end
		if reset.Skills then
			table.insert(resets, "🌳 Skill tree")
		end
		if reset.Boosts then
			table.insert(resets, "🧪 Active potions")
		end
		Kit.header("Resets", { LayoutOrder = 6, Parent = scroll })
		Kit.text({
			Text = table.concat(resets, "\n"),
			TextColor3 = C.Bad,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			Size = UDim2.new(1, -8, 0, 24 * #resets),
			LayoutOrder = 7,
			MaxTextSize = 16,
			Parent = scroll,
		})
		Kit.header("You keep", { LayoutOrder = 8, Parent = scroll })
		Kit.text({
			Text = "✓ " .. table.concat(RebirthConfig.KeptDescription, "\n✓ "),
			TextColor3 = C.Good,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			Size = UDim2.new(1, -8, 0, 24 * #RebirthConfig.KeptDescription),
			LayoutOrder = 9,
			MaxTextSize = 15,
			Parent = scroll,
		})
		local button = Kit.button("♻ REBIRTH", "Gold", function()
			if
				UIController.confirm(
					"Rebirth now?",
					"Coins and monster upgrade ranks reset. You keep your monsters and gain permanent bonuses.",
					"Rebirth",
					true
				)
			then
				local result = UIController.call("Rebirth", count)
				if result.ok then
					AudioController.play("Rebirth")
				end
			end
		end, { Size = UDim2.new(1, -8, 0, 56), LayoutOrder = 10, Parent = scroll })
		Kit.setEnabled(button, derived.CanRebirth)
	end
	renderers.Rebirth = render
	render()
end

-- Regions ------------------------------------------------------------------------------------

local function buildRegions(body: Frame)
	local top = Kit.frame({ BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 44), Parent = body })
	Kit.list(top, Enum.FillDirection.Horizontal, 8)
	Kit.button("🏝 Main Island", "Primary", function()
		UIController.call("TravelToHub", false)
		UIController.close()
	end, { Size = UDim2.fromOffset(180, 42), Parent = top })
	Kit.button("🏠 My Base", "Dark", function()
		UIController.call("TravelToHub", true)
		UIController.close()
	end, { Size = UDim2.fromOffset(160, 42), Parent = top })
	local grid =
		Kit.scroll({ Size = UDim2.new(1, 0, 1, -52), Position = UDim2.fromOffset(0, 52), Parent = body })
	Kit.grid(grid, UDim2.new(1 / 3, -8, 0, 190), 8)
	local render = function()
		local profile = StateController.Profile
		if not profile then
			return
		end
		Kit.clear(grid)
		for i, regionId in RegionConfig.Order do
			local region = RegionConfig.Regions[regionId]
			local unlocked = profile.Progression.UnlockedRegions[regionId] == true
			local card = Kit.card({
				BackgroundColor3 = region.Theme.Ground:Lerp(C.PanelDark, 0.6),
				LayoutOrder = i,
				Parent = grid,
			})
			Kit.stroke(card, region.Theme.Accent, 3)
			Kit.padding(card, 8)
			local title = Kit.text({
				Text = (if unlocked then "" else "🔒 ") .. region.DisplayName,
				Font = Theme.Fonts.Title,
				Size = UDim2.new(1, 0, 0, 28),
				MaxTextSize = 22,
				Parent = card,
			})
			Kit.textStroke(title)
			Kit.text({
				Text = region.Description,
				TextColor3 = C.Muted,
				Size = UDim2.new(1, 0, 0, 40),
				Position = UDim2.fromOffset(0, 30),
				MaxTextSize = 14,
				Parent = card,
			})
			local lines = {}
			if not unlocked then
				if region.RequiresBossOf then
					local done = (profile.Progression.BossesDefeated[region.RequiresBossOf] or 0) > 0
					table.insert(
						lines,
						(if done then "✓" else "✗")
							.. " Defeat the "
							.. RegionConfig.Regions[region.RequiresBossOf].DisplayName
							.. " boss"
					)
				end
				if region.RequiredRebirths > 0 then
					table.insert(
						lines,
						(if profile.Progression.RebirthCount >= region.RequiredRebirths then "✓" else "✗")
							.. " "
							.. region.RequiredRebirths
							.. " rebirth(s)"
					)
				end
				table.insert(
					lines,
					(if profile.Currencies.Coins >= region.UnlockCost then "✓" else "✗")
						.. " 💰 "
						.. Format.number(region.UnlockCost)
				)
			else
				table.insert(
					lines,
					"Boss defeated: " .. ((profile.Progression.BossesDefeated[regionId] or 0) .. "×")
				)
			end
			table.insert(lines, "💪 Recommended team power: " .. Format.number(region.RecommendedPower))
			Kit.text({
				Text = table.concat(lines, "\n"),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top,
				Size = UDim2.new(1, 0, 0, 60),
				Position = UDim2.fromOffset(0, 72),
				MaxTextSize = 14,
				Parent = card,
			})
			if unlocked then
				Kit.button("Travel ✈", "Good", function()
					local result = UIController.call("TravelToRegion", regionId)
					if result.ok then
						AudioController.play("RegionTravel")
						UIController.close()
					end
				end, {
					Size = UDim2.new(0.48, 0, 0, 40),
					Position = UDim2.new(0, 0, 1, -40),
					Parent = card,
				})
				Kit.button(
					"Battles ⚔",
					"Primary",
					function()
						UIController.open("Battle", { Region = regionId })
					end,
					{ Size = UDim2.new(0.48, 0, 0, 40), Position = UDim2.new(0.52, 0, 1, -40), Parent = card }
				)
			else
				Kit.button("Unlock", "Gold", function()
					local result = UIController.call("UnlockRegion", regionId)
					if result.ok then
						UIController.toast("success", region.DisplayName .. " unlocked!")
					end
				end, { Size = UDim2.new(1, 0, 0, 40), Position = UDim2.new(0, 0, 1, -40), Parent = card })
			end
		end
	end
	renderers.Regions = render
	render()
end

function ProgressionController.init()
	UIController.registerPanel({
		Id = "Skills",
		Title = "Skill Tree",
		Glyph = "🌳",
		Wide = true,
		Build = buildSkills,
		OnOpen = function()
			if renderers.Skills then
				renderers.Skills()
			end
		end,
	})
	UIController.registerPanel({
		Id = "Ascension",
		Title = "Ascension Tree",
		Glyph = "🌟",
		Wide = true,
		Build = buildAscension,
		OnOpen = function()
			if renderers.Ascension then
				renderers.Ascension()
			end
		end,
	})
	UIController.registerPanel({
		Id = "Rebirth",
		Title = "Rebirth Temple",
		Glyph = "♻",
		Build = buildRebirth,
		OnOpen = function()
			if renderers.Rebirth then
				renderers.Rebirth()
			end
		end,
	})
	UIController.registerPanel({
		Id = "Regions",
		Title = "World Map",
		Glyph = "🗺",
		Wide = true,
		Build = buildRegions,
		OnOpen = function()
			if renderers.Regions then
				renderers.Regions()
			end
		end,
	})
end

function ProgressionController.start()
	StateController.Changed:Connect(function(key)
		local open = UIController.openId()
		if not open or not renderers[open] then
			return
		end
		-- Currencies tick every second from income, so trees only re-render on real changes
		if
			key == "Skills"
			or key == "Progression"
			or key == "*"
			or (key == "Derived" and open ~= "Skills" and open ~= "Ascension")
		then
			renderers[open]()
		end
	end)
end

return ProgressionController
