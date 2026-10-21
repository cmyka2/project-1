--!strict
-- Base management UI: income overview, slots per floor (with locked floors
-- and their rebirth milestone), placement/removal/upgrades, cosmetics and
-- visiting other players' plots.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Util = Shared:WaitForChild("Util")
local MonsterConfig = require(Config:WaitForChild("MonsterConfig"))
local RarityConfig = require(Config:WaitForChild("RarityConfig"))
local EconomyConfig = require(Config:WaitForChild("EconomyConfig"))
local BaseLayout = require(Util:WaitForChild("BaseLayout"))
local StatMath = require(Util:WaitForChild("StatMath"))
local Format = require(Util:WaitForChild("Format"))
local Types = require(Shared:WaitForChild("Types"))
local UI = script.Parent.Parent:WaitForChild("UI")
local Kit = require(UI:WaitForChild("Kit"))
local Theme = require(UI:WaitForChild("Theme"))
local Icons = require(UI:WaitForChild("Icons"))
local Cards = require(UI:WaitForChild("Cards"))
local StateController = require(script.Parent:WaitForChild("StateController"))
local UIController = require(script.Parent:WaitForChild("UIController"))
local InventoryController = require(script.Parent:WaitForChild("InventoryController"))

local C = Theme.Colors

local TycoonController = {}

local floorTab = 1
local renderPanel: (() -> ())? = nil

local function mods(): { [string]: number }
	local d = StateController.Derived
	return if d then d.Modifiers else {}
end

-- Opens the picker to place a monster into a specific slot.
function TycoonController.pickForSlot(slotId: number)
	local candidates = {}
	for _, inst in StateController.monsters() do
		if not StateController.slotOf(inst.Id) then
			table.insert(candidates, inst)
		end
	end
	table.sort(candidates, function(a, b)
		return InventoryController.incomeOf(a) > InventoryController.incomeOf(b)
	end)
	Cards.picker({
		Title = "Place a monster in slot " .. slotId,
		Candidates = candidates,
		Max = 1,
		Subtitle = function(inst: Types.MonsterInstance): string
			return "💰 " .. Format.number(InventoryController.incomeOf(inst)) .. "/s"
		end,
		Overlay = UIController.overlay(),
		OnConfirm = function(ids)
			if ids[1] then
				UIController.call("PlaceMonster", ids[1], slotId)
			end
		end,
	})
end

-- World slot prompt on the player's own plot.
function TycoonController.manageSlot(slotId: number)
	local profile = StateController.Profile
	if not profile then
		return
	end
	local instanceId = profile.Base.PlacedMonsters[tostring(slotId)]
	if not instanceId then
		TycoonController.pickForSlot(slotId)
		return
	end
	floorTab = BaseLayout.floorOfSlot(slotId, profile.Progression.RebirthCount)
	UIController.open("Base")
end

local function slotRow(parent: Instance, info: BaseLayout.SlotInfo, profile: Types.Profile, order: number)
	local instanceId = profile.Base.PlacedMonsters[tostring(info.SlotId)]
	local inst = instanceId and profile.Inventory.Monsters[instanceId]
	local row = Kit.card({ Size = UDim2.new(1, -8, 0, 64), LayoutOrder = order, Parent = parent })
	Kit.text({
		Text = "#" .. info.SlotId,
		Font = Theme.Fonts.Title,
		TextColor3 = C.Muted,
		Size = UDim2.fromOffset(40, 56),
		Position = UDim2.fromOffset(4, 4),
		MaxTextSize = 18,
		Parent = row,
	})
	if inst then
		local def = MonsterConfig.Monsters[inst.MonsterId]
		local rarity = RarityConfig.Rarities[def.Rarity]
		Kit.stroke(row, rarity.Color, 2)
		local holder = Kit.frame({
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(54, 54),
			Position = UDim2.fromOffset(44, 5),
			Parent = row,
		})
		Icons.monster(inst.MonsterId, holder)
		Kit.text({
			Text = def.DisplayName .. "  Lv" .. inst.Level .. "  +" .. inst.Upgrade,
			Font = Theme.Fonts.Bold,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(1, -380, 0.5, 0),
			Position = UDim2.fromOffset(106, 4),
			MaxTextSize = 16,
			Parent = row,
		})
		local income = (StateController.Derived and StateController.Derived.MonsterIncome[inst.Id]) or 0
		Kit.text({
			Text = "💰 " .. Format.number(income) .. "/s",
			TextColor3 = C.Gold,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(1, -380, 0.45, 0),
			Position = UDim2.new(0, 106, 0.5, 0),
			MaxTextSize = 15,
			Parent = row,
		})
		local maxed = inst.Upgrade >= StatMath.maxUpgrade(inst)
		local cost = StatMath.upgradeCost(inst, mods())
		local up = Kit.button(if maxed then "MAX" else "⬆ 💰" .. Format.number(cost), "Gold", function()
			UIController.call("UpgradeMonster", inst.Id, 1)
		end, { Size = UDim2.fromOffset(130, 44), Position = UDim2.new(1, -270, 0, 10), Parent = row })
		Kit.setEnabled(up, not maxed and profile.Currencies.Coins >= cost)
		Kit.button("x10", "Gold", function()
			UIController.call("UpgradeMonster", inst.Id, 10)
		end, { Size = UDim2.fromOffset(56, 44), Position = UDim2.new(1, -134, 0, 10), Parent = row })
		Kit.button("✕", "Bad", function()
			UIController.call("RemoveMonster", info.SlotId)
		end, { Size = UDim2.fromOffset(64, 44), Position = UDim2.new(1, -72, 0, 10), Parent = row })
	else
		Kit.text({
			Text = "Empty slot",
			TextColor3 = C.Muted,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(1, -220, 1, -10),
			Position = UDim2.fromOffset(50, 5),
			MaxTextSize = 17,
			Parent = row,
		})
		Kit.button("Place", "Good", function()
			TycoonController.pickForSlot(info.SlotId)
		end, { Size = UDim2.fromOffset(130, 44), Position = UDim2.new(1, -136, 0, 10), Parent = row })
	end
end

local function buildBase(body: Frame)
	local summary =
		Kit.frame({ BackgroundColor3 = C.PanelDark, Size = UDim2.new(1, 0, 0, 74), Parent = body })
	Kit.corner(summary)
	Kit.padding(summary, 8)
	local title = Kit.header("", { Size = UDim2.new(0.6, 0, 0, 28), Parent = summary })
	local sub = Kit.text({
		Text = "",
		TextColor3 = C.Muted,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(0.6, 0, 0, 24),
		Position = UDim2.fromOffset(0, 32),
		MaxTextSize = 15,
		Parent = summary,
	})
	Kit.button("🏠 Go Home", "Primary", function()
		UIController.call("TravelToHub", true)
	end, { Size = UDim2.new(0.18, 0, 1, 0), Position = UDim2.fromScale(0.62, 0), Parent = summary })
	Kit.button("⚡ Auto-place", "Good", function()
		local result = UIController.call("AutoPlaceBest")
		if result.ok then
			UIController.toast("success", "Placed " .. result.data.Placed .. " monster(s).")
		end
	end, { Size = UDim2.new(0.19, 0, 1, 0), Position = UDim2.fromScale(0.81, 0), Parent = summary })

	local content = Kit.frame({
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, -128),
		Position = UDim2.fromOffset(0, 128),
		Parent = body,
	})
	local slotsView = Kit.scroll({ Parent = content })
	Kit.list(slotsView, Enum.FillDirection.Vertical, 6)
	local cosmeticsView = Kit.scroll({ Visible = false, Parent = content })
	Kit.grid(cosmeticsView, UDim2.new(0.5, -6, 0, 86), 8)
	local visitView = Kit.scroll({ Visible = false, Parent = content })
	Kit.list(visitView, Enum.FillDirection.Vertical, 6)
	local mode = "Slots"

	local function renderVisit()
		Kit.clear(visitView)
		local result = UIController.call("GetPlots")
		if not result.ok then
			return
		end
		for i, plot in result.data do
			local row = Kit.card({ Size = UDim2.new(1, -8, 0, 52), LayoutOrder = i, Parent = visitView })
			local owner = plot.OwnerName or "Unclaimed"
			Kit.text({
				Text = string.format(
					"Plot %d · %s%s",
					plot.Index,
					owner,
					if plot.Income then "  ·  💰 " .. Format.number(plot.Income) .. "/s" else ""
				),
				TextXAlignment = Enum.TextXAlignment.Left,
				Size = UDim2.new(1, -150, 1, -8),
				Position = UDim2.fromOffset(10, 4),
				MaxTextSize = 17,
				Parent = row,
			})
			Kit.button("Visit", "Primary", function()
				UIController.call("TeleportToPlot", plot.Index)
				UIController.close()
			end, { Size = UDim2.fromOffset(120, 40), Position = UDim2.new(1, -126, 0, 6), Parent = row })
		end
	end

	local function render()
		local profile = StateController.Profile
		local derived = StateController.Derived
		if not profile or not derived then
			return
		end
		local rebirths = profile.Progression.RebirthCount
		title.Text = if derived.PlotIndex
			then "🏠 Your Base · Plot " .. derived.PlotIndex
			else "🏠 No plot on this server"
		sub.Text = string.format(
			"💰 %s/s total · x%.2f income multiplier · %d slots on %d floor(s)",
			Format.number(derived.TotalIncome),
			derived.IncomeMultiplier,
			derived.TotalSlots,
			derived.Floors
		)
		slotsView.Visible = mode == "Slots"
		cosmeticsView.Visible = mode == "Cosmetics"
		visitView.Visible = mode == "Visit"
		if mode == "Slots" then
			Kit.clear(slotsView)
			local floorUnlocked = floorTab <= derived.Floors
			if not floorUnlocked then
				local lockCard = Kit.card({ Size = UDim2.new(1, -8, 0, 80), Parent = slotsView })
				Kit.text({
					Text = string.format(
						"🔒 Floor %d unlocks at Rebirth %d (you have %d).\nEvery rebirth also adds one base slot.",
						floorTab,
						BaseLayout.floorUnlockRebirth(floorTab),
						rebirths
					),
					TextColor3 = C.Warn,
					Size = UDim2.new(1, -20, 1, -10),
					Position = UDim2.fromOffset(10, 5),
					MaxTextSize = 18,
					Parent = lockCard,
				})
			else
				local order = 0
				for _, info in BaseLayout.layout(rebirths) do
					if info.Floor == floorTab then
						order += 1
						slotRow(slotsView, info, profile, order)
					end
				end
			end
		elseif mode == "Cosmetics" then
			Kit.clear(cosmeticsView)
			local ids = {}
			for id in EconomyConfig.BaseCosmetics do
				table.insert(ids, id)
			end
			table.sort(ids)
			for i, id in ids do
				local def = EconomyConfig.BaseCosmetics[id]
				local owned = profile.Base.CosmeticUpgrades[id] == true
				local equipped = profile.Base.EquippedCosmetics[def.Category] == id
				local card = Kit.card({ LayoutOrder = i, Parent = cosmeticsView })
				Kit.stroke(card, def.Color, 2)
				Kit.text({
					Text = def.DisplayName .. "  (" .. def.Category .. ")",
					Font = Theme.Fonts.Bold,
					TextXAlignment = Enum.TextXAlignment.Left,
					Size = UDim2.new(1, -150, 0, 26),
					Position = UDim2.fromOffset(10, 6),
					MaxTextSize = 16,
					Parent = card,
				})
				Kit.text({
					Text = def.Description
						.. (if def.RequiredRebirths > 0 then " · Rebirth " .. def.RequiredRebirths else ""),
					TextColor3 = C.Muted,
					TextXAlignment = Enum.TextXAlignment.Left,
					Size = UDim2.new(1, -150, 0, 40),
					Position = UDim2.fromOffset(10, 34),
					MaxTextSize = 13,
					Parent = card,
				})
				local label = if equipped
					then "Unequip"
					elseif owned then "Equip"
					else (if def.CostCurrency == "Gems" then "💎" else "💰") .. Format.number(
						def.Cost
					)
				Kit.button(label, if owned then "Primary" else "Gold", function()
					if equipped then
						UIController.call("EquipCosmetic", def.Category, nil)
					elseif owned then
						UIController.call("EquipCosmetic", def.Category, id)
					else
						UIController.call("BuyCosmetic", id)
					end
				end, {
					Size = UDim2.fromOffset(130, 44),
					Position = UDim2.new(1, -136, 0.5, -22),
					Parent = card,
				})
			end
		end
	end
	local floorBar = Kit.frame({
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 40),
		Position = UDim2.fromOffset(0, 82),
		Parent = body,
	})
	Kit.list(floorBar, Enum.FillDirection.Horizontal, 6)
	local floorButtons: { TextButton } = {}
	local function selectMode(newMode: string, floor: number?)
		mode = newMode
		if floor then
			floorTab = floor
		end
		for i, b in floorButtons do
			b.BackgroundColor3 = if (newMode == "Slots" and i == floorTab)
					or (newMode == "Cosmetics" and i == 4)
					or (newMode == "Visit" and i == 5)
				then C.Accent
				else C.PanelLight
		end
		if newMode == "Visit" then
			renderVisit()
		end
		render()
	end
	for floor = 1, 3 do
		floorButtons[floor] = Kit.button("Floor " .. floor, "Dark", function()
			selectMode("Slots", floor)
		end, { Size = UDim2.new(0.2, -6, 1, 0), Parent = floorBar })
	end
	floorButtons[4] = Kit.button("🎨 Cosmetics", "Dark", function()
		selectMode("Cosmetics")
	end, { Size = UDim2.new(0.2, -6, 1, 0), Parent = floorBar })
	floorButtons[5] = Kit.button("👀 Visit", "Dark", function()
		selectMode("Visit")
	end, { Size = UDim2.new(0.2, -6, 1, 0), Parent = floorBar })
	renderPanel = function()
		selectMode(mode, nil)
	end
	selectMode("Slots", floorTab)
end

function TycoonController.init()
	UIController.registerPanel({
		Id = "Base",
		Title = "My Base",
		Glyph = "🏠",
		Build = buildBase,
		OnOpen = function()
			if renderPanel then
				renderPanel()
			end
		end,
	})
end

function TycoonController.start()
	StateController.Changed:Connect(function(key)
		if
			UIController.openId() == "Base"
			and renderPanel
			and (key == "Base" or key == "Monsters" or key == "*" or key == "Progression")
		then
			renderPanel()
		end
	end)
end

return TycoonController
