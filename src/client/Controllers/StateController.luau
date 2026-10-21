--!strict
-- Client replica of the local player's profile plus server-derived values.
-- Read-only from the UI's perspective: it is updated exclusively by the
-- server's StateSync pushes. Controllers subscribe to Changed signals.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))
local Types = require(Shared:WaitForChild("Types"))

local StateController = {}

StateController.Profile = nil :: Types.Profile?
StateController.Derived = nil :: Types.DerivedState?
StateController.Changed = Signal.new() :: Signal.Signal<string>
StateController.Ready = Signal.new() :: Signal.Signal<()>

local isReady = false
-- Offset between server unix time and local os.time(), from derived.ServerTime.
local clockOffset = 0

function StateController.isReady(): boolean
	return isReady
end

function StateController.waitForReady()
	while not isReady do
		task.wait(0.1)
	end
end

function StateController.profile(): Types.Profile
	return StateController.Profile :: Types.Profile
end

function StateController.derived(): Types.DerivedState
	return StateController.Derived :: Types.DerivedState
end

function StateController.serverTime(): number
	return os.time() + clockOffset
end

function StateController.monsters(): { Types.MonsterInstance }
	local profile = StateController.Profile
	local out = {}
	if profile then
		for _, inst in profile.Inventory.Monsters do
			table.insert(out, inst)
		end
	end
	return out
end

function StateController.monster(id: string): Types.MonsterInstance?
	local profile = StateController.Profile
	return profile and profile.Inventory.Monsters[id]
end

function StateController.slotOf(instanceId: string): number?
	local profile = StateController.Profile
	if not profile then
		return nil
	end
	for slot, id in profile.Base.PlacedMonsters do
		if id == instanceId then
			return tonumber(slot)
		end
	end
	return nil
end

function StateController.inTeam(instanceId: string): boolean
	local profile = StateController.Profile
	return profile ~= nil and table.find(profile.Battle.Team, instanceId) ~= nil
end

function StateController.equipmentOn(instanceId: string): { Types.EquipmentInstance }
	local profile = StateController.Profile
	local out = {}
	if profile then
		for _, item in profile.Inventory.Equipment do
			if item.EquippedTo == instanceId then
				table.insert(out, item)
			end
		end
	end
	return out
end

local function onSync(kind: string, a: any, b: any)
	if kind == "Full" then
		StateController.Profile = a
		StateController.Derived = b
		if b and b.ServerTime then
			clockOffset = b.ServerTime - os.time()
		end
		StateController.Changed:Fire("*")
		if not isReady then
			isReady = true
			StateController.Ready:Fire()
		end
		return
	end
	local profile = StateController.Profile
	if not profile then
		return
	end
	if kind == "Key" then
		if a == "Inventory" then
			-- partial: monsters/equipment arrive as deltas
			local inv = profile.Inventory :: any
			for field, value in b do
				inv[field] = value
			end
		else
			(profile :: any)[a] = b
		end
		StateController.Changed:Fire(a)
	elseif kind == "Monsters" then
		for id, inst in a do
			if inst == false then
				profile.Inventory.Monsters[id] = nil
			else
				profile.Inventory.Monsters[id] = inst
			end
		end
		StateController.Changed:Fire("Monsters")
	elseif kind == "Equipment" then
		for id, item in a do
			if item == false then
				profile.Inventory.Equipment[id] = nil
			else
				profile.Inventory.Equipment[id] = item
			end
		end
		StateController.Changed:Fire("Equipment")
	elseif kind == "Derived" then
		StateController.Derived = a
		if a and a.ServerTime then
			clockOffset = a.ServerTime - os.time()
		end
		StateController.Changed:Fire("Derived")
	end
end

function StateController.init()
	Net.on("StateSync", onSync)
end

function StateController.start()
	-- If the first snapshot arrived before we were listening, ask again.
	local waited = 0
	while not isReady do
		task.wait(1)
		waited += 1
		if not isReady and waited % 3 == 0 then
			Net.request("RequestState")
		end
	end
end

return StateController
