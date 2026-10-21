--!strict
-- Idle tycoon: monster placement on base slots, the centralized income tick,
-- and the physical monster displays. Income is computed only here, on the
-- server, from Util/StatMath + Util/Modifiers; one loop serves all players.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Util = Shared:WaitForChild("Util")
local EconomyConfig = require(Config:WaitForChild("EconomyConfig"))
local GameConfig = require(Config:WaitForChild("GameConfig"))
local MonsterConfig = require(Config:WaitForChild("MonsterConfig"))
local RarityConfig = require(Config:WaitForChild("RarityConfig"))
local CombatConfig = require(Config:WaitForChild("CombatConfig"))
local AssetConfig = require(Config:WaitForChild("AssetConfig"))
local BaseLayout = require(Util:WaitForChild("BaseLayout"))
local Modifiers = require(Util:WaitForChild("Modifiers"))
local StatMath = require(Util:WaitForChild("StatMath"))
local Format = require(Util:WaitForChild("Format"))
local Guard = require(Util:WaitForChild("Guard"))
local AssetRegistry = require(Shared:WaitForChild("AssetRegistry"))
local Types = require(Shared:WaitForChild("Types"))
local Modules = script.Parent.Parent:WaitForChild("Modules")
local NetServer = require(Modules:WaitForChild("NetServer"))
local GameEvents = require(Modules:WaitForChild("GameEvents"))
local BuildKit = require(Modules:WaitForChild("BuildKit"))
local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))
local EconomyService = require(script.Parent:WaitForChild("EconomyService"))
local InventoryService = require(script.Parent:WaitForChild("InventoryService"))
local PlotService = require(script.Parent:WaitForChild("PlotService"))
local ReplicationService = require(script.Parent:WaitForChild("ReplicationService"))

type Profile = Types.Profile

local TycoonService = {}

type IncomeState = { Rate: number, PerMonster: { [string]: number }, Fraction: number, Session: number }

local income: { [Player]: IncomeState } = {}

-- Income -------------------------------------------------------------------------

function TycoonService.computeIncome(player: Player): (number, { [string]: number })
	local profile = PlayerDataService.get(player)
	if not profile then
		return 0, {}
	end
	local mods = PlayerDataService.mods(player)
	return StatMath.totalIncome(profile, mods, Modifiers.incomeMultiplier(mods, true))
end

function TycoonService.rate(player: Player): number
	local state = income[player]
	return if state then state.Rate else 0
end

function TycoonService.sessionEarnings(player: Player): number
	local state = income[player]
	return if state then state.Session else 0
end

local function refreshIncome(player: Player)
	local state = income[player]
	if not state then
		return
	end
	state.Rate, state.PerMonster = TycoonService.computeIncome(player)
end
TycoonService.refreshIncome = refreshIncome

-- Grants `dt` seconds of income to every ready player. Called by the loop and by tests.
function TycoonService.tick(dt: number)
	for player, state in income do
		if PlayerDataService.isReady(player) then
			refreshIncome(player)
			local earned = state.Rate * dt + state.Fraction
			local whole = math.floor(earned)
			state.Fraction = earned - whole
			if whole > 0 then
				EconomyService.grant(player, "Coins", whole, "Income")
				state.Session += whole
			end
		end
	end
end

-- Displays -------------------------------------------------------------------------

local function displaysFolder(player: Player): Instance?
	local index = PlotService.plotIndex(player)
	local model = index and PlotService.plotModel(index)
	return model and model:FindFirstChild("Displays")
end

local function removeDisplay(player: Player, slotId: string)
	local folder = displaysFolder(player)
	local existing = folder and folder:FindFirstChild("Slot_" .. slotId)
	if existing then
		existing:Destroy()
	end
	local index = PlotService.plotIndex(player)
	local model = index and PlotService.plotModel(index)
	local slots = model and model:FindFirstChild("Slots")
	local pad = slots and slots:FindFirstChild("Slot_" .. slotId)
	if pad and pad:IsA("BasePart") then
		local prompt = pad:FindFirstChildOfClass("ProximityPrompt")
		if prompt then
			prompt.ActionText = "Place"
			prompt.ObjectText = "Slot " .. slotId
		end
		pad:SetAttribute("Occupied", false)
		pad:SetAttribute("MonsterInstanceId", nil)
	end
end

local function playIdle(model: Model, def: MonsterConfig.MonsterDef)
	local animId = AssetConfig.Animations[def.AnimationKeys.Idle]
	if not animId or animId == "" then
		return
	end
	local animator: Animator? = nil
	local humanoid = model:FindFirstChildWhichIsA("Humanoid", true)
	local controller = model:FindFirstChildWhichIsA("AnimationController", true)
	local host: Instance? = humanoid or controller
	if host then
		local existing = host:FindFirstChildOfClass("Animator")
		if existing then
			animator = existing
		else
			local created = Instance.new("Animator")
			created.Parent = host
			animator = created
		end
	end
	if not animator then
		return
	end
	local animation = Instance.new("Animation")
	animation.AnimationId = animId
	local ok, track = pcall(function()
		return (animator :: Animator):LoadAnimation(animation)
	end)
	if ok and track then
		track.Looped = true
		track:Play()
	end
end

local function spawnDisplay(player: Player, slotId: string, instanceId: string)
	local profile = PlayerDataService.get(player)
	local index = PlotService.plotIndex(player)
	local folder = displaysFolder(player)
	if not profile or not index or not folder then
		return
	end
	local inst = profile.Inventory.Monsters[instanceId]
	local def = inst and MonsterConfig.Monsters[inst.MonsterId]
	if not inst or not def then
		return
	end
	removeDisplay(player, slotId)
	local cf = PlotService.slotCFrame(index, tonumber(slotId) or 0, profile.Progression.RebirthCount)
	if not cf then
		return
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
	model.Name = "Slot_" .. slotId
	model:SetAttribute("MonsterId", def.MonsterId)
	model:SetAttribute("InstanceId", instanceId)
	model:SetAttribute("SlotId", tonumber(slotId))
	model.Parent = folder
	-- face the plot entrance
	local origin = PlotService.origin(index) :: CFrame
	local facing = CFrame.lookAt(cf.Position, cf.Position + origin.LookVector)
	AssetRegistry.fitModel(model, facing * CFrame.new(0, 0.3, 0), GameConfig.Plots.MonsterDisplayHeight)
	playIdle(model, def)
	-- rarity glow + label
	local anchor = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	if anchor and anchor:IsA("BasePart") and RarityConfig.tierOf(def.Rarity) >= 5 then
		BuildKit.light(anchor, rarity.Color, 12, 1)
	end
	if anchor and anchor:IsA("BasePart") and profile.Settings.ShowIncomeLabels then
		local state = income[player]
		local perSecond = if state then state.PerMonster[instanceId] or 0 else 0
		local gui = BuildKit.billboard(
			anchor,
			def.DisplayName .. "\n💰 " .. Format.number(perSecond) .. "/s",
			GameConfig.Plots.MonsterDisplayHeight * 0.6 + 2,
			rarity.Color,
			45,
			0.7
		)
		gui.Name = "IncomeLabel"
	end
	-- update the pad prompt
	local model2 = PlotService.plotModel(index)
	local slots = model2 and model2:FindFirstChild("Slots")
	local pad = slots and slots:FindFirstChild("Slot_" .. slotId)
	if pad and pad:IsA("BasePart") then
		local prompt = pad:FindFirstChildOfClass("ProximityPrompt")
		if prompt then
			prompt.ActionText = "Manage"
			prompt.ObjectText = def.DisplayName
		end
		pad:SetAttribute("Occupied", true)
		pad:SetAttribute("MonsterInstanceId", instanceId)
		pad.Color = rarity.Color
	end
end

function TycoonService.rebuildDisplays(player: Player)
	local profile = PlayerDataService.get(player)
	local folder = displaysFolder(player)
	if not profile or not folder then
		return
	end
	folder:ClearAllChildren()
	refreshIncome(player)
	for slotId, instanceId in profile.Base.PlacedMonsters do
		spawnDisplay(player, slotId, instanceId)
	end
end

local function updateLabels(player: Player)
	local state = income[player]
	local folder = displaysFolder(player)
	local index = PlotService.plotIndex(player)
	if not state or not index then
		return
	end
	PlotService.setSign(index, player.DisplayName .. "'s Base\n💰 " .. Format.number(state.Rate) .. "/s")
	local model = PlotService.plotModel(index)
	if model then
		model:SetAttribute("Income", state.Rate)
	end
	if not folder then
		return
	end
	for _, display in folder:GetChildren() do
		local instanceId = display:GetAttribute("InstanceId")
		local monsterId = display:GetAttribute("MonsterId")
		local label = display:FindFirstChild("IncomeLabel", true)
		if typeof(instanceId) == "string" and typeof(monsterId) == "string" and label then
			local def = MonsterConfig.Monsters[monsterId]
			local text = label:FindFirstChild("Text")
			if def and text and text:IsA("TextLabel") then
				text.Text = def.DisplayName
					.. "\n💰 "
					.. Format.number(state.PerMonster[instanceId] or 0)
					.. "/s"
			end
		end
	end
end

-- Placement ------------------------------------------------------------------------

function TycoonService.place(player: Player, instanceId: string, slotId: number): (boolean, string?)
	local profile = PlayerDataService.get(player)
	if not profile then
		return false, "Not ready"
	end
	if not PlotService.plotIndex(player) then
		return false, "You don't have a base on this server."
	end
	if not BaseLayout.isValidSlot(slotId, profile.Progression.RebirthCount) then
		return false, "That slot is locked."
	end
	local inst = profile.Inventory.Monsters[instanceId]
	if not inst then
		return false, "You don't own that monster."
	end
	local def = MonsterConfig.Monsters[inst.MonsterId]
	if not def or not def.CanPlaceInBase then
		return false, "That monster can't be placed."
	end
	local key = tostring(slotId)
	if profile.Base.PlacedMonsters[key] then
		return false, "That slot is occupied."
	end
	if InventoryService.slotOf(profile, instanceId) then
		return false, "That monster is already placed."
	end
	local lock = InventoryService.transientLock(player, instanceId)
	if lock == "Trade" then
		return false, "That monster is in a trade."
	end
	profile.Base.PlacedMonsters[key] = instanceId
	PlayerDataService.changed(player, "Base")
	refreshIncome(player)
	spawnDisplay(player, key, instanceId)
	updateLabels(player)
	GameEvents.fire(player, "PlaceMonster", { InstanceId = instanceId, SlotId = slotId })
	return true, nil
end

function TycoonService.remove(player: Player, slotId: number): (boolean, string?)
	local profile = PlayerDataService.get(player)
	if not profile then
		return false, "Not ready"
	end
	local key = tostring(slotId)
	if not profile.Base.PlacedMonsters[key] then
		return false, "That slot is empty."
	end
	profile.Base.PlacedMonsters[key] = nil
	PlayerDataService.changed(player, "Base")
	removeDisplay(player, key)
	refreshIncome(player)
	updateLabels(player)
	return true, nil
end

-- Fills empty slots with the highest-income monsters not yet placed.
function TycoonService.autoPlace(player: Player): number
	local profile = PlayerDataService.get(player)
	if not profile or not PlotService.plotIndex(player) then
		return 0
	end
	local mods = PlayerDataService.mods(player)
	local candidates = {}
	for id, inst in profile.Inventory.Monsters do
		if not InventoryService.slotOf(profile, id) and not InventoryService.transientLock(player, id) then
			table.insert(candidates, { Id = id, Income = StatMath.monsterIncome(inst, 0, mods) })
		end
	end
	table.sort(candidates, function(a, b)
		return a.Income > b.Income
	end)
	local placed = 0
	local nextCandidate = 1
	for slotId = 1, BaseLayout.totalSlots(profile.Progression.RebirthCount) do
		if not profile.Base.PlacedMonsters[tostring(slotId)] then
			local candidate = candidates[nextCandidate]
			if not candidate then
				break
			end
			nextCandidate += 1
			local ok = TycoonService.place(player, candidate.Id, slotId)
			if ok then
				placed += 1
			end
		end
	end
	return placed
end

-- Lifecycle -------------------------------------------------------------------------

function TycoonService.init()
	NetServer.handle("PlaceMonster", { Rate = 6, Burst = 10 }, function(player, rawInstance, rawSlot)
		local instanceId = Guard.string(rawInstance)
		local slotId = Guard.integer(rawSlot, 1, 200)
		if not instanceId or not slotId then
			return NetServer.invalid(player, "PlaceMonster")
		end
		local ok, err = TycoonService.place(player, instanceId, slotId)
		if not ok then
			return NetServer.fail(err or "Can't place.")
		end
		return NetServer.ok()
	end)

	NetServer.handle("RemoveMonster", { Rate = 6, Burst = 10 }, function(player, rawSlot)
		local slotId = Guard.integer(rawSlot, 1, 200)
		if not slotId then
			return NetServer.invalid(player, "RemoveMonster")
		end
		local ok, err = TycoonService.remove(player, slotId)
		if not ok then
			return NetServer.fail(err or "Can't remove.")
		end
		return NetServer.ok()
	end)

	NetServer.handle("AutoPlaceBest", { Rate = 1, Burst = 2 }, function(player)
		local count = TycoonService.autoPlace(player)
		if count == 0 then
			return NetServer.fail("No free slots or no monsters to place.")
		end
		return NetServer.ok({ Placed = count })
	end)

	ReplicationService.addProvider(function(player, _profile, derived)
		local state = income[player]
		if state then
			derived.TotalIncome = state.Rate
			derived.MonsterIncome = state.PerMonster
		end
	end)

	PlotService.LayoutChanged:Connect(function(player)
		if income[player] then
			TycoonService.rebuildDisplays(player)
			updateLabels(player)
		end
	end)
end

function TycoonService.onPlayerReady(player: Player, _profile: Profile)
	income[player] = { Rate = 0, PerMonster = {}, Fraction = 0, Session = 0 }
	TycoonService.rebuildDisplays(player)
	updateLabels(player)
end

function TycoonService.onPlayerRemoving(player: Player, _profile: Profile)
	income[player] = nil
end

function TycoonService.start()
	local accumulator = 0
	local labelTimer = 0
	RunService.Heartbeat:Connect(function(dt: number)
		accumulator += dt
		labelTimer += dt
		if accumulator >= EconomyConfig.IncomeTickSeconds then
			local elapsed = accumulator
			accumulator = 0
			TycoonService.tick(elapsed)
		end
		if labelTimer >= 3 then
			labelTimer = 0
			for player in income do
				updateLabels(player)
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		income[player] = nil
	end)
end

return TycoonService
