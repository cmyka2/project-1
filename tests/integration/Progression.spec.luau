-- Mid/late-game systems driven through the real remotes: battles and bosses,
-- region unlocks, rebirth slot/floor growth, skills, equipment, crafting,
-- fusion/evolution, chests, achievements, the tutorial, offline QA and a
-- full server (more players than plots).
return function(ctx)
	local T = ctx.Test
	local describe, it, expect = T.describe, T.it, T.expect
	local G = require("../harness/GameHarness")
	local Mock = G.Mock
	G.boot()

	local GameConfig = G.module("ReplicatedStorage.Shared.Config.GameConfig")
	local RegionConfig = G.module("ReplicatedStorage.Shared.Config.RegionConfig")
	local RebirthConfig = G.module("ReplicatedStorage.Shared.Config.RebirthConfig")
	local SkillTreeConfig = G.module("ReplicatedStorage.Shared.Config.SkillTreeConfig")
	local CraftingConfig = G.module("ReplicatedStorage.Shared.Config.CraftingConfig")
	local MonsterConfig = G.module("ReplicatedStorage.Shared.Config.MonsterConfig")
	local RarityConfig = G.module("ReplicatedStorage.Shared.Config.RarityConfig")
	local EnemyConfig = G.module("ReplicatedStorage.Shared.Config.EnemyConfig")
	local BaseLayout = G.module("ReplicatedStorage.Shared.Util.BaseLayout")
	local RateLimiter = G.module("ServerScriptService.Server.Modules.RateLimiter")
	local Combat = G.service("CombatService")
	local Plot = G.service("PlotService")
	local Region = G.service("RegionService")
	local Inventory = G.service("InventoryService")
	local Data = G.service("PlayerDataService")

	local function invoke(player, name, ...)
		RateLimiter.clear(player)
		return G.invoke(player, name, ...)
	end
	local function cheat(player, command, arg)
		local r = invoke(player, "Cheat", command, arg)
		assert(r.ok, "cheat " .. command .. " failed: " .. tostring(r.err))
	end
	local function give(player, monsterId)
		local inst = assert(Inventory.addMonster(player, monsterId, "Test", { IgnoreCapacity = true }))
		return inst.Id
	end
	local function count(t)
		local n = 0
		for _ in t do
			n += 1
		end
		return n
	end

	-- Plays a battle to the end with basic attacks on the first living enemy.
	local function fight(player, encounterId)
		local r = invoke(player, "StartBattle", encounterId)
		if not r.ok then
			return nil, r.err
		end
		for _ = 1, 300 do
			local session = Combat.session(player)
			if not session or session.Finished then
				break
			end
			local battle = session.Battle
			if battle.State == "PlayerTurn" then
				local unit, target
				for _, u in battle.Units do
					if u.Id == battle.Active then
						unit = u
					elseif u.Side == "Enemy" and u.Alive and not target then
						target = u.Id
					end
				end
				invoke(player, "BattleAction", battle.Id, "Ability", unit.Abilities[1], target, nil)
			end
			G.wait(1)
		end
		return Combat.session(player), nil
	end

	local hero = G.join(4001, "Hero")
	local profile = G.profile(hero)
	cheat(hero, "AddCoins", 100000)
	cheat(hero, "AddGems", 1000)
	local team = { give(hero, "moss_golem"), give(hero, "moss_golem"), give(hero, "sprout_bunny") }
	assert(invoke(hero, "SetTeam", team).ok, "SetTeam failed")
	cheat(hero, "MaxLevelTeam")

	describe("battles and regions", function()
		it("wins a regular encounter and pays rewards once", function()
			local coins = profile.Currencies.Coins
			local gems = profile.Currencies.Gems
			local session = fight(hero, "grassland_1")
			expect(session.Battle.State).toBe("Victory")
			expect(session.Rewards.Victory).toBe(true)
			expect(profile.Progression.EncounterClears.grassland_1).toBe(1)
			expect(profile.Statistics.BattlesWon).toBe(1)
			local encounter = EnemyConfig.Encounters.grassland_1
			expect(profile.Currencies.Coins >= coins + encounter.RewardCoins).toBe(true)
			expect(profile.Currencies.Gems >= gems + encounter.FirstClearGems).toBe(true)
			-- the finished session cannot be rewarded again
			local clears = profile.Progression.EncounterClears.grassland_1
			invoke(hero, "BattleAction", session.Battle.Id, "Ability", "quick_jab", nil, nil)
			expect(profile.Progression.EncounterClears.grassland_1).toBe(clears)
		end)

		it("cannot unlock Forest before the Grassland boss is defeated", function()
			local coins = profile.Currencies.Coins
			local r = invoke(hero, "UnlockRegion", "Forest")
			expect(r.ok).toBe(false)
			expect(string.find(r.err, "boss") ~= nil).toBe(true)
			expect(profile.Currencies.Coins).toBe(coins)
		end)

		it("defeats the boss, drops its chest and puts it on cooldown", function()
			local session = fight(hero, "grassland_boss")
			expect(session.Battle.State).toBe("Victory")
			expect(profile.Progression.BossesDefeated.Grassland).toBe(1)
			expect((profile.Inventory.Chests.boss_chest or 0) >= 1).toBe(true)
			G.wait(GameConfig.Combat and 1 or 1)
			local again = invoke(hero, "StartBattle", "grassland_boss")
			expect(again.ok).toBe(false)
			expect(string.find(again.err, "Available again") ~= nil).toBe(true)
		end)

		it("unlocks Forest for its coin cost and travels there", function()
			local coins = profile.Currencies.Coins
			expect(invoke(hero, "UnlockRegion", "Forest").ok).toBe(true)
			expect(profile.Progression.UnlockedRegions.Forest).toBe(true)
			expect(profile.Currencies.Coins).toBe(coins - RegionConfig.Regions.Forest.UnlockCost)
			expect(invoke(hero, "UnlockRegion", "Forest").ok).toBe(false)
			G.wait(2)
			local r = invoke(hero, "TravelToRegion", "Forest")
			expect(r.ok).toBe(true)
			expect(Region.currentRegion(hero)).toBe("Forest")
			G.wait(5)
			expect(invoke(hero, "TravelToHub").ok).toBe(true)
		end)

		it("cannot start an encounter in a locked region", function()
			expect(invoke(hero, "StartBattle", "desert_1").ok).toBe(false)
		end)

		it("a forfeited battle pays nothing", function()
			local coins = profile.Currencies.Coins
			local won = profile.Statistics.BattlesWon
			expect(invoke(hero, "StartBattle", "forest_1").ok).toBe(true)
			expect(invoke(hero, "ForfeitBattle").ok).toBe(true)
			local session = Combat.session(hero)
			expect(session.Finished).toBe(true)
			expect(session.Battle.State).toBe("Defeat")
			expect(profile.Statistics.BattlesWon).toBe(won)
			expect(profile.Currencies.Coins <= coins + 5).toBe(true)
		end)
	end)

	describe("skill tree", function()
		it("enforces prerequisites, max level and gem costs", function()
			expect(invoke(hero, "BuySkillNode", "luck_3").ok).toBe(false)
			local gems = profile.Currencies.Gems
			local node = SkillTreeConfig.Nodes.luck_1
			expect(invoke(hero, "BuySkillNode", "luck_1").ok).toBe(true)
			expect(profile.Skills.Nodes.luck_1).toBe(1)
			expect(profile.Currencies.Gems).toBe(gems - SkillTreeConfig.costOf(node, 0))
			for _ = 2, node.MaxLevel do
				expect(invoke(hero, "BuySkillNode", "luck_1").ok).toBe(true)
			end
			expect(invoke(hero, "BuySkillNode", "luck_1").ok).toBe(false)
			expect(Data.mods(hero).Luck >= 0.25 - 1e-9).toBe(true)
			expect(invoke(hero, "BuySkillNode", "luck_3").ok).toBe(true)
		end)

		it("respec refunds gems for a fee and then goes on cooldown", function()
			local spent = profile.Skills.GemsSpent
			local gems = profile.Currencies.Gems
			local r = invoke(hero, "RespecSkills")
			expect(r.ok).toBe(true)
			expect(count(profile.Skills.Nodes)).toBe(0)
			expect(profile.Currencies.Gems).toBe(gems + spent - SkillTreeConfig.RespecCostGems)
			invoke(hero, "BuySkillNode", "luck_1")
			expect(invoke(hero, "RespecSkills").ok).toBe(false)
		end)
	end)

	describe("equipment", function()
		it("one item per category per monster, upgrades cost resources, salvage refunds", function()
			cheat(hero, "GiveEquipment", "wooden_claws")
			cheat(hero, "GiveEquipment", "wooden_claws")
			cheat(hero, "AddMaterials", 200)
			local ids = {}
			for id, item in profile.Inventory.Equipment do
				if item.ItemId == "wooden_claws" then
					table.insert(ids, id)
				end
			end
			table.sort(ids)
			expect(#ids >= 2).toBe(true)
			local wearer = team[1]
			expect(invoke(hero, "EquipItem", ids[1], wearer).ok).toBe(true)
			expect(invoke(hero, "EquipItem", ids[2], wearer).ok).toBe(true)
			expect(profile.Inventory.Equipment[ids[1]].EquippedTo).toBeNil()
			expect(profile.Inventory.Equipment[ids[2]].EquippedTo).toBe(wearer)
			local coins = profile.Currencies.Coins
			expect(invoke(hero, "UpgradeEquipment", ids[2]).ok).toBe(true)
			expect(profile.Inventory.Equipment[ids[2]].Level).toBe(1)
			expect(profile.Currencies.Coins < coins).toBe(true)
			local essence = profile.Currencies.Materials.grassland_essence or 0
			expect(invoke(hero, "SalvageEquipment", { ids[1] }).ok).toBe(true)
			expect(profile.Inventory.Equipment[ids[1]]).toBeNil()
			expect((profile.Currencies.Materials.grassland_essence or 0) >= essence).toBe(true)
		end)
	end)

	describe("crafting", function()
		it("charges ingredients, completes after its timer and can be claimed once", function()
			local recipe = CraftingConfig.Recipes.craft_battle_tonic
			local essence = profile.Currencies.Materials.grassland_essence
			local tonics = profile.Inventory.Consumables.battle_tonic or 0
			local r = invoke(hero, "StartCraft", "craft_battle_tonic", 1)
			expect(r.ok).toBe(true)
			expect(profile.Currencies.Materials.grassland_essence).toBe(essence - 3)
			local job = profile.Crafting.Queue[#profile.Crafting.Queue]
			expect(invoke(hero, "ClaimCraft", job.JobId).ok).toBe(false)
			G.wait(recipe.CraftSeconds + 1)
			expect(invoke(hero, "ClaimCraft", job.JobId).ok).toBe(true)
			expect(profile.Inventory.Consumables.battle_tonic).toBe(tonics + 1)
			expect(invoke(hero, "ClaimCraft", job.JobId).ok).toBe(false)
		end)

		it("respects the queue size", function()
			local size = CraftingConfig.BaseQueueSize
			for _ = 1, size do
				expect(invoke(hero, "StartCraft", "craft_battle_tonic", 1).ok).toBe(true)
			end
			expect(invoke(hero, "StartCraft", "craft_battle_tonic", 1).ok).toBe(false)
			cheat(hero, "SkipCooldowns")
			for _, job in table.clone(profile.Crafting.Queue) do
				invoke(hero, "ClaimCraft", job.JobId)
			end
			expect(#profile.Crafting.Queue).toBe(0)
		end)

		it("refuses recipes from locked regions", function()
			expect(invoke(hero, "StartCraft", "craft_income_potion", 1).ok).toBe(false)
		end)
	end)

	describe("fusion and evolution", function()
		it("star fusion consumes a duplicate and raises stars", function()
			local target = give(hero, "sprout_bunny")
			local dupe = give(hero, "sprout_bunny")
			local other = give(hero, "moss_golem")
			expect(invoke(hero, "StarFuse", target, { other }, true).ok).toBe(false)
			expect(invoke(hero, "StarFuse", target, { dupe }, true).ok).toBe(true)
			expect(profile.Inventory.Monsters[target].Stars).toBe(1)
			expect(profile.Inventory.Monsters[dupe]).toBeNil()
			expect(profile.Inventory.Monsters[other]).notToBeNil()
		end)

		it("rarity fusion turns four same-rarity monsters into one of the next rarity", function()
			local commons = {}
			for _, id in MonsterConfig.Order do
				local def = MonsterConfig.Monsters[id]
				if def.Region == "Grassland" and def.Rarity == "Common" and not def.EvolutionOnly then
					table.insert(commons, id)
				end
			end
			local ids = {}
			for i = 1, CraftingConfig.RarityFusion.InputCount do
				table.insert(ids, give(hero, commons[(i - 1) % #commons + 1]))
			end
			local before = count(profile.Inventory.Monsters)
			local r = invoke(hero, "RarityFuse", ids, true)
			expect(r.ok).toBe(true)
			local made = profile.Inventory.Monsters[r.data.InstanceId]
			expect(RarityConfig.tierOf(MonsterConfig.Monsters[made.MonsterId].Rarity)).toBe(
				RarityConfig.tierOf("Common") + 1
			)
			expect(count(profile.Inventory.Monsters)).toBe(before - #ids + 1)
			for _, id in ids do
				expect(profile.Inventory.Monsters[id]).toBeNil()
			end
		end)

		it("evolution requires the level and transforms the monster in place", function()
			local id = give(hero, "sprout_bunny")
			expect(invoke(hero, "Evolve", id, {}, true).ok).toBe(false)
			profile.Inventory.Monsters[id].Level =
				MonsterConfig.Monsters.sprout_bunny.EvolutionRequirements.Level
			local r = invoke(hero, "Evolve", id, {}, true)
			expect(r.ok).toBe(true)
			local inst = profile.Inventory.Monsters[id]
			expect(inst.MonsterId).toBe("bloom_hare")
			expect(inst.EvolvedFrom).toBe("sprout_bunny")
			expect(profile.Discovery.DiscoveredMonsters.bloom_hare ~= nil).toBe(true)
		end)

		it("will not consume a locked monster", function()
			local target = give(hero, "moss_golem")
			local dupe = give(hero, "moss_golem")
			profile.Inventory.Monsters[dupe].Locked = true
			expect(invoke(hero, "StarFuse", target, { dupe }, true).ok).toBe(false)
			expect(profile.Inventory.Monsters[dupe]).notToBeNil()
		end)
	end)

	describe("chests", function()
		it("opens an owned chest exactly as many times as owned", function()
			local owned = profile.Inventory.Chests.boss_chest or 0
			expect(owned >= 1).toBe(true)
			local r = invoke(hero, "OpenChest", "boss_chest", 1, true)
			expect(r.ok).toBe(true)
			expect(#r.data.Rewards >= 1).toBe(true)
			expect(profile.Inventory.Chests.boss_chest or 0).toBe(owned - 1)
			for _ = 1, owned - 1 do
				invoke(hero, "OpenChest", "boss_chest", 1, true)
			end
			expect(invoke(hero, "OpenChest", "boss_chest", 1, true).ok).toBe(false)
		end)
	end)

	describe("achievements and quests", function()
		it("completes achievements from gameplay and pays their reward once", function()
			local completed = profile.Achievements.Completed
			expect(count(completed) > 0).toBe(true)
			local id = next(completed)
			if not profile.Achievements.Claimed[id] then
				expect(invoke(hero, "ClaimAchievement", id).ok).toBe(true)
			end
			expect(invoke(hero, "ClaimAchievement", id).ok).toBe(false)
		end)

		it("tracks daily quests", function()
			expect(#profile.Quests.Daily > 0).toBe(true)
		end)
	end)

	describe("rebirth", function()
		it("refuses a stale request and an unaffordable rebirth", function()
			local coins = profile.Currencies.Coins
			profile.Currencies.Coins = 0
			expect(invoke(hero, "Rebirth", 0).ok).toBe(false)
			profile.Currencies.Coins = coins
			expect(invoke(hero, "Rebirth", 5).ok).toBe(false)
			expect(profile.Progression.RebirthCount).toBe(0)
		end)

		it("adds one slot per rebirth, unlocks floor 2 at 6 and floor 3 at 12, keeping placements", function()
			cheat(hero, "UnlockAllRegions")
			local index = Plot.plotIndex(hero)
			local model = Plot.plotModel(index)
			local placed = {}
			for n = 0, 12 do
				expect(profile.Progression.RebirthCount).toBe(n)
				-- fill every slot of the current layout
				for slot = 1, BaseLayout.totalSlots(n) do
					if not profile.Base.PlacedMonsters[tostring(slot)] then
						local id = give(hero, "moss_golem")
						local r = invoke(hero, "PlaceMonster", id, slot)
						assert(r.ok, "place slot " .. slot .. ": " .. tostring(r.err))
						placed[slot] = id
					end
				end
				-- the plot shows exactly the layout's pads on the right floors
				local pads = model.Slots:GetChildren()
				expect(#pads).toBe(BaseLayout.totalSlots(n))
				local perFloor = {}
				for _, pad in pads do
					local f = pad:GetAttribute("Floor")
					perFloor[f] = (perFloor[f] or 0) + 1
				end
				for floor, expected in BaseLayout.slotsPerFloor(n) do
					expect(perFloor[floor]).toBe(expected)
				end
				expect(model:GetAttribute("UnlockedFloors")).toBe(BaseLayout.floorCount(n))
				if n == 12 then
					break
				end
				local upgrades = profile.Inventory.Monsters[team[1]]
				upgrades.Upgrade = 2
				local skillsBefore = count(profile.Skills.Nodes)
				cheat(hero, "AddCoins", RebirthConfig.cost(n) + 10)
				G.wait(1.1)
				local r = invoke(hero, "Rebirth", n)
				assert(r.ok, "rebirth " .. n .. ": " .. tostring(r.err))
				expect(r.data.TotalSlots).toBe(5 + n + 1)
				expect(r.data.FloorUnlocked).toBe(n + 1 == 6 or n + 1 == 12)
				expect(profile.Inventory.Monsters[team[1]].Upgrade).toBe(0)
				-- only what RebirthConfig.Reset lists is reset
				expect(count(profile.Skills.Nodes)).toBe(
					if RebirthConfig.Reset.Skills then 0 else skillsBefore
				)
				expect(profile.Progression.UnlockedRegions.Forest).toBe(true)
				expect(profile.Currencies.Coins < RebirthConfig.cost(n)).toBe(true)
			end
			-- every monster placed along the way is still placed in its slot
			for slot, id in placed do
				expect(profile.Base.PlacedMonsters[tostring(slot)]).toBe(id)
			end
			expect(BaseLayout.floorCount(profile.Progression.RebirthCount)).toBe(3)
			expect(profile.Currencies.AscensionPoints > 0).toBe(true)
		end)

		it("slots that moved to a new floor keep earning", function()
			local Tycoon = G.service("TycoonService")
			Tycoon.refreshIncome(hero)
			expect(Tycoon.rate(hero) > 0).toBe(true)
			local pad = Plot.plotModel(Plot.plotIndex(hero)).Slots:FindFirstChild("Slot_6")
			expect(pad:GetAttribute("Floor")).toBe(2)
		end)
	end)

	describe("tutorial", function()
		it("advances info steps, waits on action steps and can be skipped", function()
			local rookie = G.join(4002, "Rookie")
			local p = G.profile(rookie)
			expect(p.Tutorial.Step).toBe(1)
			local steps = GameConfig.Tutorial.Steps
			while steps[p.Tutorial.Step].Advance == "Info" do
				expect(invoke(rookie, "TutorialNext").ok).toBe(true)
			end
			local step = steps[p.Tutorial.Step]
			expect(step.Advance).toBe("Roll")
			expect(invoke(rookie, "TutorialNext").ok).toBe(false)
			G.wait(1)
			expect(invoke(rookie, "Roll", "grassland_dice", 1, false).ok).toBe(true)
			expect(steps[p.Tutorial.Step].Id ~= step.Id).toBe(true)
			expect(invoke(rookie, "TutorialSkip").ok).toBe(true)
			expect(p.Tutorial.Completed).toBe(true)
			expect(p.Tutorial.Skipped).toBe(true)
			G.leave(rookie)
		end)
	end)

	describe("offline QA cheat", function()
		it("SimulateOffline makes the next join pay offline income", function()
			cheat(hero, "SimulateOffline", 3600)
			G.leave(hero)
			Mock.clearClientEvents()
			hero = G.join(4001, "Hero")
			local found = false
			for _, args in G.pushed(hero, "Popup") do
				if args[1] == "Offline" and args[2].Coins > 0 then
					found = true
				end
			end
			expect(found).toBe(true)
			profile = G.profile(hero)
		end)
	end)

	describe("full server", function()
		it("a player beyond the plot count gets no plot, then gets the next free one", function()
			local plots = GameConfig.Plots.Count
			local others = {}
			local userId = 4100
			while true do
				local taken = 0
				for i = 1, plots do
					if Plot.owner(i) then
						taken += 1
					end
				end
				if taken >= plots then
					break
				end
				userId += 1
				table.insert(others, G.join(userId, "Filler" .. userId))
			end
			Mock.clearClientEvents()
			local late = G.join(4999, "Latecomer")
			expect(G.profile(late)).notToBeNil()
			expect(Plot.plotIndex(late)).toBeNil()
			local warned = false
			for _, args in G.pushed(late, "Notify") do
				if string.find(args[2], "plots are taken") then
					warned = true
				end
			end
			expect(warned).toBe(true)
			-- can still play: roll, but not place
			G.wait(1)
			expect(invoke(late, "Roll", "grassland_dice", 1, false).ok).toBe(true)
			local id = next(G.profile(late).Inventory.Monsters)
			expect(invoke(late, "PlaceMonster", id, 1).ok).toBe(false)
			-- a plot frees up
			local leaver = others[1]
			local freed = Plot.plotIndex(leaver)
			G.leave(leaver)
			expect(Plot.plotIndex(late)).toBe(freed)
			expect(#Plot.plotModel(freed).Slots:GetChildren()).toBe(BaseLayout.totalSlots(0))
			expect(Plot.plotModel(freed):GetAttribute("OwnerUserId")).toBe(4999)
			expect(invoke(late, "PlaceMonster", id, 1).ok).toBe(true)
		end)
	end)
end
