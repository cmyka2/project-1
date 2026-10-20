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
	assert(R.requirement(0).minTier == 3 and R.requirement(2).minTier == 4 and R.requirement(100).minTier == 12, "monster requirement climbs, capped")

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
	assert(m.Rebirths == 2 and m.Materials and m.BattleTeams and m.Gear.g1.lvl == 1, "fields kept/added")
	assert(m.Skills.start == 1 and m.Skills.money1 == nil and m.Cash == 10 + S.OLD_TREE_COST.money1, "old tree refunded in cash")
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
	-- Evolution Tree: ranks, prerequisites (incl. cross-branch), rebirth gates, each rank applied once
	local T = require(M.SkillTree)
	local owned = { start = 1 }
	assert(T.blocked(T.ById.lucky_charm, owned, 0) == nil, "first node buyable")
	assert(T.blocked(T.ById.rare_hunter, owned, 0), "second node needs the first")
	assert(T.blocked(T.ById.fortune_engine, { start = 1, legendary_focus = 1 }, 0), "cross node needs both branches")
	assert(T.blocked(T.ById.fortune_engine, { start = 1, legendary_focus = 1, golden_pedestals = 1 }, 0) == nil)
	assert(T.blocked(T.ById.cosmic_fortune, { mythic_resonance = 1, double_fortune = 1, discovery_streak = 1 }, 2) == "Needs Rebirth 3")
	assert(T.blocked(T.ById.lucky_charm, { lucky_charm = 5 }, 0) == "Maxed")
	assert(math.abs(T.stat({ lucky_charm = 3, fortune_engine = 1 }, "luck") - (0.15 + 0.15)) < 1e-9, "ranks x value, summed across nodes")
	assert(T.stat({ lucky_charm = 99 }, "luck") == 0.25, "rank clamped to max")
	assert(T.cost(T.ById.coin_collector, 0) == 100 and T.cost(T.ById.coin_collector, 1) == 300, "cash cost grows per rank")
	assert(T.cost(T.AscById.fated_luck, 0) == 2 and T.cost(T.AscById.fated_luck, 2) == 6, "AP cost grows per rank")
	local seen = {}
	for _, node in T.Nodes do
		assert(not seen[node.q .. "," .. node.r], "two nodes on one hex: " .. node.id)
		seen[node.q .. "," .. node.r] = true
		for _, req in node.requires or {} do assert(T.ById[req], node.id .. " requires unknown " .. req) end
		for effect in node.effects do assert(T.Effects[effect], node.id .. " has unknown effect " .. effect) end
	end
	for _, b in T.Branches do
		if b.id ~= "cross" then
			local count = 0
			for _, node in T.Nodes do if node.branch == b.id then count += 1 end end
			assert(count == 7, b.id .. " should have 7 nodes")
		end
	end

	-- daily cycle: once per UTC day, streak continues on consecutive days, restarts after a gap, wraps after 7
	local P = require(M.ProgressConfig)
	local day = 86400
	local d0 = { day = 0, last = -1 }
	local n1 = P.nextDaily(d0, 100 * day)
	assert(n1.day == 1 and P.nextDaily(n1, 100 * day + 3600) == nil, "one claim per day")
	local n2 = P.nextDaily(n1, 101 * day + 5)
	assert(n2.day == 2, "streak")
	assert(P.nextDaily(n2, 105 * day).day == 1, "gap restarts")
	assert(P.nextDaily({ day = 7, last = 200 }, 201 * day).day == 1, "wraps after day 7")
	-- events: date window, weekday, forced
	local hw = P.EventById.halloween_hunt
	local function has(list, id) for _, e in list do if e.id == id then return true end end return false end
	assert(has(P.activeEvents(hw.from + 10), "halloween_hunt") and not has(P.activeEvents(hw.to + 10), "halloween_hunt"))
	assert(has(P.activeEvents(1792886400), "weekend_income") and not has(P.activeEvents(1792886400 + 2 * day), "weekend_income"), "2026-10-25 is a Sunday")
	assert(has(P.activeEvents(0, { weekend_income = 10 }), "weekend_income"), "forced event")
	local sat = 1792886400 - day -- Saturday 2026-10-24 00:00 UTC
	assert(not has(P.activeEvents(sat + 17 * 3600), "lucky_hour") and has(P.activeEvents(sat + 18 * 3600 + 60), "lucky_hour"), "Lucky Hour 18:00 UTC Saturday only")
	assert(P.eventMult({ hw }, "luck") == 1.5 and P.eventMult({ hw }, "income") == 1)
	return "progression ok"
end
