--!strict
-- Secure monster trading between two players in the same server.
--   request -> accept -> both edit offers -> both confirm -> countdown ->
--   full revalidation -> atomic in-memory swap -> immediate save of both.
-- Offered monsters are locked against selling, fusing, placing and battling.
-- Any change to either offer clears both confirmations. Disconnects, timeouts
-- and failed validation cancel the trade and release every lock.
-- Limitation (documented): the two profiles are separate DataStore keys, so
-- the final persistence is two writes; both are attempted immediately.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Util = Shared:WaitForChild("Util")
local GameConfig = require(Config:WaitForChild("GameConfig"))
local Modifiers = require(Util:WaitForChild("Modifiers"))
local Guard = require(Util:WaitForChild("Guard"))
local Types = require(Shared:WaitForChild("Types"))
local Modules = script.Parent.Parent:WaitForChild("Modules")
local NetServer = require(Modules:WaitForChild("NetServer"))
local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))
local InventoryService = require(script.Parent:WaitForChild("InventoryService"))
local MonsterService = require(script.Parent:WaitForChild("MonsterService"))
local CombatService = require(script.Parent:WaitForChild("CombatService"))

type Profile = Types.Profile

type Trade = {
	Id: number,
	A: Player,
	B: Player,
	State: "Pending" | "Active" | "Countdown" | "Done" | "Cancelled",
	Offers: { [Player]: { string } },
	Confirmed: { [Player]: boolean },
	CreatedAt: number,
	CountdownEnd: number,
	LastActivity: number,
}

local S = GameConfig.Social

local TradingService = {}

local trades: { [Player]: Trade } = {}
local counter = 0

local function other(trade: Trade, player: Player): Player
	return if trade.A == player then trade.B else trade.A
end

local function view(trade: Trade, forPlayer: Player): { [string]: any }
	local function offerView(p: Player): { { [string]: any } }
		local profile = PlayerDataService.get(p)
		local out = {}
		local offer: { string } = trade.Offers[p] or {}
		for _, id in offer do
			local inst = profile and profile.Inventory.Monsters[id]
			if inst then
				table.insert(out, {
					Id = id,
					MonsterId = inst.MonsterId,
					Level = inst.Level,
					Stars = inst.Stars,
					Upgrade = inst.Upgrade,
				})
			end
		end
		return out
	end
	local partner = other(trade, forPlayer)
	return {
		Id = trade.Id,
		State = trade.State,
		Partner = partner.DisplayName,
		PartnerUserId = partner.UserId,
		IsRequester = trade.A == forPlayer,
		MyOffer = offerView(forPlayer),
		TheirOffer = offerView(partner),
		MyConfirmed = trade.Confirmed[forPlayer] == true,
		TheirConfirmed = trade.Confirmed[partner] == true,
		CountdownEnd = trade.CountdownEnd,
	}
end

local function broadcast(trade: Trade)
	NetServer.push(trade.A, "TradeUpdate", view(trade, trade.A))
	NetServer.push(trade.B, "TradeUpdate", view(trade, trade.B))
end

local function release(trade: Trade)
	for _, p in { trade.A, trade.B } do
		InventoryService.clearTransientLocks(p, "Trade")
		if trades[p] == trade then
			trades[p] = nil
		end
	end
end

function TradingService.cancel(trade: Trade, reason: string)
	if trade.State == "Done" or trade.State == "Cancelled" then
		return
	end
	trade.State = "Cancelled"
	release(trade)
	for _, p in { trade.A, trade.B } do
		if p.Parent then
			NetServer.push(p, "TradeUpdate", nil)
			NetServer.notify(p, "info", "Trade cancelled: " .. reason)
		end
	end
end

local function eligible(player: Player): (boolean, string?)
	if not PlayerDataService.isReady(player) then
		return false, "is still loading"
	end
	if trades[player] then
		return false, "is already trading"
	end
	local session = CombatService.session(player)
	if session and not session.Finished then
		return false, "is in a battle"
	end
	if player.AccountAge < S.TradeMinAccountAgeDays then
		return false, "account is too new to trade"
	end
	return true, nil
end

local function validOffer(player: Player, ids: { string }): (boolean, string?)
	local profile = PlayerDataService.get(player)
	if not profile then
		return false, "Not ready"
	end
	if #ids > S.TradeMaxMonsters then
		return false, "You can offer at most " .. S.TradeMaxMonsters .. " monsters."
	end
	for _, id in ids do
		local inst = profile.Inventory.Monsters[id]
		if not inst then
			return false, "invalid"
		end
		local lock = InventoryService.transientLock(player, id)
		if lock and lock ~= "Trade" then
			return false, "A monster is busy (" .. lock .. ")."
		end
		if InventoryService.slotOf(profile, id) then
			return false, "Remove monsters from your base before trading them."
		end
		if inst.Locked or inst.Favorite then
			return false, "Unlock / unfavorite monsters before trading them."
		end
		if table.find(profile.Battle.Team, id) then
			return false, "Remove monsters from your battle team before trading them."
		end
	end
	return true, nil
end

-- Final, atomic swap. Returns false (changing nothing) if anything is invalid.
local function execute(trade: Trade): (boolean, string?)
	local a, b = trade.A, trade.B
	local pa, pb = PlayerDataService.get(a), PlayerDataService.get(b)
	if not pa or not pb or not a.Parent or not b.Parent then
		return false, "a player left"
	end
	local offerA: { string } = trade.Offers[a] or {}
	local offerB: { string } = trade.Offers[b] or {}
	if #offerA == 0 and #offerB == 0 then
		return false, "both offers are empty"
	end
	-- temporarily drop our own trade locks so validation sees real state
	local okA, errA = validOffer(a, offerA)
	local okB, errB = validOffer(b, offerB)
	if not okA or not okB then
		return false, errA or errB
	end
	local capA = Modifiers.monsterCapacity(PlayerDataService.mods(a))
		- InventoryService.monsterCount(pa)
		+ #offerA
	local capB = Modifiers.monsterCapacity(PlayerDataService.mods(b))
		- InventoryService.monsterCount(pb)
		+ #offerB
	if capA < #offerB or capB < #offerA then
		return false, "not enough storage space"
	end
	-- snapshot, remove, then add (no yields in between: atomic within this server)
	local movingA: { Types.MonsterInstance } = {}
	for _, id in offerA do
		table.insert(movingA, table.clone(pa.Inventory.Monsters[id]))
	end
	local movingB: { Types.MonsterInstance } = {}
	for _, id in offerB do
		table.insert(movingB, table.clone(pb.Inventory.Monsters[id]))
	end
	InventoryService.clearTransientLocks(a, "Trade")
	InventoryService.clearTransientLocks(b, "Trade")
	for _, inst in movingA do
		InventoryService.removeMonster(a, inst.Id)
	end
	for _, inst in movingB do
		InventoryService.removeMonster(b, inst.Id)
	end
	local function give(to: Player, profile: Profile, list: { Types.MonsterInstance })
		for _, inst in list do
			local copy = table.clone(inst)
			copy.Id = PlayerDataService.nextId(profile, "m")
			copy.Source = "Trade"
			copy.Locked = false
			copy.Favorite = false
			profile.Inventory.Monsters[copy.Id] = copy
			MonsterService.discover(to, profile, copy.MonsterId, "Trade")
			PlayerDataService.monsterChanged(to, copy.Id)
		end
		PlayerDataService.changed(to, "Inventory")
	end
	give(b, pb, movingA)
	give(a, pa, movingB)
	return true, nil
end

local function finishTrade(trade: Trade)
	local ok, err = execute(trade)
	if not ok then
		TradingService.cancel(trade, err or "validation failed")
		return
	end
	trade.State = "Done"
	release(trade)
	for _, p in { trade.A, trade.B } do
		NetServer.push(p, "TradeUpdate", nil)
		NetServer.notify(p, "success", "Trade complete!")
		task.spawn(PlayerDataService.saveNow, p)
	end
end

function TradingService.tradeOf(player: Player): Trade?
	return trades[player]
end

function TradingService.init()
	NetServer.handle("TradeRequest", { Rate = 1, Burst = 3 }, function(player, rawUserId)
		if not S.TradingEnabled then
			return NetServer.fail("Trading is disabled.")
		end
		local userId = Guard.integer(rawUserId, 1, 2 ^ 53)
		local target = userId and Players:GetPlayerByUserId(userId)
		if not target or target == player then
			return NetServer.fail("That player isn't available.")
		end
		local ok, why = eligible(player)
		if not ok then
			return NetServer.fail("You " .. (why or "can't trade") .. ".")
		end
		local okT, whyT = eligible(target)
		if not okT then
			return NetServer.fail(target.DisplayName .. " " .. (whyT or "can't trade") .. ".")
		end
		counter += 1
		local now = os.clock()
		local trade: Trade = {
			Id = counter,
			A = player,
			B = target,
			State = "Pending",
			Offers = { [player] = {}, [target] = {} },
			Confirmed = {},
			CreatedAt = now,
			CountdownEnd = 0,
			LastActivity = now,
		}
		trades[player] = trade
		trades[target] = trade
		broadcast(trade)
		return NetServer.ok({ TradeId = trade.Id })
	end)

	NetServer.handle("TradeRespond", { Rate = 2, Burst = 4 }, function(player, rawAccept)
		local trade = trades[player]
		local accept = Guard.boolean(rawAccept)
		if not trade or accept == nil or trade.B ~= player or trade.State ~= "Pending" then
			return NetServer.fail("No trade request to answer.")
		end
		if not accept then
			TradingService.cancel(trade, player.DisplayName .. " declined")
			return NetServer.ok()
		end
		trade.State = "Active"
		trade.LastActivity = os.clock()
		broadcast(trade)
		return NetServer.ok()
	end)

	NetServer.handle("TradeSetOffer", { Rate = 4, Burst = 8 }, function(player, rawIds)
		local trade = trades[player]
		local ids = Guard.stringArray(rawIds, S.TradeMaxMonsters)
		if not trade or not ids then
			return NetServer.invalid(player, "TradeSetOffer")
		end
		if trade.State ~= "Active" and trade.State ~= "Countdown" then
			return NetServer.fail("The trade isn't open.")
		end
		local ok, err = validOffer(player, ids)
		if not ok then
			if err == "invalid" then
				return NetServer.invalid(player, "TradeSetOffer")
			end
			return NetServer.fail(err or "Invalid offer.")
		end
		InventoryService.clearTransientLocks(player, "Trade")
		for _, id in ids do
			InventoryService.setTransientLock(player, id, "Trade")
		end
		trade.Offers[player] = ids
		trade.Confirmed = {}
		trade.State = "Active"
		trade.LastActivity = os.clock()
		broadcast(trade)
		return NetServer.ok()
	end)

	NetServer.handle("TradeConfirm", { Rate = 2, Burst = 4 }, function(player)
		local trade = trades[player]
		if not trade or trade.State ~= "Active" then
			return NetServer.fail("Nothing to confirm.")
		end
		trade.Confirmed[player] = true
		trade.LastActivity = os.clock()
		if trade.Confirmed[trade.A] and trade.Confirmed[trade.B] then
			trade.State = "Countdown"
			trade.CountdownEnd = os.time() + S.TradeConfirmCountdown
		end
		broadcast(trade)
		return NetServer.ok()
	end)

	NetServer.handle("TradeCancel", { Rate = 2, Burst = 4 }, function(player)
		local trade = trades[player]
		if trade then
			TradingService.cancel(trade, player.DisplayName .. " cancelled")
		end
		return NetServer.ok()
	end)
end

function TradingService.start()
	Players.PlayerRemoving:Connect(function(player)
		local trade = trades[player]
		if trade then
			TradingService.cancel(trade, "a player left")
		end
	end)
	while true do
		task.wait(0.5)
		local now = os.clock()
		local seen: { [Trade]: boolean } = {}
		for _, trade in trades do
			if not seen[trade] then
				seen[trade] = true
				if trade.State == "Pending" and now - trade.CreatedAt > S.TradeRequestTimeout then
					TradingService.cancel(trade, "the request expired")
				elseif
					(trade.State == "Active" or trade.State == "Countdown")
					and now - trade.LastActivity > S.TradeSessionTimeout
				then
					TradingService.cancel(trade, "the trade timed out")
				elseif trade.State == "Countdown" and os.time() >= trade.CountdownEnd then
					finishTrade(trade)
				end
			end
		end
	end
end

function TradingService.onPlayerRemoving(player: Player, _profile: Profile)
	local trade = trades[player]
	if trade then
		TradingService.cancel(trade, "a player left")
	end
end

-- Exposed for tests.
TradingService._finish = finishTrade

return TradingService
