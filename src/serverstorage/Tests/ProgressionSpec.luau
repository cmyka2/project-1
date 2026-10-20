-- run from the command bar: require(game.ServerStorage.Tests.ProgressionSpec)()
-- slots/floors formula, upgrade + offline math, rebirth reset, save migration and session-lock rules
return function()
	local M = game.ReplicatedStorage.Monster
	local F = require(M.Formulas)
	local R = require(M.RebirthConfig)
	local S = require(game.ServerScriptService.DataSchema)

	-- slots = 5 + rebirths, floors = min(3, 1 + floor(r / 6))
	for r, want in { [0] = { 5, 1 }, [1] = { 6, 1 }, [5] = { 10, 1 }, [6] = { 11, 2 }, [11] = { 16, 2 }, [12] = { 17, 3 }, [30] = { 35, 3 } } do
		assert(F.slots(r) == want[1], ("slots(%d) = %d"):format(r, F.slots(r)))
		assert(F.floors(r) == want[2], ("floors(%d) = %d"):format(r, F.floors(r)))
	end
	assert(F.floors(1000) == 3 and F.slots(1000) == F.MAX_SLOTS, "caps")
	assert(F.slotFloor(1) == 1 and F.slotFloor(10) == 1 and F.slotFloor(11) == 2 and F.slotFloor(16) == 2 and F.slotFloor(17) == 3 and F.slotFloor(40) == 3)
	assert(F.slotRebirth(5) == 0 and F.slotRebirth(6) == 1 and F.slotRebirth(17) == 12)
	-- every unlocked slot sits on an unlocked floor
	for r = 0, 40 do for i = 1, F.slots(r) do assert(F.slotFloor(i) <= F.floors(r), "slot " .. i .. " above unlocked floors at rebirth " .. r) end end
	-- floor 2 gets exactly the 6 slots of rebirths 6-11
	local f2 = 0 for i = 1, F.MAX_SLOTS do if F.slotFloor(i) == 2 then f2 += 1 end end
	assert(f2 == 6, "floor 2 slot count " .. f2)

	-- upgrades: cost grows, income grows, level 1 is the base
	assert(F.levelMult(1) == 1 and F.fusionMult(0) == 1 and F.combatMult(1, 0) == 1)
	assert(F.upgradeCost(10, 2) > F.upgradeCost(10, 1) and F.upgradeCost(10, 1) == 250, "cost curve")
	assert(F.levelMult(2) > F.levelMult(1))
	-- offline: capped at 8h, never negative, ignores NaN
	assert(F.offline(3600, 2) == 7200)
	local amt, secs = F.offline(100 * 3600, 1)
	assert(secs == 8 * 3600 and amt == 8 * 3600, "8h cap")
	assert(F.offline(-500, 10) == 0 and F.offline(0 / 0, 10) == 0, "bad elapsed")

	-- rebirth reset: cash resets, everything else stays, +1 slot, floor milestone at 6
	local d = S.default()
	d.Cash, d.Rebirths = 1e9, 5
	d.Monsters.m1 = { id = "moss_goblin", v = "Normal", lvl = 7, fr = 1, t = 0 }
	d.Placed["1"], d.Gear.g1, d.Dice.forest = "m1", { r = "Rare", t = "weapon", m = "m1" }, true
	local slotsBefore = F.slots(d.Rebirths)
	local ap = R.apply(d)
	assert(d.Cash == 0 and d.Rebirths == 6, "cash reset, count +1")
	assert(d.Monsters.m1.lvl == 7 and d.Placed["1"] == "m1" and d.Gear.g1.m == "m1" and d.Dice.forest, "kept progress")
	assert(F.slots(d.Rebirths) == slotsBefore + 1 and F.floors(d.Rebirths) == 2, "slot + floor 2")
	assert(ap == 6 and d.AscensionPoints == 6, "milestone AP")
	assert(R.requirement(0).stage == nil and R.requirement(3).stage == "grass3", "boss gate from rebirth 3")

	-- v1 -> v2 migration: stacks become instances, placements and gear follow them, nothing is lost
	local v1 = { Version = 1, Cash = 10, Rolls = 4, Discovered = { moss_goblin = { Normal = true } },
		Owned = { ["moss_goblin|Normal"] = 3, ["frostfang|Huge"] = 1 }, Placed = { ["2"] = "frostfang|Huge", ["3"] = "moss_goblin|Normal" },
		Gear = { g1 = { r = "Rare", t = "armor", slot = "2" }, g2 = { r = "Common", t = "weapon" } }, NextGearId = 3,
		Skills = { start = true, money1 = true }, Rebirths = 2, Dice = { grassland = true }, SelectedDie = "grassland", BattleProgress = {} }
	local m = S.migrate(v1, function() return 5 end)
	assert(m.Version == S.VERSION and m.Owned == nil, "version bumped")
	local n, frost = 0, nil
	for iid, inst in m.Monsters do n += 1 if inst.id == "frostfang" then frost = iid end end
	assert(n == 4, "4 instances, got " .. n)
	assert(m.Placed["2"] == frost and m.Monsters[m.Placed["3"]].id == "moss_goblin", "placements mapped to instances")
	assert(m.Gear.g1.m == frost and m.Gear.g1.slot == nil and m.Gear.g2.m == nil, "gear follows the monster")
	assert(m.Skills.money1 and m.Rebirths == 2 and m.Cash == 10 and m.Materials and m.BattleTeams, "fields kept/added")
	-- stacks beyond the cap are refunded, not lost
	local big = S.migrate({ Version = 1, Cash = 0, Owned = { ["moss_goblin|Normal"] = S.MIGRATE_CAP + 10 } }, function() return 5 end)
	local bn = 0 for _ in big.Monsters do bn += 1 end
	assert(bn == S.MIGRATE_CAP and big.Cash == 50, "cap + refund")
	-- defaults and re-migrating are stable
	local fresh = S.migrate(S.default())
	assert(fresh.Version == S.VERSION and fresh.Dice.grassland and fresh.SelectedDie == "grassland")

	-- session locks: free, own, or expired locks can be taken; another live server's can't
	assert(S.canTake(nil, "A", 1000))
	assert(S.canTake({ job = "A", t = 990 }, "A", 1000))
	assert(not S.canTake({ job = "B", t = 990 }, "A", 1000), "live foreign lock")
	assert(S.canTake({ job = "B", t = 1000 - S.LOCK_EXPIRE }, "A", 1000), "expired lock")
	return "progression ok"
end
