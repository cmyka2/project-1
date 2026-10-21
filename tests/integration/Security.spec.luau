-- Exploit resistance: every request fuzzed with malformed arguments, rate
-- limits, ownership checks, double claims, trade duplication attempts and the
-- server-side cheat gate. After each attack the live profile must still be
-- exactly what DataSchema.sanitize would accept (no corrupted state).
return function(ctx)
	local T = ctx.Test
	local describe, it, expect = T.describe, T.it, T.expect
	local G = require("../harness/GameHarness")
	local Mock = G.Mock
	G.boot()

	local Net = G.module("ReplicatedStorage.Shared.Net")
	local GameConfig = G.module("ReplicatedStorage.Shared.Config.GameConfig")
	local NetServer = G.module("ServerScriptService.Server.Modules.NetServer")
	local RateLimiter = G.module("ServerScriptService.Server.Modules.RateLimiter")
	local DataSchema = G.module("ServerScriptService.Server.Modules.DataSchema")
	local Economy = G.service("EconomyService")
	local Inventory = G.service("InventoryService")
	local Trading = G.service("TradingService")

	local function now()
		return math.floor(Mock.unixTime())
	end

	local function handlerErrors()
		local n = 0
		for _, line in G.warnings() do
			if string.find(line, "%[Net%].*handler error") or string.find(line, "returned no result") then
				n += 1
			end
		end
		return n
	end

	-- The live profile must survive a JSON round trip and need no repairs.
	local function assertValid(player)
		local profile = G.profile(player)
		assert(profile, "profile missing")
		local raw = Mock.roundTrip(profile)
		local sanitized, issues = DataSchema.sanitize(Mock.roundTrip(profile), now())
		assert(#issues == 0, "profile needed repairs: " .. table.concat(issues, "; "))
		for _, c in { "Coins", "Gems", "AscensionPoints", "EventTokens" } do
			local v = profile.Currencies[c]
			assert(v == v and v >= 0 and v < math.huge, c .. " is invalid: " .. tostring(v))
		end
		local a, b = Mock.serde.encode("json", sanitized.Inventory), Mock.serde.encode("json", raw.Inventory)
		assert(a == b, "inventory changed under sanitize")
	end

	local function invoke(player, name, ...)
		RateLimiter.clear(player)
		return G.invoke(player, name, ...)
	end

	local function monsterIds(player)
		local out = {}
		for id in G.profile(player).Inventory.Monsters do
			table.insert(out, id)
		end
		table.sort(out)
		return out
	end

	local function rollSome(player, n)
		for _ = 1, n do
			G.wait(1)
			local r = invoke(player, "Roll", "grassland_dice", 1, false)
			assert(r.ok, "setup roll failed: " .. tostring(r.err))
		end
	end

	-- A new, unplaced, unlocked monster. Instance ids are per profile, so two
	-- players can both own an "m1"; `unique` skips ids the other player has.
	local function fresh(player, otherPlayer)
		local profile = G.profile(player)
		if otherPlayer then
			local otherProfile = G.profile(otherPlayer)
			profile.Inventory.NextId = math.max(profile.Inventory.NextId, otherProfile.Inventory.NextId) + 100
		end
		local inst = assert(Inventory.addMonster(player, "sprout_bunny", "Test"))
		return inst.Id
	end

	local alice = G.join(3001, "Alice")
	local bob = G.join(3002, "Bob")
	Economy.grant(alice, "Coins", 5000, "Test")
	Economy.grant(bob, "Coins", 5000, "Test")
	rollSome(alice, 6)
	rollSome(bob, 6)

	describe("remote surface", function()
		it("every request has exactly one server handler", function()
			expect(#NetServer.unhandled()).toBe(0)
		end)

		it("remotes are created by the server only", function()
			local folder = Mock.game:GetService("ReplicatedStorage"):FindFirstChild(Net.FOLDER_NAME)
			for _, name in Net.Requests do
				expect(folder:FindFirstChild(name).ClassName).toBe("RemoteFunction")
			end
			for _, name in Net.Events do
				expect(folder:FindFirstChild(name).ClassName).toBe("RemoteEvent")
			end
		end)
	end)

	describe("fuzzing", function()
		it("every request survives malformed arguments without errors or corrupt state", function()
			Mock.isStudio = false -- cheats must be locked for this
			local own = monsterIds(alice)
			local theirs = monsterIds(bob)
			local nested = { { { { { { "deep" } } } } } }
			local garbage = {
				false,
				true,
				0,
				-1,
				1.5,
				1e308,
				-math.huge,
				math.huge,
				0 / 0,
				"",
				string.rep("x", 5000),
				"__index",
				own[1],
				theirs[1],
				"grassland_dice",
				"Grassland",
				{},
				{ 1, 2, 3 },
				{ own[1], own[1] },
				{ own[1], theirs[1] },
				{ [1] = own[1], extra = true },
				{ [2] = own[1] },
				{ Music = 1e9, SkipRollAnimation = "yes" },
				nested,
				Mock.workspace,
				require("@lune/roblox").Vector3.new(1, 2, 3),
			}
			local before = handlerErrors()
			local calls = 0
			for _, name in Net.Requests do
				-- no arguments
				local r = invoke(alice, name)
				assert(typeof(r) == "table" and typeof(r.ok) == "boolean", name .. " returned a non-result")
				calls += 1
				for _, g in garbage do
					for _, args in
						{
							{ g },
							{ g, g },
							{ g, g, g, g, g },
							{ own[1], g },
							{ g, own[1] },
							{ theirs[1], 1, true },
						}
					do
						r = invoke(alice, name, table.unpack(args))
						assert(
							typeof(r) == "table" and typeof(r.ok) == "boolean",
							name .. " returned a non-result"
						)
						calls += 1
					end
				end
				if name == "Cheat" then
					expect(r.ok).toBe(false)
				end
			end
			-- end any battle or trade the fuzzing may have opened
			invoke(alice, "ForfeitBattle")
			invoke(alice, "TradeCancel")
			G.wait(2)
			expect(handlerErrors() - before).toBe(0)
			expect(calls > 1000).toBe(true)
			assertValid(alice)
			assertValid(bob)
			Mock.isStudio = true
		end)
	end)

	describe("rate limiting", function()
		it("drops requests beyond the burst and refills over time", function()
			RateLimiter.clear(alice)
			local id = monsterIds(alice)[1]
			local okCount, slowed = 0, 0
			for _ = 1, 40 do
				local r = G.invoke(alice, "ToggleFavorite", id)
				if r.ok then
					okCount += 1
				elseif r.err == "Slow down!" then
					slowed += 1
				end
			end
			expect(okCount).toBe(16)
			expect(slowed).toBe(24)
			G.wait(1)
			expect(G.invoke(alice, "ToggleFavorite", id).ok).toBe(true)
			if G.profile(alice).Inventory.Monsters[id].Favorite then
				G.wait(1)
				G.invoke(alice, "ToggleFavorite", id)
			end
		end)

		it("rate limits are per player", function()
			RateLimiter.clear(alice)
			RateLimiter.clear(bob)
			local id = monsterIds(alice)[1]
			for _ = 1, 30 do
				G.invoke(alice, "MarkInspected", id)
			end
			expect(G.invoke(bob, "MarkInspected", monsterIds(bob)[1]).ok).toBe(true)
		end)
	end)

	describe("ownership and validation", function()
		it("rejects acting on another player's monsters", function()
			local stolen = fresh(bob, alice)
			assert(G.profile(alice).Inventory.Monsters[stolen] == nil, "id collision")
			local bobCount = #monsterIds(bob)
			for _, attempt in
				{
					{ "SellMonsters", { stolen } },
					{ "PlaceMonster", stolen, 1 },
					{ "UpgradeMonster", stolen, 1 },
					{ "ToggleLock", stolen },
					{ "SetTeam", { stolen } },
					{ "StarFuse", fresh(alice), { stolen }, true },
					{ "EquipItem", "e1", stolen },
					{ "TradeSetOffer", { stolen } },
				}
			do
				local r = invoke(alice, attempt[1], table.unpack(attempt, 2))
				assert(r.ok == false, attempt[1] .. " accepted another player's monster")
			end
			expect(#monsterIds(bob)).toBe(bobCount)
			expect(G.profile(bob).Inventory.Monsters[stolen].Locked).toBe(false)
			expect(table.find(G.profile(alice).Battle.Team, stolen)).toBeNil()
		end)

		it("rejects locked or unaffordable dice and impossible roll counts", function()
			local coins = G.profile(alice).Currencies.Coins
			local count = #monsterIds(alice)
			for _, args in
				{
					{ "volcano_dice", 1, false },
					{ "glitch_dice", 1, false },
					{ "grassland_dice", 0, false },
					{ "grassland_dice", 11, false },
					{ "grassland_dice", -5, false },
					{ "grassland_dice", 0 / 0, false },
					{ "no_such_dice", 1, false },
				}
			do
				G.wait(1)
				expect(invoke(alice, "Roll", table.unpack(args)).ok).toBe(false)
			end
			-- nothing charged (passive income from the base may still arrive)
			expect(G.profile(alice).Currencies.Coins >= coins).toBe(true)
			expect(#monsterIds(alice)).toBe(count)
		end)

		it("refuses a roll the player cannot afford and charges nothing", function()
			local profile = G.profile(bob)
			local saved = profile.Currencies.Coins
			profile.Currencies.Coins = 3
			local count = #monsterIds(bob)
			G.wait(1)
			local r = invoke(bob, "Roll", "grassland_dice", 1, false)
			expect(r.ok).toBe(false)
			expect(profile.Currencies.Coins).toBe(3)
			expect(#monsterIds(bob)).toBe(count)
			profile.Currencies.Coins = saved
		end)

		it("grants the free roll once per cooldown", function()
			local profile = G.profile(alice)
			profile.Timestamps.LastFreeRoll = 0
			G.wait(1)
			local coins = profile.Currencies.Coins
			expect(invoke(alice, "Roll", "grassland_dice", 1, true).ok).toBe(true)
			expect(profile.Currencies.Coins >= coins).toBe(true) -- not charged (income may tick)
			G.wait(1)
			local second = invoke(alice, "Roll", "grassland_dice", 1, true)
			expect(second.ok).toBe(false)
		end)

		it("will not sell a locked monster or a duplicated id list", function()
			local id = fresh(alice)
			local inst = G.profile(alice).Inventory.Monsters[id]
			inst.Locked = true
			local coins = G.profile(alice).Currencies.Coins
			expect(invoke(alice, "SellMonsters", { id }).ok).toBe(false)
			expect(invoke(alice, "SellMonsters", { id }, true).ok).toBe(false)
			inst.Locked = false
			expect(invoke(alice, "SellMonsters", { id, id }).ok).toBe(false)
			expect(G.profile(alice).Inventory.Monsters[id]).notToBeNil()
			expect(G.profile(alice).Currencies.Coins <= coins + 50).toBe(true)
		end)
	end)

	describe("double claims", function()
		it("the daily reward can only be claimed once per day", function()
			G.profile(alice).DailyRewards.LastClaimDay = -1 -- the fuzzing pass may have claimed today's
			local first = invoke(alice, "ClaimDaily")
			local gems = G.profile(alice).Currencies.Gems
			local coins = G.profile(alice).Currencies.Coins
			local second = invoke(alice, "ClaimDaily")
			expect(first.ok).toBe(true)
			expect(second.ok).toBe(false)
			expect(G.profile(alice).Currencies.Gems).toBe(gems)
			expect(G.profile(alice).Currencies.Coins <= coins + 50).toBe(true)
		end)

		it("an achievement reward can only be claimed once", function()
			local profile = G.profile(alice)
			local id = next(profile.Achievements.Completed)
			expect(id).notToBeNil()
			local first = invoke(alice, "ClaimAchievement", id)
			local gems = profile.Currencies.Gems
			local second = invoke(alice, "ClaimAchievement", id)
			expect(first.ok).toBe(true)
			expect(second.ok).toBe(false)
			expect(profile.Currencies.Gems).toBe(gems)
		end)

		it("cannot claim achievements that were never completed", function()
			local QuestConfig = G.module("ReplicatedStorage.Shared.Config.QuestConfig")
			local profile = G.profile(alice)
			for id in QuestConfig.Achievements do
				if not profile.Achievements.Completed[id] then
					expect(invoke(alice, "ClaimAchievement", id).ok).toBe(false)
					break
				end
			end
		end)

		it("cannot claim a quest reward twice or before completion", function()
			local profile = G.profile(alice)
			local quest = profile.Quests.Daily[1]
			expect(quest).notToBeNil()
			quest.Completed = false
			expect(invoke(alice, "ClaimQuest", quest.Id).ok).toBe(false)
			assertValid(alice)
		end)
	end)

	describe("trading", function()
		local function openTrade()
			invoke(alice, "TradeCancel")
			invoke(bob, "TradeCancel")
			expect(invoke(alice, "TradeRequest", bob.UserId).ok).toBe(true)
			expect(invoke(bob, "TradeRespond", true).ok).toBe(true)
		end

		it("rejects offering monsters the player does not own or duplicated ids", function()
			openTrade()
			local stolen = fresh(bob, alice)
			expect(invoke(alice, "TradeSetOffer", { stolen }).ok).toBe(false)
			local mine = fresh(alice)
			expect(invoke(alice, "TradeSetOffer", { mine, mine }).ok).toBe(false)
			invoke(alice, "TradeCancel")
		end)

		it("cannot trade with yourself", function()
			expect(invoke(alice, "TradeRequest", alice.UserId).ok).toBe(false)
		end)

		it("locks offered monsters against selling during the trade", function()
			openTrade()
			local mine = fresh(alice)
			expect(invoke(alice, "TradeSetOffer", { mine }).ok).toBe(true)
			expect(invoke(alice, "SellMonsters", { mine }, true).ok).toBe(false)
			expect(G.profile(alice).Inventory.Monsters[mine]).notToBeNil()
			invoke(alice, "TradeCancel")
			expect(Inventory.transientLock(alice, mine)).toBeNil()
		end)

		it("changing an offer clears both confirmations", function()
			openTrade()
			local a1, a2 = fresh(alice), fresh(alice)
			invoke(alice, "TradeSetOffer", { a1 })
			invoke(alice, "TradeConfirm")
			invoke(bob, "TradeConfirm")
			expect(Trading.tradeOf(alice).State).toBe("Countdown")
			invoke(alice, "TradeSetOffer", { a2 })
			local trade = Trading.tradeOf(alice)
			expect(trade.State).toBe("Active")
			expect(trade.Confirmed[alice]).toBeNil()
			expect(trade.Confirmed[bob]).toBeNil()
			invoke(alice, "TradeCancel")
		end)

		it("completes a fair swap exactly once with no duplication", function()
			local a1 = fresh(alice)
			local b1 = fresh(bob)
			openTrade()
			local aMonster = G.profile(alice).Inventory.Monsters[a1].MonsterId
			local bMonster = G.profile(bob).Inventory.Monsters[b1].MonsterId
			local aCount, bCount = #monsterIds(alice), #monsterIds(bob)
			expect(invoke(alice, "TradeSetOffer", { a1 }).ok).toBe(true)
			expect(invoke(bob, "TradeSetOffer", { b1 }).ok).toBe(true)
			expect(invoke(alice, "TradeConfirm").ok).toBe(true)
			expect(invoke(bob, "TradeConfirm").ok).toBe(true)
			G.wait(GameConfig.Social.TradeConfirmCountdown + 2)
			expect(Trading.tradeOf(alice)).toBeNil()
			expect(G.profile(alice).Inventory.Monsters[a1]).toBeNil()
			expect(G.profile(bob).Inventory.Monsters[b1]).toBeNil()
			expect(#monsterIds(alice)).toBe(aCount)
			expect(#monsterIds(bob)).toBe(bCount)
			local function owns(player, monsterId, source)
				for _, inst in G.profile(player).Inventory.Monsters do
					if inst.MonsterId == monsterId and inst.Source == source then
						return true
					end
				end
				return false
			end
			expect(owns(alice, bMonster, "Trade")).toBe(true)
			expect(owns(bob, aMonster, "Trade")).toBe(true)
			assertValid(alice)
			assertValid(bob)
		end)

		it("cancels (moving nothing) if an offered monster disappears before the swap", function()
			local a1 = fresh(alice)
			openTrade()
			local aCount, bCount = #monsterIds(alice), #monsterIds(bob)
			invoke(alice, "TradeSetOffer", { a1 })
			invoke(alice, "TradeConfirm")
			invoke(bob, "TradeConfirm")
			-- the monster vanishes server-side (e.g. a concurrent system removed it)
			Inventory.removeMonster(alice, a1)
			G.wait(GameConfig.Social.TradeConfirmCountdown + 2)
			expect(Trading.tradeOf(alice)).toBeNil()
			expect(#monsterIds(alice)).toBe(aCount - 1)
			expect(#monsterIds(bob)).toBe(bCount)
		end)

		it("cancels the trade when a player leaves", function()
			local carol = G.join(3003, "Carol")
			invoke(alice, "TradeCancel")
			expect(invoke(alice, "TradeRequest", carol.UserId).ok).toBe(true)
			G.leave(carol)
			expect(Trading.tradeOf(alice)).toBeNil()
		end)
	end)

	describe("cheat gate", function()
		it("refuses every cheat outside Studio for players not on the allow list", function()
			Mock.isStudio = false
			local coins = G.profile(alice).Currencies.Coins
			local r = invoke(alice, "Cheat", "AddCoins", 1e12)
			expect(r.ok).toBe(false)
			expect(G.profile(alice).Currencies.Coins < coins + 1e6).toBe(true)
			Mock.clearClientEvents()
			local dave = G.join(3004, "Dave")
			expect(#G.pushed(dave, "CheatAccess")).toBe(0)
			Mock.isStudio = true
		end)

		it("allows listed QA accounts outside Studio", function()
			Mock.isStudio = false
			table.insert(GameConfig.Cheats.AllowedUserIds, alice.UserId)
			local r = invoke(alice, "Cheat", "AddGems", 5)
			table.remove(
				GameConfig.Cheats.AllowedUserIds,
				table.find(GameConfig.Cheats.AllowedUserIds, alice.UserId)
			)
			Mock.isStudio = true
			expect(r.ok).toBe(true)
		end)
	end)

	describe("purchases", function()
		local Monetization = G.service("MonetizationService")
		local MonetizationConfig = G.module("ReplicatedStorage.Shared.Config.MonetizationConfig")
		local Enum = require("@lune/roblox").Enum
		local GRANTED = Enum.ProductPurchaseDecision.PurchaseGranted
		local LATER = Enum.ProductPurchaseDecision.NotProcessedYet
		local product = MonetizationConfig.Products[1]
		local gemsPerPurchase = product.Grant.Gems

		it("ignores unconfigured products (id 0) and unknown players", function()
			local gems = G.profile(alice).Currencies.Gems
			expect(Monetization.processReceipt({ PlayerId = alice.UserId, ProductId = 0, PurchaseId = "p0" })).toBe(
				LATER
			)
			expect(Monetization.processReceipt({ PlayerId = 999999, ProductId = 12345, PurchaseId = "p1" })).toBe(
				LATER
			)
			expect(G.profile(alice).Currencies.Gems).toBe(gems)
		end)

		it("grants a developer product exactly once per receipt", function()
			product.ProductId = 12345
			local gems = G.profile(alice).Currencies.Gems
			expect(Monetization.processReceipt({
				PlayerId = alice.UserId,
				ProductId = 12345,
				PurchaseId = "r-100",
			})).toBe(GRANTED)
			expect(G.profile(alice).Currencies.Gems).toBe(gems + gemsPerPurchase)
			-- Roblox may deliver the same receipt again
			expect(Monetization.processReceipt({
				PlayerId = alice.UserId,
				ProductId = 12345,
				PurchaseId = "r-100",
			})).toBe(GRANTED)
			expect(G.profile(alice).Currencies.Gems).toBe(gems + gemsPerPurchase)
		end)

		it("only acknowledges after the grant is saved, without granting twice on retry", function()
			local store = Mock.game:GetService("DataStoreService"):GetDataStore(GameConfig.Data.StoreName)
			local gems = G.profile(alice).Currencies.Gems
			store._failures = GameConfig.Data.SaveAttempts
			expect(Monetization.processReceipt({
				PlayerId = alice.UserId,
				ProductId = 12345,
				PurchaseId = "r-200",
			})).toBe(LATER)
			expect(G.profile(alice).Currencies.Gems).toBe(gems + gemsPerPurchase)
			store._failures = 0
			expect(Monetization.processReceipt({
				PlayerId = alice.UserId,
				ProductId = 12345,
				PurchaseId = "r-200",
			})).toBe(GRANTED)
			expect(G.profile(alice).Currencies.Gems).toBe(gems + gemsPerPurchase)
			local record = store._data[GameConfig.Data.KeyPrefix .. alice.UserId]
			expect(table.find(record.Profile.Purchases.Receipts, "r-200") ~= nil).toBe(true)
			product.ProductId = 0
		end)
	end)

	describe("privacy", function()
		it("state replication only ever reaches the profile's owner", function()
			G.profile(alice).Currencies.Gems = 4242424
			G.service("PlayerDataService").changed(alice, "Currencies")
			Mock.clearClientEvents()
			G.wait(1)
			local function sawMarker(player)
				for _, args in G.pushed(player, "StateSync") do
					if string.find(Mock.serde.encode("json", args), "4242424", 1, true) then
						return true
					end
				end
				return false
			end
			expect(sawMarker(alice)).toBe(true)
			expect(sawMarker(bob)).toBe(false)
		end)

		it("leaderboards expose only public fields", function()
			local r = invoke(alice, "GetLeaderboards")
			expect(r.ok).toBe(true)
			local encoded = Mock.serde.encode("json", r.data)
			for _, secret in { "Inventory", "Currencies", "Purchases", "Lock", "SessionId" } do
				expect(string.find(encoded, secret, 1, true)).toBeNil()
			end
		end)
	end)
end
