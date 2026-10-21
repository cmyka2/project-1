--!strict
-- Procedurally builds the hub island and the region islands.
--
-- Layout (top view, north = -Z):
--
--   +-----------------------------------------------------------+  Z = -410
--   |  [Plot 1]    [Plot 2]    [Plot 3]    [Plot 4]   (north)   |
--   |===================== north promenade =====================|
--   | W: Skill Shrine    |                    | E: Dice Shop      |
--   |    Rebirth Temple  |   CENTRAL PLAZA    |    Fusion Lab     |
--   |    Ascension Spire |  statue, spawn,    |    Forge          |
--   |  [Battle Arena] ===|== daily, quests ===|==[Trading Post]   |
--   |    Region Gates x9 |  leaderboards      |    Workshop       |
--   |                    |                    |    Chest Vault    |
--   |                    |                    |    Monster Storage|
--   |===================== south promenade =====================|
--   |  [Plot 5]    [Plot 6]    [Plot 7]    [Plot 8]   (south)   |
--   +-----------------------------------------------------------+  Z = +410
--
-- Every district is skipped if a folder with the same name already exists in
-- Workspace.World, so hand-built replacements are preserved.

local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local GameConfig = require(Config:WaitForChild("GameConfig"))
local RegionConfig = require(Config:WaitForChild("RegionConfig"))
local EnemyConfig = require(Config:WaitForChild("EnemyConfig"))
local DiceConfig = require(Config:WaitForChild("DiceConfig"))
local AssetRegistry = require(Shared:WaitForChild("AssetRegistry"))
local BuildKit = require(script.Parent:WaitForChild("BuildKit"))

local block, cylinder, ball, wedge = BuildKit.block, BuildKit.cylinder, BuildKit.ball, BuildKit.wedge

export type PlotInfo = { Index: number, Model: Model, Origin: CFrame }
export type CacheInfo = { Id: string, Region: string, Position: Vector3 }
export type WorldInfo = {
	World: Folder,
	Plots: { [number]: PlotInfo },
	HubSpawn: CFrame,
	RegionArrivals: { [string]: CFrame },
	RegionCenters: { [string]: Vector3 },
	Caches: { [string]: CacheInfo },
	EncounterPositions: { [string]: Vector3 },
}

local W = GameConfig.World
local P = GameConfig.Plots

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local PALETTE = {
	Grass = rgb(104, 190, 86),
	GrassDark = rgb(80, 160, 70),
	Sand = rgb(240, 218, 160),
	Path = rgb(214, 190, 150),
	PathEdge = rgb(170, 150, 120),
	Stone = rgb(200, 200, 210),
	StoneDark = rgb(140, 140, 155),
	Wood = rgb(150, 105, 70),
	Leaf = rgb(70, 170, 80),
	Water = rgb(90, 190, 255),
	Gold = rgb(255, 200, 70),
	White = rgb(245, 245, 250),
}

-- Decorations -----------------------------------------------------------------------

local function tree(parent: Instance, position: Vector3, scale: number, leaf: Color3?)
	local m = BuildKit.model("Tree", parent)
	cylinder(
		"Trunk",
		8 * scale,
		2 * scale,
		CFrame.new(position + Vector3.new(0, 4 * scale, 0)),
		PALETTE.Wood,
		Enum.Material.Wood,
		m
	)
	ball(
		"Canopy",
		9 * scale,
		CFrame.new(position + Vector3.new(0, 10 * scale, 0)),
		leaf or PALETTE.Leaf,
		Enum.Material.Grass,
		m
	)
	ball(
		"Canopy2",
		6 * scale,
		CFrame.new(position + Vector3.new(2 * scale, 12.5 * scale, 1 * scale)),
		leaf or PALETTE.Leaf,
		Enum.Material.Grass,
		m
	)
end

local function lamp(parent: Instance, position: Vector3)
	local m = BuildKit.model("Lamp", parent)
	cylinder(
		"Pole",
		10,
		0.6,
		CFrame.new(position + Vector3.new(0, 5, 0)),
		rgb(60, 60, 70),
		Enum.Material.Metal,
		m
	)
	local bulb = ball(
		"Bulb",
		1.8,
		CFrame.new(position + Vector3.new(0, 10.5, 0)),
		rgb(255, 230, 170),
		Enum.Material.Neon,
		m
	)
	BuildKit.noCollide(bulb)
	BuildKit.light(bulb, rgb(255, 220, 160), 18, 1.2)
end

local function bench(parent: Instance, cf: CFrame)
	local m = BuildKit.model("Bench", parent)
	block(
		"Seat",
		Vector3.new(6, 0.5, 2),
		cf * CFrame.new(0, 1.5, 0),
		PALETTE.Wood,
		Enum.Material.WoodPlanks,
		m
	)
	block(
		"Back",
		Vector3.new(6, 2, 0.4),
		cf * CFrame.new(0, 2.6, 0.8),
		PALETTE.Wood,
		Enum.Material.WoodPlanks,
		m
	)
	block(
		"LegL",
		Vector3.new(0.4, 1.4, 1.6),
		cf * CFrame.new(-2.6, 0.7, 0),
		rgb(60, 60, 70),
		Enum.Material.Metal,
		m
	)
	block(
		"LegR",
		Vector3.new(0.4, 1.4, 1.6),
		cf * CFrame.new(2.6, 0.7, 0),
		rgb(60, 60, 70),
		Enum.Material.Metal,
		m
	)
end

local FLOWER_COLORS = { rgb(255, 120, 160), rgb(255, 220, 90), rgb(170, 120, 255), rgb(255, 255, 255) }

local function flowerBed(parent: Instance, position: Vector3, size: Vector2, rng: Random)
	local m = BuildKit.model("FlowerBed", parent)
	block(
		"Soil",
		Vector3.new(size.X, 1, size.Y),
		CFrame.new(position + Vector3.new(0, 0.5, 0)),
		rgb(110, 80, 60),
		Enum.Material.Ground,
		m
	)
	local count = math.floor(size.X * size.Y / 6)
	for _ = 1, count do
		local offset = Vector3.new(
			rng:NextNumber(-size.X / 2 + 0.6, size.X / 2 - 0.6),
			1.4,
			rng:NextNumber(-size.Y / 2 + 0.6, size.Y / 2 - 0.6)
		)
		local f = ball(
			"Flower",
			0.9,
			CFrame.new(position + offset),
			FLOWER_COLORS[rng:NextInteger(1, #FLOWER_COLORS)],
			Enum.Material.SmoothPlastic,
			m
		)
		BuildKit.noCollide(f)
	end
end

local function rock(parent: Instance, position: Vector3, size: number, color: Color3, rng: Random)
	local r = block(
		"Rock",
		Vector3.new(size, size * 0.7, size * 0.9),
		CFrame.new(position + Vector3.new(0, size * 0.3, 0))
			* CFrame.Angles(rng:NextNumber(-0.3, 0.3), rng:NextNumber(0, math.pi), rng:NextNumber(-0.3, 0.3)),
		color,
		Enum.Material.Rock,
		parent
	)
	return r
end

local function crystal(parent: Instance, position: Vector3, height: number, color: Color3, rng: Random)
	local c = block(
		"Crystal",
		Vector3.new(height * 0.35, height, height * 0.35),
		CFrame.new(position + Vector3.new(0, height * 0.45, 0))
			* CFrame.Angles(
				rng:NextNumber(-0.25, 0.25),
				rng:NextNumber(0, math.pi),
				rng:NextNumber(-0.25, 0.25)
			),
		color,
		Enum.Material.Glass,
		parent
	)
	c.Transparency = 0.15
	BuildKit.light(c, color, 10, 0.8)
	return c
end

local function cactus(parent: Instance, position: Vector3, scale: number)
	local m = BuildKit.model("Cactus", parent)
	local green = rgb(80, 150, 80)
	cylinder(
		"Stem",
		8 * scale,
		2 * scale,
		CFrame.new(position + Vector3.new(0, 4 * scale, 0)),
		green,
		Enum.Material.Grass,
		m
	)
	cylinder(
		"ArmL",
		3 * scale,
		1.2 * scale,
		CFrame.new(position + Vector3.new(-1.6 * scale, 5 * scale, 0)),
		green,
		Enum.Material.Grass,
		m
	)
	cylinder(
		"ArmR",
		3 * scale,
		1.2 * scale,
		CFrame.new(position + Vector3.new(1.6 * scale, 6 * scale, 0)),
		green,
		Enum.Material.Grass,
		m
	)
end

local function pine(parent: Instance, position: Vector3, scale: number, snow: boolean)
	local m = BuildKit.model("Pine", parent)
	cylinder(
		"Trunk",
		4 * scale,
		1.4 * scale,
		CFrame.new(position + Vector3.new(0, 2 * scale, 0)),
		PALETTE.Wood,
		Enum.Material.Wood,
		m
	)
	for i = 0, 2 do
		local size = (7 - i * 2) * scale
		local y = (4 + i * 3) * scale
		local color = if snow and i == 2 then PALETTE.White else rgb(40, 110, 70)
		local p = block(
			"Layer",
			Vector3.new(size, 3 * scale, size),
			CFrame.new(position + Vector3.new(0, y, 0)) * CFrame.Angles(0, math.rad(45 * i), 0),
			color,
			if snow and i == 2 then Enum.Material.Snow else Enum.Material.Grass,
			m
		)
		p.Shape = Enum.PartType.Block
	end
end

local function mushroom(parent: Instance, position: Vector3, scale: number, rng: Random)
	local m = BuildKit.model("Mushroom", parent)
	cylinder(
		"Stalk",
		4 * scale,
		1.4 * scale,
		CFrame.new(position + Vector3.new(0, 2 * scale, 0)),
		rgb(240, 230, 210),
		Enum.Material.SmoothPlastic,
		m
	)
	local capColors = { rgb(220, 60, 60), rgb(160, 90, 220), rgb(250, 160, 60) }
	ball(
		"Cap",
		5 * scale,
		CFrame.new(position + Vector3.new(0, 4.2 * scale, 0)),
		capColors[rng:NextInteger(1, #capColors)],
		Enum.Material.SmoothPlastic,
		m
	)
end

local function cloud(parent: Instance, position: Vector3, scale: number)
	local m = BuildKit.model("Cloud", parent)
	for i = -1, 1 do
		local p = ball(
			"Puff",
			(6 - math.abs(i)) * scale,
			CFrame.new(position + Vector3.new(i * 3.5 * scale, 0, 0)),
			PALETTE.White,
			Enum.Material.SmoothPlastic,
			m
		)
		BuildKit.noCollide(p)
	end
end

local function glitchCube(parent: Instance, position: Vector3, size: number, rng: Random)
	local colors = { rgb(60, 255, 140), rgb(255, 40, 90), rgb(60, 120, 255), rgb(20, 20, 20) }
	local c = block(
		"GlitchCube",
		Vector3.new(size, size, size),
		CFrame.new(position + Vector3.new(0, size / 2 + rng:NextNumber(0, 6), 0))
			* CFrame.Angles(rng:NextNumber(0, 1), rng:NextNumber(0, 1), 0),
		colors[rng:NextInteger(1, #colors)],
		Enum.Material.Neon,
		parent
	)
	c.Transparency = rng:NextNumber(0, 0.4)
	return c
end

-- Placeholder NPC (replaced automatically if an NPC model named `npcKey` is imported).
local function npc(parent: Instance, cf: CFrame, color: Color3, npcKey: string)
	local folder = ReplicatedStorage:FindFirstChild("Assets")
	local npcs = folder and folder:FindFirstChild("NPCModels")
	local source = npcs and npcs:FindFirstChild(npcKey)
	if source and source:IsA("Model") then
		local clone = source:Clone()
		clone.Parent = parent
		AssetRegistry.fitModel(clone, cf, 6)
		return
	end
	local m = BuildKit.model("NPC_" .. npcKey, parent)
	m:SetAttribute("Placeholder", true)
	block("Body", Vector3.new(2.4, 3, 1.4), cf * CFrame.new(0, 2.5, 0), color, Enum.Material.SmoothPlastic, m)
	ball("Head", 2.2, cf * CFrame.new(0, 5, 0), rgb(255, 220, 190), Enum.Material.SmoothPlastic, m)
	block(
		"Hat",
		Vector3.new(2.6, 0.6, 2.6),
		cf * CFrame.new(0, 6.1, 0),
		color:Lerp(Color3.new(0, 0, 0), 0.3),
		Enum.Material.SmoothPlastic,
		m
	)
end

-- Buildings -------------------------------------------------------------------------

-- Generic open-front shop. `cf` is the ground center; the front faces cf.LookVector.
local function shop(
	parent: Instance,
	name: string,
	cf: CFrame,
	wall: Color3,
	roof: Color3,
	glyph: string,
	title: string,
	panel: string,
	npcKey: string
)
	local m = BuildKit.model(name, parent)
	local w, d, h = 34, 28, 16
	block("Floor", Vector3.new(w, 1, d), cf * CFrame.new(0, 0.5, 0), PALETTE.Stone, Enum.Material.Slate, m)
	block(
		"Back",
		Vector3.new(w, h, 1.5),
		cf * CFrame.new(0, h / 2, d / 2),
		wall,
		Enum.Material.SmoothPlastic,
		m
	)
	block(
		"Left",
		Vector3.new(1.5, h, d),
		cf * CFrame.new(-w / 2, h / 2, 0),
		wall,
		Enum.Material.SmoothPlastic,
		m
	)
	block(
		"Right",
		Vector3.new(1.5, h, d),
		cf * CFrame.new(w / 2, h / 2, 0),
		wall,
		Enum.Material.SmoothPlastic,
		m
	)
	block(
		"PillarL",
		Vector3.new(2, h, 2),
		cf * CFrame.new(-w / 2 + 1, h / 2, -d / 2),
		PALETTE.White,
		Enum.Material.SmoothPlastic,
		m
	)
	block(
		"PillarR",
		Vector3.new(2, h, 2),
		cf * CFrame.new(w / 2 - 1, h / 2, -d / 2),
		PALETTE.White,
		Enum.Material.SmoothPlastic,
		m
	)
	-- pitched roof from two wedges
	wedge(
		"RoofFront",
		Vector3.new(w + 4, 6, d / 2 + 2),
		cf * CFrame.new(0, h + 3, -d / 4 - 0.5),
		roof,
		Enum.Material.SmoothPlastic,
		m
	)
	wedge(
		"RoofBack",
		Vector3.new(w + 4, 6, d / 2 + 2),
		cf * CFrame.new(0, h + 3, d / 4 + 0.5) * CFrame.Angles(0, math.pi, 0),
		roof,
		Enum.Material.SmoothPlastic,
		m
	)
	local sign = block(
		"Sign",
		Vector3.new(w - 6, 4, 0.6),
		cf * CFrame.new(0, h - 2.5, -d / 2 - 0.6),
		roof,
		Enum.Material.SmoothPlastic,
		m
	)
	BuildKit.surfaceText(sign, Enum.NormalId.Front, glyph .. " " .. title, PALETTE.White)
	local counter = block(
		"Counter",
		Vector3.new(14, 3.5, 3),
		cf * CFrame.new(0, 1.75, 2),
		PALETTE.Wood,
		Enum.Material.WoodPlanks,
		m
	)
	npc(m, cf * CFrame.new(0, 1, 6) * CFrame.Angles(0, math.pi, 0), roof, npcKey)
	local promptPart = block(
		"PromptAnchor",
		Vector3.new(2, 2, 2),
		cf * CFrame.new(0, 4.5, 0),
		PALETTE.White,
		Enum.Material.Neon,
		m
	)
	BuildKit.noCollide(promptPart)
	promptPart.Transparency = 1
	BuildKit.prompt(promptPart, "Open", title, { Action = "Panel", Panel = panel }, 16)
	BuildKit.billboard(counter, glyph, 8, PALETTE.White, 90, 0.6)
	return m
end

-- Districts -------------------------------------------------------------------------

local function buildIsland(world: Folder)
	if world:FindFirstChild("Island") then
		return
	end
	local island = BuildKit.folder("Island", world)
	local sx, sz, t = W.IslandSizeX, W.IslandSizeZ, W.IslandThickness
	block(
		"Beach",
		Vector3.new(sx + 60, t, sz + 60),
		CFrame.new(0, -t / 2 - 1.2, 0),
		PALETTE.Sand,
		Enum.Material.Sand,
		island
	)
	block(
		"Ground",
		Vector3.new(sx, t, sz),
		CFrame.new(0, -t / 2, 0),
		PALETTE.Grass,
		Enum.Material.Grass,
		island
	)
	-- paths
	local pathY = 0.15
	block(
		"AvenueNS",
		Vector3.new(26, 0.3, sz - 2 * (P.EdgeInset + P.Size) - 10),
		CFrame.new(0, pathY, 0),
		PALETTE.Path,
		Enum.Material.Cobblestone,
		island
	)
	block(
		"AvenueEW",
		Vector3.new(sx - 20, 0.3, 26),
		CFrame.new(0, pathY, 0),
		PALETTE.Path,
		Enum.Material.Cobblestone,
		island
	)
	local promenadeZ = sz / 2 - P.EdgeInset - P.Size - 14
	block(
		"PromenadeNorth",
		Vector3.new(sx - 30, 0.3, 22),
		CFrame.new(0, pathY, -promenadeZ),
		PALETTE.Path,
		Enum.Material.Cobblestone,
		island
	)
	block(
		"PromenadeSouth",
		Vector3.new(sx - 30, 0.3, 22),
		CFrame.new(0, pathY, promenadeZ),
		PALETTE.Path,
		Enum.Material.Cobblestone,
		island
	)
	block(
		"EastWalk",
		Vector3.new(18, 0.3, promenadeZ * 2),
		CFrame.new(sx / 2 - 92, pathY, 0),
		PALETTE.Path,
		Enum.Material.Cobblestone,
		island
	)
	block(
		"WestWalk",
		Vector3.new(18, 0.3, promenadeZ * 2),
		CFrame.new(-sx / 2 + 92, pathY, 0),
		PALETTE.Path,
		Enum.Material.Cobblestone,
		island
	)
	-- edge hedges keep players from wandering off the beach accidentally
	local rng = Random.new(7)
	for _, side in { -1, 1 } do
		for i = 0, 18 do
			local z = -sz / 2 + 30 + i * (sz - 60) / 18
			tree(island, Vector3.new(side * (sx / 2 - 8), 0, z), rng:NextNumber(0.9, 1.3), nil)
		end
	end
	-- reef: a natural ring of rocks offshore
	local reef = BuildKit.folder("Reef", island)
	local reefX, reefZ = W.BoundsX - 40, W.BoundsZ - 40
	for i = 0, 63 do
		local a = i / 64 * math.pi * 2
		local pos = Vector3.new(math.cos(a) * reefX, -6, math.sin(a) * reefZ)
		rock(reef, pos, rng:NextNumber(10, 20), rgb(120, 125, 135), rng)
	end
	-- distant scenery islands
	local far = BuildKit.folder("DistantIslands", island)
	for i = 0, 5 do
		local a = i / 6 * math.pi * 2 + 0.4
		local pos = Vector3.new(math.cos(a) * 1050, -10, math.sin(a) * 1050)
		local hill = ball(
			"Hill",
			rng:NextNumber(90, 160),
			CFrame.new(pos),
			PALETTE.GrassDark,
			Enum.Material.Grass,
			far
		)
		BuildKit.noCollide(hill)
	end
end

local function buildPlaza(world: Folder): CFrame
	local spawnCf = CFrame.new(0, 0.6, 52)
	if world:FindFirstChild("CentralPlaza") then
		local existingSpawn = world:FindFirstChild("SpawnLocation", true)
		if existingSpawn and existingSpawn:IsA("BasePart") then
			return existingSpawn.CFrame
		end
		return spawnCf
	end
	local plaza = BuildKit.folder("CentralPlaza", world)
	local rng = Random.new(11)
	cylinder("PlazaFloor", 0.4, 150, CFrame.new(0, 0.2, 0), PALETTE.Stone, Enum.Material.Slate, plaza)
	cylinder("PlazaRing", 0.5, 154, CFrame.new(0, 0.15, 0), PALETTE.StoneDark, Enum.Material.Slate, plaza)
	-- fountain with the Mythic Dice statue
	local fountain = BuildKit.model("Fountain", plaza)
	cylinder("Basin", 2.5, 40, CFrame.new(0, 1.25, 0), PALETTE.White, Enum.Material.Marble, fountain)
	local water =
		cylinder("Water", 0.6, 36, CFrame.new(0, 2.4, 0), PALETTE.Water, Enum.Material.Glass, fountain)
	water.Transparency = 0.3
	water.CanCollide = false
	cylinder("Tier2", 5, 14, CFrame.new(0, 4.5, 0), PALETTE.White, Enum.Material.Marble, fountain)
	cylinder("Tier3", 4, 8, CFrame.new(0, 9, 0), PALETTE.White, Enum.Material.Marble, fountain)
	local dice = block(
		"MythicDice",
		Vector3.new(9, 9, 9),
		CFrame.new(0, 18, 0) * CFrame.Angles(math.rad(35), math.rad(45), math.rad(20)),
		rgb(255, 214, 90),
		Enum.Material.Glass,
		fountain
	)
	dice.Transparency = 0.1
	BuildKit.light(dice, rgb(255, 210, 120), 40, 2)
	for i = 0, 3 do
		local a = i / 4 * math.pi * 2 + math.pi / 4
		local statue = AssetRegistry.makePlaceholder({
			DisplayName = "Statue",
			Color = PALETTE.White,
			Accent = PALETTE.Gold,
			Archetype = ({ "Tank", "Speedster", "Striker", "Support" })[i + 1],
			Scale = 1.3,
		})
		statue.Parent = fountain
		AssetRegistry.fitModel(
			statue,
			CFrame.new(math.cos(a) * 28, 0.4, math.sin(a) * 28) * CFrame.Angles(0, -a + math.pi / 2, 0),
			8
		)
		for _, p in statue:GetDescendants() do
			if p:IsA("BasePart") then
				p.Material = Enum.Material.Marble
			end
		end
	end
	-- spawn
	local spawnPad = Instance.new("SpawnLocation")
	spawnPad.Name = "SpawnLocation"
	spawnPad.Size = Vector3.new(14, 1, 14)
	spawnPad.CFrame = spawnCf
	spawnPad.Anchored = true
	spawnPad.Neutral = true
	spawnPad.Duration = 0
	spawnPad.Color = PALETTE.Gold
	spawnPad.Material = Enum.Material.SmoothPlastic
	spawnPad.Parent = plaza

	-- interactive stations around the fountain
	local function station(
		name: string,
		position: Vector3,
		color: Color3,
		glyph: string,
		title: string,
		panel: string
	)
		local m = BuildKit.model(name, plaza)
		local base = cylinder(
			"Base",
			3,
			10,
			CFrame.new(position + Vector3.new(0, 1.5, 0)),
			color,
			Enum.Material.SmoothPlastic,
			m
		)
		local top = block(
			"Top",
			Vector3.new(5, 5, 5),
			CFrame.new(position + Vector3.new(0, 6, 0)) * CFrame.Angles(0, math.rad(45), 0),
			color:Lerp(Color3.new(1, 1, 1), 0.35),
			Enum.Material.Neon,
			m
		)
		BuildKit.noCollide(top)
		BuildKit.billboard(base, glyph .. " " .. title, 9, PALETTE.White, 110, 0.9)
		BuildKit.prompt(base, "Open", title, { Action = "Panel", Panel = panel }, 14)
	end
	station("DailyRewards", Vector3.new(-48, 0.4, -24), rgb(255, 120, 160), "🎁", "Daily Rewards", "Daily")
	station("QuestBoard", Vector3.new(48, 0.4, -24), rgb(110, 180, 255), "📜", "Quests", "Quests")
	station(
		"Achievements",
		Vector3.new(-48, 0.4, 26),
		rgb(255, 200, 70),
		"🏆",
		"Achievements",
		"Achievements"
	)
	station("Codex", Vector3.new(48, 0.4, 26), rgb(160, 120, 255), "📖", "Monster Codex", "Codex")
	station("DiceAltar", Vector3.new(0, 0.4, -50), rgb(120, 220, 110), "🎲", "Dice Altar", "Roll")

	-- leaderboards
	local boards = BuildKit.folder("Leaderboards", plaza)
	for i, board in GameConfig.Leaderboards.Boards do
		local angle = math.rad(-60 + (i - 1) * 40)
		local pos = Vector3.new(math.sin(angle) * 66, 0, -math.cos(angle) * 66)
		local cf = CFrame.lookAt(pos, Vector3.new(0, 0, 0))
		local m = BuildKit.model("Board_" .. board.Id, boards)
		block("PostL", Vector3.new(1, 14, 1), cf * CFrame.new(-6, 7, 0), PALETTE.Wood, Enum.Material.Wood, m)
		block("PostR", Vector3.new(1, 14, 1), cf * CFrame.new(6, 7, 0), PALETTE.Wood, Enum.Material.Wood, m)
		local screen = block(
			"Screen",
			Vector3.new(12, 10, 0.6),
			cf * CFrame.new(0, 9, 0),
			rgb(30, 34, 52),
			Enum.Material.SmoothPlastic,
			m
		)
		screen:SetAttribute("BoardId", board.Id)
		screen:AddTag("LeaderboardScreen")
	end

	-- event board
	local eventBoard = block(
		"EventBoard",
		Vector3.new(16, 8, 0.8),
		CFrame.new(0, 6, 72) * CFrame.Angles(0, math.pi, 0),
		rgb(40, 30, 60),
		Enum.Material.SmoothPlastic,
		plaza
	)
	eventBoard:AddTag("EventBoard")
	BuildKit.surfaceText(eventBoard, Enum.NormalId.Front, "Events", PALETTE.Gold)
	BuildKit.prompt(eventBoard, "View", "Live Events", { Action = "Panel", Panel = "Events" }, 14)

	-- decoration ring
	for i = 0, 11 do
		local a = i / 12 * math.pi * 2
		local pos = Vector3.new(math.cos(a) * 80, 0, math.sin(a) * 80)
		if math.abs(math.cos(a)) > 0.2 and math.abs(math.sin(a)) > 0.2 then
			tree(plaza, pos, 1.2, nil)
		else
			lamp(plaza, pos + Vector3.new(0, 0, 0))
		end
	end
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2 + math.pi / 8
		local pos = Vector3.new(math.cos(a) * 60, 0.4, math.sin(a) * 60)
		bench(plaza, CFrame.lookAt(pos, Vector3.new(0, 0.4, 0)) * CFrame.Angles(0, math.pi, 0))
	end
	flowerBed(plaza, Vector3.new(-30, 0.4, 0), Vector2.new(8, 14), rng)
	flowerBed(plaza, Vector3.new(30, 0.4, 0), Vector2.new(8, 14), rng)
	return spawnCf
end

local SHOPS = {
	{
		Name = "DiceShop",
		Title = "Dice Shop",
		Glyph = "🎲",
		Panel = "Roll",
		Wall = rgb(255, 240, 200),
		Roof = rgb(90, 170, 90),
		Npc = "DiceMerchant",
	},
	{
		Name = "FusionLab",
		Title = "Fusion Lab",
		Glyph = "🧬",
		Panel = "Fusion",
		Wall = rgb(230, 220, 255),
		Roof = rgb(150, 90, 220),
		Npc = "FusionScientist",
	},
	{
		Name = "EquipmentForge",
		Title = "Equipment Forge",
		Glyph = "⚒",
		Panel = "Equipment",
		Wall = rgb(235, 225, 215),
		Roof = rgb(200, 90, 50),
		Npc = "Blacksmith",
	},
	{
		Name = "CraftingWorkshop",
		Title = "Workshop",
		Glyph = "🔧",
		Panel = "Crafting",
		Wall = rgb(240, 230, 205),
		Roof = rgb(150, 110, 70),
		Npc = "Craftsman",
	},
	{
		Name = "ChestVault",
		Title = "Chest Vault",
		Glyph = "🎁",
		Panel = "Chests",
		Wall = rgb(255, 235, 190),
		Roof = rgb(220, 170, 40),
		Npc = "VaultKeeper",
	},
	{
		Name = "MonsterStorage",
		Title = "Monster Storage",
		Glyph = "📦",
		Panel = "Inventory",
		Wall = rgb(215, 235, 255),
		Roof = rgb(70, 130, 210),
		Npc = "StorageKeeper",
	},
}

local function buildShops(world: Folder)
	if world:FindFirstChild("Shops") then
		return
	end
	local shops = BuildKit.folder("Shops", world)
	local x = W.IslandSizeX / 2 - 48
	local zs = { -200, -140, -80, 80, 140, 200 }
	for i, def in SHOPS do
		local pos = Vector3.new(x, 0.3, zs[i])
		local cf = CFrame.lookAt(pos, pos + Vector3.new(-1, 0, 0))
		shop(shops, def.Name, cf, def.Wall, def.Roof, def.Glyph, def.Title, def.Panel, def.Npc)
		lamp(shops, pos + Vector3.new(-24, 0, 18))
	end
	-- Trading Post at the end of the east-west avenue
	local tradePos = Vector3.new(W.IslandSizeX / 2 - 40, 0.3, 0)
	shop(
		shops,
		"TradingPost",
		CFrame.lookAt(tradePos, tradePos + Vector3.new(-1, 0, 0)),
		rgb(255, 245, 225),
		rgb(60, 180, 170),
		"🤝",
		"Trading Post",
		"Trade",
		"Trader"
	)
	local arch = BuildKit.model("ShopArch", shops)
	block(
		"ArchL",
		Vector3.new(3, 16, 3),
		CFrame.new(W.IslandSizeX / 2 - 100, 8, -16),
		PALETTE.White,
		Enum.Material.Marble,
		arch
	)
	block(
		"ArchR",
		Vector3.new(3, 16, 3),
		CFrame.new(W.IslandSizeX / 2 - 100, 8, 16),
		PALETTE.White,
		Enum.Material.Marble,
		arch
	)
	local top = block(
		"ArchTop",
		Vector3.new(4, 4, 36),
		CFrame.new(W.IslandSizeX / 2 - 100, 17, 0),
		PALETTE.Gold,
		Enum.Material.SmoothPlastic,
		arch
	)
	BuildKit.surfaceText(top, Enum.NormalId.Left, "🛒 Market District", PALETTE.White)
end

local function buildProgression(world: Folder): { [string]: CFrame }
	local portals: { [string]: CFrame } = {}
	if world:FindFirstChild("RegionGates") then
		return portals
	end
	local district = BuildKit.folder("ProgressionDistrict", world)
	local x = -W.IslandSizeX / 2 + 48
	local stations = {
		{
			Name = "SkillShrine",
			Title = "Skill Shrine",
			Glyph = "🌳",
			Panel = "Skills",
			Wall = rgb(220, 255, 230),
			Roof = rgb(60, 170, 110),
			Npc = "SkillSage",
			Z = -200,
		},
		{
			Name = "RebirthTemple",
			Title = "Rebirth Temple",
			Glyph = "♻",
			Panel = "Rebirth",
			Wall = rgb(255, 230, 240),
			Roof = rgb(220, 80, 140),
			Npc = "RebirthPriest",
			Z = -140,
		},
		{
			Name = "AscensionSpire",
			Title = "Ascension Spire",
			Glyph = "🌟",
			Panel = "Ascension",
			Wall = rgb(250, 235, 255),
			Roof = rgb(170, 90, 230),
			Npc = "AscensionOracle",
			Z = -80,
		},
	}
	for _, def in stations do
		local pos = Vector3.new(x, 0.3, def.Z)
		shop(
			district,
			def.Name,
			CFrame.lookAt(pos, pos + Vector3.new(1, 0, 0)),
			def.Wall,
			def.Roof,
			def.Glyph,
			def.Title,
			def.Panel,
			def.Npc
		)
	end

	-- Battle arena: a small colosseum at the end of the avenue
	local arena = BuildKit.model("BattleArena", district)
	local center = Vector3.new(-W.IslandSizeX / 2 + 52, 0.3, 0)
	cylinder(
		"ArenaFloor",
		1,
		56,
		CFrame.new(center + Vector3.new(0, 0.5, 0)),
		rgb(230, 200, 150),
		Enum.Material.Sand,
		arena
	)
	for i = 0, 15 do
		local a = i / 16 * math.pi * 2
		if math.abs(math.cos(a) - 1) > 0.15 then -- leave the east side open as the entrance
			local pos = center + Vector3.new(math.cos(a) * 28, 6, math.sin(a) * 28)
			block(
				"Wall",
				Vector3.new(4, 12, 11),
				CFrame.lookAt(pos, center + Vector3.new(0, 6, 0)),
				rgb(200, 180, 150),
				Enum.Material.Sandstone,
				arena
			)
		end
	end
	local banner = block(
		"ArenaBanner",
		Vector3.new(1, 6, 22),
		CFrame.new(center + Vector3.new(30, 16, 0)),
		rgb(200, 50, 50),
		Enum.Material.Fabric,
		arena
	)
	BuildKit.surfaceText(banner, Enum.NormalId.Right, "⚔ Battle Arena", PALETTE.White)
	local stone = cylinder(
		"BattleStone",
		3,
		8,
		CFrame.new(center + Vector3.new(0, 2, 0)),
		rgb(180, 60, 60),
		Enum.Material.Slate,
		arena
	)
	BuildKit.billboard(stone, "⚔ Battles & Arena", 7, PALETTE.White, 110, 0.9)
	BuildKit.prompt(stone, "Battle", "Team & Encounters", { Action = "Panel", Panel = "Battle" }, 14)

	-- Region gates along the south-west edge
	local gates = BuildKit.folder("RegionGates", world)
	local count = #RegionConfig.Order
	for i, regionId in RegionConfig.Order do
		local region = RegionConfig.Regions[regionId]
		local z = 46
			+ (i - 1) * ((W.IslandSizeZ / 2 - P.EdgeInset - P.Size - 40 - 46) / math.max(1, count - 1))
		local pos = Vector3.new(x - 6, 0.3, z)
		local cf = CFrame.lookAt(pos, pos + Vector3.new(1, 0, 0))
		local gate = BuildKit.model("Gate_" .. regionId, gates)
		gate:SetAttribute("RegionId", regionId)
		local theme = region.Theme
		block(
			"PillarL",
			Vector3.new(2.5, 14, 2.5),
			cf * CFrame.new(-6, 7, 0),
			theme.Accent,
			theme.AccentMaterial,
			gate
		)
		block(
			"PillarR",
			Vector3.new(2.5, 14, 2.5),
			cf * CFrame.new(6, 7, 0),
			theme.Accent,
			theme.AccentMaterial,
			gate
		)
		local top = block(
			"Lintel",
			Vector3.new(15, 3, 3),
			cf * CFrame.new(0, 15, 0),
			theme.Ground,
			theme.GroundMaterial,
			gate
		)
		BuildKit.surfaceText(top, Enum.NormalId.Front, region.DisplayName, PALETTE.White)
		local veil = block(
			"Portal",
			Vector3.new(9.5, 12.5, 0.6),
			cf * CFrame.new(0, 6.6, 0),
			theme.Accent,
			Enum.Material.Neon,
			gate
		)
		veil.Transparency = 0.35
		veil.CanCollide = false
		veil:SetAttribute("RegionId", regionId)
		veil:AddTag("RegionPortal")
		BuildKit.prompt(veil, "Enter", region.DisplayName, { Action = "Portal", RegionId = regionId }, 12)
		BuildKit.billboard(top, "", 4, PALETTE.White, 80, 1).Name = "LockLabel"
		portals[regionId] = cf
	end
	return portals
end

-- Plots ---------------------------------------------------------------------------------

local function plotOrigin(index: number): CFrame
	local perRow = P.PerRow
	local row = if index <= perRow then 1 else 2 -- 1 = north, 2 = south
	local column = ((index - 1) % perRow)
	local spacing = P.Size + P.Gap
	local x = (column - (perRow - 1) / 2) * spacing
	local zMag = W.IslandSizeZ / 2 - P.EdgeInset - P.Size / 2
	local z = if row == 1 then -zMag else zMag
	local pos = Vector3.new(x, 0.3, z)
	-- the plot's front (LookVector) faces the plaza
	return CFrame.lookAt(pos, Vector3.new(x, 0.3, 0))
end

local function buildPlotShell(parent: Instance, index: number): PlotInfo
	local origin = plotOrigin(index)
	local m = BuildKit.model("Plot" .. index, parent)
	m:SetAttribute("PlotIndex", index)
	local size = P.Size
	local originPart =
		block("Origin", Vector3.new(1, 1, 1), origin, PALETTE.White, Enum.Material.SmoothPlastic, m)
	BuildKit.noCollide(originPart)
	originPart.Transparency = 1
	local floor = block(
		"Floor1",
		Vector3.new(size, 1, size),
		origin * CFrame.new(0, 0.5, 0),
		rgb(225, 225, 232),
		Enum.Material.SmoothPlastic,
		m
	)
	floor:SetAttribute("Floor", 1)
	floor:AddTag("PlotFloor")
	-- low walls on the back and sides, open front
	local wallColor = rgb(190, 200, 215)
	block(
		"WallBack",
		Vector3.new(size, 5, 2),
		origin * CFrame.new(0, 3, size / 2 - 1),
		wallColor,
		Enum.Material.Brick,
		m
	)
	block(
		"WallLeft",
		Vector3.new(2, 5, size),
		origin * CFrame.new(-size / 2 + 1, 3, 0),
		wallColor,
		Enum.Material.Brick,
		m
	)
	block(
		"WallRight",
		Vector3.new(2, 5, size),
		origin * CFrame.new(size / 2 - 1, 3, 0),
		wallColor,
		Enum.Material.Brick,
		m
	)
	block(
		"WallFrontL",
		Vector3.new(size / 2 - 14, 5, 2),
		origin * CFrame.new(-size / 4 - 7, 3, -size / 2 + 1),
		wallColor,
		Enum.Material.Brick,
		m
	)
	block(
		"WallFrontR",
		Vector3.new(size / 2 - 14, 5, 2),
		origin * CFrame.new(size / 4 + 7, 3, -size / 2 + 1),
		wallColor,
		Enum.Material.Brick,
		m
	)
	-- entrance arch + owner sign
	block(
		"GateL",
		Vector3.new(3, 18, 3),
		origin * CFrame.new(-14, 9, -size / 2 + 1),
		PALETTE.White,
		Enum.Material.Marble,
		m
	)
	block(
		"GateR",
		Vector3.new(3, 18, 3),
		origin * CFrame.new(14, 9, -size / 2 + 1),
		PALETTE.White,
		Enum.Material.Marble,
		m
	)
	local sign = block(
		"Sign",
		Vector3.new(30, 6, 1),
		origin * CFrame.new(0, 19, -size / 2 + 1),
		rgb(50, 60, 90),
		Enum.Material.SmoothPlastic,
		m
	)
	local signLabel =
		BuildKit.surfaceText(sign, Enum.NormalId.Front, "Plot " .. index .. "\nUnclaimed", PALETTE.White)
	signLabel.Name = "OwnerText"
	local backLabel = BuildKit.surfaceText(sign, Enum.NormalId.Back, "Plot " .. index, PALETTE.White)
	backLabel.Name = "BackText"
	-- spawn pad (used as RespawnLocation for the owner)
	local spawnPad = Instance.new("SpawnLocation")
	spawnPad.Name = "PlotSpawn"
	spawnPad.Size = Vector3.new(10, 1, 10)
	spawnPad.CFrame = origin * CFrame.new(0, 1.1, -size / 2 + 12)
	spawnPad.Anchored = true
	spawnPad.Neutral = false
	spawnPad.Enabled = false -- RespawnLocation works regardless; keeps random spawning off plots
	spawnPad.Duration = 0
	spawnPad.Color = PALETTE.Gold
	spawnPad.Material = Enum.Material.SmoothPlastic
	spawnPad.Parent = m
	-- base upgrade station
	local station = cylinder(
		"UpgradeStation",
		3,
		6,
		origin * CFrame.new(size / 2 - 12, 2.5, -size / 2 + 14),
		rgb(255, 200, 70),
		Enum.Material.SmoothPlastic,
		m
	)
	BuildKit.billboard(station, "🏠 Base", 5, PALETTE.White, 60, 0.6)
	BuildKit.prompt(
		station,
		"Manage",
		"Base Upgrades",
		{ Action = "Panel", Panel = "Base", PlotIndex = index },
		12
	)
	-- upper floors (shown as locked ghosts until unlocked by PlotService)
	for floorNumber = 2, 3 do
		local y = (floorNumber - 1) * P.FloorHeight
		local upper = block(
			"Floor" .. floorNumber,
			Vector3.new(size - 16, 1.5, size - 30),
			origin * CFrame.new(0, y + 0.75, 8),
			rgb(225, 225, 232),
			Enum.Material.SmoothPlastic,
			m
		)
		upper:SetAttribute("Floor", floorNumber)
		upper:AddTag("PlotFloor")
		for _, corner in { Vector2.new(-1, -1), Vector2.new(1, -1), Vector2.new(-1, 1), Vector2.new(1, 1) } do
			block(
				"Pillar" .. floorNumber,
				Vector3.new(2, P.FloorHeight, 2),
				origin
					* CFrame.new(
						corner.X * ((size - 16) / 2 - 1),
						y - P.FloorHeight / 2,
						8 + corner.Y * ((size - 30) / 2 - 1)
					),
				wallColor,
				Enum.Material.Brick,
				m
			)
		end
		local railing = block(
			"Railing" .. floorNumber,
			Vector3.new(size - 16, 3, 1),
			origin * CFrame.new(0, y + 3, 8 + (size - 30) / 2),
			wallColor,
			Enum.Material.SmoothPlastic,
			m
		)
		railing.Transparency = 0.2
	end
	-- elevator pads between floors (client-side movement, see InteractionController)
	for floorNumber = 1, 3 do
		local y = (floorNumber - 1) * P.FloorHeight
		local pad = cylinder(
			"Elevator" .. floorNumber,
			0.6,
			7,
			origin * CFrame.new(-size / 2 + 14, y + 1.6, -30),
			rgb(120, 220, 255),
			Enum.Material.Neon,
			m
		)
		pad:SetAttribute("Floor", floorNumber)
		pad:SetAttribute("PlotIndex", index)
		pad:AddTag("PlotElevator")
		BuildKit.prompt(
			pad,
			"Change floor",
			"Elevator",
			{ Action = "Elevator", PlotIndex = index, Floor = floorNumber },
			10
		)
	end
	BuildKit.folder("Slots", m)
	BuildKit.folder("Displays", m)
	return { Index = index, Model = m, Origin = origin }
end

local function buildPlots(world: Folder): { [number]: PlotInfo }
	local plots: { [number]: PlotInfo } = {}
	local folder = world:FindFirstChild("PlayerBasePlots")
	if folder then
		-- Custom plots: Models named Plot1..PlotN each containing an "Origin" part.
		for i = 1, P.Count do
			local m = folder:FindFirstChild("Plot" .. i)
			local originPart = m and m:FindFirstChild("Origin")
			if m and m:IsA("Model") and originPart and originPart:IsA("BasePart") then
				BuildKit.folder("Slots", m)
				BuildKit.folder("Displays", m)
				m:SetAttribute("PlotIndex", i)
				plots[i] = { Index = i, Model = m, Origin = originPart.CFrame }
			end
		end
		if next(plots) then
			return plots
		end
		folder:Destroy()
	end
	local newFolder = BuildKit.folder("PlayerBasePlots", world)
	for i = 1, P.Count do
		plots[i] = buildPlotShell(newFolder, i)
	end
	return plots
end

-- Old hub -------------------------------------------------------------------------------
-- The original hand-built hub (Workspace.Hub, ground at Y 20.4) is kept as the map. What it
-- lacks is built by the normal district builders in a scratch folder, then moved onto free
-- spots of it. Old buildings keep their look and get wired to the new panels.

local OLD_GROUND = 20.4
local OLD_PANELS = {
	DiceShop = "Roll",
	SummonArea = "Roll",
	ChestShop = "Chests",
	UpgradeTree = "Skills",
	RebirthAltar = "Rebirth",
	Index = "Codex",
	Leaderboards = "Leaderboards",
	DailyRewards = "Daily",
	EventPortal = "Events",
}

local function oldSpot(x: number, z: number, faceZ: number): CFrame
	local p = Vector3.new(x, OLD_GROUND, z)
	return CFrame.lookAt(p, p + Vector3.new(0, 0, faceZ))
end

-- new-only buildings -> spot on the old plaza (front faces the fountain)
local OLD_ADDITIONS = {
	FusionLab = oldSpot(65, -190, 1),
	EquipmentForge = oldSpot(108, -190, 1),
	CraftingWorkshop = oldSpot(151, -190, 1),
	MonsterStorage = oldSpot(70, 205, -1),
	TradingPost = oldSpot(155, 205, -1),
	AscensionSpire = oldSpot(-65, 205, -1),
}

-- Old plots: 78x62 base, front +Z. Their slot pads go; PlotService places its own.
local function fitOldPlot(m: Model, index: number, parent: Instance): PlotInfo
	m.Parent = parent
	m:SetAttribute("PlotIndex", index)
	for _, d in m:GetChildren() do
		if d.Name:match("^Slot") or d.Name:match("^Collect") then
			d:Destroy()
		end
	end
	local base = m:FindFirstChild("Base") :: BasePart
	base.Name = "Floor1"
	base:SetAttribute("Floor", 1)
	base:AddTag("PlotFloor")
	-- new plot space: front = -Z, origin 4 studs behind center so the slot grid clears the front wall
	local origin = base.CFrame * CFrame.new(0, base.Size.Y / 2 - 1, -4) * CFrame.Angles(0, math.pi, 0)
	local originPart = block("Origin", Vector3.one, origin, PALETTE.White, Enum.Material.SmoothPlastic, m)
	BuildKit.noCollide(originPart)
	originPart.Transparency = 1
	local sign = m:FindFirstChild("OwnerSign")
	if sign then
		sign.Name = "Sign"
		for _, g in sign:GetChildren() do
			if g:IsA("SurfaceGui") then
				g.Name = if g.Face == Enum.NormalId.Front then "Label" else "BackLabel"
				local text = g:FindFirstChild("Label")
				if text then
					text.Name = "Text"
				end
			end
		end
	end
	local chest = m:FindFirstChild("UpgradeChest")
	local prompt = chest and chest:FindFirstChildOfClass("ProximityPrompt")
	if prompt then
		prompt:SetAttribute("Action", "Panel")
		prompt:SetAttribute("Panel", "Base")
		prompt:SetAttribute("PlotIndex", index)
	end
	local point = m:FindFirstChild("SpawnPoint")
	local spawnPad = Instance.new("SpawnLocation")
	spawnPad.Name = "PlotSpawn"
	spawnPad.Size = Vector3.new(10, 1, 10)
	spawnPad.CFrame = if point and point:IsA("BasePart") then point.CFrame else origin * CFrame.new(0, 1.1, -20)
	spawnPad.Anchored = true
	spawnPad.Neutral = false
	spawnPad.Enabled = false
	spawnPad.Duration = 0
	spawnPad.Transparency = 1
	BuildKit.noCollide(spawnPad)
	spawnPad.Parent = m
	-- upper floors + elevators, sized to the old base
	local w, d = base.Size.X - 4, base.Size.Z - 4
	local wallColor = rgb(190, 200, 215)
	for floorNumber = 2, 3 do
		local y = (floorNumber - 1) * P.FloorHeight
		local upper = block(
			"Floor" .. floorNumber,
			Vector3.new(w, 1.5, d),
			origin * CFrame.new(0, y + 0.75, -4),
			rgb(225, 225, 232),
			Enum.Material.SmoothPlastic,
			m
		)
		upper:SetAttribute("Floor", floorNumber)
		upper:AddTag("PlotFloor")
		for _, corner in { Vector2.new(-1, -1), Vector2.new(1, -1), Vector2.new(-1, 1), Vector2.new(1, 1) } do
			block(
				"Pillar" .. floorNumber,
				Vector3.new(2, P.FloorHeight, 2),
				origin * CFrame.new(corner.X * (w / 2 - 1), y - P.FloorHeight / 2, -4 + corner.Y * (d / 2 - 1)),
				wallColor,
				Enum.Material.Brick,
				m
			)
		end
		local railing = block(
			"Railing" .. floorNumber,
			Vector3.new(w, 3, 1),
			origin * CFrame.new(0, y + 3, -4 + d / 2),
			wallColor,
			Enum.Material.SmoothPlastic,
			m
		)
		railing.Transparency = 0.2
	end
	for floorNumber = 1, 3 do
		local pad = cylinder(
			"Elevator" .. floorNumber,
			0.6,
			7,
			origin * CFrame.new(-30, (floorNumber - 1) * P.FloorHeight + 1.6, 20),
			rgb(120, 220, 255),
			Enum.Material.Neon,
			m
		)
		pad:SetAttribute("Floor", floorNumber)
		pad:SetAttribute("PlotIndex", index)
		pad:AddTag("PlotElevator")
		BuildKit.prompt(
			pad,
			"Change floor",
			"Elevator",
			{ Action = "Elevator", PlotIndex = index, Floor = floorNumber },
			10
		)
	end
	BuildKit.folder("Slots", m)
	BuildKit.folder("Displays", m)
	return { Index = index, Model = m, Origin = origin }
end

local function fitOldHub(world: Folder, hub: Instance): (CFrame, { [number]: PlotInfo })
	local shops = hub:FindFirstChild("Shops") :: Instance
	for name, panel in OLD_PANELS do
		local m = shops:FindFirstChild(name)
		for _, d in if m then m:GetDescendants() else {} do
			if d:IsA("ProximityPrompt") then
				d:SetAttribute("Action", "Panel")
				d:SetAttribute("Panel", panel)
			end
		end
	end
	-- no premium panel in the new game yet
	local premium = shops:FindFirstChild("PremiumShop")
	for _, d in if premium then premium:GetDescendants() else {} do
		if d:IsA("ProximityPrompt") then
			d.Enabled = false
		end
	end

	local scratch = BuildKit.folder("Scratch", world)
	buildShops(scratch)
	buildProgression(scratch)
	buildPlaza(scratch)
	local extras = BuildKit.folder("HubExtras", world)
	local function moveTo(m: Model, ref: CFrame, target: CFrame)
		m:PivotTo(target * ref:ToObjectSpace(m:GetPivot()))
		m.Parent = extras
	end
	for name, target in OLD_ADDITIONS do
		local m = scratch:FindFirstChild(name, true) :: Model
		moveTo(m, (m:FindFirstChild("Floor") :: BasePart).CFrame * CFrame.new(0, -0.5, 0), target)
	end
	for name, pos in { QuestBoard = Vector3.new(-50, OLD_GROUND, 165), Achievements = Vector3.new(50, OLD_GROUND, 165) } do
		local m = scratch:FindFirstChild(name, true) :: Model
		moveTo(m, CFrame.new((m:FindFirstChild("Base") :: BasePart).Position - Vector3.new(0, 1.5, 0)), CFrame.new(pos))
	end
	local arena = scratch:FindFirstChild("BattleArena", true) :: Model
	local stone = arena:FindFirstChild("BattleStone") :: BasePart
	moveTo(arena, CFrame.new(stone.Position - Vector3.new(0, 2, 0)), CFrame.new(-155, OLD_GROUND, 200))
	-- region gates in a row on the north-west of the plaza
	local gates = scratch:FindFirstChild("RegionGates") :: Folder
	gates.Parent = world
	local count = #RegionConfig.Order
	for i, regionId in RegionConfig.Order do
		local gate = gates:FindFirstChild("Gate_" .. regionId) :: Model
		local portal = gate:FindFirstChild("Portal") :: BasePart
		local x = -185 + (i - 1) * 145 / math.max(1, count - 1)
		gate:PivotTo(oldSpot(x, -185, 1) * (portal.CFrame * CFrame.new(0, -6.6, 0)):ToObjectSpace(gate:GetPivot()))
	end
	scratch:Destroy()

	local plots: { [number]: PlotInfo } = {}
	local plotFolder = BuildKit.folder("PlayerBasePlots", world)
	local oldPlots = hub:FindFirstChild("Plots") :: Instance
	for i = 1, P.Count do
		local m = oldPlots:FindFirstChild("Plot" .. i)
		if m and m:IsA("Model") then
			plots[i] = fitOldPlot(m, i, plotFolder)
		end
	end
	local spawn = hub:FindFirstChild("SpawnLocation", true)
	local spawnCf = if spawn and spawn:IsA("BasePart") then spawn.CFrame else CFrame.new(0, OLD_GROUND, 150)
	return spawnCf * CFrame.new(0, 3, 0), plots
end

-- Region islands ----------------------------------------------------------------------

local function regionCenter(index: number): Vector3
	local spacing = W.RegionIslandSpacing
	local col = (index - 1) % 3 - 1
	local row = math.floor((index - 1) / 3) - 1
	return Vector3.new(col * spacing, W.RegionIslandHeight, row * spacing)
end

local function decorateRegion(parent: Instance, region: RegionConfig.RegionDef, center: Vector3, rng: Random)
	local theme = region.Theme
	local half = W.RegionIslandSize / 2 - 12
	local function spot(): Vector3
		for _ = 1, 20 do
			local p = Vector3.new(rng:NextNumber(-half, half), 0, rng:NextNumber(-half, half))
			-- keep the central play area clear
			if p.Magnitude > 55 then
				return center + p
			end
		end
		return center + Vector3.new(half, 0, half)
	end
	for _ = 1, 22 do
		local pos = spot()
		local decor = theme.Decor
		if decor == "Grass" then
			tree(parent, pos, rng:NextNumber(0.8, 1.3), nil)
		elseif decor == "Forest" then
			if rng:NextNumber() < 0.6 then
				tree(parent, pos, rng:NextNumber(1.2, 2), rgb(50, 130, 60))
			else
				mushroom(parent, pos, rng:NextNumber(0.8, 1.6), rng)
			end
		elseif decor == "Desert" then
			if rng:NextNumber() < 0.6 then
				cactus(parent, pos, rng:NextNumber(0.8, 1.4))
			else
				rock(parent, pos, rng:NextNumber(4, 9), rgb(210, 160, 100), rng)
			end
		elseif decor == "Mountain" then
			if rng:NextNumber() < 0.6 then
				pine(parent, pos, rng:NextNumber(1, 1.6), true)
			else
				rock(parent, pos, rng:NextNumber(8, 18), rgb(170, 180, 195), rng)
			end
		elseif decor == "Volcano" then
			if rng:NextNumber() < 0.5 then
				rock(parent, pos, rng:NextNumber(6, 14), rgb(50, 40, 40), rng)
			else
				local lava = cylinder(
					"Lava",
					0.4,
					rng:NextNumber(8, 16),
					CFrame.new(pos + Vector3.new(0, 0.3, 0)),
					rgb(255, 100, 20),
					Enum.Material.Neon,
					parent
				)
				lava.CanCollide = false
				BuildKit.light(lava, rgb(255, 120, 40), 16, 1.5)
			end
		elseif decor == "Cave" then
			crystal(parent, pos, rng:NextNumber(4, 12), theme.Accent, rng)
		elseif decor == "Heaven" then
			if rng:NextNumber() < 0.5 then
				cloud(parent, pos + Vector3.new(0, rng:NextNumber(4, 16), 0), rng:NextNumber(1, 2))
			else
				local column = cylinder(
					"Column",
					14,
					3,
					CFrame.new(pos + Vector3.new(0, 7, 0)),
					PALETTE.White,
					Enum.Material.Marble,
					parent
				)
				column.Name = "Column"
			end
		elseif decor == "Cosmic" then
			local star = ball(
				"Star",
				rng:NextNumber(1.5, 4),
				CFrame.new(pos + Vector3.new(0, rng:NextNumber(6, 30), 0)),
				theme.Accent,
				Enum.Material.Neon,
				parent
			)
			BuildKit.noCollide(star)
			if rng:NextNumber() < 0.4 then
				crystal(parent, pos, rng:NextNumber(5, 10), rgb(120, 90, 255), rng)
			end
		elseif decor == "Glitch" then
			glitchCube(parent, pos, rng:NextNumber(3, 9), rng)
		end
	end
end

local function buildRegion(world: Folder, region: RegionConfig.RegionDef, info: WorldInfo)
	local regionsFolder = BuildKit.folder("Regions", world)
	local center = regionCenter(region.Index)
	info.RegionCenters[region.Id] = center
	local arrival = CFrame.new(center + Vector3.new(0, 3, 80)) * CFrame.Angles(0, 0, 0)
	info.RegionArrivals[region.Id] = CFrame.lookAt(arrival.Position, center + Vector3.new(0, 3, 0))
	local existing = regionsFolder:FindFirstChild(region.Id)
	if existing then
		return
	end
	local m = BuildKit.model(region.Id, regionsFolder)
	m:SetAttribute("RegionId", region.Id)
	m:SetAttribute("Center", center)
	m:SetAttribute("Radius", W.RegionIslandSize * 0.75)
	local theme = region.Theme
	local size = W.RegionIslandSize
	local ground = block(
		"Ground",
		Vector3.new(size, 8, size),
		CFrame.new(center - Vector3.new(0, 4, 0)),
		theme.Ground,
		theme.GroundMaterial,
		m
	)
	ground:AddTag("RegionGround")
	local underside = ball(
		"Underside",
		size * 0.9,
		CFrame.new(center - Vector3.new(0, size * 0.32, 0)),
		theme.Ground:Lerp(Color3.new(0, 0, 0), 0.35),
		Enum.Material.Rock,
		m
	)
	BuildKit.noCollide(underside)
	-- invisible guard rails so nobody walks off the edge
	for _, side in
		{ Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0), Vector3.new(0, 0, 1), Vector3.new(0, 0, -1) }
	do
		local wall = block(
			"Guard",
			Vector3.new(if side.X ~= 0 then 2 else size, 30, if side.Z ~= 0 then 2 else size),
			CFrame.new(center + side * (size / 2) + Vector3.new(0, 15, 0)),
			theme.Accent,
			Enum.Material.ForceField,
			m
		)
		wall.Transparency = 0.85
	end
	-- arrival pad + return portal
	local pad = cylinder(
		"ArrivalPad",
		0.6,
		14,
		CFrame.new(center + Vector3.new(0, 0.3, 80)),
		theme.Accent,
		theme.AccentMaterial,
		m
	)
	BuildKit.billboard(pad, region.DisplayName, 10, PALETTE.White, 150, 1.2)
	local portal = block(
		"ReturnPortal",
		Vector3.new(10, 13, 0.6),
		CFrame.new(center + Vector3.new(0, 7, 98)),
		rgb(255, 230, 140),
		Enum.Material.Neon,
		m
	)
	portal.Transparency = 0.3
	portal.CanCollide = false
	BuildKit.prompt(portal, "Return", "Main Island", { Action = "Hub" }, 12)
	-- dice pedestal
	local dice = DiceConfig.Dice[region.DiceId]
	local pedestal = cylinder(
		"DicePedestal",
		4,
		8,
		CFrame.new(center + Vector3.new(-40, 2, 40)),
		theme.Accent,
		theme.AccentMaterial,
		m
	)
	local dieCube = block(
		"Die",
		Vector3.new(4, 4, 4),
		CFrame.new(center + Vector3.new(-40, 7, 40)) * CFrame.Angles(math.rad(30), math.rad(45), 0),
		if dice then dice.Color else PALETTE.White,
		Enum.Material.Neon,
		m
	)
	BuildKit.noCollide(dieCube)
	BuildKit.billboard(
		pedestal,
		"🎲 " .. (if dice then dice.DisplayName else "Dice"),
		9,
		PALETTE.White,
		100,
		0.9
	)
	BuildKit.prompt(
		pedestal,
		"Roll",
		if dice then dice.DisplayName else "Dice",
		{ Action = "Dice", DiceId = region.DiceId },
		12
	)
	-- encounter stones
	local encounters = EnemyConfig.encountersForRegion(region.Id)
	local positions =
		{ Vector3.new(-60, 0, -20), Vector3.new(0, 0, -30), Vector3.new(60, 0, -20), Vector3.new(0, 0, -80) }
	for i, encounter in encounters do
		local offset = positions[math.min(i, #positions)]
		local isBoss = encounter.IsBoss
		local stone = cylinder(
			if isBoss then "BossAltar" else "BattleStone",
			if isBoss then 5 else 3,
			if isBoss then 16 else 8,
			CFrame.new(center + offset + Vector3.new(0, if isBoss then 2.5 else 1.5, 0)),
			if isBoss then rgb(150, 30, 40) else theme.Accent:Lerp(Color3.new(0, 0, 0), 0.2),
			Enum.Material.Slate,
			m
		)
		info.EncounterPositions[encounter.Id] = stone.Position
		BuildKit.billboard(
			stone,
			(if isBoss then "💀 " else "⚔ ") .. encounter.DisplayName,
			if isBoss then 10 else 7,
			if isBoss then rgb(255, 120, 120) else PALETTE.White,
			120,
			if isBoss then 1.2 else 0.9
		)
		BuildKit.prompt(
			stone,
			if isBoss then "Challenge" else "Battle",
			encounter.DisplayName,
			{ Action = "Encounter", EncounterId = encounter.Id },
			14
		)
		-- show the enemy roster as statues
		local enemyDef = EnemyConfig.Enemies[encounter.Enemies[#encounter.Enemies].Enemy]
		if enemyDef then
			local statue = AssetRegistry.enemyModel(enemyDef.ModelKey, {
				DisplayName = enemyDef.DisplayName,
				Color = theme.Accent,
				Accent = theme.Ground,
				Archetype = enemyDef.Archetype,
				Scale = 1,
			})
			statue.Parent = m
			AssetRegistry.fitModel(
				statue,
				CFrame.new(
					center + offset + Vector3.new(0, if isBoss then 5 else 3, if isBoss then -12 else -8)
				) * CFrame.Angles(0, 0, 0),
				if isBoss then 14 else 7
			)
		end
	end
	-- exploration caches (claimable once per day each)
	local cachePositions = { Vector3.new(85, 0, 55), Vector3.new(-88, 0, -60), Vector3.new(90, 0, -85) }
	for c = 1, region.CacheCount do
		local cacheId = string.lower(region.Id) .. "_cache_" .. c
		local pos = center + cachePositions[((c - 1) % #cachePositions) + 1]
		local chest = block(
			"Cache",
			Vector3.new(4, 3, 3),
			CFrame.new(pos + Vector3.new(0, 1.5, 0)),
			PALETTE.Gold,
			Enum.Material.SmoothPlastic,
			m
		)
		chest:SetAttribute("CacheId", cacheId)
		BuildKit.prompt(chest, "Open", "Treasure Cache", { Action = "Cache", CacheId = cacheId }, 10)
		info.Caches[cacheId] = { Id = cacheId, Region = region.Id, Position = chest.Position }
	end
	decorateRegion(m, region, center, Random.new(region.Index * 101))
end

local function setupLighting()
	Lighting.Ambient = rgb(120, 120, 130)
	Lighting.OutdoorAmbient = rgb(150, 150, 160)
	Lighting.FogStart = 600
	Lighting.FogEnd = 2600
	Lighting.FogColor = rgb(200, 230, 255)
	if not Lighting:FindFirstChildOfClass("Sky") then
		local sky = Instance.new("Sky")
		sky.Name = "Sky"
		sky.Parent = Lighting
	end
	if not Lighting:FindFirstChildOfClass("Atmosphere") then
		local atmosphere = Instance.new("Atmosphere")
		atmosphere.Density = 0.25
		atmosphere.Color = rgb(200, 220, 255)
		atmosphere.Decay = rgb(120, 160, 220)
		atmosphere.Glare = 0.2
		atmosphere.Haze = 1
		atmosphere.Parent = Lighting
	end
end

local WorldBuilder = {}

function WorldBuilder.build(): WorldInfo
	local world = BuildKit.folder("World", Workspace)
	local runtime = BuildKit.folder("Runtime", Workspace)
	BuildKit.folder("ActiveMonsterDisplays", runtime)
	BuildKit.folder("TemporaryEffects", runtime)

	local info: WorldInfo = {
		World = world,
		Plots = {},
		HubSpawn = CFrame.new(0, 3, 52),
		RegionArrivals = {},
		RegionCenters = {},
		Caches = {},
		EncounterPositions = {},
	}
	local oldHub = Workspace:FindFirstChild("Hub")
	if oldHub then
		info.HubSpawn, info.Plots = fitOldHub(world, oldHub)
	else
		buildIsland(world)
		info.HubSpawn = buildPlaza(world) * CFrame.new(0, 3, 0)
		buildShops(world)
		buildProgression(world)
		info.Plots = buildPlots(world)
	end
	for _, regionId in RegionConfig.Order do
		buildRegion(world, RegionConfig.Regions[regionId], info)
	end
	setupLighting()
	return info
end

-- Exposed for tests.
WorldBuilder.plotOrigin = plotOrigin
WorldBuilder.regionCenter = regionCenter

return WorldBuilder
