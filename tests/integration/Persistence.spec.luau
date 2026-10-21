-- DataStore safety: retries, failed loads, session locks, stale-lock takeover,
-- offline income paid exactly once, migrations from stored v1 data, and the
-- BindToClose shutdown flush. Runs the real PlayerDataService in the mock engine.
return function(ctx)
	local T = ctx.Test
	local describe, it, expect = T.describe, T.it, T.expect
	local G = require("../harness/GameHarness")
	local Mock = G.Mock
	G.boot()

	local GameConfig = G.module("ReplicatedStorage.Shared.Config.GameConfig")
	local DataSchema = G.module("ServerScriptService.Server.Modules.DataSchema")
	local OfflineIncome = G.module("ServerScriptService.Server.Modules.OfflineIncome")
	local Data = G.service("PlayerDataService")
	local DATA = GameConfig.Data

	local store = Mock.game:GetService("DataStoreService"):GetDataStore(DATA.StoreName)
	local function key(userId)
		return DATA.KeyPrefix .. tostring(userId)
	end
	local function stored(userId)
		return store._data[key(userId)]
	end
	local function now()
		return math.floor(Mock.unixTime())
	end
	local function seed(userId, profile, lock)
		store._data[key(userId)] = Mock.roundTrip({ Profile = profile, Lock = lock })
	end
	local function kicked(player)
		return rawget(player, "_kicked")
	end
	local function warnedWith(pattern)
		for _, line in G.warnings() do
			if string.find(line, pattern) then
				return true
			end
		end
		return false
	end

	describe("saving", function()
		it("writes the profile and releases the lock when a player leaves", function()
			local player = G.join(2001, "Saver")
			local profile = G.profile(player)
			expect(stored(2001).Lock.SessionId).toBe(Data.SessionId)
			profile.Currencies.Coins = 4321
			G.leave(player)
			local record = stored(2001)
			expect(record.Profile.Currencies.Coins).toBe(4321)
			expect(record.Lock).toBeNil()
			expect(Data.get(player)).toBeNil()
		end)

		it("retries transient save failures with backoff and succeeds", function()
			local player = G.join(2002, "Retry")
			G.profile(player).Currencies.Coins = 999
			store._failures = 2
			local ok = Data.saveNow(player)
			expect(ok).toBe(true)
			expect(store._failures).toBe(0)
			expect(stored(2002).Profile.Currencies.Coins).toBe(999)
			expect(warnedWith("save attempt 1/%d+ failed for 2002")).toBe(true)
			expect(Data.saveStatus(player).LastSaveOk).toBe(true)
			G.leave(player)
		end)

		it("reports failure (and keeps the session) when every save attempt fails", function()
			local player = G.join(2003, "Outage")
			local before = stored(2003).Profile.Currencies.Coins
			G.profile(player).Currencies.Coins = before + 50
			store._failures = DATA.SaveAttempts
			expect(Data.saveNow(player)).toBe(false)
			expect(Data.saveStatus(player).FailedSaves).toBe(1)
			expect(stored(2003).Profile.Currencies.Coins).toBe(before)
			expect(#G.pushed(player, "Notify") > 0).toBe(true)
			-- the next save (leave) still lands
			G.leave(player)
			expect(stored(2003).Profile.Currencies.Coins).toBe(before + 50)
		end)
	end)

	describe("loading", function()
		it("kicks the player and never overwrites saved data when loading keeps failing", function()
			local saved = DataSchema.default(now())
			saved.Currencies.Coins = 777
			seed(2010, saved, nil)
			local before = Mock.roundTrip(stored(2010))
			store._failures = 1000
			local player = G.join(2010, "Unlucky")
			G.wait(80)
			store._failures = 0
			expect(kicked(player) ~= nil).toBe(true)
			expect(string.find(kicked(player), "Nothing was lost") ~= nil).toBe(true)
			expect(Data.get(player)).toBeNil()
			expect(Mock.serde.encode("json", stored(2010))).toBe(Mock.serde.encode("json", before))
		end)

		it("recovers from a transient load failure without kicking", function()
			local saved = DataSchema.default(now())
			saved.Currencies.Coins = 1234
			seed(2011, saved, nil)
			store._failures = 2
			local player = G.join(2011, "Patient")
			G.wait(10)
			expect(kicked(player)).toBeNil()
			expect(G.profile(player).Currencies.Coins).toBe(1234)
			G.leave(player)
		end)

		it("waits while another server holds a fresh lock and refuses to load it", function()
			local saved = DataSchema.default(now())
			saved.Currencies.Coins = 55
			seed(2012, saved, { SessionId = "other-server", Time = now(), PlaceId = 1 })
			local player = G.join(2012, "Hopper")
			G.wait(DATA.LockWaitSeconds * DATA.LoadAttempts + 5)
			expect(kicked(player) ~= nil).toBe(true)
			expect(string.find(kicked(player), "another server") ~= nil).toBe(true)
			local record = stored(2012)
			expect(record.Lock.SessionId).toBe("other-server")
			expect(record.Profile.Currencies.Coins).toBe(55)
		end)

		it("loads as soon as the other server releases its lock", function()
			local saved = DataSchema.default(now())
			saved.Currencies.Coins = 66
			seed(2013, saved, { SessionId = "other-server", Time = now(), PlaceId = 1 })
			local player = G.join(2013, "Teleporter")
			G.wait(DATA.LockWaitSeconds + 1)
			expect(Data.get(player)).toBeNil()
			-- the other server finishes its final save and releases the lock
			saved.Currencies.Coins = 67
			seed(2013, saved, nil)
			G.wait(DATA.LockWaitSeconds + 1)
			expect(kicked(player)).toBeNil()
			expect(G.profile(player).Currencies.Coins).toBe(67)
			expect(stored(2013).Lock.SessionId).toBe(Data.SessionId)
			G.leave(player)
		end)

		it("takes over a stale lock left by a crashed server", function()
			local saved = DataSchema.default(now())
			saved.Currencies.Coins = 88
			seed(
				2014,
				saved,
				{ SessionId = "crashed-server", Time = now() - DATA.LockStaleSeconds - 1, PlaceId = 1 }
			)
			local player = G.join(2014, "Survivor")
			expect(kicked(player)).toBeNil()
			expect(G.profile(player).Currencies.Coins).toBe(88)
			expect(stored(2014).Lock.SessionId).toBe(Data.SessionId)
			G.leave(player)
		end)

		it("refuses data written by a newer game version without touching it", function()
			local future = DataSchema.default(now())
			future.SchemaVersion = DataSchema.CURRENT_VERSION + 1
			future.Currencies.Coins = 31337
			seed(2015, future, nil)
			local player = G.join(2015, "TimeTraveller")
			G.wait(5)
			expect(kicked(player) ~= nil).toBe(true)
			expect(string.find(kicked(player), "newer version") ~= nil).toBe(true)
			expect(stored(2015).Profile.SchemaVersion).toBe(DataSchema.CURRENT_VERSION + 1)
			expect(stored(2015).Profile.Currencies.Coins).toBe(31337)
		end)

		it("migrates a stored v1 profile and writes it back at the current version", function()
			local t = now()
			local v1 = {
				SchemaVersion = 1,
				Currencies = { Coins = 5000, Gems = 40, Materials = {} },
				Progression = { RebirthCount = 1, UnlockedRegions = { Grassland = true, Forest = true } },
				Inventory = {
					Monsters = {
						m1 = {
							Id = "m1",
							MonsterId = "moss_golem",
							Level = 7,
							Xp = 0,
							Upgrade = 2,
							Stars = 0,
						},
					},
				},
				Base = { PlacedMonsters = {} },
				Achievements = { first_roll = t - 500 },
				DailyRewards = { LastClaimTimestamp = t - 86400, CurrentStreak = 3 },
				Quests = { Completed = { "main_first_roll" } },
				Timestamps = { LastSeen = t, LastSaved = t },
			}
			seed(2016, v1, nil)
			local player = G.join(2016, "Veteran")
			local profile = G.profile(player)
			expect(profile.SchemaVersion).toBe(DataSchema.CURRENT_VERSION)
			expect(profile.Currencies.Coins).toBe(5000)
			expect(profile.Inventory.Monsters.m1.Upgrade).toBe(2)
			expect(profile.DailyRewards.CurrentStreak).toBe(3)
			expect(profile.Achievements.Claimed.first_roll).toBe(true)
			expect(stored(2016).Profile.SchemaVersion).toBe(DataSchema.CURRENT_VERSION)
			G.leave(player)
		end)

		it("repairs a tampered stored profile on load", function()
			local bad = Mock.roundTrip(DataSchema.default(now()))
			bad.Currencies = "lots"
			bad.Inventory.Monsters.m1 = { Id = "m1", MonsterId = "not_real", Level = 1 }
			bad.Base.PlacedMonsters["1"] = "m1"
			bad.Injected = { evil = true }
			seed(2017, bad, nil)
			local player = G.join(2017, "Tamperer")
			local profile = G.profile(player)
			expect(profile.Currencies.Coins >= 0).toBe(true)
			expect(profile.Inventory.Monsters.m1).toBeNil()
			expect(profile.Base.PlacedMonsters["1"]).toBeNil()
			expect((profile :: any).Injected).toBeNil()
			expect(warnedWith("repaired %d+ issue")).toBe(true)
			G.leave(player)
		end)
	end)

	describe("offline income", function()
		local function idleProfile(lastSeen)
			local p = DataSchema.default(lastSeen)
			p.Inventory.Monsters.m1 = {
				Id = "m1",
				MonsterId = "moss_golem",
				Level = 10,
				Xp = 0,
				Upgrade = 3,
				Stars = 0,
				Locked = false,
				Favorite = false,
				Source = "Roll",
				Acquired = lastSeen,
			}
			p.Inventory.NextId = 2
			p.Base.PlacedMonsters["1"] = "m1"
			p.Currencies.Coins = 1000
			p.Timestamps.LastSeen = lastSeen
			return p
		end

		it("pays the capped, efficiency-scaled amount once, atomically with the lock claim", function()
			local loadAt = now()
			local seeded = idleProfile(loadAt - 3600)
			seed(2020, seeded, nil)
			local expected =
				OfflineIncome.compute(DataSchema.sanitize(Mock.roundTrip(seeded), loadAt), loadAt)
			expect(expected.Coins > 0).toBe(true)
			local player = G.join(2020, "Idler")
			local profile = G.profile(player)
			-- (the live profile may already have a second of online income on top)
			expect(profile.Currencies.Coins >= 1000 + expected.Coins).toBe(true)
			-- the store already holds the paid amount and the moved LastSeen
			expect(stored(2020).Profile.Currencies.Coins).toBe(1000 + expected.Coins)
			expect(stored(2020).Profile.Timestamps.LastSeen).toBe(loadAt)
			local popups = G.pushed(player, "Popup")
			local found = false
			for _, args in popups do
				if args[1] == "Offline" and args[2].Coins == expected.Coins then
					found = true
				end
			end
			expect(found).toBe(true)
			G.leave(player)
		end)

		it("does not pay again on an immediate rejoin", function()
			local coins = stored(2020).Profile.Currencies.Coins
			Mock.clearClientEvents()
			local player = G.join(2020, "Idler")
			-- the load write is the only store write so far: no offline coins added
			expect(stored(2020).Profile.Currencies.Coins).toBe(coins)
			for _, args in G.pushed(player, "Popup") do
				expect(args[1] ~= "Offline").toBe(true)
			end
			G.leave(player)
		end)

		it("does not pay twice when a server crashes after loading", function()
			local loadAt = now()
			seed(2021, idleProfile(loadAt - 7200), nil)
			local player = G.join(2021, "Crasher")
			local paid = G.profile(player).Currencies.Coins
			-- simulate the server dying: no final save, the lock goes stale
			local record = Mock.roundTrip(stored(2021))
			record.Lock.SessionId = "dead-server"
			record.Lock.Time = now() - DATA.LockStaleSeconds - 1
			G.leave(player) -- this server's save is refused: the record now belongs to "dead-server"
			store._data[key(2021)] = record
			local again = G.join(2021, "Crasher")
			-- only the time since the crash-time load counts, which is under the minimum absence
			expect(G.profile(again).Currencies.Coins).toBe(paid)
			G.leave(again)
		end)
	end)

	describe("session takeover", function()
		it("stops saving and kicks the player if another server takes the profile", function()
			local player = G.join(2030, "Twin")
			G.profile(player).Currencies.Coins = 1
			local record = Mock.roundTrip(stored(2030))
			record.Lock = { SessionId = "thief-server", Time = now(), PlaceId = 1 }
			record.Profile.Currencies.Coins = 5555
			store._data[key(2030)] = record
			expect(Data.saveNow(player)).toBe(false)
			G.wait(1)
			expect(kicked(player) ~= nil).toBe(true)
			expect(stored(2030).Profile.Currencies.Coins).toBe(5555)
			expect(stored(2030).Lock.SessionId).toBe("thief-server")
		end)
	end)

	describe("shutdown", function()
		it("BindToClose saves and releases every player's profile", function()
			local a = G.join(2040, "Last1")
			local b = G.join(2041, "Last2")
			G.profile(a).Currencies.Coins = 4040
			G.profile(b).Currencies.Coins = 4141
			Mock.shutdown()
			expect(stored(2040).Profile.Currencies.Coins).toBe(4040)
			expect(stored(2041).Profile.Currencies.Coins).toBe(4141)
			expect(stored(2040).Lock).toBeNil()
			expect(stored(2041).Lock).toBeNil()
		end)
	end)
end
