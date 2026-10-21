--!strict
-- Small helpers for building anchored geometry from code (used by WorldBuilder
-- and PlotService). Everything created here is anchored and server-owned.

local BuildKit = {}

export type Props = { [string]: any }

function BuildKit.make(className: string, props: Props?, parent: Instance?): Instance
	local inst = Instance.new(className)
	if props then
		for key, value in props do
			(inst :: any)[key] = value
		end
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

function BuildKit.folder(name: string, parent: Instance): Folder
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("Folder") then
		return existing
	end
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

function BuildKit.model(name: string, parent: Instance): Model
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end

local function basePart(
	p: BasePart,
	name: string,
	cf: CFrame,
	color: Color3,
	material: Enum.Material,
	parent: Instance
)
	p.Name = name
	p.Anchored = true
	p.CFrame = cf
	p.Color = color
	p.Material = material
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
end

function BuildKit.block(
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material,
	parent: Instance
): Part
	local p = Instance.new("Part")
	p.Size = size
	basePart(p, name, cf, color, material, parent)
	return p
end

-- Upright cylinder (Roblox cylinders run along X, so rotate onto Y).
function BuildKit.cylinder(
	name: string,
	height: number,
	diameter: number,
	cf: CFrame,
	color: Color3,
	material: Enum.Material,
	parent: Instance
): Part
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Cylinder
	p.Size = Vector3.new(height, diameter, diameter)
	basePart(p, name, cf * CFrame.Angles(0, 0, math.rad(90)), color, material, parent)
	return p
end

function BuildKit.ball(
	name: string,
	diameter: number,
	cf: CFrame,
	color: Color3,
	material: Enum.Material,
	parent: Instance
): Part
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Ball
	p.Size = Vector3.new(diameter, diameter, diameter)
	basePart(p, name, cf, color, material, parent)
	return p
end

function BuildKit.wedge(
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material,
	parent: Instance
): WedgePart
	local p = Instance.new("WedgePart")
	p.Size = size
	basePart(p, name, cf, color, material, parent)
	return p
end

function BuildKit.noCollide(p: BasePart): BasePart
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	return p
end

function BuildKit.light(parent: BasePart, color: Color3, range: number, brightness: number?): PointLight
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = range
	light.Brightness = brightness or 1.5
	light.Shadows = false
	light.Parent = parent
	return light
end

-- Text on one face of a part.
function BuildKit.surfaceText(
	part: BasePart,
	face: Enum.NormalId,
	text: string,
	textColor: Color3?,
	background: Color3?
): TextLabel
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Label"
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 30
	gui.LightInfluence = 0
	gui.Parent = part
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = if background then 0 else 1
	label.BackgroundColor3 = background or Color3.new(0, 0, 0)
	label.TextColor3 = textColor or Color3.new(1, 1, 1)
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.Text = text
	label.TextStrokeTransparency = 0.6
	label.Parent = gui
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0.04, 0)
	pad.PaddingRight = UDim.new(0.04, 0)
	pad.PaddingTop = UDim.new(0.08, 0)
	pad.PaddingBottom = UDim.new(0.08, 0)
	pad.Parent = label
	return label
end

-- Floating label above a part.
function BuildKit.billboard(
	adornee: BasePart,
	text: string,
	offsetY: number,
	color: Color3?,
	maxDistance: number?,
	sizeScale: number?
): BillboardGui
	local gui = Instance.new("BillboardGui")
	gui.Name = "Billboard"
	gui.Size = UDim2.fromOffset(220 * (sizeScale or 1), 56 * (sizeScale or 1))
	gui.StudsOffsetWorldSpace = Vector3.new(0, offsetY, 0)
	gui.AlwaysOnTop = false
	gui.MaxDistance = maxDistance or 120
	gui.LightInfluence = 0
	gui.Adornee = adornee
	gui.Parent = adornee
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = color or Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.2
	label.Text = text
	label.Parent = gui
	return gui
end

-- Interaction prompt. Attributes tell the client what the prompt does:
--   Action = "Panel" | "Slot" | "Portal" | "Hub" | "Cache" | "Encounter" | "Elevator" | "Dice"
function BuildKit.prompt(
	parent: BasePart,
	actionText: string,
	objectText: string,
	attributes: { [string]: any },
	distance: number?
): ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "Prompt"
	prompt.ActionText = actionText
	prompt.ObjectText = objectText
	prompt.MaxActivationDistance = distance or 12
	prompt.HoldDuration = 0
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	for key, value in attributes do
		prompt:SetAttribute(key, value)
	end
	prompt.Parent = parent
	return prompt
end

return BuildKit
