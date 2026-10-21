--!strict
-- Monster, equipment, consumable and chest inventories. Owns protection
-- rules: locked/favorite monsters, monsters placed in the base, and monsters
-- temporarily locked by an active battle or trade can never be sold or
-- consumed by accident.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Util = Shared:WaitForChild("Util")
local MonsterConfig = require(Config:WaitForChild("MonsterConfig"))
local EquipmentConfig = require(Config:WaitForChild("EquipmentConfig"))
local CraftingConfig = require(Config:WaitForChild("CraftingConfig"))
local ChestConfig = require(Config:WaitForChild("ChestConfig"))
local Modifiers = require(Util:WaitForChild("Modifiers"))
local StatMath = require(Util:WaitForChild("StatMath"))
local Guard = require(Util:WaitForChild("Guard"))
local Types = require(Shared:WaitForChild("Types"))
local Modules = script.Parent.Parent:WaitForChild("Modules")
local NetServer = require(Modules:WaitForChild("NetServer"))
local GameEvents = require(Modules:WaitForChild("GameEvents"))
local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))
local MonsterService = require(script.Parent:WaitForChild("MonsterService"))
local EconomyService = require(script.Parent:WaitForChild("EconomyService"))

type Profile = Types.Profile
type MonsterInstance = Types.MonsterInstance

local InventoryService = {}

local transientLocks: { [Player]: { [string]: string } } = {}

-- Capacity ---------------------------------------------------------------------

function InventoryService.monsterCount(profile: Profile): number
	local n = 0
	for _ in profile.Inventory.Monsters do
		n += 1
	end
	return n
end

function InventoryService.equipmentCount(profile: Profile): number
	local n = 0
	for _ in profile.Inventory.Equipment do
		n += 1
	end
	return n
end

function InventoryService.freeMonsterSlots(player: Player): number
	local profile = PlayerDataService.get(player)
	if not profile then
		return 0
	end
	return Modifiers.monsterCapacity(PlayerDataService.mods(player)) - InventoryService.monsterCount(profile)
end

-- Transient locks (battle / trade) -----------------------------------------------

function InventoryService.setTransientLock(player: Player, instanceId: string, reason: string?)
	local map = transientLocks[player]
	if not map then
		map = {}
		transientLocks[player] = map
	end
	if reason then
		map[instanceId] = reason
	else
		map[instanceId] = nil
	end
end

function InventoryService.transientLock(player: Player, instanceId: string): string?
	local map = transientLocks[player]
	return map and map[instanceId]
end

function InventoryService.clearTransientLocks(player: Player, reason: string)
	local map = transientLocks[player]
	if not map then
		return
	end
	for id, r in map do
		if r == reason then
			map[id] = nil
		end
	end
end

-- Queries ------------------------------------------------------------------------

function InventoryService.slotOf(profile: Profile, instanceId: string): string?
	for slotId, id in profile.Base.PlacedMonsters do
		if id == instanceId then
			return slotId
		end
	end
	return nil
end

export type ConsumeOptions = { AllowProtected: boolean?, AllowPlaced: boolean? }

-- Can this monster be sold / fused / traded away right now?
function InventoryService.canConsume(
	player: Player,
	inst: MonsterInstance,
	options: ConsumeOptions?
): (boolean, string?)
	local profile = PlayerDataService.get(player)
	if not profile or profile.Inventory.Monsters[inst.Id] ~= inst then
		return false, "You don't own that monster."
	end
	local lock = InventoryService.transientLock(player, inst.Id)
	if lock then
		return false, "That monster is busy (" .. lock .. ")."
	end
	if not (options and options.AllowPlaced) and InventoryService.slotOf(profile, inst.Id) then
		return false, "Remove it from your base first."
	end
	-- Locked is a hard lock (unlock it first); Favorite only needs the player's confirmation.
	if inst.Locked then
		return false, "That monster is locked. Unlock it first."
	end
	if not (options and options.AllowProtected) and inst.Favorite then
		return false, "That monster is a favorite. Confirm to use it."
	end
	return true, nil
end

-- Mutations ------------------------------------------------------------------------

export type AddOptions = { IgnoreCapacity: boolean?, NoDiscover: boolean? }

function InventoryService.addMonster(
	player: Player,
	monsterId: string,
	source: string,
	options: AddOptions?
): (MonsterInstance?, string?)
	local profile = PlayerDataService.get(player)
	if not profile then
		return nil, "Not ready"
	end
	if not MonsterConfig.Monsters[monsterId] then
		return nil, "Unknown monster"
	end
	if not (options and options.IgnoreCapacity) and InventoryService.freeMonsterSlots(player) <= 0 then
		return nil, "Your monster storage is full."
	end
	local inst = MonsterService.newInstance(profile, monsterId, source)
	profile.Inventory.Monsters[inst.Id] = inst
	if not (options and options.NoDiscover) then
		MonsterService.discover(player, profile, monsterId, source)
	end
	PlayerDataService.monsterChanged(player, inst.Id)
	PlayerDataService.changed(player, "Inventory")
	return inst, nil
end

-- Removes a monster and every reference to it (team, loadouts, equipment).
-- Callers must have checked canConsume first.
function InventoryService.removeMonster(player: Player, instanceId: string)
	local profile = PlayerDataService.get(player)
	if not profile or not profile.Inventory.Monsters[instanceId] then
		return
	end
	profile.Inventory.Monsters[instanceId] = nil
	local slot = InventoryService.slotOf(profile, instanceId)
	if slot then
		profile.Base.PlacedMonsters[slot] = nil
		PlayerDataService.changed(player, "Base")
	end
	for _, item in profile.Inventory.Equipment do
		if item.EquippedTo == instanceId then
			item.EquippedTo = nil
			PlayerDataService.equipmentChanged(player, item.Id)
		end
	end
	local battle = profile.Battle
	local function strip(list: { string })
		local i = table.find(list, instanceId)
		if i then
			table.remove(list, i)
		end
	end
	strip(battle.Team)
	for _, loadout in battle.Loadouts do
		strip(loadout)
	end
	PlayerDataService.changed(player, "Battle")
	PlayerDataService.monsterChanged(player, instanceId)
	PlayerDataService.changed(player, "Inventory")
end

function InventoryService.addEquipment(
	player: Player,
	itemId: string,
	level: number?,
	options: AddOptions?
): (Types.EquipmentInstance?, string?)
	local profile = PlayerDataService.get(player)
	if not profile then
		return nil, "Not ready"
	end
	if not EquipmentConfig.Items[itemId] then
		return nil, "Unknown item"
	end
	local capacity = Modifiers.equipmentCapacity(PlayerDataService.mods(player))
	if not (options and options.IgnoreCapacity) and InventoryService.equipmentCount(profile) >= capacity then
		return nil, "Your equipment storage is full."
	end
	local item: Types.EquipmentInstance = {
		Id = PlayerDataService.nextId(profile, "e"),
		ItemId = itemId,
		Level = level or 0,
		EquippedTo = nil,
		Locked = false,
	}
	profile.Inventory.Equipment[item.Id] = item
	PlayerDataService.equipmentChanged(player, item.Id)
	PlayerDataService.changed(player, "Inventory")
	return item, nil
end

function InventoryService.removeEquipment(player: Player, equipId: string)
	local profile = PlayerDataService.get(player)
	if not profile or not profile.Inventory.Equipment[equipId] then
		return
	end
	profile.Inventory.Equipment[equipId] = nil
	PlayerDataService.equipmentChanged(player, equipId)
	PlayerDataService.changed(player, "Inventory")
end

function InventoryService.addConsumable(player: Player, consumableId: string, amount: number)
	local profile = PlayerDataService.get(player)
	if not profile or not CraftingConfig.Consumables[consumableId] or amount <= 0 then
		return
	end
	local c = profile.Inventory.Consumables
	c[consumableId] = math.min(1e6, (c[consumableId] or 0) + math.floor(amount))
	PlayerDataService.changed(player, "Inventory")
end

function InventoryService.takeConsumable(player: Player, consumableId: string, amount: number): boolean
	local profile = PlayerDataService.get(player)
	if not profile then
		return false
	end
	local c = profile.Inventory.Consumables
	local have = c[consumableId] or 0
	if have < amount or amount <= 0 then
		return false
	end
	if have - amount > 0 then
		c[consumableId] = have - amount
	else
		c[consumableId] = nil
	end
	PlayerDataService.changed(player, "Inventory")
	return true
end

function InventoryService.addChest(player: Player, chestId: string, amount: number)
	local profile = PlayerDataService.get(player)
	if not profile or not ChestConfig.Chests[chestId] or amount <= 0 then
		return
	end
	local c = profile.Inventory.Chests
	c[chestId] = math.min(1e6, (c[chestId] or 0) + math.floor(amount))
	PlayerDataService.changed(player, "Inventory")
end

function InventoryService.takeChest(player: Player, chestId: string, amount: number): boolean
	local profile = PlayerDataService.get(player)
	if not profile then
		return false
	end
	local c = profile.Inventory.Chests
	local have = c[chestId] or 0
	if have < amount or amount <= 0 then
		return false
	end
	if have - amount > 0 then
		c[chestId] = have - amount
	else
		c[chestId] = nil
	end
	PlayerDataService.changed(player, "Inventory")
	return true
end

-- Activates a boost potion: extends its timer up to the configured cap.
function InventoryService.useBoost(player: Player, consumableId: string): (boolean, string?)
	local profile = PlayerDataService.get(player)
	local def = CraftingConfig.Consumables[consumableId]
	if not profile or not def or def.Kind ~= "Boost" or not def.Boost then
		return false, "That item can't be used here."
	end
	local now = os.time()
	local current = math.max(now, profile.Boosts[consumableId] or 0)
	if current - now + def.Boost.DurationSeconds > def.Boost.MaxStackSeconds then
		return false, "That boost is already at its maximum duration."
	end
	if not InventoryService.takeConsumable(player, consumableId, 1) then
		return false, "You don't have that item."
	end
	profile.Boosts[consumableId] = current + def.Boost.DurationSeconds
	PlayerDataService.changed(player, "Boosts")
	PlayerDataService.invalidateMods(player)
	return true, nil
end

-- Handlers ------------------------------------------------------------------------

local function ownedMonster(player: Player, raw: unknown): (Profile?, MonsterInstance?)
	local profile = PlayerDataService.get(player)
	local id = Guard.string(raw)
	if not profile or not id then
		return profile, nil
	end
	return profile, profile.Inventory.Monsters[id]
end

function InventoryService.init()
	NetServer.handle("ToggleLock", { Rate = 8, Burst = 16 }, function(player, rawId)
		local _, inst = ownedMonster(player, rawId)
		if not inst then
			return NetServer.invalid(player, "ToggleLock")
		end
		inst.Locked = not inst.Locked
		PlayerDataService.monsterChanged(player, inst.Id)
		return NetServer.ok({ Locked = inst.Locked })
	end)

	NetServer.handle("ToggleFavorite", { Rate = 8, Burst = 16 }, function(player, rawId)
		local _, inst = ownedMonster(player, rawId)
		if not inst then
			return NetServer.invalid(player, "ToggleFavorite")
		end
		inst.Favorite = not inst.Favorite
		PlayerDataService.monsterChanged(player, inst.Id)
		return NetServer.ok({ Favorite = inst.Favorite })
	end)

	NetServer.handle("MarkInspected", { Rate = 4, Burst = 8 }, function(player, rawId)
		local _, inst = ownedMonster(player, rawId)
		if not inst then
			return NetServer.invalid(player, "MarkInspected")
		end
		GameEvents.fire(player, "Inspect", { InstanceId = inst.Id })
		return NetServer.ok()
	end)

	-- SellMonsters(ids, confirmProtected): sells every listed monster or none.
	NetServer.handle("SellMonsters", { Rate = 3, Burst = 6 }, function(player, rawIds, rawConfirm)
		local profile = PlayerDataService.get(player)
		local ids = Guard.stringArray(rawIds, 200)
		if not profile or not ids or #ids == 0 then
			return NetServer.invalid(player, "SellMonsters")
		end
		local confirmProtected = Guard.boolean(rawConfirm) == true
		local mods = PlayerDataService.mods(player)
		local total = 0
		local toSell: { MonsterInstance } = {}
		for _, id in ids do
			local inst = profile.Inventory.Monsters[id]
			if not inst then
				return NetServer.invalid(player, "SellMonsters")
			end
			local ok, reason =
				InventoryService.canConsume(player, inst, { AllowProtected = confirmProtected })
			if not ok then
				local def = MonsterConfig.Monsters[inst.MonsterId]
				return NetServer.fail(
					(if def then def.DisplayName .. ": " else "") .. (reason or "Can't sell")
				)
			end
			total += StatMath.sellValue(inst, mods)
			table.insert(toSell, inst)
		end
		for _, inst in toSell do
			InventoryService.removeMonster(player, inst.Id)
		end
		EconomyService.grant(player, "Coins", total, "Sell")
		profile.Statistics.MonstersSold += #toSell
		PlayerDataService.changed(player, "Statistics")
		GameEvents.fire(player, "SellMonster", { Count = #toSell, Value = total })
		return NetServer.ok({ Sold = #toSell, Coins = total })
	end)

	NetServer.handle("UseConsumable", { Rate = 3, Burst = 5 }, function(player, rawId)
		local id = Guard.string(rawId)
		if not id or not CraftingConfig.Consumables[id] then
			return NetServer.invalid(player, "UseConsumable")
		end
		local ok, err = InventoryService.useBoost(player, id)
		if not ok then
			return NetServer.fail(err or "Can't use that.")
		end
		return NetServer.ok()
	end)

	Players.PlayerRemoving:Connect(function(player)
		transientLocks[player] = nil
	end)
end

return InventoryService
