--!strict
-- Builds the world once at startup and exposes key locations to other
-- services. Also keeps players inside the playable area: anyone who falls
-- or swims past the reef is returned to safety.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig =
	require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("GameConfig"))
local Modules = script.Parent.Parent:WaitForChild("Modules")
local WorldBuilder = require(Modules:WaitForChild("WorldBuilder"))
local NetServer = require(Modules:WaitForChild("NetServer"))

local WorldService = {}

local info: WorldBuilder.WorldInfo? = nil
local safePosition: (Player) -> CFrame = function(_player: Player)
	return if info then info.HubSpawn else CFrame.new(0, 5, 50)
end

function WorldService.info(): WorldBuilder.WorldInfo
	assert(info, "WorldService.init has not run")
	return info
end

function WorldService.setSafePositionProvider(fn: (Player) -> CFrame)
	safePosition = fn
end

function WorldService.rootPart(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

function WorldService.teleport(player: Player, cf: CFrame): boolean
	local character = player.Character
	if not character or not WorldService.rootPart(player) then
		return false
	end
	character:PivotTo(cf + Vector3.new(0, 3, 0))
	return true
end

-- Which region island (if any) a position is on.
function WorldService.regionAt(position: Vector3): string?
	local current = info
	if not current then
		return nil
	end
	local half = GameConfig.World.RegionIslandSize / 2 + 20
	for regionId, center in current.RegionCenters do
		local d = position - center
		if math.abs(d.X) <= half and math.abs(d.Z) <= half and d.Y > -40 and d.Y < 200 then
			return regionId
		end
	end
	return nil
end

function WorldService.init()
	info = WorldBuilder.build()
end

function WorldService.start()
	local W = GameConfig.World
	task.spawn(function()
		while true do
			task.wait(1)
			for _, player in Players:GetPlayers() do
				local root = WorldService.rootPart(player)
				if root then
					local p = root.Position
					local onRegion = WorldService.regionAt(p) ~= nil
					local outOfBounds = if onRegion
						then false
						else (p.Y < W.MinY or math.abs(p.X) > W.BoundsX or math.abs(p.Z) > W.BoundsZ)
							and p.Y < W.RegionIslandHeight - 100
					local fellOffRegion = p.Y < W.RegionIslandHeight - 60 and p.Y > W.RegionIslandHeight - 400
					if outOfBounds or fellOffRegion then
						WorldService.teleport(player, safePosition(player))
						NetServer.notify(player, "info", "The currents carried you back to safety!")
					end
				end
			end
		end
	end)
end

return WorldService
