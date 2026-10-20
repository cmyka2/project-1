local K = {}
K.G = 20
local G = K.G
local V = Vector3.new
local S, In = Enum.SurfaceType.Studs, Enum.SurfaceType.Inlet
local CS = game:GetService("CollectionService")

function K.P(parent, size, cf, color, props)
	local p = Instance.new("Part")
	p.Anchored = true p.Size = size p.CFrame = cf p.Color = color p.Material = Enum.Material.Plastic
	p.TopSurface = S p.BottomSurface = In p.FrontSurface = S p.BackSurface = S p.LeftSurface = S p.RightSurface = S
	if props then for k, v in props do p[k] = v end end
	p.Parent = parent
	return p
end
local P = K.P
function K.Neon(t) t = t or {} t.Material = Enum.Material.Neon return t end
local Neon = K.Neon
function K.Cyl(parent, d, h, where, color, props)
	local cf = typeof(where) == "Vector3" and CFrame.new(where) or where
	local p = P(parent, V(h, d, d), cf * CFrame.Angles(0, 0, math.pi / 2), color, props)
	p.Shape = Enum.PartType.Cylinder
	return p
end
function K.Ball(parent, d, cf, color, props)
	local p = P(parent, V(d, d, d), cf, color, props) p.Shape = Enum.PartType.Ball return p
end
function K.Text(part, face, text, color)
	local g = Instance.new("SurfaceGui") g.Face = face g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud g.PixelsPerStud = 30
	local t = Instance.new("TextLabel") t.Name = "Label" t.Size = UDim2.fromScale(1, 1) t.BackgroundTransparency = 1 t.Text = text t.TextScaled = true
	t.Font = Enum.Font.FredokaOne t.TextColor3 = color or Color3.new(1, 1, 1) t.TextStrokeTransparency = 0 t.Parent = g
	g.Parent = part
	return g
end
function K.Bill(part, text, color, size, offset)
	local b = Instance.new("BillboardGui") b.Size = size or UDim2.fromScale(10, 2.5) b.StudsOffset = offset or V(0, 4, 0) b.MaxDistance = 150 b.LightInfluence = 0
	local t = Instance.new("TextLabel") t.Size = UDim2.fromScale(1, 1) t.BackgroundTransparency = 1 t.Text = text t.TextScaled = true t.Font = Enum.Font.FredokaOne
	t.TextColor3 = color or Color3.new(1, 1, 1) t.TextStrokeTransparency = 0 t.Parent = b
	b.Parent = part
	return b
end
function K.Prompt(part, action, object, dist)
	local pp = Instance.new("ProximityPrompt") pp.ActionText = action pp.ObjectText = object or "" pp.MaxActivationDistance = dist or 12 pp.Parent = part return pp
end
function K.Light(part, color, range, bright)
	local l = Instance.new("PointLight") l.Color = color l.Range = range or 16 l.Brightness = bright or 1.5 l.Parent = part return l
end
-- blocky NPC facing cf.LookVector
function K.NPC(parent, cf, shirt, name)
	local m = Instance.new("Model") m.Name = name
	local skin = Color3.fromRGB(255, 205, 80)
	for _, x in {-0.5, 0.5} do P(m, V(1, 2, 1), cf * CFrame.new(x, 1, 0), Color3.fromRGB(40, 60, 120), {Name = "Leg"}) end
	local torso = P(m, V(2, 2, 1), cf * CFrame.new(0, 3, 0), shirt, {Name = "Torso"})
	for _, x in {-1.5, 1.5} do P(m, V(1, 2, 1), cf * CFrame.new(x, 3, 0), skin, {Name = "Arm"}) end
	local head = P(m, V(1.2, 1.2, 1.2), cf * CFrame.new(0, 4.6, 0), skin, {Name = "Head"})
	local face = Instance.new("Decal") face.Texture = "rbxasset://textures/face.png" face.Face = Enum.NormalId.Front face.Parent = head
	m.PrimaryPart = torso m.Parent = parent
	return m, head
end
local pats = {{{0, 0}}, {{-1, -1}, {1, 1}}, {{-1, -1}, {0, 0}, {1, 1}}, {{-1, -1}, {1, 1}, {-1, 1}, {1, -1}}, {{-1, -1}, {1, 1}, {-1, 1}, {1, -1}, {0, 0}}, {{-1, -1}, {1, 1}, {-1, 1}, {1, -1}, {-1, 0}, {1, 0}}}
local faces = {{Vector3.zAxis, Vector3.xAxis, Vector3.yAxis}, {Vector3.xAxis, Vector3.zAxis, Vector3.yAxis}, {Vector3.yAxis, Vector3.xAxis, Vector3.zAxis}, {-Vector3.yAxis, Vector3.xAxis, Vector3.zAxis}, {-Vector3.xAxis, Vector3.zAxis, Vector3.yAxis}, {-Vector3.zAxis, Vector3.xAxis, Vector3.yAxis}}
function K.Die(parent, cf, D, col, pip)
	local d = P(parent, V(D, D, D), cf, col, {Name = "Die"})
	for i, f in faces do for _, uv in pats[i] do
		K.Ball(parent, D * 0.2, cf * CFrame.new(f[1] * D / 2 + f[2] * uv[1] * D * 0.28 + f[3] * uv[2] * D * 0.28), pip, {Name = "Pip", CanCollide = false})
	end end
	return d
end
local greens = {Color3.fromRGB(60, 160, 60), Color3.fromRGB(85, 185, 70), Color3.fromRGB(45, 135, 55)}
function K.Tree(parent, pos, h, rng)
	rng = rng or Random.new()
	local m = Instance.new("Model") m.Name = "Tree"
	local function g() return greens[rng:NextInteger(1, #greens)] end
	P(m, V(3, h, 3), CFrame.new(pos + V(0, G + h / 2, 0)), Color3.fromRGB(115, 75, 40), {Name = "Trunk"})
	local s, top = h * 0.75, pos + V(0, G + h, 0)
	P(m, V(s, s * 0.8, s), CFrame.new(top + V(0, s * 0.15, 0)), g(), {Name = "Leaves"})
	P(m, V(s * 0.65, s * 0.55, s * 0.65), CFrame.new(top + V(rng:NextNumber(-1, 1), s * 0.75, rng:NextNumber(-1, 1))), g(), {Name = "Leaves"})
	for _ = 1, 3 do
		local a = rng:NextNumber(0, math.pi * 2)
		P(m, V(s * 0.4, s * 0.4, s * 0.4), CFrame.new(top + V(math.cos(a) * s * 0.5, rng:NextNumber(-s * 0.2, s * 0.3), math.sin(a) * s * 0.5)), g(), {Name = "Leaves"})
	end
	m.Parent = parent
	return m
end
function K.Lamp(parent, pos)
	local dark = Color3.fromRGB(40, 42, 50)
	P(parent, V(2.4, 1, 2.4), CFrame.new(pos + V(0, G + 0.5, 0)), dark, {Name = "LampBase"})
	P(parent, V(1, 10, 1), CFrame.new(pos + V(0, G + 5, 0)), dark, {Name = "LampPost"})
	P(parent, V(2.4, 0.6, 2.4), CFrame.new(pos + V(0, G + 9.9, 0)), dark, {Name = "LampFrame"})
	local h = P(parent, V(1.8, 2, 1.8), CFrame.new(pos + V(0, G + 11.2, 0)), Color3.fromRGB(255, 215, 130), Neon({Name = "Lantern"}))
	P(parent, V(2.8, 0.6, 2.8), CFrame.new(pos + V(0, G + 12.5, 0)), dark, {Name = "LampCap"})
	K.Light(h, Color3.fromRGB(255, 210, 140), 18, 1.5)
end
local function seg(a, b, y)
	local A, B = V(a.X, y, a.Z), V(b.X, y, b.Z)
	return CFrame.lookAt((A + B) / 2, B), (B - A).Magnitude
end
function K.Fence(parent, a, b)
	local wood = Color3.fromRGB(150, 100, 55)
	local cf, len = seg(a, b, G + 2)
	for i = 0, math.floor(len / 5) do P(parent, V(1, 4, 1), cf * CFrame.new(0, 0, -len / 2 + i * len / math.max(1, math.floor(len / 5))), wood, {Name = "FencePost"}) end
	for _, y in {-0.6, 1} do P(parent, V(0.5, 0.6, len), cf * CFrame.new(0, y, 0), wood, {Name = "FenceRail"}) end
end
function K.Wall(parent, a, b, h, t, color)
	local cf, len = seg(a, b, G + h / 2)
	P(parent, V(t, h, len), cf, color, {Name = "CastleWall"})
	for i = 1, math.floor(len / 4) - 1, 2 do P(parent, V(t + 0.4, 2, 2), cf * CFrame.new(0, h / 2 + 1, -len / 2 + i * 4), color, {Name = "Crenel"}) end
end
function K.Tower(parent, pos, s, h, color, flag)
	local m = Instance.new("Model") m.Name = "Tower"
	P(m, V(s, h, s), CFrame.new(pos + V(0, G + h / 2, 0)), color, {Name = "TowerBody"})
	P(m, V(s + 2, 2, s + 2), CFrame.new(pos + V(0, G + h + 1, 0)), color:Lerp(Color3.new(1, 1, 1), 0.25), {Name = "TowerBand"})
	for _, x in {-1, 0, 1} do for _, z in {-1, 0, 1} do
		if x ~= 0 or z ~= 0 then P(m, V(2, 2.5, 2), CFrame.new(pos + V(x * s / 2, G + h + 3.25, z * s / 2)), color, {Name = "Crenel"}) end
	end end
	for _, f in {V(0, 0, 1), V(0, 0, -1), V(1, 0, 0), V(-1, 0, 0)} do
		P(m, V(f.X ~= 0 and 0.4 or 1.4, 4, f.Z ~= 0 and 0.4 or 1.4), CFrame.new(pos + f * (s / 2 + 0.1) + V(0, G + h * 0.65, 0)), Color3.fromRGB(30, 30, 40), {Name = "Slit"})
	end
	P(m, V(0.5, 10, 0.5), CFrame.new(pos + V(0, G + h + 7, 0)), Color3.fromRGB(60, 60, 70), {Name = "FlagPole"})
	P(m, V(0.3, 3, 5), CFrame.new(pos + V(0, G + h + 10.5, 2.5)), flag or color, {Name = "Flag"})
	m.Parent = parent
	return m
end
function K.Stall(parent, at, w, d, awn)
	local wood, white = Color3.fromRGB(150, 100, 55), Color3.new(1, 1, 1)
	local m = Instance.new("Model") m.Name = "Stall"
	m.PrimaryPart = P(m, V(w + 2, 1, d + 2), at(0, 0.5, 0), Color3.fromRGB(190, 150, 100), {Name = "Floor"})
	P(m, V(w, 3.5, 2.5), at(0, 2.75, d / 2 - 1.25), wood, {Name = "Counter"})
	for _, x in {-1, 1} do for _, z in {-1, 1} do P(m, V(1, 9, 1), at(x * (w / 2 - 0.5), 5.5, z * (d / 2 - 0.5)), wood, {Name = "Post"}) end end
	local n = math.floor(w / 2)
	for i = 0, n - 1 do
		P(m, V(2, 0.5, d + 3), at(-w / 2 + 1 + i * 2, 10.5, 0.5) * CFrame.Angles(math.rad(12), 0, 0), i % 2 == 0 and awn or white, {Name = "Awning"})
	end
	for i, c in {Color3.fromRGB(255, 90, 90), Color3.fromRGB(255, 220, 70), Color3.fromRGB(110, 220, 120)} do
		P(m, V(1.4, 1.4, 1.4), at(-w / 2 + 2 + i * 2, 5.2, d / 2 - 1.25), c, {Name = "Goods"})
	end
	P(m, V(3, 3, 3), at(w / 2 - 2.5, 2.5, -d / 2 + 2), wood, {Name = "Crate"})
	m.Parent = parent
	return m
end
-- shop building, local front = +Z. returns roof top y (local)
function K.Building(m, at, o)
	local w, d, H, door = o.w, o.d, o.H or 18, 12
	local stone = Color3.fromRGB(125, 130, 140)
	m.PrimaryPart = P(m, V(w + 4, 2, d + 4), at(0, 1, 0), stone, {Name = "Foundation"})
	P(m, V(door + 6, 1, 3), at(0, 0.5, d / 2 + 3.5), stone, {Name = "Step"})
	local y0 = 2
	P(m, V(w, H, 2), at(0, y0 + H / 2, -d / 2 + 1), o.wall, {Name = "Wall"})
	local segW = (w - door) / 2
	for _, s in {-1, 1} do
		P(m, V(2, H, d), at(s * (w / 2 - 1), y0 + H / 2, 0), o.wall, {Name = "Wall"})
		P(m, V(segW, H, 2), at(s * (door / 2 + segW / 2), y0 + H / 2, d / 2 - 1), o.wall, {Name = "FrontWall"})
		local wx, ww = s * (door / 2 + segW / 2), math.min(segW - 4, 8)
		P(m, V(ww + 1.5, 7.5, 0.6), at(wx, y0 + H * 0.45, d / 2 + 0.1), o.trim, {Name = "WindowFrame"})
		P(m, V(ww, 6, 0.6), at(wx, y0 + H * 0.45, d / 2 + 0.3), Color3.fromRGB(255, 215, 130), Neon({Name = "Window", Transparency = 0.1}))
		for _, sz in {-1, 1} do P(m, V(3, H + 1, 3), at(s * w / 2, y0 + (H + 1) / 2, sz * d / 2), o.trim, {Name = "Pillar"}) end
		local lan = P(m, V(1.4, 2, 1.4), at(s * (door / 2 + 1.5), y0 + 9, d / 2 + 1.2), Color3.fromRGB(255, 210, 120), Neon({Name = "Lantern"}))
		K.Light(lan, Color3.fromRGB(255, 200, 120), 14)
	end
	P(m, V(door, H - 12, 2), at(0, y0 + 12 + (H - 12) / 2, d / 2 - 1), o.wall, {Name = "Lintel"})
	P(m, V(door + 3, 1.2, 2.6), at(0, y0 + 12.6, d / 2 - 0.7), o.trim, {Name = "DoorTrim"})
	local ry = y0 + H
	P(m, V(w + 6, 2, d + 6), at(0, ry + 1, 0), o.roof, {Name = "Roof"})
	P(m, V(w + 1, 2, d + 1), at(0, ry + 3, 0), o.trim, {Name = "RoofTrim"})
	P(m, V(w - 6, 2, d - 6), at(0, ry + 5, 0), o.roof, {Name = "RoofTop"})
	local sb = P(m, V(math.min(w - 6, 30), 5, 1), at(0, y0 + 15, d / 2 + 0.6), o.signBg or o.roof, {Name = "Sign"})
	K.Text(sb, Enum.NormalId.Back, o.sign, o.signColor)
	local counter = P(m, V(14, 4, 3), at(0, y0 + 2, -d / 2 + 9), Color3.fromRGB(150, 95, 55), {Name = "Counter"})
	K.Prompt(counter, o.action or "Open", o.sign)
	K.NPC(m, at(0, y0, -d / 2 + 5) * CFrame.Angles(0, math.pi, 0), o.shirt or o.roof, (o.key or "Shop") .. "NPC")
	local inner = P(m, V(1, 1, 1), at(0, y0 + H - 3, 0), Color3.new(1, 1, 1), {Name = "InteriorLight", Transparency = 1, CanCollide = false})
	K.Light(inner, Color3.fromRGB(255, 225, 170), 26, 1.5)
	return ry + 6
end
-- player plot, o = ground CFrame with front +Z
function K.Plot(parent, id, o, c)
	local carpetC, cashC = Color3.fromRGB(235, 35, 85), Color3.fromRGB(60, 230, 90)
	local light, dark = c:Lerp(Color3.new(1, 1, 1), 0.55), c:Lerp(Color3.new(0, 0, 0), 0.25)
	local function at(x, y, z) return o * CFrame.new(x, G + y, z) end
	local m = Instance.new("Model") m.Name = "Plot" .. id
	m:SetAttribute("PlotId", id) m:SetAttribute("Owner", "") m:SetAttribute("Color", c)
	P(m, V(84, 2.5, 68), at(0, 1.25, 0), light, {Name = "Frame"})
	m.PrimaryPart = P(m, V(78, 3, 62), at(0, 1.5, 0), c, {Name = "Base"})
	P(m, V(78, 2, 2), at(0, 4, -30), dark, {Name = "Wall"})
	for _, s in {-1, 1} do
		P(m, V(2, 2, 62), at(s * 38, 4, 0), dark, {Name = "Wall"})
		P(m, V(28, 2, 2), at(s * 25, 4, 30), dark, {Name = "Wall"})
	end
	P(m, V(20, 0.4, 62), at(0, 3.2, 0), carpetC, {Name = "Carpet"})
	P(m, V(24, 1.6, 6), at(0, 0.8, 34), light, {Name = "Step"})
	P(m, V(20, 0.3, 6), at(0, 1.75, 34), carpetC, {Name = "Carpet"})
	P(m, V(32, 0.8, 14), at(0, 0.4, 44), light, {Name = "Landing"})
	P(m, V(28, 0.3, 12), at(0, 0.95, 44), carpetC, {Name = "Carpet"})
	for i = 1, 10 do
		local s = i <= 5 and -1 or 1
		local z = ((i - 1) % 5 - 2) * 12
		P(m, V(9, 1.5, 9), at(s * 26, 3.75, z), light, {Name = "SlotBase" .. i})
		local slot = P(m, V(8, 1, 8), at(s * 26, 5, z), dark, {Name = "Slot" .. i})
		slot:SetAttribute("SlotIndex", i)
		local pad = P(m, V(6, 0.4, 8), at(s * 15, 3.2, z), cashC, {Name = "Collect" .. i})
		K.Text(pad, Enum.NormalId.Top, "$0")
		if s == 1 then
			slot:SetAttribute("RequiredRebirth", i - 5)
			K.Bill(slot, "Rebirth " .. (i - 5), nil, UDim2.fromScale(8, 2), V(0, 5, 0))
		end
	end
	for _, px in {-34, -24} do P(m, V(1, 8, 1), at(px, 4, 40), Color3.fromRGB(110, 70, 40), {Name = "SignPost"}) end
	local sign = P(m, V(14, 5, 0.8), at(-29, 7, 40), light, {Name = "OwnerSign"})
	K.Text(sign, Enum.NormalId.Front, "#" .. id .. "\nUnclaimed", dark)
	K.Text(sign, Enum.NormalId.Back, "#" .. id .. "\nUnclaimed", dark)
	P(m, V(9, 1, 9), at(29, 0.5, 42), light, {Name = "ChestPad"})
	local chest = P(m, V(6, 3, 4), at(29, 2.5, 42), Color3.fromRGB(220, 50, 60), {Name = "UpgradeChest"})
	P(m, V(6.2, 1.2, 4.2), at(29, 4.4, 42), Color3.fromRGB(70, 90, 160), {Name = "ChestLid"})
	P(m, V(1.2, 4, 4.4), at(29, 3, 42), Color3.fromRGB(245, 195, 60), {Name = "ChestBand"})
	K.Prompt(chest, "Upgrade Base", "Plot " .. id)
	P(m, V(12, 0.2, 10), at(0, 1.15, 44), Color3.new(1, 1, 1), {Name = "SpawnPoint", Transparency = 1, CanCollide = false, CanQuery = false})
	CS:AddTag(m, "Plot")
	m.Parent = parent
	return m
end
return K
