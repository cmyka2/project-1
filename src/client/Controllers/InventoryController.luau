--!strict
-- Inventory (monsters / equipment / items) and the Codex. Search, sorting,
-- filters, multi-select selling, lock/favorite, detail view with stats,
-- abilities, equipment and actions. Every action is a server request; the
-- UI updates from the replicated state the server sends back.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Util = Shared:WaitForChild("Util")
local MonsterConfig = require(Config:WaitForChild("MonsterConfig"))
local RarityConfig = require(Config:WaitForChild("RarityConfig"))
local RegionConfig = require(Config:WaitForChild("RegionConfig"))
local CombatConfig = require(Config:WaitForChild("CombatConfig"))
local AbilityConfig = require(Config:WaitForChild("AbilityConfig"))
local EquipmentConfig = require(Config:WaitForChild("EquipmentConfig"))
local CraftingConfig = require(Config:WaitForChild("CraftingConfig"))
local ChestConfig = require(Config:WaitForChild("ChestConfig"))
local QuestConfig = require(Config:WaitForChild("QuestConfig"))
local StatMath = require(Util:WaitForChild("StatMath"))
local EquipMath = require(Util:WaitForChild("EquipMath"))
local Codex = require(Util:WaitForChild("Codex"))
local Format = require(Util:WaitForChild("Format"))
local Types = require(Shared:WaitForChild("Types"))
local UI = script.Parent.Parent:WaitForChild("UI")
local Kit = require(UI:WaitForChild("Kit"))
local Theme = require(UI:WaitForChild("Theme"))
local Icons = require(UI:WaitForChild("Icons"))
local Cards = require(UI:WaitForChild("Cards"))
local StateController = require(script.Parent:WaitForChild("StateController"))
local UIController = require(script.Parent:WaitForChild("UIController"))

local C = Theme.Colors

local InventoryController = {}

type MonsterInstance = Types.MonsterInstance

local SORTS = { "Rarity", "Income", "Power", "Level", "Newest", "Name" }
local state = {
	tab = 1,
	search = "",
	sort = 1,
	rarityFilter = 0, -- 0 = all, else tier
	selectedMonster = nil :: string?,
	selectedItem = nil :: string?,
	multiSelect = false,
	multi = {} :: { string },
	codexRegion = 0,
}

local refreshers: { () -> () } = {}

local function mods(): { [string]: number }
	local d = StateController.Derived
	return if d then d.Modifiers else {}
end

function InventoryController.incomeOf(inst: MonsterInstance): number
	local d = StateController.Derived
	if d and d.MonsterIncome[inst.Id] then
		return d.MonsterIncome[inst.Id]
	end
	local equip = EquipMath.monsterBonuses(StateController.equipmentOn(inst.Id)).IncomePct
	return StatMath.monsterIncome(inst, equip, mods()) * (if d then d.IncomeMultiplier else 1)
end

function InventoryController.powerOf(inst: MonsterInstance): number
	return StatMath.power(StatMath.monsterStats(inst, StateController.equipmentOn(inst.Id), mods()))
end

local function sortedMonsters(): { MonsterInstance }
	local list = StateController.monsters()
	local query = string.lower(state.search)
	local filtered = {}
	for _, inst in list do
		local def = MonsterConfig.Monsters[inst.MonsterId]
		if def then
			local okSearch = query == "" or string.find(string.lower(def.DisplayName), query, 1, true) ~= nil
			local okRarity = state.rarityFilter == 0 or RarityConfig.tierOf(def.Rarity) == state.rarityFilter
			if okSearch and okRarity then
				table.insert(filtered, inst)
			end
		end
	end
	local key = SORTS[state.sort]
	local cache: { [string]: number } = {}
	local function value(inst: MonsterInstance): number
		local cached = cache[inst.Id]
		if cached then
			return cached
		end
		local def = MonsterConfig.Monsters[inst.MonsterId]
		local v: number = 0
		if key == "Rarity" then
			v = RarityConfig.tierOf(def.Rarity) * 1e6 + inst.Level * 100 + inst.Upgrade
		elseif key == "Income" then
			v = InventoryController.incomeOf(inst)
		elseif key == "Power" then
			v = InventoryController.powerOf(inst)
		elseif key == "Level" then
			v = inst.Level
		elseif key == "Newest" then
			v = inst.Acquired
		end
		cache[inst.Id] = v
		return v
	end
	table.sort(filtered, function(a, b)
		if key == "Name" then
			return MonsterConfig.Monsters[a.MonsterId].DisplayName
				< MonsterConfig.Monsters[b.MonsterId].DisplayName
		end
		local va, vb = value(a), value(b)
		if va == vb then
			return a.Id < b.Id
		end
		return va > vb
	end)
	return filtered
end

function InventoryController.badges(inst: MonsterInstance): { string }
	local badges = {}
	if StateController.slotOf(inst.Id) then
		table.insert(badges, "🏠")
	end
	if StateController.inTeam(inst.Id) then
		table.insert(badges, "⚔")
	end
	return badges
end

-- Equipment picker ------------------------------------------------------------------

local function equipmentPicker(monsterId: string, category: string)
	local profile = StateController.Profile
	if not profile then
		return
	end
	local items = {}
	for _, item in profile.Inventory.Equipment do
		local def = EquipmentConfig.Items[item.ItemId]
		if def and def.Category == category and item.EquippedTo ~= monsterId then
			table.insert(items, item)
		end
	end
	table.sort(items, function(a, b)
		return RarityConfig.tierOf(EquipmentConfig.Items[a.ItemId].Rarity)
			> RarityConfig.tierOf(EquipmentConfig.Items[b.ItemId].Rarity)
	end)
	local shade = Instance.new("TextButton")
	shade.Text = ""
	shade.AutoButtonColor = false
	shade.BackgroundColor3 = C.Backdrop
	shade.BackgroundTransparency = 0.35
	shade.Size = UDim2.fromScale(1, 1)
	shade.Parent = UIController.overlay()
	local box = Kit.frame({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(520, 460),
		Parent = shade,
	})
	Kit.corner(box)
	Kit.stroke(box)
	Kit.padding(box, 12)
	Kit.header("Equip " .. category, { Parent = box })
	local list =
		Kit.scroll({ Size = UDim2.new(1, 0, 1, -90), Position = UDim2.fromOffset(0, 34), Parent = box })
	Kit.list(list, Enum.FillDirection.Vertical, 6)
	for i, item in items do
		local def = EquipmentConfig.Items[item.ItemId]
		local row = Kit.card({ Size = UDim2.new(1, -8, 0, 50), LayoutOrder = i, Parent = list })
		local holder = Kit.frame({
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(42, 42),
			Position = UDim2.fromOffset(4, 4),
			Parent = row,
		})
		Icons.equipment(item.ItemId, holder)
		local where = if item.EquippedTo then " (moves from another monster)" else ""
		Kit.text({
			Text = def.DisplayName .. " Lv" .. item.Level .. where,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(1, -170, 1, -8),
			Position = UDim2.fromOffset(52, 4),
			MaxTextSize = 16,
			Parent = row,
		})
		Kit.button("Equip", "Good", function()
			shade:Destroy()
			UIController.call("EquipItem", item.Id, monsterId)
		end, { Size = UDim2.fromOffset(100, 38), Position = UDim2.new(1, -106, 0, 6), Parent = row })
	end
	if #items == 0 then
		Kit.text({
			Text = "No " .. category .. " items. Craft some at the Workshop or open chests!",
			TextColor3 = C.Muted,
			Size = UDim2.new(1, 0, 0, 40),
			Parent = list,
		})
	end
	Kit.button("Close", "Dark", function()
		shade:Destroy()
	end, { Size = UDim2.new(1, 0, 0, 44), Position = UDim2.new(0, 0, 1, -44), Parent = box })
end

-- Monster detail -------------------------------------------------------------------------

local function statRow(parent: Instance, label: string, value: string, order: number)
	local row = Kit.frame({
		BackgroundTransparency = 1,
		Size = UDim2.new(0.5, -4, 0, 22),
		LayoutOrder = order,
		Parent = parent,
	})
	Kit.text({
		Text = label,
		TextColor3 = C.Muted,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.fromScale(0.5, 1),
		MaxTextSize = 15,
		Parent = row,
	})
	Kit.text({
		Text = value,
		Font = Theme.Fonts.Bold,
		TextXAlignment = Enum.TextXAlignment.Right,
		Size = UDim2.fromScale(0.5, 1),
		Position = UDim2.fromScale(0.5, 0),
		MaxTextSize = 15,
		Parent = row,
	})
end

function InventoryController.renderDetail(detail: Frame, instanceId: string?)
	Kit.clear(detail)
	local inst = instanceId and StateController.monster(instanceId)
	local def = inst and MonsterConfig.Monsters[inst.MonsterId]
	if not inst or not def then
		Kit.text({
			Text = "Select a monster to see its details.",
			TextColor3 = C.Muted,
			Size = UDim2.new(1, 0, 0, 40),
			Parent = detail,
		})
		return
	end
	local rarity = RarityConfig.Rarities[def.Rarity]
	local element = CombatConfig.Elements[def.Element]
	local region = RegionConfig.Regions[def.Region]
	local scroll = Kit.scroll({ Parent = detail })
	Kit.list(scroll, Enum.FillDirection.Vertical, 6)
	local top = Kit.frame({
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -8, 0, 150),
		LayoutOrder = 1,
		Parent = scroll,
	})
	local view =
		Kit.frame({ BackgroundColor3 = C.PanelDark, Size = UDim2.fromOffset(150, 150), Parent = top })
	Kit.corner(view)
	Kit.stroke(view, rarity.Color, 3)
	Icons.viewport(def.MonsterId, view, true)
	local name = Kit.text({
		Text = def.DisplayName,
		Font = Theme.Fonts.Title,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -160, 0, 34),
		Position = UDim2.fromOffset(160, 0),
		MaxTextSize = 28,
		Parent = top,
	})
	Kit.textStroke(name)
	Kit.text({
		Text = string.format(
			'<font color="#%s">%s %s</font> · %s %s · %s',
			rarity.Color:ToHex(),
			rarity.Glyph,
			rarity.DisplayName,
			element.Glyph,
			element.DisplayName,
			region.DisplayName
		),
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -160, 0, 24),
		Position = UDim2.fromOffset(160, 36),
		MaxTextSize = 16,
		Parent = top,
	})
	Kit.text({
		Text = string.format(
			"Level %d (%s / %s XP) · Upgrade %d/%d · %s",
			inst.Level,
			Format.number(inst.Xp),
			Format.number(StatMath.xpToNext(inst.Level)),
			inst.Upgrade,
			StatMath.maxUpgrade(inst),
			if inst.Stars > 0 then string.rep("★", inst.Stars) else "☆ no stars"
		),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = C.Muted,
		Size = UDim2.new(1, -160, 0, 22),
		Position = UDim2.fromOffset(160, 62),
		MaxTextSize = 14,
		Parent = top,
	})
	Kit.text({
		Text = def.Description,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = C.Muted,
		Size = UDim2.new(1, -160, 0, 40),
		Position = UDim2.fromOffset(160, 86),
		MaxTextSize = 14,
		Parent = top,
	})
	local income = InventoryController.incomeOf(inst)
	local placed = StateController.slotOf(inst.Id)
	Kit.text({
		Text = string.format(
			"💰 %s/s%s",
			Format.number(income),
			if placed then "  (placed in slot " .. placed .. ")" else "  (if placed)"
		),
		Font = Theme.Fonts.Bold,
		TextColor3 = C.Gold,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -160, 0, 22),
		Position = UDim2.fromOffset(160, 128),
		MaxTextSize = 16,
		Parent = top,
	})

	local stats = StatMath.monsterStats(inst, StateController.equipmentOn(inst.Id), mods())
	local statsFrame = Kit.frame({
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -8, 0, 92),
		LayoutOrder = 2,
		Parent = scroll,
	})
	Kit.grid(statsFrame, UDim2.new(0.5, -4, 0, 20), 4)
	statRow(statsFrame, "❤ Health", Format.number(stats.MaxHealth), 1)
	statRow(statsFrame, "⚔ Attack", Format.number(stats.Attack), 2)
	statRow(statsFrame, "🛡 Defense", Format.number(stats.Defense), 3)
	statRow(statsFrame, "⏩ Speed", string.format("%.1f", stats.Speed), 4)
	statRow(
		statsFrame,
		"🎯 Crit",
		Format.percent(stats.CritChance, 1) .. " / x" .. string.format("%.2f", stats.CritDamage),
		5
	)
	statRow(statsFrame, "💪 Power", Format.number(StatMath.power(stats)), 6)

	-- actions
	local actions = Kit.frame({
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -8, 0, 100),
		LayoutOrder = 3,
		Parent = scroll,
	})
	Kit.grid(actions, UDim2.new(0.25, -6, 0, 44), 6)
	local cost = StatMath.upgradeCost(inst, mods())
	Kit.button(
		if inst.Upgrade >= StatMath.maxUpgrade(inst)
			then "Max Upgrade"
			else "Upgrade 💰" .. Format.number(cost),
		"Gold",
		function()
			UIController.call("UpgradeMonster", inst.Id, 1)
		end,
		{ LayoutOrder = 1, Parent = actions }
	)
	if placed then
		Kit.button("Remove 🏠", "Dark", function()
			UIController.call("RemoveMonster", placed)
		end, { LayoutOrder = 2, Parent = actions })
	else
		Kit.button("Place 🏠", "Good", function()
			InventoryController.placeAnywhere(inst.Id)
		end, { LayoutOrder = 2, Parent = actions })
	end
	local inTeam = StateController.inTeam(inst.Id)
	Kit.button(if inTeam then "Leave Team" else "Add to Team ⚔", "Primary", function()
		local profile = StateController.Profile
		if not profile then
			return
		end
		local team = table.clone(profile.Battle.Team)
		local i = table.find(team, inst.Id)
		if i then
			table.remove(team, i)
		elseif #team < CombatConfig.TeamSize then
			table.insert(team, inst.Id)
		else
			UIController.toast("error", "Team is full (" .. CombatConfig.TeamSize .. "). Remove one first.")
			return
		end
		UIController.call("SetTeam", team)
	end, { LayoutOrder = 3, Parent = actions })
	Kit.button(if inst.Locked then "Unlock 🔓" else "Lock 🔒", "Dark", function()
		UIController.call("ToggleLock", inst.Id)
	end, { LayoutOrder = 4, Parent = actions })
	Kit.button(if inst.Favorite then "Unfavorite" else "Favorite ❤", "Dark", function()
		UIController.call("ToggleFavorite", inst.Id)
	end, { LayoutOrder = 5, Parent = actions })
	Kit.button("Sell 💰" .. Format.number(StatMath.sellValue(inst, mods())), "Bad", function()
		InventoryController.sell({ inst.Id })
	end, { LayoutOrder = 6, Parent = actions })
	Kit.button("Fuse 🧬", "Primary", function()
		UIController.open("Fusion", { TargetId = inst.Id })
	end, { LayoutOrder = 7, Parent = actions })
	if def.EvolvesTo then
		Kit.button("Evolve ✨", "Gem", function()
			UIController.open("Fusion", { Tab = 4, TargetId = inst.Id })
		end, { LayoutOrder = 8, Parent = actions })
	end

	-- equipment
	Kit.header("Equipment", { LayoutOrder = 4, Size = UDim2.new(1, -8, 0, 24), Parent = scroll })
	local equipFrame = Kit.frame({
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -8, 0, 96),
		LayoutOrder = 5,
		Parent = scroll,
	})
	Kit.grid(equipFrame, UDim2.new(0.5, -4, 0, 44), 6)
	local equipped: { [string]: Types.EquipmentInstance } = {}
	for _, item in StateController.equipmentOn(inst.Id) do
		local itemDef = EquipmentConfig.Items[item.ItemId]
		if itemDef then
			equipped[itemDef.Category] = item
		end
	end
	for i, category in EquipmentConfig.Categories do
		local item = equipped[category]
		local itemDef = item and EquipmentConfig.Items[item.ItemId]
		local label = (EquipmentConfig.CategoryGlyphs :: any)[category]
			.. " "
			.. (
				if itemDef and item then itemDef.DisplayName .. " Lv" .. item.Level else category .. ": empty"
			)
		Kit.button(label, if item then "Primary" else "Ghost", function()
			if item then
				UIController.call("UnequipItem", item.Id)
			else
				equipmentPicker(inst.Id, category)
			end
		end, { LayoutOrder = i, Parent = equipFrame })
	end

	-- abilities
	Kit.header("Abilities", { LayoutOrder = 6, Size = UDim2.new(1, -8, 0, 24), Parent = scroll })
	for i, abilityId in def.Abilities do
		local ability = AbilityConfig.Abilities[abilityId]
		if ability then
			local row = Kit.card({ Size = UDim2.new(1, -8, 0, 46), LayoutOrder = 6 + i, Parent = scroll })
			local kindColor = if ability.Kind == "Ultimate"
				then C.Gold
				elseif ability.Kind == "Special" then C.Accent
				else C.Muted
			Kit.text({
				Text = string.format(
					'<font color="#%s">[%s]</font> <b>%s</b>%s',
					kindColor:ToHex(),
					ability.Kind,
					ability.Name,
					if ability.Cooldown > 0 then "  ⏱" .. ability.Cooldown else ""
				),
				TextXAlignment = Enum.TextXAlignment.Left,
				Size = UDim2.new(1, -12, 0.5, 0),
				Position = UDim2.fromOffset(8, 2),
				MaxTextSize = 15,
				Parent = row,
			})
			Kit.text({
				Text = ability.Description,
				TextColor3 = C.Muted,
				TextXAlignment = Enum.TextXAlignment.Left,
				Size = UDim2.new(1, -12, 0.45, 0),
				Position = UDim2.new(0, 8, 0.5, 0),
				MaxTextSize = 13,
				Parent = row,
			})
		end
	end
end

-- Actions ---------------------------------------------------------------------------------

function InventoryController.placeAnywhere(instanceId: string)
	local profile = StateController.Profile
	local derived = StateController.Derived
	if not profile or not derived then
		return
	end
	for slotId = 1, derived.TotalSlots do
		if not profile.Base.PlacedMonsters[tostring(slotId)] then
			UIController.call("PlaceMonster", instanceId, slotId)
			return
		end
	end
	UIController.toast("error", "All base slots are full. Remove a monster or rebirth for more slots.")
end

function InventoryController.sell(ids: { string })
	local profile = StateController.Profile
	if not profile or #ids == 0 then
		return
	end
	local total = 0
	local favorites = 0
	for _, id in ids do
		local inst = profile.Inventory.Monsters[id]
		if inst then
			if inst.Locked then
				UIController.toast("error", "Unlock locked monsters before selling them.")
				return
			end
			total += StatMath.sellValue(inst, mods())
			if inst.Favorite then
				favorites += 1
			end
		end
	end
	local protected = favorites
	local text = string.format("Sell %d monster(s) for 💰 %s?", #ids, Format.number(total))
	if favorites > 0 then
		text ..= string.format("\n⚠ %d of them are favorites!", favorites)
	end
	if UIController.confirm("Sell monsters", text, "Sell", true) then
		local result = UIController.call("SellMonsters", ids, protected > 0)
		if result.ok then
			UIController.toast(
				"success",
				string.format("Sold %d for 💰 %s", result.data.Sold, Format.number(result.data.Coins))
			)
			state.multi = {}
			state.selectedMonster = nil
		end
	end
end

-- Panel builders -----------------------------------------------------------------------------

local function buildMonstersTab(container: Frame): () -> ()
	local toolbar =
		Kit.frame({ BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 40), Parent = container })
	local search =
		Kit.textbox({ PlaceholderText = "🔎 Search", Size = UDim2.new(0.22, 0, 1, -4), Parent = toolbar })
	local sortButton = Kit.button(
		"Sort: Rarity",
		"Dark",
		nil,
		{ Size = UDim2.new(0.18, 0, 1, -4), Position = UDim2.fromScale(0.23, 0), Parent = toolbar }
	)
	local rarityButton = Kit.button(
		"Rarity: All",
		"Dark",
		nil,
		{ Size = UDim2.new(0.18, 0, 1, -4), Position = UDim2.fromScale(0.42, 0), Parent = toolbar }
	)
	local multiButton = Kit.button(
		"Select ☐",
		"Dark",
		nil,
		{ Size = UDim2.new(0.14, 0, 1, -4), Position = UDim2.fromScale(0.61, 0), Parent = toolbar }
	)
	local sellSelected = Kit.button(
		"Sell (0)",
		"Bad",
		nil,
		{ Size = UDim2.new(0.12, 0, 1, -4), Position = UDim2.fromScale(0.76, 0), Parent = toolbar }
	)
	local capacity = Kit.text({
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = C.Muted,
		Size = UDim2.new(0.11, 0, 1, 0),
		Position = UDim2.fromScale(0.89, 0),
		MaxTextSize = 16,
		Parent = toolbar,
	})
	local grid = Kit.scroll({
		Size = UDim2.new(0.56, -6, 1, -46),
		Position = UDim2.fromOffset(0, 46),
		Parent = container,
	})
	Kit.grid(grid, UDim2.fromOffset(100, 124), 8)
	Kit.padding(grid, 4)
	local detail = Kit.frame({
		BackgroundColor3 = C.PanelDark,
		Size = UDim2.new(0.44, -6, 1, -46),
		Position = UDim2.new(0.56, 6, 0, 46),
		Parent = container,
	})
	Kit.corner(detail)
	Kit.padding(detail, 8)

	local function render()
		local profile = StateController.Profile
		local derived = StateController.Derived
		if not profile or not derived then
			return
		end
		Kit.clear(grid)
		local list = sortedMonsters()
		for i, inst in list do
			Cards.monster(grid, inst, {
				Selected = if state.multiSelect
					then table.find(state.multi, inst.Id) ~= nil
					else state.selectedMonster == inst.Id,
				Badges = InventoryController.badges(inst),
				LayoutOrder = i,
				OnClick = function()
					if state.multiSelect then
						local idx = table.find(state.multi, inst.Id)
						if idx then
							table.remove(state.multi, idx)
						else
							table.insert(state.multi, inst.Id)
						end
					else
						state.selectedMonster = inst.Id
						UIController.call("MarkInspected", inst.Id)
					end
					render()
				end,
			})
		end
		local count = #StateController.monsters()
		capacity.Text = string.format("%d / %d", count, derived.MonsterCapacity)
		capacity.TextColor3 = if count >= derived.MonsterCapacity then C.Bad else C.Muted
		Kit.setText(sortButton, "Sort: " .. SORTS[state.sort])
		Kit.setText(
			rarityButton,
			"Rarity: " .. (if state.rarityFilter == 0 then "All" else RarityConfig.Order[state.rarityFilter])
		)
		Kit.setText(multiButton, if state.multiSelect then "Select ☑" else "Select ☐")
		Kit.setText(sellSelected, "Sell (" .. #state.multi .. ")")
		sellSelected.Visible = state.multiSelect
		Kit.setEnabled(sellSelected, #state.multi > 0)
		InventoryController.renderDetail(detail, state.selectedMonster)
	end
	search:GetPropertyChangedSignal("Text"):Connect(function()
		state.search = search.Text
		render()
	end)
	sortButton.Activated:Connect(function()
		state.sort = (state.sort % #SORTS) + 1
		render()
	end)
	rarityButton.Activated:Connect(function()
		state.rarityFilter = (state.rarityFilter + 1) % (#RarityConfig.Order + 1)
		render()
	end)
	multiButton.Activated:Connect(function()
		state.multiSelect = not state.multiSelect
		state.multi = {}
		render()
	end)
	sellSelected.Activated:Connect(function()
		InventoryController.sell(table.clone(state.multi))
	end)
	return render
end

local function buildEquipmentTab(container: Frame): () -> ()
	local grid = Kit.scroll({ Size = UDim2.new(0.56, -6, 1, 0), Parent = container })
	Kit.grid(grid, UDim2.fromOffset(100, 110), 8)
	Kit.padding(grid, 4)
	local detail = Kit.frame({
		BackgroundColor3 = C.PanelDark,
		Size = UDim2.new(0.44, -6, 1, 0),
		Position = UDim2.new(0.56, 6, 0, 0),
		Parent = container,
	})
	Kit.corner(detail)
	Kit.padding(detail, 10)
	local function render()
		local profile = StateController.Profile
		if not profile then
			return
		end
		Kit.clear(grid)
		local items = {}
		for _, item in profile.Inventory.Equipment do
			table.insert(items, item)
		end
		table.sort(items, function(a, b)
			local ra = RarityConfig.tierOf(EquipmentConfig.Items[a.ItemId].Rarity)
			local rb = RarityConfig.tierOf(EquipmentConfig.Items[b.ItemId].Rarity)
			if ra == rb then
				return a.Id < b.Id
			end
			return ra > rb
		end)
		for i, item in items do
			local def = EquipmentConfig.Items[item.ItemId]
			local card = Kit.card({
				BackgroundColor3 = if state.selectedItem == item.Id
					then C.Accent:Lerp(C.PanelDark, 0.4)
					else C.PanelDark,
				LayoutOrder = i,
				Parent = grid,
			})
			local holder = Kit.frame({
				BackgroundTransparency = 1,
				Size = UDim2.fromScale(0.7, 0.58),
				Position = UDim2.fromScale(0.15, 0.04),
				Parent = card,
			})
			Kit.aspect(holder, 1)
			Icons.equipment(item.ItemId, holder)
			Kit.text({
				Text = def.DisplayName,
				Font = Theme.Fonts.Title,
				Size = UDim2.fromScale(0.96, 0.2),
				Position = UDim2.fromScale(0.02, 0.62),
				MaxTextSize = 13,
				Parent = card,
			})
			Kit.text({
				Text = "Lv " .. item.Level .. (if item.EquippedTo then " · worn" else ""),
				TextColor3 = C.Muted,
				Size = UDim2.fromScale(0.96, 0.16),
				Position = UDim2.fromScale(0.02, 0.82),
				MaxTextSize = 12,
				Parent = card,
			})
			local hit = Instance.new("TextButton")
			hit.Text = ""
			hit.BackgroundTransparency = 1
			hit.Size = UDim2.fromScale(1, 1)
			hit.Parent = card
			hit.Activated:Connect(function()
				state.selectedItem = item.Id
				render()
			end)
		end
		if #items == 0 then
			Kit.text({
				Text = "No equipment yet. Craft gear at the Workshop or open chests.",
				TextColor3 = C.Muted,
				Size = UDim2.new(1, 0, 0, 50),
				Parent = grid,
			})
		end
		Kit.clear(detail)
		local item = state.selectedItem and profile.Inventory.Equipment[state.selectedItem]
		if not item then
			Kit.text({
				Text = "Select an item.",
				TextColor3 = C.Muted,
				Size = UDim2.new(1, 0, 0, 30),
				Parent = detail,
			})
			return
		end
		local def = EquipmentConfig.Items[item.ItemId]
		local rarity = RarityConfig.Rarities[def.Rarity]
		Kit.list(detail, Enum.FillDirection.Vertical, 6)
		Kit.header(def.Glyph .. " " .. def.DisplayName, { LayoutOrder = 1, Parent = detail })
		Kit.text({
			Text = string.format(
				'<font color="#%s">%s</font> %s · Level %d/%d',
				rarity.Color:ToHex(),
				rarity.DisplayName,
				def.Category,
				item.Level,
				EquipMath.maxLevel(def)
			),
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(1, 0, 0, 22),
			LayoutOrder = 2,
			MaxTextSize = 16,
			Parent = detail,
		})
		Kit.text({
			Text = def.Description,
			TextColor3 = C.Muted,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(1, 0, 0, 36),
			LayoutOrder = 3,
			MaxTextSize = 14,
			Parent = detail,
		})
		local bonuses = EquipMath.itemBonuses(item)
		local lines = {}
		for _, key in EquipMath.STAT_KEYS do
			local v = (bonuses :: any)[key]
			if v and v > 0 then
				table.insert(lines, "+" .. Format.percent(v, 1) .. " " .. string.gsub(key, "Pct$", ""))
			end
		end
		Kit.text({
			Text = table.concat(lines, "\n"),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			Size = UDim2.new(1, 0, 0, 22 * math.max(1, #lines)),
			LayoutOrder = 4,
			MaxTextSize = 16,
			Parent = detail,
		})
		if def.SetId then
			local set = EquipmentConfig.Sets[def.SetId]
			Kit.text({
				Text = "Set: " .. set.DisplayName,
				TextColor3 = C.Gold,
				TextXAlignment = Enum.TextXAlignment.Left,
				Size = UDim2.new(1, 0, 0, 20),
				LayoutOrder = 5,
				MaxTextSize = 14,
				Parent = detail,
			})
		end
		local wearer = item.EquippedTo and StateController.monster(item.EquippedTo)
		local wearerDef = wearer and MonsterConfig.Monsters[wearer.MonsterId]
		Kit.text({
			Text = "Worn by: " .. (if wearerDef then wearerDef.DisplayName else "nobody"),
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(1, 0, 0, 20),
			LayoutOrder = 6,
			MaxTextSize = 15,
			Parent = detail,
		})
		local row = Kit.frame({
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 96),
			LayoutOrder = 7,
			Parent = detail,
		})
		Kit.grid(row, UDim2.new(0.5, -4, 0, 44), 6)
		Kit.button("Upgrade ⬆", "Gold", function()
			UIController.call("UpgradeEquipment", item.Id)
		end, { Parent = row })
		Kit.button(if item.EquippedTo then "Unequip" else "Equip on…", "Primary", function()
			if item.EquippedTo then
				UIController.call("UnequipItem", item.Id)
				return
			end
			Cards.picker({
				Title = "Equip " .. def.DisplayName .. " on…",
				Candidates = sortedMonsters(),
				Max = 1,
				Badges = InventoryController.badges,
				Overlay = UIController.overlay(),
				OnConfirm = function(ids)
					if ids[1] then
						UIController.call("EquipItem", item.Id, ids[1])
					end
				end,
			})
		end, { Parent = row })
		Kit.button("Salvage ♻", "Bad", function()
			if
				UIController.confirm(
					"Salvage",
					"Salvage " .. def.DisplayName .. " into materials?",
					"Salvage",
					true
				)
			then
				UIController.call("SalvageEquipment", { item.Id })
				state.selectedItem = nil
			end
		end, { Parent = row })
	end
	return render
end

local function buildItemsTab(container: Frame): () -> ()
	local scroll = Kit.scroll({ Parent = container })
	Kit.list(scroll, Enum.FillDirection.Vertical, 6)
	local function render()
		local profile = StateController.Profile
		if not profile then
			return
		end
		Kit.clear(scroll)
		local order = 0
		local function row(
			icon: (Instance) -> (),
			title: string,
			sub: string,
			buttonText: string?,
			onClick: (() -> ())?
		)
			order += 1
			local r = Kit.card({ Size = UDim2.new(1, -8, 0, 54), LayoutOrder = order, Parent = scroll })
			local holder = Kit.frame({
				BackgroundTransparency = 1,
				Size = UDim2.fromOffset(46, 46),
				Position = UDim2.fromOffset(4, 4),
				Parent = r,
			})
			icon(holder)
			Kit.text({
				Text = title,
				Font = Theme.Fonts.Bold,
				TextXAlignment = Enum.TextXAlignment.Left,
				Size = UDim2.new(1, -200, 0.5, 0),
				Position = UDim2.fromOffset(58, 2),
				MaxTextSize = 16,
				Parent = r,
			})
			Kit.text({
				Text = sub,
				TextColor3 = C.Muted,
				TextXAlignment = Enum.TextXAlignment.Left,
				Size = UDim2.new(1, -200, 0.45, 0),
				Position = UDim2.new(0, 58, 0.5, 0),
				MaxTextSize = 13,
				Parent = r,
			})
			if buttonText and onClick then
				Kit.button(
					buttonText,
					"Good",
					onClick,
					{ Size = UDim2.fromOffset(120, 40), Position = UDim2.new(1, -126, 0, 7), Parent = r }
				)
			end
		end
		Kit.header("Consumables", { LayoutOrder = 0, Parent = scroll })
		for id, count in profile.Inventory.Consumables do
			local def = CraftingConfig.Consumables[id]
			if def then
				local active = profile.Boosts[id]
				local sub = def.Description
				if active and active > StateController.serverTime() then
					sub = "Active: "
						.. Format.duration(active - StateController.serverTime())
						.. " left · "
						.. sub
				end
				row(
					function(h)
						Icons.consumable(id, h)
					end,
					def.DisplayName .. " x" .. count,
					sub,
					if def.Kind == "Boost" then "Use" else nil,
					if def.Kind == "Boost"
						then function()
							UIController.call("UseConsumable", id)
						end
						else nil
				)
			end
		end
		order += 1
		Kit.header("Chests", { LayoutOrder = order, Parent = scroll })
		for id, count in profile.Inventory.Chests do
			local def = ChestConfig.Chests[id]
			if def then
				row(
					function(h)
						Icons.chest(id, h)
					end,
					def.DisplayName .. " x" .. count,
					def.Description,
					"Open",
					function()
						UIController.open("Chests", { OpenOwned = id })
					end
				)
			end
		end
		order += 1
		Kit.header("Materials", { LayoutOrder = order, Parent = scroll })
		for _, id in CraftingConfig.MaterialOrder do
			local amount = profile.Currencies.Materials[id]
			if amount and amount > 0 then
				local def = CraftingConfig.Materials[id]
				row(
					function(h)
						Icons.material(id, h)
					end,
					def.DisplayName .. " x" .. Format.number(amount),
					"From " .. def.Region .. " battles, chests and caches"
				)
			end
		end
	end
	return render
end

local function buildInventory(body: Frame)
	local content = Kit.frame({
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, -46),
		Position = UDim2.fromOffset(0, 46),
		Parent = body,
	})
	local tabFrames: { Frame } = {}
	local renders: { () -> () } = {}
	for i, builder in { buildMonstersTab, buildEquipmentTab, buildItemsTab } do
		local f = Kit.frame({
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Visible = i == 1,
			Parent = content,
		})
		tabFrames[i] = f
		renders[i] = builder(f)
	end
	local _, selectTab = Kit.tabs(body, { "🐾 Monsters", "⚔ Equipment", "🧪 Items" }, function(index)
		state.tab = index
		for i, f in tabFrames do
			f.Visible = i == index
		end
		renders[index]()
	end)
	InventoryController.selectTab = selectTab
	table.insert(refreshers, function()
		renders[state.tab]()
	end)
	selectTab(state.tab)
end

InventoryController.selectTab = nil :: ((number) -> ())?

local function buildCodex(body: Frame)
	local header = Kit.frame({ BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 86), Parent = body })
	local percent = Kit.header("", { Parent = header })
	local milestoneRow = Kit.frame({
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 44),
		Position = UDim2.fromOffset(0, 32),
		Parent = header,
	})
	Kit.list(milestoneRow, Enum.FillDirection.Horizontal, 6)
	local regionButton = Kit.button(
		"Region: All",
		"Dark",
		nil,
		{ Size = UDim2.fromOffset(180, 36), Position = UDim2.new(1, -180, 0, 0), Parent = header }
	)
	local grid =
		Kit.scroll({ Size = UDim2.new(1, 0, 1, -92), Position = UDim2.fromOffset(0, 92), Parent = body })
	Kit.grid(grid, UDim2.fromOffset(96, 120), 8)
	Kit.padding(grid, 4)
	local function render()
		local profile = StateController.Profile
		if not profile then
			return
		end
		percent.Text = string.format(
			"📖 Codex: %d / %d discovered (%s)",
			Codex.discoveredCount(profile),
			Codex.totalEntries(),
			Format.percent(Codex.percent(profile) / 100, 1)
		)
		Kit.clear(milestoneRow)
		for i, milestone in QuestConfig.DiscoveryMilestones do
			local claimed = profile.Discovery.ClaimedMilestones[milestone.Id]
			local reached = Codex.percent(profile) >= milestone.Percent
			local b = Kit.button(
				(if claimed then "✓ " else "") .. milestone.Percent .. "%",
				if claimed then "Ghost" elseif reached then "Gold" else "Dark",
				function()
					local result = UIController.call("ClaimMilestone", milestone.Id)
					if result.ok then
						UIController.toast("reward", "Codex milestone " .. milestone.Percent .. "% claimed!")
					end
				end,
				{ Size = UDim2.fromOffset(90, 40), LayoutOrder = i, Parent = milestoneRow }
			)
			Kit.setEnabled(b, reached and not claimed)
		end
		local regionId = if state.codexRegion == 0 then nil else RegionConfig.Order[state.codexRegion]
		Kit.setText(
			regionButton,
			"Region: " .. (if regionId then RegionConfig.Regions[regionId].DisplayName else "All")
		)
		Kit.clear(grid)
		for i, id in MonsterConfig.Order do
			local def = MonsterConfig.Monsters[id]
			if not regionId or def.Region == regionId then
				local found = profile.Discovery.DiscoveredMonsters[id] ~= nil
				local rarity = RarityConfig.Rarities[def.Rarity]
				local card = Kit.card({ BackgroundColor3 = C.PanelDark, LayoutOrder = i, Parent = grid })
				Kit.stroke(card, if found then rarity.Color else C.Disabled, 2)
				local holder = Kit.frame({
					BackgroundTransparency = 1,
					Size = UDim2.fromScale(0.74, 0.6),
					Position = UDim2.fromScale(0.13, 0.04),
					Parent = card,
				})
				Kit.aspect(holder, 1)
				Icons.monster(id, holder, found)
				Kit.text({
					Text = if found then def.DisplayName else "???",
					Font = Theme.Fonts.Title,
					Size = UDim2.fromScale(0.96, 0.18),
					Position = UDim2.fromScale(0.02, 0.64),
					MaxTextSize = 13,
					Parent = card,
				})
				local tag = rarity.DisplayName
				if def.EvolutionOnly then
					tag ..= " · Evolve"
				elseif def.FusionOnly then
					tag ..= " · Fusion"
				elseif def.EventId then
					tag ..= " · Event"
				end
				Kit.text({
					Text = tag,
					TextColor3 = if found then rarity.Color else C.Muted,
					Size = UDim2.fromScale(0.96, 0.14),
					Position = UDim2.fromScale(0.02, 0.83),
					MaxTextSize = 12,
					Parent = card,
				})
			end
		end
	end
	regionButton.Activated:Connect(function()
		state.codexRegion = (state.codexRegion + 1) % (#RegionConfig.Order + 1)
		render()
	end)
	table.insert(refreshers, render)
	render()
end

function InventoryController.init()
	UIController.registerPanel({
		Id = "Inventory",
		Title = "Monsters & Items",
		Glyph = "🎒",
		Wide = true,
		Build = buildInventory,
		OnOpen = function(args)
			local selectFn = InventoryController.selectTab
			if typeof(args) == "table" and args.Tab and selectFn then
				selectFn(args.Tab)
			end
		end,
	})
	UIController.registerPanel({
		Id = "Equipment",
		Title = "Equipment Forge",
		Glyph = "⚒",
		Wide = true,
		Build = function(body)
			local f = Kit.frame({ BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = body })
			local render = buildEquipmentTab(f)
			table.insert(refreshers, render)
			render()
		end,
	})
	UIController.registerPanel({
		Id = "Codex",
		Title = "Monster Codex",
		Glyph = "📖",
		Wide = true,
		Build = buildCodex,
	})
end

function InventoryController.start()
	StateController.Changed:Connect(function(key)
		-- deliberately not refreshing on Currencies/Derived: those change every second
		if
			key == "Monsters"
			or key == "Equipment"
			or key == "*"
			or key == "Inventory"
			or key == "Base"
			or key == "Battle"
			or key == "Discovery"
			or key == "Boosts"
		then
			local open = UIController.openId()
			if open == "Inventory" or open == "Codex" or open == "Equipment" then
				for _, fn in refreshers do
					fn()
				end
			end
		end
	end)
	UIController.on("PanelOpened", function(id)
		if id == "Inventory" or id == "Codex" or id == "Equipment" then
			for _, fn in refreshers do
				fn()
			end
		end
	end)
end

return InventoryController
