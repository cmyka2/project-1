-- Validates every config module loads and cross-references resolve.
return function(ctx)
	local T, Loader = ctx.Test, ctx.Loader
	local describe, it, expect = T.describe, T.it, T.expect
	local function cfg(name)
		return Loader.requirePath("ReplicatedStorage.Shared.Config." .. name)
	end

	describe("Config", function()
		it("loads every config module", function()
			for _, name in
				{
					"GameConfig",
					"RarityConfig",
					"RegionConfig",
					"CombatConfig",
					"AbilityConfig",
					"MonsterConfig",
					"DiceConfig",
					"EconomyConfig",
					"EnemyConfig",
					"EquipmentConfig",
					"CraftingConfig",
					"ChestConfig",
					"SkillTreeConfig",
					"RebirthConfig",
					"QuestConfig",
					"EventConfig",
					"MonetizationConfig",
					"AssetConfig",
				}
			do
				expect(cfg(name)).notToBeNil()
			end
		end)

		it("monsters reference valid rarities, regions, elements and abilities", function()
			local Monster, Rarity, Region, Combat, Ability =
				cfg("MonsterConfig"),
				cfg("RarityConfig"),
				cfg("RegionConfig"),
				cfg("CombatConfig"),
				cfg("AbilityConfig")
			local count = 0
			for id, def in Monster.Monsters do
				count += 1
				expect(def.MonsterId).toBe(id)
				expect(Rarity.Rarities[def.Rarity]).notToBeNil()
				expect(Region.Regions[def.Region]).notToBeNil()
				expect(Combat.Elements[def.Element]).notToBeNil()
				expect(#def.Abilities >= 2).toBeTruthy()
				for i, abilityId in def.Abilities do
					local ability = Ability.Abilities[abilityId]
					assert(ability, id .. " has unknown ability " .. abilityId)
					if i == 1 then
						assert(ability.Kind == "Basic", id .. " first ability must be Basic")
					end
				end
				local ult = Ability.Abilities[def.Abilities[#def.Abilities]]
				assert(ult.Kind == "Ultimate", id .. " last ability must be an Ultimate")
				expect(def.BaseIncomePerSecond > 0).toBeTruthy()
				expect(def.BaseStats.MaxHealth > 0).toBeTruthy()
				if def.EvolvesTo then
					assert(Monster.Monsters[def.EvolvesTo], id .. " evolves to unknown monster")
					assert(def.EvolutionRequirements, id .. " missing evolution requirements")
				end
			end
			expect(count >= 60).toBeTruthy()
			expect(#Monster.Order).toBe(count)
		end)

		it("moss_golem matches the spec example", function()
			local m = cfg("MonsterConfig").Monsters.moss_golem
			expect(m.DisplayName).toBe("Moss Golem")
			expect(m.Rarity).toBe("Rare")
			expect(m.Region).toBe("Forest")
			expect(m.ModelKey).toBe("MossGolem")
			expect(m.Element).toBe("Nature")
		end)

		it("every dice has a non-empty pool covering each weighted rarity", function()
			local Dice, Monster = cfg("DiceConfig"), cfg("MonsterConfig")
			for id, dice in Dice.Dice do
				expect(#dice.Pool > 0).toBeTruthy()
				local present = {}
				for _, m in dice.Pool do
					local def = Monster.Monsters[m]
					assert(def, id .. " pool has unknown monster " .. m)
					present[def.Rarity] = true
				end
				for rarity in dice.RarityWeights do
					assert(present[rarity], id .. " weights rarity " .. rarity .. " but has no monster of it")
				end
			end
		end)

		it("every region has a dice, material and boss encounter", function()
			local Region, Dice, Crafting, Enemy =
				cfg("RegionConfig"), cfg("DiceConfig"), cfg("CraftingConfig"), cfg("EnemyConfig")
			for _, id in Region.Order do
				local r = Region.Regions[id]
				assert(Dice.Dice[r.DiceId], id .. " dice missing")
				assert(Crafting.Materials[r.MaterialId], id .. " material missing")
				local boss = Enemy.Encounters[r.BossEncounterId]
				assert(boss and boss.IsBoss, id .. " boss missing")
				expect(#Enemy.encountersForRegion(id)).toBe(4)
			end
		end)

		it("encounters reference valid enemies, abilities and drops", function()
			local Enemy, Ability, Crafting, Chest =
				cfg("EnemyConfig"), cfg("AbilityConfig"), cfg("CraftingConfig"), cfg("ChestConfig")
			for id, e in Enemy.Enemies do
				for _, a in e.Abilities do
					assert(Ability.Abilities[a], id .. " unknown ability " .. a)
				end
				for _, phase in e.Phases do
					if phase.Summon then
						assert(Enemy.Enemies[phase.Summon], id .. " summons unknown enemy")
					end
				end
			end
			for id, enc in Enemy.Encounters do
				for _, entry in enc.Enemies do
					assert(Enemy.Enemies[entry.Enemy], id .. " unknown enemy " .. entry.Enemy)
				end
				for _, drop in enc.Drops do
					if drop.Kind == "Material" then
						assert(Crafting.Materials[drop.Id], id .. " unknown material")
					elseif drop.Kind == "Chest" then
						assert(Chest.Chests[drop.Id], id .. " unknown chest " .. drop.Id)
					elseif drop.Kind == "Consumable" then
						assert(Crafting.Consumables[drop.Id], id .. " unknown consumable")
					end
				end
			end
		end)

		it("recipes, chests and fusions reference valid ids", function()
			local Crafting, Chest, Equipment, Monster, Region =
				cfg("CraftingConfig"),
				cfg("ChestConfig"),
				cfg("EquipmentConfig"),
				cfg("MonsterConfig"),
				cfg("RegionConfig")
			for id, recipe in Crafting.Recipes do
				assert(Region.Regions[recipe.RequiredRegion], id .. " bad region")
				local out = recipe.Output
				if out.Kind == "Equipment" then
					assert(Equipment.Items[out.Id], id .. " bad equipment output")
				elseif out.Kind == "Consumable" then
					assert(Crafting.Consumables[out.Id], id .. " bad consumable output")
				else
					assert(Crafting.Materials[out.Id], id .. " bad material output")
				end
				for _, ing in recipe.Ingredients do
					if ing.Kind == "Material" then
						assert(Crafting.Materials[ing.Id], id .. " bad material " .. ing.Id)
					end
					assert(ing.Amount > 0, id .. " non-positive ingredient")
				end
			end
			for id, chest in Chest.Chests do
				for _, reward in chest.Rewards do
					assert(reward.Weight > 0 and reward.Min <= reward.Max, id .. " bad reward weights")
					if reward.Kind == "Equipment" then
						assert(Equipment.Items[reward.Id], id .. " unknown equipment " .. reward.Id)
					elseif reward.Kind == "Monster" then
						assert(Monster.Monsters[reward.Id], id .. " unknown monster " .. reward.Id)
					elseif reward.Kind == "Consumable" then
						assert(Crafting.Consumables[reward.Id], id .. " unknown consumable " .. reward.Id)
					elseif reward.Kind == "Material" and reward.Id ~= "@region" then
						assert(Crafting.Materials[reward.Id], id .. " unknown material " .. reward.Id)
					end
				end
			end
			for id, fusion in Crafting.SpecialFusions do
				assert(Monster.Monsters[fusion.Result].FusionOnly, id .. " result should be fusion-only")
				for _, input in fusion.Inputs do
					assert(Monster.Monsters[input], id .. " unknown input " .. input)
				end
			end
		end)

		it("skill and ascension prerequisites exist and are acyclic", function()
			local Skill, Rebirth = cfg("SkillTreeConfig"), cfg("RebirthConfig")
			local branchCount = 0
			for _, b in Skill.BranchOrder do
				branchCount += 1
			end
			expect(branchCount).toBe(6)
			for id, node in Skill.Nodes do
				for _, pre in node.Prerequisites do
					assert(Skill.Nodes[pre], id .. " unknown prereq " .. pre)
				end
			end
			local crossCount = 0
			for _, node in Skill.Nodes do
				if node.Branch == "Cross" then
					crossCount += 1
					local branches = {}
					for _, pre in node.Prerequisites do
						branches[Skill.Nodes[pre].Branch] = true
					end
					local n = 0
					for _ in branches do
						n += 1
					end
					assert(n >= 2, node.Id .. " cross node must require two branches")
				end
			end
			expect(crossCount >= 4).toBeTruthy()
			for id, node in Rebirth.AscensionNodes do
				for _, pre in node.Prerequisites do
					assert(Rebirth.AscensionNodes[pre], id .. " unknown ascension prereq " .. pre)
				end
			end
		end)

		it("quests and achievements are well formed", function()
			local Quest = cfg("QuestConfig")
			for id, q in Quest.Quests do
				expect(q.Objective.Target > 0).toBeTruthy()
				assert(q.Title ~= "", id .. " missing title")
			end
			expect(#Quest.MainOrder >= 20).toBeTruthy()
			expect(#Quest.DailyPool >= Quest.DailyQuestCount).toBeTruthy()
			expect(#Quest.WeeklyPool >= Quest.WeeklyQuestCount).toBeTruthy()
			expect(#Quest.DailyRewards).toBe(7)
		end)

		it("movement: 2x base speed, 1.5x sprint, max sprint below the speed telemetry limit", function()
			local Game = cfg("GameConfig")
			local Modifiers = Loader.requirePath("ReplicatedStorage.Shared.Util.Modifiers")
			expect(Modifiers.walkSpeed({})).toBe(32)
			expect(Modifiers.sprintSpeed({})).toBe(48)
			-- every WalkSpeed source at max level, as if a player owned all of them
			local total = 0
			for _, node in cfg("SkillTreeConfig").Nodes do
				for _, effect in node.Effects do
					if effect.Key == "WalkSpeed" then
						total += effect.PerLevel * node.MaxLevel
					end
				end
			end
			for _, node in cfg("RebirthConfig").AscensionNodes do
				for _, effect in node.Effects do
					if effect.Key == "WalkSpeed" then
						total += effect.PerLevel * node.MaxLevel
					end
				end
			end
			for _, pass in cfg("MonetizationConfig").Passes do
				total += pass.Modifiers.WalkSpeed or 0
			end
			local maxSprint = Modifiers.sprintSpeed({ WalkSpeed = total })
			assert(
				maxSprint * 1.5 < Game.AntiExploit.MaxSpeedStudsPerSecond,
				string.format("max sprint %.1f studs/s leaves too little telemetry headroom", maxSprint)
			)
		end)
	end)
end
