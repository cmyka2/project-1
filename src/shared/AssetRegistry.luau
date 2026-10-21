--!strict
-- Resolves ModelKeys / IconKeys / SoundKeys / AnimationKeys to assets and
-- generates placeholders when an asset has not been imported yet. Gameplay
-- code only ever asks for keys, so swapping a placeholder for a real model is
-- just "drop a Model with that name into the folder".

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AssetConfig = require(script.Parent.Config.AssetConfig)

export type PlaceholderInfo = {
	DisplayName: string,
	Color: Color3,
	Accent: Color3,
	Archetype: string?,
	Scale: number?,
}

local AssetRegistry = {}

local warned: { [string]: boolean } = {}
local missing: { [string]: string } = {} -- key -> kind

local function warnOnce(kind: string, key: string, message: string)
	local id = kind .. ":" .. key
	missing[key] = kind
	if warned[id] then
		return
	end
	warned[id] = true
	warn(string.format("[Assets] %s '%s' %s - using a placeholder", kind, key, message))
end

local function resolveFolder(path: string): Instance?
	local parts = string.split(path, "/")
	local root: Instance? = nil
	local serviceName = parts[1]
	if serviceName == "ServerStorage" then
		if not RunService:IsServer() then
			return nil
		end
		root = game:GetService("ServerStorage")
	elseif serviceName == "ReplicatedStorage" then
		root = ReplicatedStorage
	else
		return nil
	end
	local node = root
	for i = 2, #parts do
		if not node then
			return nil
		end
		node = node:FindFirstChild(parts[i])
	end
	return node
end

local function findIn(folders: { string }, key: string): Model?
	for _, path in folders do
		local folder = resolveFolder(path)
		if folder then
			local found = folder:FindFirstChild(key)
			if found and found:IsA("Model") then
				return found
			end
		end
	end
	return nil
end

function AssetRegistry.findMonsterModel(modelKey: string): Model?
	return findIn(AssetConfig.MonsterModelFolders, modelKey)
end

function AssetRegistry.findEnemyModel(modelKey: string): Model?
	return findIn(AssetConfig.EnemyModelFolders, modelKey)
end

local function part(
	name: string,
	shape: Enum.PartType,
	size: Vector3,
	color: Color3,
	parent: Instance,
	offset: CFrame
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = shape
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p:SetAttribute("Offset", offset)
	p.CFrame = offset
	p.Parent = parent
	return p
end

-- A friendly blob creature tinted by rarity/element. Height ~= 5 studs * Scale.
function AssetRegistry.makePlaceholder(info: PlaceholderInfo): Model
	local s = info.Scale or 1
	local model = Instance.new("Model")
	model.Name = info.DisplayName
	model:SetAttribute("Placeholder", true)
	local archetype = info.Archetype or "Bruiser"
	local bodySize = if archetype == "Tank"
		then Vector3.new(5, 4.2, 4.6)
		elseif archetype == "Speedster" then Vector3.new(3.4, 3.4, 3.4)
		elseif archetype == "Striker" then Vector3.new(3.8, 4, 3.8)
		else Vector3.new(4.2, 4, 4.2)
	local body = part(
		"Body",
		Enum.PartType.Ball,
		bodySize * s,
		info.Color,
		model,
		CFrame.new(0, bodySize.Y * 0.5 * s, 0)
	)
	model.PrimaryPart = body
	part(
		"Belly",
		Enum.PartType.Ball,
		bodySize * Vector3.new(0.7, 0.6, 0.5) * s,
		info.Accent,
		model,
		CFrame.new(0, bodySize.Y * 0.42 * s, -bodySize.Z * 0.28 * s)
	)
	local eyeY = bodySize.Y * 0.68 * s
	local eyeZ = -bodySize.Z * 0.42 * s
	for _, side in { -1, 1 } do
		local eyeX = side * bodySize.X * 0.2 * s
		part(
			"Eye",
			Enum.PartType.Ball,
			Vector3.new(1.1, 1.1, 1.1) * s,
			Color3.new(1, 1, 1),
			model,
			CFrame.new(eyeX, eyeY, eyeZ)
		)
		part(
			"Pupil",
			Enum.PartType.Ball,
			Vector3.new(0.55, 0.55, 0.55) * s,
			Color3.fromRGB(20, 20, 30),
			model,
			CFrame.new(eyeX, eyeY, eyeZ - 0.4 * s)
		)
		if archetype == "Speedster" then
			local wing = part(
				"Wing",
				Enum.PartType.Block,
				Vector3.new(2.4, 0.3, 1.4) * s,
				info.Accent,
				model,
				CFrame.new(side * bodySize.X * 0.6 * s, bodySize.Y * 0.6 * s, 0.3 * s)
					* CFrame.Angles(0, 0, side * math.rad(25))
			)
			wing.Material = Enum.Material.Neon
		elseif archetype == "Striker" then
			part(
				"Horn",
				Enum.PartType.Block,
				Vector3.new(0.5, 1.6, 0.5) * s,
				info.Accent,
				model,
				CFrame.new(side * bodySize.X * 0.25 * s, bodySize.Y * 1.05 * s, -0.2 * s)
					* CFrame.Angles(0, 0, side * math.rad(-15))
			)
		elseif archetype == "Tank" then
			part(
				"Plate",
				Enum.PartType.Block,
				Vector3.new(1.4, 1.6, 2.6) * s,
				info.Accent,
				model,
				CFrame.new(side * bodySize.X * 0.5 * s, bodySize.Y * 0.5 * s, 0)
			)
		elseif archetype == "Support" then
			part(
				"Ear",
				Enum.PartType.Ball,
				Vector3.new(1.2, 1.8, 0.8) * s,
				info.Accent,
				model,
				CFrame.new(side * bodySize.X * 0.32 * s, bodySize.Y * 1.0 * s, 0)
			)
		end
	end
	return model
end

-- Returns a fresh clone of the real model, or a placeholder if it is missing.
function AssetRegistry.monsterModel(modelKey: string, info: PlaceholderInfo): Model
	local source = AssetRegistry.findMonsterModel(modelKey)
	if source then
		local clone = source:Clone()
		clone:SetAttribute("ModelKey", modelKey)
		return clone
	end
	warnOnce(
		"Monster model",
		modelKey,
		"not found in " .. table.concat(AssetConfig.MonsterModelFolders, ", ")
	)
	local placeholder = AssetRegistry.makePlaceholder(info)
	placeholder:SetAttribute("ModelKey", modelKey)
	return placeholder
end

function AssetRegistry.enemyModel(modelKey: string, info: PlaceholderInfo): Model
	local source = AssetRegistry.findEnemyModel(modelKey)
	if source then
		return source:Clone()
	end
	warnOnce("Enemy model", modelKey, "not found")
	return AssetRegistry.makePlaceholder(info)
end

-- Scales a model to `targetHeight` studs and stands it on `groundCFrame`.
-- Works with or without a PrimaryPart (uses the bounding box).
function AssetRegistry.fitModel(model: Model, groundCFrame: CFrame, targetHeight: number)
	local override = AssetConfig.ModelOverrides[model:GetAttribute("ModelKey") :: string? or ""]
	local _, size = model:GetBoundingBox()
	if size.Y > 0 then
		local scale = targetHeight / size.Y * (if override and override.Scale then override.Scale else 1)
		if scale > 0 and scale == scale and math.abs(scale - 1) > 0.01 then
			local ok = pcall(function()
				model:ScaleTo(model:GetScale() * scale)
			end)
			if not ok then
				warn("[Assets] could not scale model " .. model.Name)
			end
		end
	end
	local boxCFrame, boxSize = model:GetBoundingBox()
	local pivot = model:GetPivot()
	-- offset from pivot to the bottom-center of the bounding box
	local bottomOffset = pivot:ToObjectSpace(boxCFrame * CFrame.new(0, -boxSize.Y / 2, 0))
	local rotation =
		CFrame.Angles(0, math.rad(if override and override.Rotation then override.Rotation else 0), 0)
	local yOffset = if override and override.YOffset then override.YOffset else 0
	model:PivotTo(groundCFrame * rotation * CFrame.new(0, yOffset, 0) * CFrame.new(-bottomOffset.Position))
	AssetRegistry.anchorForDisplay(model)
end

-- Makes a display model non-colliding and keeps it in place. Static models
-- are fully anchored. Rigged models (Motor6D joints) only anchor their root:
-- Roblox does not animate anchored limbs, so every part joined to the root
-- (directly or through welds) stays unanchored for animations to play.
function AssetRegistry.anchorForDisplay(model: Model)
	local parts: { BasePart } = {}
	local links: { [BasePart]: { BasePart } } = {}
	local rigged = false
	local function link(a: BasePart?, b: BasePart?)
		if a and b then
			links[a] = links[a] or {}
			links[b] = links[b] or {}
			table.insert(links[a], b)
			table.insert(links[b], a)
		end
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(parts, d)
		elseif d:IsA("JointInstance") then
			rigged = rigged or d:IsA("Motor6D")
			link(d.Part0, d.Part1)
		elseif d:IsA("WeldConstraint") then
			link(d.Part0, d.Part1)
		end
	end
	local root: BasePart? = model.PrimaryPart
	if not root then
		local hrp = model:FindFirstChild("HumanoidRootPart", true)
		root = if hrp and hrp:IsA("BasePart") then hrp else nil
	end
	local free: { [BasePart]: boolean } = {}
	if rigged and root then
		-- everything reachable from the root through joints moves with the rig
		local queue = { root }
		local seen: { [BasePart]: boolean } = { [root] = true }
		while #queue > 0 do
			local current = table.remove(queue) :: BasePart
			local neighbours: { BasePart } = links[current] or {}
			for _, other in neighbours do
				if not seen[other] then
					seen[other] = true
					free[other] = true
					table.insert(queue, other)
				end
			end
		end
	end
	for _, p in parts do
		p.Anchored = not free[p]
		p.CanCollide = false
	end
end

function AssetRegistry.icon(iconKey: string): string?
	local id = AssetConfig.Icons[iconKey]
	if id and id ~= "" then
		return id
	end
	return nil
end

function AssetRegistry.sound(soundKey: string): string?
	local id = AssetConfig.Sounds[soundKey]
	if id and id ~= "" then
		return id
	end
	return nil
end

function AssetRegistry.animation(animationKey: string): string?
	local id = AssetConfig.Animations[animationKey]
	if id and id ~= "" then
		return id
	end
	return nil
end

-- Keys requested this session that had no asset (for the import checklist).
function AssetRegistry.missingReport(): { [string]: string }
	return table.clone(missing)
end

return AssetRegistry
