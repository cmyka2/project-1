-- Builds a monster model. Real art: drop a Model named <monster id> into ReplicatedStorage.Assets.Monsters
-- (resolved through AssetRegistry); anything missing or partless gets the generated placeholder below.
local Config = require(script.Parent.MonsterConfig)
local Assets = require(script.Parent.AssetRegistry)

local ELEMENT = {
	Nature = Color3.fromRGB(80, 180, 70), Earth = Color3.fromRGB(150, 110, 70), Water = Color3.fromRGB(70, 150, 240),
	Fire = Color3.fromRGB(240, 90, 40), Lightning = Color3.fromRGB(250, 220, 60), Light = Color3.fromRGB(255, 245, 200),
	Shadow = Color3.fromRGB(70, 50, 100), Cosmic = Color3.fromRGB(120, 60, 200),
}
local V, Ball = Vector3.new, Enum.PartType.Ball

local function part(m, size, cf, color, shape, neon)
	local p = Instance.new("Part")
	p.Anchored = true p.CanCollide = false p.CanQuery = false p.CanTouch = false
	p.Size = size p.CFrame = cf p.Color = color p.TopSurface = Enum.SurfaceType.Studs
	p.Material = neon and Enum.Material.Neon or Enum.Material.Plastic
	if shape then p.Shape = shape end
	p.Parent = m
	return p
end

-- front = -Z, feet at y = 0
local function placeholder(def)
	local m = Instance.new("Model") m.Name = def.id
	local root = part(m, V(0.2, 0.2, 0.2), CFrame.new(), Color3.new()) root.Name = "Root" root.Transparency = 1
	m.PrimaryPart = root
	local body = def.rarity == "Glitched" and Color3.fromRGB(255, 0, 200) or ELEMENT[def.element]
	local dark = body:Lerp(Color3.new(0, 0, 0), 0.3)
	local accent = Config.RarityById[def.rarity].color
	local tier = Config.Tier[def.rarity]
	local eyeY, eyeZ, hornY, hornZ
	if def.shape == "blob" then
		part(m, V(4, 4, 4), CFrame.new(0, 2, 0), body, Ball)
		part(m, V(4.2, 1, 4.2), CFrame.new(0, 0.5, 0), dark)
		eyeY, eyeZ, hornY, hornZ = 2.6, -1.8, 4, 0
	elseif def.shape == "biped" then
		for _, x in {-0.8, 0.8} do part(m, V(1.2, 2, 1.2), CFrame.new(x, 1, 0), dark) end
		part(m, V(3, 3, 2), CFrame.new(0, 3.5, 0), body)
		for _, x in {-2, 2} do part(m, V(1, 2.6, 1), CFrame.new(x, 3.6, 0), dark) end
		part(m, V(2.6, 2.4, 2.4), CFrame.new(0, 6.2, 0), body)
		eyeY, eyeZ, hornY, hornZ = 6.4, -1.25, 7.9, 0
	else
		for _, x in {-1, 1} do for _, z in {-1.6, 1.6} do part(m, V(1, 2, 1), CFrame.new(x, 1, z), dark) end end
		part(m, V(2.6, 2.4, 5), CFrame.new(0, 3.2, 0), body)
		part(m, V(2.4, 2.2, 2.4), CFrame.new(0, 4.2, -3.4), body)
		part(m, V(1.4, 1, 1), CFrame.new(0, 3.8, -4.9), dark)
		part(m, V(0.6, 0.6, 2.4), CFrame.new(0, 3.9, 3.4) * CFrame.Angles(math.rad(30), 0, 0), dark)
		eyeY, eyeZ, hornY, hornZ = 4.6, -4.62, 5.8, -3.4
	end
	for _, x in {-0.6, 0.6} do part(m, V(0.6, 0.5, 0.2), CFrame.new(x, eyeY, eyeZ), accent, nil, true).Name = "Eye" end
	if tier >= 4 then
		for _, s in {-1, 1} do part(m, V(0.5, 1.5, 0.5), CFrame.new(s * 0.9, hornY, hornZ) * CFrame.Angles(0, 0, math.rad(-s * 20)), accent).Name = "Horn" end
	end
	if tier >= 7 then part(m, V(2.2, 0.3, 2.2), CFrame.new(0, hornY + 1.4, hornZ), accent, nil, true).Name = "Halo" end
	return m
end

local Model = {}
function Model.build(def, variant: string?)
	local asset = Assets.GetAsset("Monsters", def.id)
	local m
	if asset and asset:IsA("Model") and Assets.usable(asset) then
		m = asset:Clone()
		m.PrimaryPart = m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart", true)
		for _, d in m:GetDescendants() do if d:IsA("BasePart") then d.Anchored = true d.CanCollide = false end end
	elseif asset then
		warn("Monster asset has no parts, using placeholder:", def.id)
	end
	m = m or placeholder(def)
	local v = Config.VariantById[variant or "Normal"]
	if v.scale ~= 1 then m:ScaleTo(m:GetScale() * v.scale) end
	if v.id == "Monstrous" then
		for _, d in m:GetDescendants() do
			if d:IsA("BasePart") and d.Material ~= Enum.Material.Neon then d.Color = d.Color:Lerp(Color3.fromRGB(110, 0, 10), 0.4) end
		end
	end
	m:SetAttribute("MonsterId", def.id) m:SetAttribute("Variant", v.id)
	return m
end
return Model
