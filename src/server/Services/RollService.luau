--!strict
-- Dice rolling. The server validates the dice, unlocks, cost, cooldown and
-- storage, picks every result with server-side randomness BEFORE the client
-- animates anything, grants the monsters and returns the results.
-- Auto-roll runs on the server at a fixed pace and stops safely on failure.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Util = Shared:WaitForChild("Util")
local DiceConfig = require(Config:WaitForChild("DiceConfig"))
local MonsterConfig = require(Config:WaitForChild("MonsterConfig"))
local RarityConfig = require(Config:WaitForChild("RarityConfig"))
local GameConfig = require(Config:WaitForChild("GameConfig"))
local Modifiers = require(Util:WaitForChild("Modifiers"))
local RollMath = require(Util:WaitForChild("RollMath"))
local StatMath = require(Util:WaitForChild("StatMath"))
local EventSchedule = require(Util:WaitForChild("EventSchedule"))
local Guard = require(Util:WaitForChild("Guard"))
local Types = require(Shared:WaitForChild("Types"))
local Modules = script.Parent.Parent:WaitForChild("Modules")
local NetServer = require(Modules:WaitForChild("NetServer"))
local GameEvents = require(Modules:WaitForChild("GameEvents"))
local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))
local EconomyService = require(script.Parent:WaitForChild("EconomyService"))
local InventoryService = require(script.Parent:WaitForChild("InventoryService"))
local MonsterService = require(script.Parent:WaitForChild("MonsterService"))
local ReplicationService = require(script.Parent:WaitForChild("ReplicationService"))
local AnalyticsService = require(script.Parent:WaitForChild("AnalyticsService"))

type Profile = Types.Profile

export type RollResult = {
	MonsterId: string,
	Rarity: string,
	InstanceId: string?,
	AutoSold: boolean,
	SoldFor: number,
	New: boolean,
}

export type RollOutcome = {
	Results: { RollResult },
	Spent: number,
	Currency: string,
	Free: boolean,
	StoppedReason: string?,
	Luck: number,
}

local RollService = {}

local rng = Random.new()
local lastRoll: { [Player]: number } = {}
local autoRoll: { [Player]: { DiceId: string, Count: number, Token: number } } = {}
local autoToken = 0

function RollService.setRng(seeded: Random)
	rng = seeded
end

local function nextFloat(): number
	return rng:NextNumber()
end

-- Is this dice usable by the player right now? Returns (ok, reason).
function RollService.canUseDice(profile: Profile, dice: DiceConfig.DiceDef, now: number): (boolean, string?)
	if not profile.Progression.UnlockedRegions[dice.RequiredRegion] then
		return false, "Unlock " .. dice.RequiredRegion .. " to use " .. dice.DisplayName .. "."
	end
	if profile.Progression.RebirthCount < dice.RequiredRebirths then
		return false, dice.DisplayName .. " requires " .. dice.RequiredRebirths .. " rebirth(s)."
	end
	if dice.EventId and not EventSchedule.isEventActive(dice.EventId, now) then
		return false, dice.DisplayName .. " is only available during its event."
	end
	return true, nil
end

function RollService.multiRollAllowed(profile: Profile, count: number): boolean
	for _, option in DiceConfig.MultiRoll do
		if option.Count == count then
			return profile.Discovery.TotalRolls >= option.RequiredTotalRolls
				and profile.Progression.RebirthCount >= option.RequiredRebirths
		end
	end
	return false
end

function RollService.autoRollUnlocked(player: Player, profile: Profile): boolean
	local mods = PlayerDataService.mods(player)
	return profile.Discovery.TotalRolls >= DiceConfig.AutoRoll.RequiredTotalRolls
		or (mods.AutoRollUnlock or 0) >= 1
end

local function announce(player: Player, monsterId: string, rarity: RarityConfig.RarityDef)
	if not GameConfig.Social.AnnounceRareRolls or rarity.Announce == "None" then
		return
	end
	local def = MonsterConfig.Monsters[monsterId]
	local text = string.format(
		"%s rolled a %s %s!",
		player.DisplayName,
		rarity.DisplayName,
		if def then def.DisplayName else monsterId
	)
	NetServer.pushAll("Announce", text, rarity.Color, rarity.Announce == "ServerLoud")
end

-- Core roll used by manual rolls, auto-roll and QA. Charges per completed roll,
-- so a batch interrupted by full storage only pays for what it produced.
function RollService.performRoll(
	player: Player,
	diceId: string,
	count: number,
	useFree: boolean
): (RollOutcome?, string?)
	local profile = PlayerDataService.get(player)
	if not profile then
		return nil, "Not ready"
	end
	local dice = DiceConfig.Dice[diceId]
	if not dice then
		return nil, "Unknown dice"
	end
	local now = os.time()
	local ok, reason = RollService.canUseDice(profile, dice, now)
	if not ok then
		return nil, reason
	end
	if not RollService.multiRollAllowed(profile, count) then
		return nil, "That multi-roll isn't unlocked yet."
	end
	local mods = PlayerDataService.mods(player)
	local costEach = Modifiers.rollCost(dice, mods)
	local free = false
	if useFree then
		if count ~= 1 then
			return nil, "The free roll is a single roll."
		end
		if now < profile.Timestamps.LastFreeRoll + DiceConfig.FreeRollCooldownSeconds then
			return nil, "Your free roll isn't ready yet."
		end
		free = true
	end
	if not free and not EconomyService.canAfford(profile, dice.CostCurrency, costEach) then
		return nil, "Not enough " .. dice.CostCurrency .. "."
	end
	if InventoryService.freeMonsterSlots(player) <= 0 then
		local anyAutoSell = next(profile.Settings.AutoSell) ~= nil
		if not anyAutoSell then
			return nil, "Your monster storage is full. Sell or fuse some monsters first."
		end
	end

	local _, luck = Modifiers.luckFor(dice, mods)
	local outcome: RollOutcome = {
		Results = {},
		Spent = 0,
		Currency = dice.CostCurrency,
		Free = free,
		StoppedReason = nil,
		Luck = luck,
	}
	for _ = 1, count do
		if not free and not EconomyService.canAfford(profile, dice.CostCurrency, costEach) then
			outcome.StoppedReason = "Ran out of " .. dice.CostCurrency .. "."
			break
		end
		local monsterId, rarityId = RollMath.roll(dice.RarityWeights, dice.Pool, luck, nextFloat)
		if not monsterId or not rarityId then
			warn("[Roll] empty pool for dice " .. diceId)
			outcome.StoppedReason = "This dice has nothing to roll."
			break
		end
		local rarity = RarityConfig.Rarities[rarityId]
		local alreadyDiscovered = profile.Discovery.DiscoveredMonsters[monsterId] ~= nil
		local autoSell = alreadyDiscovered and profile.Settings.AutoSell[rarityId] == true
		if not autoSell and InventoryService.freeMonsterSlots(player) <= 0 then
			outcome.StoppedReason = "Monster storage is full."
			break
		end
		-- charge for this roll
		if free then
			profile.Timestamps.LastFreeRoll = now
			PlayerDataService.changed(player, "Timestamps")
		else
			EconomyService.spend(player, dice.CostCurrency, costEach, "Roll:" .. diceId)
			outcome.Spent += costEach
		end
		local result: RollResult = {
			MonsterId = monsterId,
			Rarity = rarityId,
			InstanceId = nil,
			AutoSold = false,
			SoldFor = 0,
			New = not alreadyDiscovered,
		}
		if autoSell then
			MonsterService.discover(player, profile, monsterId, "Roll")
			local temp: Types.MonsterInstance = {
				Id = "",
				MonsterId = monsterId,
				Level = 1,
				Xp = 0,
				Upgrade = 0,
				Stars = 0,
				Locked = false,
				Favorite = false,
				Source = "Roll",
				Acquired = now,
			}
			local value = StatMath.sellValue(temp, mods)
			EconomyService.grant(player, "Coins", value, "AutoSell")
			result.AutoSold = true
			result.SoldFor = value
			profile.Statistics.MonstersSold += 1
		else
			local inst, err = InventoryService.addMonster(player, monsterId, "Roll:" .. diceId)
			if not inst then
				-- should not happen (capacity checked above); refund this roll
				if not free then
					EconomyService.grant(player, dice.CostCurrency, costEach, "RollRefund")
					outcome.Spent -= costEach
				end
				outcome.StoppedReason = err
				break
			end
			result.InstanceId = inst.Id
		end
		table.insert(outcome.Results, result)
		profile.Discovery.TotalRolls += 1
		profile.Discovery.RollCounts[diceId] = (profile.Discovery.RollCounts[diceId] or 0) + 1
		announce(player, monsterId, rarity)
		if free then
			break
		end
	end
	if #outcome.Results == 0 then
		return nil, outcome.StoppedReason or "Roll failed."
	end
	PlayerDataService.changed(player, "Discovery")
	PlayerDataService.changed(player, "Statistics")
	local tiers = {}
	for _, r in outcome.Results do
		table.insert(tiers, RarityConfig.tierOf(r.Rarity))
	end
	GameEvents.fire(player, "Roll", { Count = #outcome.Results, Dice = diceId, Tiers = tiers })
	AnalyticsService.count("Rolls", #outcome.Results)
	return outcome, nil
end

local function stopAuto(player: Player, reason: string?)
	if autoRoll[player] then
		autoRoll[player] = nil
		if reason and player.Parent then
			NetServer.notify(player, "info", "Auto-roll stopped: " .. reason)
		end
		ReplicationService.refreshDerived(player)
	end
end
RollService.stopAutoRoll = stopAuto

function RollService.isAutoRolling(player: Player): boolean
	return autoRoll[player] ~= nil
end

local function runAuto(player: Player, token: number)
	while true do
		task.wait(DiceConfig.AutoRoll.IntervalSeconds)
		local state = autoRoll[player]
		if not state or state.Token ~= token or not player.Parent then
			return
		end
		local outcome, err = RollService.performRoll(player, state.DiceId, state.Count, false)
		if not outcome then
			stopAuto(player, err)
			return
		end
		NetServer.push(player, "AutoRollResult", outcome)
		if outcome.StoppedReason then
			stopAuto(player, outcome.StoppedReason)
			return
		end
	end
end

function RollService.init()
	NetServer.handle("Roll", { Rate = 4, Burst = 6 }, function(player, rawDice, rawCount, rawFree)
		local diceId = Guard.string(rawDice)
		local count = Guard.integer(rawCount, 1, 10)
		local useFree = Guard.boolean(rawFree) == true
		if not diceId or not count or not DiceConfig.Dice[diceId] then
			return NetServer.invalid(player, "Roll")
		end
		local nowClock = os.clock()
		if nowClock - (lastRoll[player] or 0) < DiceConfig.RollCooldownSeconds then
			return NetServer.fail("Rolling too fast!")
		end
		if autoRoll[player] then
			return NetServer.fail("Stop auto-roll first.")
		end
		lastRoll[player] = nowClock
		local outcome, err = RollService.performRoll(player, diceId, count, useFree)
		if not outcome then
			return NetServer.fail(err or "Roll failed.")
		end
		return NetServer.ok(outcome)
	end)

	NetServer.handle("SetAutoRoll", { Rate = 2, Burst = 4 }, function(player, rawEnabled, rawDice, rawCount)
		local enabled = Guard.boolean(rawEnabled)
		if enabled == nil then
			return NetServer.invalid(player, "SetAutoRoll")
		end
		if not enabled then
			stopAuto(player, nil)
			return NetServer.ok({ Enabled = false })
		end
		local profile = PlayerDataService.get(player)
		local diceId = Guard.string(rawDice)
		local count = Guard.integer(rawCount, 1, DiceConfig.AutoRoll.MaxBatch)
		local dice = diceId and DiceConfig.Dice[diceId]
		if not profile or not diceId or not dice or not count then
			return NetServer.invalid(player, "SetAutoRoll")
		end
		if not RollService.autoRollUnlocked(player, profile) then
			return NetServer.fail(
				"Auto-roll unlocks after " .. DiceConfig.AutoRoll.RequiredTotalRolls .. " rolls."
			)
		end
		if not dice.AutoRollEligible then
			return NetServer.fail("This dice can't be auto-rolled.")
		end
		local ok, reason = RollService.canUseDice(profile, dice, os.time())
		if not ok then
			return NetServer.fail(reason or "Dice locked.")
		end
		if not RollService.multiRollAllowed(profile, count) then
			return NetServer.fail("That multi-roll isn't unlocked yet.")
		end
		autoToken += 1
		autoRoll[player] = { DiceId = diceId, Count = count, Token = autoToken }
		task.spawn(runAuto, player, autoToken)
		ReplicationService.refreshDerived(player)
		return NetServer.ok({ Enabled = true })
	end)

	ReplicationService.addProvider(function(player, _profile, derived)
		local state = autoRoll[player]
		derived.AutoRolling = state ~= nil
		derived.AutoRollDice = if state then state.DiceId else nil
	end)
end

function RollService.onPlayerRemoving(player: Player, _profile: Profile)
	autoRoll[player] = nil
	lastRoll[player] = nil
end

function RollService.start()
	Players.PlayerRemoving:Connect(function(player)
		autoRoll[player] = nil
		lastRoll[player] = nil
	end)
end

return RollService
