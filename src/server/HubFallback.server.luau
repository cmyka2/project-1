-- Makes sure the world pieces the scripts rely on exist. The real hub is built in Studio (Workspace.Hub); anything
-- missing gets a clearly labeled placeholder, resolved through AssetRegistry first so imported models win.
-- Layout below is only used for those placeholders (studs; island top at y = HubBuildKit.G).
local RS = game:GetService("ReplicatedStorage")
local Assets = require(RS.Monster.AssetRegistry)
local Kit = require(game:GetService("ServerStorage").HubBuildKit)
local V = Vector3.new

local Layout = {
	islandSize = 600,
	plotsPerSide = 4, plotSpacing = 100, plotX = 200, -- left district at -X (blue), right at +X (red)
	sideColors = { Color3.fromRGB(70, 120, 230), Color3.fromRGB(220, 70, 70) },
	-- name = what the client scripts look for (FindFirstAncestor), asset = AssetRegistry Shops id
	shops = {
		{ name = "DiceShop", asset = "dice_shop", pos = V(-120, 0, -230), action = "Shop" },
		{ name = "ChestShop", asset = "chest_shop", pos = V(-40, 0, -230), action = "Shop" },
		{ name = "UpgradeTree", asset = "upgrade_tree", pos = V(40, 0, -230), action = "Upgrade" },
		{ name = "RebirthAltar", asset = "rebirth_altar", pos = V(120, 0, -230), action = "Rebirth" },
		{ name = "Index", asset = "index_codex", pos = V(-60, 0, 230), action = "Open Index" },
	},
	summon = V(60, 0, 230),
	statue = V(0, 0, -40),
}

local function folder(parent, name)
	local f = parent:FindFirstChild(name)
	if not f then f = Instance.new("Folder") f.Name = name f.Parent = parent end
	return f
end
local function promptOn(model, action, object)
	local pp = model:FindFirstChildWhichIsA("ProximityPrompt", true)
	if pp then return pp end
	pp = Instance.new("ProximityPrompt") pp.ActionText = action pp.ObjectText = object pp.MaxActivationDistance = 14
	pp.Parent = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	return pp
end
local function placeAt(inst, pos)
	local _, size = inst:GetBoundingBox()
	inst:PivotTo(CFrame.new(pos + V(0, Kit.G + size.Y / 2, 0)))
end

local hub = workspace:FindFirstChild("Hub")
if not hub then
	warn("Workspace.Hub missing: building a placeholder island")
	hub = Instance.new("Folder") hub.Name = "Hub" hub.Parent = workspace
	local s = Layout.islandSize
	Kit.P(hub, V(s, Kit.G, s), CFrame.new(0, Kit.G / 2, 0), Color3.fromRGB(90, 180, 80), { Name = "PlaceholderIsland" })
	local spawn = Instance.new("SpawnLocation") spawn.Anchored = true spawn.Size = V(12, 1, 12) spawn.Position = V(0, Kit.G + 0.5, 30) spawn.Parent = hub
	local statue = Assets.CreateAsset("Statues", "main_statue", hub, V(12, 24, 12))
	placeAt(statue, Layout.statue)
end

local plots = folder(hub, "Plots")
if #plots:GetChildren() == 0 then
	warn("Workspace.Hub.Plots empty: generating placeholder plots")
	local id = 0
	for side, sx in { -1, 1 } do
		for k = 1, Layout.plotsPerSide do
			id += 1
			local z = (k - (Layout.plotsPerSide + 1) / 2) * Layout.plotSpacing
			Kit.Plot(plots, id, CFrame.new(sx * Layout.plotX, 0, z) * CFrame.Angles(0, math.rad(-sx * 90), 0), Layout.sideColors[side])
		end
	end
end

local shops = folder(hub, "Shops")
for _, s in Layout.shops do
	if not hub:FindFirstChild(s.name, true) then
		local m = Instance.new("Model") m.Name = s.name
		local inst = Assets.CreateAsset("Shops", s.asset, m, V(16, 12, 16))
		m.PrimaryPart = inst:IsA("Model") and inst.PrimaryPart or inst
		placeAt(m, s.pos)
		promptOn(m, s.action, s.name)
		m.Parent = shops
	end
end
local area = shops:FindFirstChild("SummonArea")
if not (area and area:FindFirstChild("SummonCore")) then
	area = area or Instance.new("Model")
	area.Name = "SummonArea"
	local station = Assets.CreateAsset("Shops", "summon_station", area, V(10, 6, 10))
	placeAt(station, Layout.summon)
	local core = Kit.P(area, V(4, 4, 4), CFrame.new(Layout.summon + V(0, Kit.G + 9, 0)), Color3.fromRGB(255, 220, 90),
		Kit.Neon({ Name = "SummonCore", CanCollide = false }))
	Kit.Prompt(core, "Roll", "Summon")
	area.Parent = shops
elseif not area.SummonCore:FindFirstChildOfClass("ProximityPrompt") then
	Kit.Prompt(area.SummonCore, "Roll", "Summon")
end

-- one line per category so missing art is obvious without flooding the output
for category, r in Assets.ValidateRegistry() do
	print(("AssetRegistry %s: %d imported, %d missing (placeholders), %d broken"):format(category, #r.found, #r.missing, #r.broken))
end
