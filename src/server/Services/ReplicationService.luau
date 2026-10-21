--!strict
-- Replicates each player's own profile and server-derived values to that
-- player only. Changes are batched (at most ~10 pushes/sec per player) and
-- sent as deltas: top-level keys, or individual monster/equipment entries.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Util = Shared:WaitForChild("Util")
local Config = Shared:WaitForChild("Config")
local DiceConfig = require(Config:WaitForChild("DiceConfig"))
local RebirthConfig = require(Config:WaitForChild("RebirthConfig"))
local RegionConfig = require(Config:WaitForChild("RegionConfig"))
local Modifiers = require(Util:WaitForChild("Modifiers"))
local RollMath = require(Util:WaitForChild("RollMath"))
local BaseLayout = require(Util:WaitForChild("BaseLayout"))
local EventSchedule = require(Util:WaitForChild("EventSchedule"))
local Codex = require(Util:WaitForChild("Codex"))
local Types = require(Shared:WaitForChild("Types"))
local Modules = script.Parent.Parent:WaitForChild("Modules")
local NetServer = require(Modules:WaitForChild("NetServer"))
local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))

type Profile = Types.Profile
type Derived = Types.DerivedState

local ReplicationService = {}

local FLUSH_INTERVAL = 0.1
local DERIVED_REFRESH = 5

local providers: { (Player, Profile, Derived) -> ...any } = {}
local lastDerived: { [Player]: number } = {}
local ready: { [Player]: boolean } = {}

-- Other services add their own derived fields (income, plot index, auto-roll state...).
function ReplicationService.addProvider(provider: (Player, Profile, Derived) -> ...any)
	table.insert(providers, provider)
end

local function diceUnlocked(profile: Profile, dice: DiceConfig.DiceDef, now: number): boolean
	if not profile.Progression.UnlockedRegions[dice.RequiredRegion] then
		return false
	end
	if profile.Progression.RebirthCount < dice.RequiredRebirths then
		return false
	end
	if dice.EventId and not EventSchedule.isEventActive(dice.EventId, now) then
		return false
	end
	return true
end
ReplicationService.diceUnlocked = diceUnlocked

function ReplicationService.computeDerived(player: Player, profile: Profile): Derived
	local now = os.time()
	local mods = PlayerDataService.mods(player)
	local rebirths = profile.Progression.RebirthCount
	local luck: { [string]: number } = {}
	local odds: { [string]: { Types.DiceOdds } } = {}
	local costs: { [string]: number } = {}
	local unlocked: { [string]: boolean } = {}
	for _, diceId in DiceConfig.Order do
		local dice = DiceConfig.Dice[diceId]
		local _, effective = Modifiers.luckFor(dice, mods)
		luck[diceId] = effective
		costs[diceId] = Modifiers.rollCost(dice, mods)
		local isUnlocked = diceUnlocked(profile, dice, now)
		unlocked[diceId] = isUnlocked
		if isUnlocked or not dice.EventId then
			odds[diceId] = RollMath.rarityOdds(dice.RarityWeights, dice.Pool, effective)
		end
	end
	local multi: { number } = {}
	for _, option in DiceConfig.MultiRoll do
		if
			profile.Discovery.TotalRolls >= option.RequiredTotalRolls
			and rebirths >= option.RequiredRebirths
		then
			table.insert(multi, option.Count)
		end
	end
	local requiredRegion = RebirthConfig.requiredRegion(rebirths)
	local rebirthCost = RebirthConfig.cost(rebirths)
	local derived: Derived = {
		PlotIndex = nil,
		TotalIncome = 0,
		MonsterIncome = {},
		IncomeMultiplier = Modifiers.incomeMultiplier(mods, true),
		TotalSlots = BaseLayout.totalSlots(rebirths),
		Floors = BaseLayout.floorCount(rebirths),
		MonsterCapacity = Modifiers.monsterCapacity(mods),
		EquipmentCapacity = Modifiers.equipmentCapacity(mods),
		Luck = luck,
		Odds = odds,
		RollCosts = costs,
		UnlockedDice = unlocked,
		MultiRollOptions = multi,
		AutoRollUnlocked = profile.Discovery.TotalRolls >= DiceConfig.AutoRoll.RequiredTotalRolls
			or (mods.AutoRollUnlock or 0) >= 1,
		ActiveEvents = EventSchedule.activeIds(now),
		RebirthCost = rebirthCost,
		RebirthRegion = requiredRegion,
		CanRebirth = rebirths < RebirthConfig.MaxRebirths
			and profile.Currencies.Coins >= rebirthCost
			and profile.Progression.UnlockedRegions[requiredRegion] == true,
		Modifiers = mods,
		WalkSpeed = Modifiers.walkSpeed(mods),
		SprintSpeed = Modifiers.sprintSpeed(mods),
		JumpPower = Modifiers.jumpPower(mods),
		CraftQueueSize = Modifiers.craftQueueSize(mods),
		LoadoutSlots = Modifiers.loadoutSlots(mods),
		FreeRollReadyAt = profile.Timestamps.LastFreeRoll + DiceConfig.FreeRollCooldownSeconds,
		ServerTime = now,
		CodexPercent = Codex.percent(profile),
		AutoRolling = false,
		AutoRollDice = nil,
	}
	for _, provider in providers do
		local ok, err = pcall(provider, player, profile, derived)
		if not ok then
			warn("[Replication] derived provider error: " .. tostring(err))
		end
	end
	return derived
end

local function clientProfile(profile: Profile): { [string]: any }
	local copy = table.clone(profile) :: any
	copy.Purchases = { GamePasses = profile.Purchases.GamePasses }
	return copy
end

function ReplicationService.sendFull(player: Player)
	local profile = PlayerDataService.get(player)
	if not profile then
		return
	end
	PlayerDataService.takeDirty(player)
	NetServer.push(
		player,
		"StateSync",
		"Full",
		clientProfile(profile),
		ReplicationService.computeDerived(player, profile)
	)
	lastDerived[player] = os.clock()
	ready[player] = true
end

-- Forces a derived refresh in the next flush.
function ReplicationService.refreshDerived(player: Player)
	PlayerDataService.changed(player, "__Derived")
end

local function flush(player: Player, force: boolean)
	local profile = PlayerDataService.get(player)
	if not profile or not ready[player] then
		return
	end
	local keys, monsters, equipment = PlayerDataService.takeDirty(player)
	if keys and keys.__Full then
		ReplicationService.sendFull(player)
		return
	end
	if keys then
		for key in keys do
			if string.sub(key, 1, 2) ~= "__" then
				local value = (profile :: any)[key]
				if key == "Purchases" then
					value = { GamePasses = profile.Purchases.GamePasses }
				elseif key == "Inventory" then
					-- monsters/equipment replicate as per-entry deltas instead
					value = {
						Consumables = profile.Inventory.Consumables,
						Chests = profile.Inventory.Chests,
						NextId = profile.Inventory.NextId,
					}
				end
				NetServer.push(player, "StateSync", "Key", key, value)
			end
		end
	end
	if monsters then
		local delta: { [string]: any } = {}
		for id in monsters do
			delta[id] = profile.Inventory.Monsters[id] or false
		end
		NetServer.push(player, "StateSync", "Monsters", delta)
	end
	if equipment then
		local delta: { [string]: any } = {}
		for id in equipment do
			delta[id] = profile.Inventory.Equipment[id] or false
		end
		NetServer.push(player, "StateSync", "Equipment", delta)
	end
	if force or (keys and keys.__Derived) then
		NetServer.push(player, "StateSync", "Derived", ReplicationService.computeDerived(player, profile))
		lastDerived[player] = os.clock()
	end
end

function ReplicationService.flushNow(player: Player)
	flush(player, false)
end

function ReplicationService.init()
	-- Clients that connected after the initial snapshot ask for it explicitly.
	NetServer.handle("RequestState", { Rate = 0.5, Burst = 3 }, function(player)
		ReplicationService.sendFull(player)
		return NetServer.ok()
	end)
end

function ReplicationService.start()
	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt: number)
		accumulator += dt
		if accumulator < FLUSH_INTERVAL then
			return
		end
		accumulator = 0
		local clock = os.clock()
		for _, player in PlayerDataService.players() do
			local stale = clock - (lastDerived[player] or 0) >= DERIVED_REFRESH
			flush(player, stale)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastDerived[player] = nil
		ready[player] = nil
	end)
end

-- Bootstrap lifecycle: initial snapshot once every service has set up the player.
function ReplicationService.onPlayerReady(player: Player, _profile: Profile, info: any)
	ReplicationService.sendFull(player)
	local offline = info and info.Offline
	if offline and offline.Coins > 0 then
		NetServer.push(player, "Popup", "Offline", offline)
	end
end

function ReplicationService.onPlayerRemoving(player: Player, _profile: Profile)
	lastDerived[player] = nil
	ready[player] = nil
end

-- Exposed for tests and services that need the highest region's income scale.
function ReplicationService.highestRegionScale(profile: Profile): number
	local region = RegionConfig.Regions[profile.Progression.HighestRegion]
	return if region then region.IncomeScale else 1
end

return ReplicationService
