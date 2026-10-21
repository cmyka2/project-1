-- Profile defaults, versioned migrations (fixtures from older schema
-- versions) and sanitization of corrupted or tampered data.
return function(ctx)
	local T, Loader = ctx.Test, ctx.Loader
	local describe, it, expect = T.describe, T.it, T.expect
	local DataSchema = Loader.requirePath("ServerScriptService.Server.Modules.DataSchema")
	local serde = require("@lune/serde")
	local NOW = 1792549555

	local function roundTrip(v)
		return serde.decode("json", serde.encode("json", v))
	end

	-- A profile shaped like the original v1 spec layout.
	local function v1Fixture()
		return {
			SchemaVersion = 1,
			Currencies = { Coins = 5000, Gems = 40, AscensionPoints = 2, Materials = { forest_essence = 7 } },
			Progression = {
				RebirthCount = 2,
				AscensionUpgrades = { asc_wealth = 3 },
				UnlockedRegions = { Grassland = true, Forest = true },
				HighestRegion = "Forest",
			},
			Inventory = {
				Monsters = {
					m1 = {
						Id = "m1",
						MonsterId = "moss_golem",
						Level = 12,
						Xp = 30,
						Upgrade = 4,
						Stars = 1,
						Locked = true,
						Favorite = false,
						Source = "Roll",
						Acquired = 100,
					},
					m2 = {
						Id = "m2",
						MonsterId = "sprout_bunny",
						Level = 3,
						Xp = 0,
						Upgrade = 0,
						Stars = 0,
						Locked = false,
						Favorite = false,
						Source = "Roll",
						Acquired = 120,
					},
				},
				Equipment = {},
				Consumables = { luck_potion = 2 },
			},
			Base = {
				PlacedMonsters = { ["1"] = "m1", ["2"] = "m2" },
				UnlockedFloors = 1,
				CosmeticUpgrades = {},
			},
			Skills = { Nodes = { luck_1 = 2 } },
			Battle = { Team = { "m1" }, Loadouts = {}, BattleRating = 1100 },
			Discovery = {
				DiscoveredMonsters = { moss_golem = 100, sprout_bunny = 120 },
				TotalRolls = 77,
				RareDiscoveries = {},
			},
			Quests = { Active = {}, Completed = { "main_first_roll" }, ClaimedRewards = {} },
			Achievements = { first_roll = 150 },
			DailyRewards = { LastClaimTimestamp = NOW - 86400, CurrentStreak = 4 },
			Statistics = { LifetimeCoinsEarned = 90000, BattlesWon = 3, MonstersSold = 1, BossesDefeated = 0 },
			Timestamps = { LastSeen = NOW - 3600, LastSaved = NOW - 3600 },
		}
	end

	describe("DataSchema.default", function()
		it("creates a valid, JSON-serializable profile", function()
			local p = DataSchema.default(NOW)
			expect(p.SchemaVersion).toBe(DataSchema.CURRENT_VERSION)
			expect(p.Currencies.Coins).toBe(100)
			expect(p.Progression.UnlockedRegions.Grassland).toBe(true)
			local again = roundTrip(p)
			local sanitized, issues = DataSchema.sanitize(again, NOW)
			expect(#issues).toBe(0)
			expect(sanitized.Currencies.Gems).toBe(p.Currencies.Gems)
		end)

		it("returns independent tables for each player", function()
			local a, b = DataSchema.default(NOW), DataSchema.default(NOW)
			a.Inventory.Monsters.x = {}
			expect(b.Inventory.Monsters.x).toBeNil()
		end)
	end)

	describe("DataSchema.migrate", function()
		it("upgrades a v1 profile to the current version without losing progress", function()
			local migrated = DataSchema.migrate(roundTrip(v1Fixture()))
			local p, issues = DataSchema.sanitize(migrated, NOW)
			expect(p.SchemaVersion).toBe(DataSchema.CURRENT_VERSION)
			expect(p.Currencies.Coins).toBe(5000)
			expect(p.Progression.RebirthCount).toBe(2)
			expect(p.Inventory.Monsters.m1.Level).toBe(12)
			expect(p.Inventory.Monsters.m1.Locked).toBe(true)
			expect(p.Base.PlacedMonsters["1"]).toBe("m1")
			expect(p.Skills.Nodes.luck_1).toBe(2)
			expect(p.Discovery.TotalRolls).toBe(77)
			-- v1 -> v2: timestamp became a day index
			expect(p.DailyRewards.LastClaimDay).toBe(math.floor((NOW - 86400) / 86400))
			expect(p.DailyRewards.CurrentStreak).toBe(4)
			-- v2 -> v3: achievements moved into Completed/Claimed
			expect(p.Achievements.Completed.first_roll).toBe(150)
			expect(p.Achievements.Claimed.first_roll).toBe(true)
			expect(p.Quests.Completed.main_first_roll).toBe(true)
			-- new fields added with defaults
			expect(p.Crafting ~= nil and p.Tutorial ~= nil and p.Settings ~= nil).toBe(true)
			expect(p.Inventory.NextId >= 3).toBe(true)
			local _ = issues
		end)

		it("refuses data from a newer schema version", function()
			local future = DataSchema.default(NOW)
			future.SchemaVersion = DataSchema.CURRENT_VERSION + 1
			expect(function()
				DataSchema.migrate(future)
			end).toThrow()
		end)
	end)

	describe("DataSchema.sanitize", function()
		it("repairs invalid currencies and counters", function()
			local raw = roundTrip(DataSchema.default(NOW))
			raw.Currencies.Coins = -500
			raw.Currencies.Gems = 1e40
			raw.Currencies.Materials = { forest_essence = -3, fake_mat = 99, desert_shard = 4.7 }
			raw.Statistics.BattlesWon = -1
			raw.Inventory.Consumables = { luck_potion = -2, hack_item = 5 }
			local p, issues = DataSchema.sanitize(raw, NOW)
			expect(p.Currencies.Coins).toBe(0)
			expect(p.Currencies.Gems <= 1e30).toBe(true)
			expect(p.Currencies.Materials.fake_mat).toBeNil()
			expect(p.Currencies.Materials.forest_essence).toBeNil()
			expect(p.Currencies.Materials.desert_shard).toBe(4)
			expect(p.Statistics.BattlesWon).toBe(0)
			expect(p.Inventory.Consumables.hack_item).toBeNil()
			local _ = issues
		end)

		it("drops unknown monsters, duplicate placements and bad slots", function()
			local raw = roundTrip(v1Fixture())
			raw = DataSchema.migrate(raw)
			raw.Inventory.Monsters.m9 = { Id = "m9", MonsterId = "does_not_exist", Level = 1 }
			raw.Base.PlacedMonsters["3"] = "m1" -- same monster twice
			raw.Base.PlacedMonsters["99"] = "m2" -- slot beyond the layout
			raw.Base.PlacedMonsters["4"] = "ghost" -- monster not owned
			local p, issues = DataSchema.sanitize(raw, NOW)
			expect(p.Inventory.Monsters.m9).toBeNil()
			local count, seen = 0, {}
			for slot, id in p.Base.PlacedMonsters do
				count += 1
				expect(seen[id]).toBeNil()
				seen[id] = true
				expect(tonumber(slot) <= 7).toBe(true)
			end
			expect(count).toBe(2)
			expect(#issues >= 3).toBe(true)
		end)

		it("clamps levels/upgrades to legal ranges and fixes equipment double slots", function()
			local raw = roundTrip(DataSchema.default(NOW))
			raw.Inventory.Monsters.m1 =
				{ Id = "m1", MonsterId = "sprout_bunny", Level = 9999, Upgrade = 500, Stars = -2, Xp = 0 / 0 }
			raw.Inventory.Equipment.e2 =
				{ Id = "e2", ItemId = "wooden_claws", Level = 999, EquippedTo = "m1" }
			raw.Inventory.Equipment.e3 = { Id = "e3", ItemId = "forest_fang", Level = 1, EquippedTo = "m1" } -- second weapon
			raw.Inventory.Equipment.e4 = { Id = "e4", ItemId = "leaf_vest", Level = 0, EquippedTo = "m404" } -- missing wearer
			local p = DataSchema.sanitize(raw, NOW)
			local m = p.Inventory.Monsters.m1
			expect(m.Level).toBe(60)
			expect(m.Upgrade).toBe(15)
			expect(m.Stars).toBe(0)
			expect(m.Xp).toBe(0)
			local weapons = 0
			for _, item in p.Inventory.Equipment do
				if item.EquippedTo == "m1" then
					weapons += 1
				end
			end
			expect(weapons).toBe(1)
			expect(p.Inventory.Equipment.e4.EquippedTo).toBeNil()
			expect(p.Inventory.Equipment.e2.Level <= 5).toBe(true)
			expect(p.Inventory.NextId >= 5).toBe(true)
		end)

		it("clamps future timestamps so offline time can never be negative", function()
			local raw = roundTrip(DataSchema.default(NOW))
			raw.Timestamps.LastSeen = NOW + 99999
			local p = DataSchema.sanitize(raw, NOW)
			expect(p.Timestamps.LastSeen <= NOW).toBe(true)
		end)

		it("survives garbage input and removes unknown top-level keys", function()
			for _, junk in { nil, 5, "text", { Currencies = "nope", Inventory = 3 }, { Hacked = true } } do
				local p = DataSchema.sanitize(junk, NOW)
				expect(p.Currencies.Coins >= 0).toBe(true)
				expect((p :: any).Hacked).toBeNil()
			end
		end)

		it("is idempotent", function()
			local once = DataSchema.sanitize(DataSchema.migrate(roundTrip(v1Fixture())), NOW)
			local twice, issues = DataSchema.sanitize(roundTrip(once), NOW)
			expect(#issues).toBe(0)
			expect(serde.encode("json", twice)).toBe(serde.encode("json", roundTrip(once)))
		end)
	end)
end
