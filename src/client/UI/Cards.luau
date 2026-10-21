--!strict
-- Reusable cards and the modal monster picker (used by base slots, teams,
-- fusion, evolution and trading).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local MonsterConfig = require(Config:WaitForChild("MonsterConfig"))
local RarityConfig = require(Config:WaitForChild("RarityConfig"))
local Types = require(Shared:WaitForChild("Types"))
local Kit = require(script.Parent.Kit)
local Theme = require(script.Parent.Theme)
local Icons = require(script.Parent.Icons)

local C = Theme.Colors

local Cards = {}

export type MonsterCardOptions = {
	Selected: boolean?,
	Badges: { string }?, -- small text badges (e.g. "🏠", "⚔")
	Subtitle: string?,
	OnClick: (() -> ())?,
	LayoutOrder: number?,
}

function Cards.monster(parent: Instance, inst: Types.MonsterInstance, options: MonsterCardOptions?): Frame
	local o: MonsterCardOptions = options or {}
	local def = MonsterConfig.Monsters[inst.MonsterId]
	local rarity = if def then RarityConfig.Rarities[def.Rarity] else RarityConfig.Rarities.Common
	local card = Kit.card({
		BackgroundColor3 = if o.Selected then C.Accent:Lerp(C.PanelDark, 0.4) else C.PanelDark,
		LayoutOrder = o.LayoutOrder or 0,
		Parent = parent,
	})
	Kit.stroke(card, if o.Selected then C.Gold else rarity.Color, if o.Selected then 3 else 2)
	local iconHolder = Kit.frame({
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(0.74, 0.56),
		Position = UDim2.fromScale(0.13, 0.04),
		Parent = card,
	})
	Kit.aspect(iconHolder, 1)
	Icons.monster(inst.MonsterId, iconHolder)
	local name = Kit.text({
		Text = if def then def.DisplayName else inst.MonsterId,
		Font = Theme.Fonts.Title,
		Size = UDim2.fromScale(0.96, 0.17),
		Position = UDim2.fromScale(0.02, 0.6),
		MaxTextSize = 15,
		Parent = card,
	})
	Kit.textStroke(name)
	local stars = if inst.Stars > 0 then " " .. string.rep("★", inst.Stars) else ""
	Kit.text({
		Text = o.Subtitle
			or ("Lv " .. inst.Level .. (if inst.Upgrade > 0 then " +" .. inst.Upgrade else "") .. stars),
		TextColor3 = rarity.Color,
		Font = Theme.Fonts.Bold,
		Size = UDim2.fromScale(0.96, 0.15),
		Position = UDim2.fromScale(0.02, 0.79),
		MaxTextSize = 13,
		Parent = card,
	})
	local badges = table.clone(o.Badges or {})
	if inst.Locked then
		table.insert(badges, "🔒")
	end
	if inst.Favorite then
		table.insert(badges, "❤")
	end
	if #badges > 0 then
		Kit.text({
			Text = table.concat(badges, ""),
			Size = UDim2.fromScale(0.6, 0.16),
			Position = UDim2.fromScale(0.02, 0.01),
			TextXAlignment = Enum.TextXAlignment.Left,
			MaxTextSize = 14,
			Parent = card,
		})
	end
	if o.OnClick then
		local hit = Instance.new("TextButton")
		hit.Text = ""
		hit.BackgroundTransparency = 1
		hit.Size = UDim2.fromScale(1, 1)
		hit.ZIndex = 5
		hit.Parent = card
		hit.Activated:Connect(o.OnClick)
	end
	return card
end

export type PickerOptions = {
	Title: string,
	Candidates: { Types.MonsterInstance },
	Max: number, -- 1 = single select (confirms immediately)
	Min: number?,
	Preselected: { string }?,
	Subtitle: ((Types.MonsterInstance) -> string)?,
	Badges: ((Types.MonsterInstance) -> { string })?,
	ConfirmText: string?,
	OnConfirm: ({ string }) -> (),
	Overlay: Instance,
}

function Cards.picker(o: PickerOptions)
	local shade = Instance.new("TextButton")
	shade.Text = ""
	shade.AutoButtonColor = false
	shade.BackgroundColor3 = C.Backdrop
	shade.BackgroundTransparency = 0.35
	shade.Size = UDim2.fromScale(1, 1)
	shade.Parent = o.Overlay
	local box = Kit.frame({
		BackgroundColor3 = C.Panel,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.7, 0.74),
		Parent = shade,
	})
	Kit.corner(box)
	Kit.stroke(box, C.Stroke, 3)
	Kit.padding(box, 12)
	local sizeConstraint = Instance.new("UISizeConstraint")
	sizeConstraint.MaxSize = Vector2.new(1000, 700)
	sizeConstraint.Parent = box
	Kit.header(o.Title, { Parent = box })
	local selected: { string } = table.clone(o.Preselected or {})
	local grid =
		Kit.scroll({ Size = UDim2.new(1, 0, 1, -96), Position = UDim2.fromOffset(0, 34), Parent = box })
	Kit.grid(grid, UDim2.fromOffset(104, 128), 8)
	Kit.padding(grid, 4)
	local footer = Kit.frame({
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 50),
		Position = UDim2.new(0, 0, 1, -50),
		Parent = box,
	})
	local status = Kit.text({
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(0.5, 0, 1, 0),
		TextColor3 = C.Muted,
		MaxTextSize = 18,
		Parent = footer,
	})
	local function close()
		shade:Destroy()
	end
	local confirm: TextButton
	local render: () -> ()
	render = function()
		Kit.clear(grid)
		for i, inst in o.Candidates do
			local isSelected = table.find(selected, inst.Id) ~= nil
			Cards.monster(grid, inst, {
				Selected = isSelected,
				LayoutOrder = i,
				Subtitle = if o.Subtitle then o.Subtitle(inst) else nil,
				Badges = if o.Badges then o.Badges(inst) else nil,
				OnClick = function()
					if o.Max == 1 then
						close()
						o.OnConfirm({ inst.Id })
						return
					end
					local index = table.find(selected, inst.Id)
					if index then
						table.remove(selected, index)
					elseif #selected < o.Max then
						table.insert(selected, inst.Id)
					end
					render()
				end,
			})
		end
		if #o.Candidates == 0 then
			Kit.text({
				Text = "No eligible monsters.",
				TextColor3 = C.Muted,
				Size = UDim2.new(1, 0, 0, 40),
				Parent = grid,
			})
		end
		status.Text = if o.Max > 1
			then string.format("Selected %d / %d", #selected, o.Max)
			else "Tap a monster"
		if confirm then
			Kit.setEnabled(confirm, #selected >= (o.Min or 1))
		end
	end
	Kit.button(
		"Cancel",
		"Dark",
		close,
		{ Size = UDim2.new(0.22, 0, 1, -6), Position = UDim2.new(0.52, 0, 0, 3), Parent = footer }
	)
	confirm = Kit.button(o.ConfirmText or "Confirm", "Good", function()
		close()
		o.OnConfirm(selected)
	end, {
		Size = UDim2.new(0.24, 0, 1, -6),
		Position = UDim2.new(0.76, 0, 0, 3),
		Visible = o.Max > 1,
		Parent = footer,
	})
	render()
	Kit.pop(box, 0.06)
end

return Cards
