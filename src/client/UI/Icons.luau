--!strict
-- Icons for monsters, equipment, currencies and materials. Uses a registered
-- image (AssetConfig.Icons) when available, otherwise a styled glyph tile.
-- `Icons.viewport` renders the actual 3D model (or its placeholder).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local MonsterConfig = require(Config:WaitForChild("MonsterConfig"))
local RarityConfig = require(Config:WaitForChild("RarityConfig"))
local CombatConfig = require(Config:WaitForChild("CombatConfig"))
local EquipmentConfig = require(Config:WaitForChild("EquipmentConfig"))
local CraftingConfig = require(Config:WaitForChild("CraftingConfig"))
local ChestConfig = require(Config:WaitForChild("ChestConfig"))
local EconomyConfig = require(Config:WaitForChild("EconomyConfig"))
local AssetRegistry = require(Shared:WaitForChild("AssetRegistry"))
local Kit = require(script.Parent.Kit)
local Theme = require(script.Parent.Theme)

local Icons = {}

local function initials(name: string): string
	local out = ""
	for word in string.gmatch(name, "%S+") do
		out ..= string.sub(word, 1, 1)
		if #out >= 2 then
			break
		end
	end
	return string.upper(out)
end

local function tile(parent: Instance?, color: Color3, accent: Color3, glyph: string, image: string?): Frame
	local f = Kit.frame({ BackgroundColor3 = color, Size = UDim2.fromScale(1, 1), Parent = parent })
	Kit.corner(f, Theme.SmallCorner)
	Kit.gradient(f, color:Lerp(Color3.new(1, 1, 1), 0.25), color:Lerp(Color3.new(0, 0, 0), 0.35), 90)
	Kit.stroke(f, accent, 2)
	if image then
		Kit.image({
			Image = image,
			Size = UDim2.fromScale(0.86, 0.86),
			Position = UDim2.fromScale(0.07, 0.07),
			Parent = f,
		})
	else
		local t = Kit.text({
			Name = "Glyph",
			Text = glyph,
			Font = Theme.Fonts.Title,
			Size = UDim2.fromScale(0.9, 0.9),
			Position = UDim2.fromScale(0.05, 0.05),
			MaxTextSize = 40,
			Parent = f,
		})
		Kit.textStroke(t, Color3.new(0, 0, 0), 1.5)
	end
	return f
end

function Icons.monster(monsterId: string, parent: Instance?, discovered: boolean?): Frame
	local def = MonsterConfig.Monsters[monsterId]
	if not def then
		return tile(parent, Theme.Colors.Disabled, Theme.Colors.Stroke, "?", nil)
	end
	if discovered == false then
		return tile(parent, Color3.fromRGB(30, 30, 40), Color3.fromRGB(60, 60, 80), "?", nil)
	end
	local rarity = RarityConfig.Rarities[def.Rarity]
	local element = CombatConfig.Elements[def.Element]
	local f = tile(
		parent,
		element.Color:Lerp(rarity.Color, 0.45),
		rarity.Color,
		initials(def.DisplayName),
		AssetRegistry.icon(def.IconKey)
	)
	local badge = Kit.text({
		Text = element.Glyph,
		Size = UDim2.fromScale(0.36, 0.36),
		Position = UDim2.fromScale(0.64, 0),
		MaxTextSize = 18,
		Parent = f,
	})
	badge.ZIndex = 3
	return f
end

function Icons.equipment(itemId: string, parent: Instance?): Frame
	local def = EquipmentConfig.Items[itemId]
	if not def then
		return tile(parent, Theme.Colors.Disabled, Theme.Colors.Stroke, "?", nil)
	end
	local rarity = RarityConfig.Rarities[def.Rarity]
	return tile(
		parent,
		rarity.Color:Lerp(Color3.new(0, 0, 0), 0.35),
		rarity.Color,
		def.Glyph,
		AssetRegistry.icon(def.IconKey)
	)
end

function Icons.material(materialId: string, parent: Instance?): Frame
	local def = CraftingConfig.Materials[materialId]
	return tile(
		parent,
		if def then def.Color:Lerp(Color3.new(0, 0, 0), 0.3) else Theme.Colors.Disabled,
		if def then def.Color else Theme.Colors.Stroke,
		if def then def.Glyph else "?",
		nil
	)
end

function Icons.consumable(id: string, parent: Instance?): Frame
	local def = CraftingConfig.Consumables[id]
	return tile(
		parent,
		Color3.fromRGB(70, 60, 110),
		Color3.fromRGB(170, 140, 255),
		if def then def.Glyph else "?",
		nil
	)
end

function Icons.chest(id: string, parent: Instance?): Frame
	local def = ChestConfig.Chests[id]
	return tile(
		parent,
		if def then def.Color:Lerp(Color3.new(0, 0, 0), 0.3) else Theme.Colors.Disabled,
		if def then def.Color else Theme.Colors.Stroke,
		if def then def.Glyph else "?",
		nil
	)
end

function Icons.currencyGlyph(currency: string): string
	local def = EconomyConfig.Currencies[currency]
	return if def then def.Glyph else "?"
end

-- Human-readable name + glyph for a reward key ("Coins", "Material:id", "Chest:id", ...)
function Icons.rewardLabel(key: string, amount: number, format: (number) -> string): string
	local kind, id = string.match(key, "^([^:]+):(.+)$")
	if not kind then
		return Icons.currencyGlyph(key) .. " " .. format(amount)
	end
	if kind == "Material" then
		local def = CraftingConfig.Materials[id :: string]
		return (if def then def.Glyph .. " " .. def.DisplayName else id :: string) .. " x" .. format(amount)
	elseif kind == "Consumable" then
		local def = CraftingConfig.Consumables[id :: string]
		return (if def then def.Glyph .. " " .. def.DisplayName else id :: string) .. " x" .. format(amount)
	elseif kind == "Chest" then
		local def = ChestConfig.Chests[id :: string]
		return (if def then def.Glyph .. " " .. def.DisplayName else id :: string) .. " x" .. format(amount)
	elseif kind == "Equipment" then
		local def = EquipmentConfig.Items[id :: string]
		return (if def then def.Glyph .. " " .. def.DisplayName else id :: string) .. " x" .. format(amount)
	end
	return key .. " x" .. format(amount)
end

-- 3D preview of a monster model framed by its bounding box. Static (no per-frame updates).
function Icons.viewport(monsterId: string, parent: Instance?, spin: boolean?): ViewportFrame
	local vp = Instance.new("ViewportFrame")
	vp.BackgroundTransparency = 1
	vp.Size = UDim2.fromScale(1, 1)
	vp.LightDirection = Vector3.new(-1, -1, -1)
	vp.Ambient = Color3.fromRGB(180, 180, 190)
	vp.Parent = parent
	local def = MonsterConfig.Monsters[monsterId]
	if not def then
		return vp
	end
	local rarity = RarityConfig.Rarities[def.Rarity]
	local element = CombatConfig.Elements[def.Element]
	local model = AssetRegistry.monsterModel(def.ModelKey, {
		DisplayName = def.DisplayName,
		Color = element.Color,
		Accent = rarity.Color,
		Archetype = def.Archetype,
		Scale = 1,
	})
	local worldModel = Instance.new("WorldModel")
	worldModel.Parent = vp
	model.Parent = worldModel
	AssetRegistry.fitModel(model, CFrame.new(0, 0, 0), 6)
	local cf, size = model:GetBoundingBox()
	local radius = math.max(size.X, size.Y, size.Z)
	local camera = Instance.new("Camera")
	camera.FieldOfView = 40
	local target = cf.Position
	camera.CFrame = CFrame.lookAt(target + Vector3.new(radius * 0.9, radius * 0.45, -radius * 1.6), target)
	camera.Parent = vp
	vp.CurrentCamera = camera
	if spin then
		task.spawn(function()
			local angle = 0
			while vp.Parent do
				angle += math.rad(1.5)
				local offset = CFrame.Angles(0, angle, 0)
					* Vector3.new(radius * 0.9, radius * 0.45, -radius * 1.6)
				camera.CFrame = CFrame.lookAt(target + offset, target)
				task.wait(1 / 30)
			end
		end)
	end
	return vp
end

return Icons
