-- Single source of truth for model references, keyed by stable ids (never display names).
-- Connect real art by dropping a Model named <id> into ReplicatedStorage.Assets.<Category>
-- (e.g. Assets.Monsters.moss_goblin, Assets.Shops.dice_shop) or by calling RegisterAsset at runtime.
-- A missing or unusable asset never errors: CreateAsset hands back a clearly labeled placeholder.
local RS = game:GetService("ReplicatedStorage")
local A = {}
A.Categories = {
	"Monsters", "Dice", "Shops", "Bases", "Statues", "Chests", "Weapons", "Armor", "Accessories", "Relics",
	"Arenas", "Enemies", "Bosses", "Icons", "Sounds", "Particles", "Animations", "Portals",
}
-- ids the code asks for today, per category (Monsters come from MonsterConfig)
A.Wanted = {
	Shops = { "summon_station", "dice_shop", "chest_shop", "upgrade_tree", "rebirth_altar", "index_codex" },
	Statues = { "main_statue" },
}
local registered = {}

function A.GetAsset(category: string, id: string): Instance?
	local r = registered[category] and registered[category][id]
	if r then return r end
	local root = RS:FindFirstChild("Assets")
	local folder = root and root:FindFirstChild(category)
	return folder and folder:FindFirstChild(id)
end
function A.HasAsset(category: string, id: string): boolean
	return A.GetAsset(category, id) ~= nil
end
function A.RegisterAsset(category: string, id: string, inst: Instance)
	assert(table.find(A.Categories, category), "unknown asset category " .. tostring(category))
	registered[category] = registered[category] or {}
	registered[category][id] = inst
end

-- a Model needs a PrimaryPart (or any BasePart to pivot on); rigged or static both work, no Humanoid required
function A.usable(inst: Instance?): boolean
	if not inst then return false end
	if inst:IsA("BasePart") then return true end
	if not inst:IsA("Model") then return false end
	return inst.PrimaryPart ~= nil or inst:FindFirstChildWhichIsA("BasePart", true) ~= nil
end

local function placeholder(category, id, size)
	local m = Instance.new("Model") m.Name = id
	local p = Instance.new("Part") p.Name = "Placeholder" p.Anchored = true p.Size = size or Vector3.new(8, 8, 8)
	p.Color = Color3.fromRGB(255, 0, 200) p.Material = Enum.Material.SmoothPlastic p.Transparency = 0.2 p.Parent = m
	local b = Instance.new("BillboardGui") b.Size = UDim2.fromScale(12, 3) b.StudsOffset = Vector3.new(0, p.Size.Y / 2 + 2, 0) b.MaxDistance = 120
	local t = Instance.new("TextLabel") t.Size = UDim2.fromScale(1, 1) t.BackgroundTransparency = 1 t.TextScaled = true t.Font = Enum.Font.FredokaOne
	t.Text = "PLACEHOLDER " .. category .. "/" .. id t.TextColor3 = Color3.new(1, 1, 1) t.TextStrokeTransparency = 0 t.Parent = b
	b.Parent = p
	m.PrimaryPart = p
	m:SetAttribute("Placeholder", true)
	return m
end

-- returns (instance, isPlaceholder); the clone keeps the asset id as its Name
function A.CreateAsset(category: string, id: string, parent: Instance?, size: Vector3?): (Instance, boolean)
	local src = A.GetAsset(category, id)
	local inst, fake
	if A.usable(src) then
		inst, fake = (src :: Instance):Clone(), false
		if inst:IsA("Model") and not inst.PrimaryPart then inst.PrimaryPart = inst:FindFirstChildWhichIsA("BasePart", true) end
		inst.Name = id
	else
		if src then warn("AssetRegistry: " .. category .. "/" .. id .. " has no parts to pivot on, using a placeholder") end
		inst, fake = placeholder(category, id, size), true
	end
	inst.Parent = parent
	return inst, fake
end

-- { [category] = { found = {ids}, missing = {ids}, broken = {ids} } } for every id the code wants
function A.ValidateRegistry()
	local Monsters = require(script.Parent.MonsterConfig)
	local wanted = table.clone(A.Wanted)
	wanted.Monsters = {}
	for _, d in Monsters.Monsters do table.insert(wanted.Monsters, d.id) end
	local report = {}
	for category, ids in wanted do
		local r = { found = {}, missing = {}, broken = {} }
		for _, id in ids do
			local src = A.GetAsset(category, id)
			table.insert(not src and r.missing or (A.usable(src) and r.found or r.broken), id)
		end
		report[category] = r
	end
	return report
end

return A
