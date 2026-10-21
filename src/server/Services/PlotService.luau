--!strict
-- Server-authoritative plot ownership. Each occupied plot belongs to exactly
-- one player; plots are released (and visually reset) when the owner leaves.
-- Builds the slot pads for the owner's current layout (Util/BaseLayout) and
-- shows locked floors with their unlock requirement.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Util = Shared:WaitForChild("Util")
local GameConfig = require(Config:WaitForChild("GameConfig"))
local EconomyConfig = require(Config:WaitForChild("EconomyConfig"))
local BaseLayout = require(Util:WaitForChild("BaseLayout"))
local Signal = require(Util:WaitForChild("Signal"))
local Types = require(Shared:WaitForChild("Types"))
local Modules = script.Parent.Parent:WaitForChild("Modules")
local BuildKit = require(Modules:WaitForChild("BuildKit"))
local NetServer = require(Modules:WaitForChild("NetServer"))
local WorldService = require(script.Parent:WaitForChild("WorldService"))
local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))
local ReplicationService = require(script.Parent:WaitForChild("ReplicationService"))

type Profile = Types.Profile

local P = GameConfig.Plots

local PlotService = {}

PlotService.LayoutChanged = Signal.new() :: Signal.Signal<Player>

local owners: { [number]: Player } = {}
local plotOf: { [Player]: number } = {}
local characterConnections: { [Player]: RBXScriptConnection } = {}

local EMPTY_COLOR = Color3.fromRGB(235, 240, 255)
local UNOWNED_COLOR = Color3.fromRGB(150, 155, 165)

function PlotService.plotIndex(player: Player): number?
	return plotOf[player]
end

function PlotService.owner(index: number): Player?
	return owners[index]
end

function PlotService.plotModel(index: number): Model?
	local plot = WorldService.info().Plots[index]
	return if plot then plot.Model else nil
end

function PlotService.origin(index: number): CFrame?
	local plot = WorldService.info().Plots[index]
	return if plot then plot.Origin else nil
end

function PlotService.spawnCFrame(index: number): CFrame?
	local model = PlotService.plotModel(index)
	local pad = model and model:FindFirstChild("PlotSpawn")
	if pad and pad:IsA("BasePart") then
		return pad.CFrame
	end
	local origin = PlotService.origin(index)
	return if origin then origin * CFrame.new(0, 2, -P.Size / 2 + 12) else nil
end

-- Local offset of a slot pad from the plot origin.
function PlotService.slotOffset(info: BaseLayout.SlotInfo): CFrame
	local column = (info.Index - 1) % P.SlotColumns
	local row = math.floor((info.Index - 1) / P.SlotColumns)
	local x = (column - (P.SlotColumns - 1) / 2) * P.SlotSpacing
	local z = -26 + row * P.SlotSpacing
	local y = (info.Floor - 1) * P.FloorHeight + (if info.Floor == 1 then 1.3 else 1.8)
	return CFrame.new(x, y, z)
end

function PlotService.slotCFrame(index: number, slotId: number, rebirths: number): CFrame?
	local origin = PlotService.origin(index)
	if not origin then
		return nil
	end
	for _, info in BaseLayout.layout(rebirths) do
		if info.SlotId == slotId then
			return origin * PlotService.slotOffset(info)
		end
	end
	return nil
end

local function setSign(index: number, text: string)
	local model = PlotService.plotModel(index)
	local sign = model and model:FindFirstChild("Sign")
	local gui = sign and sign:FindFirstChild("Label")
	local label = gui and gui:FindFirstChild("Text")
	if label and label:IsA("TextLabel") then
		label.Text = text
	end
end
PlotService.setSign = setSign

local function applyFloorVisuals(index: number, unlockedFloors: number, owned: boolean)
	local model = PlotService.plotModel(index)
	if not model then
		return
	end
	model:SetAttribute("UnlockedFloors", if owned then unlockedFloors else 1)
	for floorNumber = 2, 3 do
		local floor = model:FindFirstChild("Floor" .. floorNumber)
		if floor and floor:IsA("BasePart") then
			local unlocked = owned and floorNumber <= unlockedFloors
			floor.Transparency = if unlocked then 0 elseif owned then 0.75 else 0.9
			floor.CanCollide = unlocked
			local existing = floor:FindFirstChild("Billboard")
			if existing then
				existing:Destroy()
			end
			if owned and not unlocked then
				BuildKit.billboard(
					floor,
					string.format(
						"🔒 Floor %d · unlocks at Rebirth %d",
						floorNumber,
						BaseLayout.floorUnlockRebirth(floorNumber)
					),
					3,
					Color3.fromRGB(255, 230, 140),
					90,
					1.2
				)
			end
		end
		local elevator = model:FindFirstChild("Elevator" .. floorNumber)
		if elevator and elevator:IsA("BasePart") then
			local active = owned and floorNumber <= unlockedFloors
			elevator.Transparency = if active then 0 else 0.8
		end
	end
end

local function applyCosmetics(index: number, profile: Profile?)
	local model = PlotService.plotModel(index)
	if not model then
		return
	end
	local floorCosmetic = profile and profile.Base.EquippedCosmetics.Floor
	local def = floorCosmetic and EconomyConfig.BaseCosmetics[floorCosmetic]
	for floorNumber = 1, 3 do
		local floor = model:FindFirstChild("Floor" .. floorNumber)
		if floor and floor:IsA("BasePart") then
			floor.Color = if def then def.Color else Color3.fromRGB(225, 225, 232)
			floor.Material = if def then def.Material else Enum.Material.SmoothPlastic
		end
	end
	local lights = model:FindFirstChild("CosmeticLights")
	if lights then
		lights:Destroy()
	end
	local lighting = profile and profile.Base.EquippedCosmetics.Lighting
	local lightDef = lighting and EconomyConfig.BaseCosmetics[lighting]
	local origin = PlotService.origin(index)
	if lightDef and origin then
		local folder = BuildKit.folder("CosmeticLights", model)
		for i = 0, 5 do
			local x = (i % 3 - 1) * 40
			local z = if i < 3 then -40 else 40
			local lantern = BuildKit.ball(
				"Lantern",
				2.2,
				origin * CFrame.new(x, 9, z),
				lightDef.Color,
				Enum.Material.Neon,
				folder
			)
			BuildKit.noCollide(lantern)
			BuildKit.light(lantern, lightDef.Color, 16, 1)
		end
	end
	local decoFolder = model:FindFirstChild("CosmeticDecor")
	if decoFolder then
		decoFolder:Destroy()
	end
	local deco = profile and profile.Base.EquippedCosmetics.Decoration
	local decoDef = deco and EconomyConfig.BaseCosmetics[deco]
	if decoDef and origin then
		local folder = BuildKit.folder("CosmeticDecor", model)
		BuildKit.cylinder(
			"FountainBase",
			2,
			12,
			origin * CFrame.new(30, 1.5, -48),
			decoDef.Color,
			decoDef.Material,
			folder
		)
		local water = BuildKit.cylinder(
			"FountainWater",
			0.5,
			10,
			origin * CFrame.new(30, 2.6, -48),
			Color3.fromRGB(90, 190, 255),
			Enum.Material.Glass,
			folder
		)
		water.Transparency = 0.3
	end
	local sign = model:FindFirstChild("Sign")
	if sign and sign:IsA("BasePart") then
		local banner = profile and profile.Base.EquippedCosmetics.Sign
		local bannerDef = banner and EconomyConfig.BaseCosmetics[banner]
		sign.Color = if bannerDef then bannerDef.Color else Color3.fromRGB(50, 60, 90)
	end
end
PlotService.applyCosmetics = applyCosmetics

-- (Re)creates slot pads for the owner's layout.
function PlotService.buildSlots(player: Player)
	local index = plotOf[player]
	local profile = PlayerDataService.get(player)
	if not index or not profile then
		return
	end
	local model = PlotService.plotModel(index)
	local origin = PlotService.origin(index)
	if not model or not origin then
		return
	end
	local slots = BuildKit.folder("Slots", model)
	slots:ClearAllChildren()
	local rebirths = profile.Progression.RebirthCount
	local platform = profile.Base.EquippedCosmetics.Platform
	local platformDef = platform and EconomyConfig.BaseCosmetics[platform]
	for _, info in BaseLayout.layout(rebirths) do
		local cf = origin * PlotService.slotOffset(info)
		local pad = BuildKit.cylinder(
			"Slot_" .. info.SlotId,
			0.6,
			P.SlotPadSize,
			cf,
			if platformDef then platformDef.Color else EMPTY_COLOR,
			if platformDef then platformDef.Material else Enum.Material.SmoothPlastic,
			slots
		)
		pad:SetAttribute("SlotId", info.SlotId)
		pad:SetAttribute("Floor", info.Floor)
		pad:SetAttribute("PlotIndex", index)
		pad:AddTag("BaseSlot")
		BuildKit.prompt(
			pad,
			"Place",
			"Slot " .. info.SlotId,
			{ Action = "Slot", PlotIndex = index, SlotId = info.SlotId },
			9
		)
	end
	model:SetAttribute("TotalSlots", BaseLayout.totalSlots(rebirths))
	profile.Base.UnlockedFloors = BaseLayout.floorCount(rebirths)
	applyFloorVisuals(index, profile.Base.UnlockedFloors, true)
	applyCosmetics(index, profile)
	PlotService.LayoutChanged:Fire(player)
end

local function resetPlot(index: number)
	local model = PlotService.plotModel(index)
	if not model then
		return
	end
	local slots = model:FindFirstChild("Slots")
	if slots then
		slots:ClearAllChildren()
	end
	local displays = model:FindFirstChild("Displays")
	if displays then
		displays:ClearAllChildren()
	end
	model:SetAttribute("OwnerUserId", nil)
	model:SetAttribute("OwnerName", nil)
	model:SetAttribute("TotalSlots", 0)
	setSign(index, "Plot " .. index .. "\nUnclaimed")
	applyFloorVisuals(index, 1, false)
	applyCosmetics(index, nil)
	-- show grey pads so empty plots don't look broken
	local origin = PlotService.origin(index)
	if origin and model:FindFirstChild("Slots") then
		for _, info in BaseLayout.layout(0) do
			local pad = BuildKit.cylinder(
				"Slot_" .. info.SlotId,
				0.6,
				P.SlotPadSize,
				origin * PlotService.slotOffset(info),
				UNOWNED_COLOR,
				Enum.Material.SmoothPlastic,
				model:FindFirstChild("Slots") :: Instance
			)
			pad:SetAttribute("SlotId", info.SlotId)
		end
	end
end

function PlotService.assign(player: Player): number?
	if plotOf[player] then
		return plotOf[player]
	end
	for i = 1, P.Count do
		if not owners[i] and PlotService.plotModel(i) then
			owners[i] = player
			plotOf[player] = i
			local model = PlotService.plotModel(i) :: Model
			model:SetAttribute("OwnerUserId", player.UserId)
			model:SetAttribute("OwnerName", player.DisplayName)
			setSign(i, player.DisplayName .. "'s Base")
			return i
		end
	end
	return nil
end

function PlotService.release(player: Player)
	local index = plotOf[player]
	if not index then
		return
	end
	plotOf[player] = nil
	if owners[index] == player then
		owners[index] = nil
	end
	resetPlot(index)
end

function PlotService.teleportHome(player: Player): boolean
	local index = plotOf[player]
	local cf = index and PlotService.spawnCFrame(index)
	if not cf then
		return false
	end
	return WorldService.teleport(player, cf)
end

function PlotService.init()
	for i = 1, P.Count do
		resetPlot(i)
	end
	WorldService.setSafePositionProvider(function(player: Player): CFrame
		local index = plotOf[player]
		local cf = index and PlotService.spawnCFrame(index)
		return cf or WorldService.info().HubSpawn
	end)
	ReplicationService.addProvider(function(player, _profile, derived)
		derived.PlotIndex = plotOf[player]
	end)

	NetServer.handle("TeleportToPlot", { Rate = 1, Burst = 3 }, function(player, rawIndex)
		local index = if rawIndex == nil
			then plotOf[player]
			else (typeof(rawIndex) == "number" and rawIndex or nil)
		if typeof(index) ~= "number" or index ~= math.floor(index) or index < 1 or index > P.Count then
			return NetServer.invalid(player, "TeleportToPlot")
		end
		if index ~= plotOf[player] and not GameConfig.Social.VisitEnabled then
			return NetServer.fail("Visiting is disabled.")
		end
		local cf = PlotService.spawnCFrame(index)
		if not cf or not WorldService.teleport(player, cf) then
			return NetServer.fail("Can't teleport right now.")
		end
		return NetServer.ok()
	end)

	NetServer.handle("GetPlots", { Rate = 1, Burst = 3 }, function(_player)
		local list = {}
		for i = 1, P.Count do
			local owner = owners[i]
			local model = PlotService.plotModel(i)
			table.insert(list, {
				Index = i,
				OwnerName = if owner then owner.DisplayName else nil,
				OwnerUserId = if owner then owner.UserId else nil,
				Income = if model then model:GetAttribute("Income") else nil,
			})
		end
		return NetServer.ok(list)
	end)
end

function PlotService.onPlayerReady(player: Player, _profile: Profile)
	local index = PlotService.assign(player)
	if not index then
		NetServer.notify(
			player,
			"error",
			"All base plots are taken on this server. Your monsters still earn offline; try another server for a base."
		)
		return
	end
	local pad = PlotService.plotModel(index)
		and (PlotService.plotModel(index) :: Model):FindFirstChild("PlotSpawn")
	if pad and pad:IsA("SpawnLocation") then
		player.RespawnLocation = pad
	end
	PlotService.buildSlots(player)
	local function onCharacter(_character: Model)
		task.defer(function()
			PlotService.teleportHome(player)
		end)
	end
	characterConnections[player] = player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		onCharacter(player.Character)
	end
end

-- Hands a freed plot to a player who joined while every plot was taken.
local function assignWaiting(leaving: Player)
	for _, waiting in Players:GetPlayers() do
		local profile = PlayerDataService.get(waiting)
		if waiting ~= leaving and profile and not plotOf[waiting] then
			PlotService.onPlayerReady(waiting, profile)
			if plotOf[waiting] then
				NetServer.notify(waiting, "success", "A base plot opened up. It's yours now!")
			end
			return
		end
	end
end

function PlotService.onPlayerRemoving(player: Player, _profile: Profile)
	local conn = characterConnections[player]
	if conn then
		conn:Disconnect()
		characterConnections[player] = nil
	end
	local hadPlot = plotOf[player] ~= nil
	PlotService.release(player)
	if hadPlot then
		assignWaiting(player)
	end
end

function PlotService.start()
	Players.PlayerRemoving:Connect(function(player)
		-- safety net if the data lifecycle never reached ready
		if plotOf[player] then
			PlotService.release(player)
		end
	end)
end

return PlotService
