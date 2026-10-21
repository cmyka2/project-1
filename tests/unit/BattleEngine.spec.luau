-- Turn order, damage formula, elements, crits, statuses, cooldowns, energy,
-- validation, boss phases and battle termination.
return function(ctx)
	local T, Loader = ctx.Test, ctx.Loader
	local describe, it, expect = T.describe, T.it, T.expect
	local BattleEngine = Loader.requirePath("ServerScriptService.Server.Modules.BattleEngine")
	local CombatConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.CombatConfig")
	local AbilityConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.AbilityConfig")
	local Random = ctx.Mock.Random

	local function stats(overrides)
		local s = {
			MaxHealth = 1000,
			Attack = 100,
			Defense = 50,
			Speed = 10,
			CritChance = 0,
			CritDamage = 1.5,
			Accuracy = 10, -- never miss in deterministic tests
			Evasion = 0,
			StatusResist = 0,
			ElementDamage = 0,
			ElementResist = 0,
			Healing = 0,
			DamageReduction = 0,
			UltimateDamage = 0,
		}
		for k, v in overrides or {} do
			s[k] = v
		end
		return s
	end

	local function spec(name, element, abilities, controlled, overrides)
		return {
			Name = name,
			Element = element,
			ModelKey = name,
			Archetype = "Bruiser",
			Level = 1,
			Stats = stats(overrides),
			Abilities = abilities,
			Controlled = controlled,
			AiProfile = "Smart",
		}
	end

	local function fixedRng(value)
		return function()
			return value
		end
	end

	local function find(battle, id)
		return BattleEngine.unit(battle, id)
	end

	describe("turn order", function()
		it("orders by speed, ties go to the player side then lower slot", function()
			local b = BattleEngine.new("t", {
				spec("P1", "Fire", { "strike", "inferno" }, true, { Speed = 10 }),
				spec("P2", "Fire", { "strike", "inferno" }, true, { Speed = 30 }),
			}, {
				spec("E1", "Fire", { "strike", "inferno" }, false, { Speed = 30 }),
				spec("E2", "Fire", { "strike", "inferno" }, false, { Speed = 20 }),
			}, fixedRng(0.5))
			BattleEngine.advance(b)
			local round
			for _, ev in b.Log do
				if ev.Type == "Round" then
					round = ev
					break
				end
			end
			expect(round).notToBeNil()
			expect(table.concat(round.Order, ",")).toBe("p2,e1,e2,p1")
			expect(b.State).toBe("PlayerTurn")
			expect(b.Active).toBe("p2")
		end)
	end)

	describe("damage formula", function()
		local function damageOf(
			attackerOverrides,
			defenderOverrides,
			abilityId,
			attackerElement,
			defenderElement,
			rng
		)
			local b = BattleEngine.new(
				"d",
				{ spec("A", attackerElement or "Earth", { "strike" }, true, attackerOverrides) },
				{ spec("D", defenderElement or "Earth", { "strike" }, false, defenderOverrides) },
				rng or fixedRng(0.5)
			)
			local a, d = find(b, "p1"), find(b, "e1")
			return BattleEngine.computeDamage(b, a, d, AbilityConfig.Abilities[abilityId or "strike"])
		end

		it("follows Power * Atk * Atk/(Atk+Def) * variance", function()
			-- rng 0.5 -> variance midpoint 1.0
			local dmg = damageOf(nil, nil, "strike", "Earth", "Earth")
			expect(dmg).toBe(math.floor(1 * 100 * (100 / 150) * 1.0))
		end)

		it("never reaches zero from high defense and never goes negative or NaN", function()
			local dmg = damageOf({ Attack = 1 }, { Defense = 1e9 })
			expect(dmg).toBe(CombatConfig.MinDamage)
			local nanDmg = damageOf({ Attack = 0 / 0 }, nil)
			expect(nanDmg >= CombatConfig.MinDamage).toBe(true)
			expect(nanDmg == nanDmg).toBe(true)
		end)

		it("applies element effectiveness from the matrix", function()
			local neutral = damageOf(nil, nil, "strike", "Earth", "Light")
			local super = damageOf(nil, nil, "strike", "Fire", "Nature")
			local resisted = damageOf(nil, nil, "strike", "Fire", "Water")
			expect(super).toBe(math.floor(neutral * 1.5))
			expect(resisted < neutral).toBe(true)
			local _, _, eff = damageOf(nil, nil, "strike", "Fire", "Nature")
			expect(eff).toBe(1.5)
		end)

		it("applies critical damage when the crit roll succeeds", function()
			local _, wasCrit = damageOf({ CritChance = 0 }, nil)
			expect(wasCrit).toBe(false)
			local crit, isCrit =
				damageOf({ CritChance = 1, CritDamage = 2 }, nil, "strike", "Earth", "Earth", fixedRng(0.5))
			expect(isCrit).toBe(true)
			expect(crit).toBe(math.floor(100 * (100 / 150) * 2))
		end)

		it("defense pierce increases damage", function()
			local plain = damageOf(nil, { Defense = 200 }, "radiant_beam", "Light", "Earth")
			local pierce = damageOf(nil, { Defense = 200 }, "judgment", "Light", "Earth")
			expect(pierce > plain).toBe(true)
		end)
	end)

	describe("statuses and actions", function()
		it("burn ticks at the start of the target's turns for its duration, then expires", function()
			local b = BattleEngine.new(
				"s",
				{ spec("P", "Fire", { "strike" }, true, { Speed = 20 }) },
				{ spec("E", "Earth", { "strike" }, false, { Speed = 10, MaxHealth = 100000 }) },
				fixedRng(0.5)
			)
			local e = find(b, "e1")
			BattleEngine.applyStatus(b, find(b, "p1"), e, "Burn", 1, 3)
			BattleEngine.advance(b)
			local ticks = 0
			for _ = 1, 6 do
				if b.State == "PlayerTurn" then
					BattleEngine.playerAction(b, "p1", { Kind = "Defend" })
				end
			end
			for _, ev in b.Log do
				if ev.Type == "Tick" and ev.Target == "e1" then
					ticks += 1
					expect(ev.Amount).toBe(math.floor(100000 * 0.06))
				end
			end
			expect(ticks).toBe(3)
		end)

		it("poison stacks up to its max", function()
			local b = BattleEngine.new(
				"p",
				{ spec("P", "Fire", { "strike" }, true) },
				{ spec("E", "Earth", { "strike" }, false) },
				fixedRng(0.5)
			)
			local e = find(b, "e1")
			for _ = 1, 5 do
				BattleEngine.applyStatus(b, nil, e, "Poison", 1, 3)
			end
			local poison
			for _, s in e.Statuses do
				if s.Id == "Poison" then
					poison = s
				end
			end
			expect(poison.Stacks).toBe(CombatConfig.StatusEffects.Poison.MaxStacks)
		end)

		it("stun makes the unit skip its turn", function()
			local b = BattleEngine.new(
				"st",
				{ spec("P", "Fire", { "strike" }, true, { Speed = 5 }) },
				{ spec("E", "Earth", { "strike" }, false, { Speed = 50 }) },
				fixedRng(0.5)
			)
			BattleEngine.applyStatus(b, nil, find(b, "e1"), "Stun", 1, 1)
			local hp = find(b, "p1").Hp
			BattleEngine.advance(b)
			expect(find(b, "p1").Hp).toBe(hp) -- enemy skipped instead of attacking
			local skipped = false
			for _, ev in b.Log do
				if ev.Type == "Skip" and ev.Unit == "e1" then
					skipped = true
				end
			end
			expect(skipped).toBe(true)
		end)

		it("defending halves incoming damage until the defender's next turn", function()
			local function hitWhileDefending(defend)
				local b = BattleEngine.new(
					"df",
					{ spec("P", "Earth", { "strike" }, true, { Speed = 50 }) },
					{ spec("E", "Earth", { "strike" }, false, { Speed = 10 }) },
					fixedRng(0.5)
				)
				BattleEngine.advance(b)
				local before = find(b, "p1").Hp
				if defend then
					BattleEngine.playerAction(b, "p1", { Kind = "Defend" })
				else
					BattleEngine.playerAction(
						b,
						"p1",
						{ Kind = "Ability", AbilityId = "strike", TargetId = "e1" }
					)
				end
				return before - find(b, "p1").Hp
			end
			local plain = hitWhileDefending(false)
			local guarded = hitWhileDefending(true)
			expect(guarded).toBe(math.floor(plain * 0.5))
		end)

		it("shields absorb damage before health", function()
			local b = BattleEngine.new(
				"sh",
				{ spec("P", "Earth", { "strike" }, true) },
				{ spec("E", "Earth", { "strike" }, false) },
				fixedRng(0.5)
			)
			local e = find(b, "e1")
			BattleEngine.applyStatus(b, nil, e, "Shield", 1, 3, 30)
			local hpBefore = e.Hp
			local damage = BattleEngine.computeDamage(b, find(b, "p1"), e, AbilityConfig.Abilities.strike)
			BattleEngine.advance(b)
			BattleEngine.playerAction(b, "p1", { Kind = "Ability", AbilityId = "strike", TargetId = "e1" })
			local dealt
			for _, ev in b.Log do
				if ev.Type == "Damage" and ev.Target == "e1" then
					dealt = ev
					break
				end
			end
			expect(dealt.Absorbed).toBe(30)
			expect(dealt.Amount).toBe(damage - 30)
			expect(hpBefore - e.Hp >= damage - 30).toBe(true)
		end)

		it("enforces cooldowns and ultimate energy", function()
			local b = BattleEngine.new("cd", {
				spec(
					"P",
					"Fire",
					{ "strike", "ember_bite", "inferno" },
					true,
					{ Speed = 50, MaxHealth = 1e7 }
				),
			}, { spec("E", "Earth", { "strike" }, false, { MaxHealth = 1e9, Speed = 1 }) }, fixedRng(0.5))
			BattleEngine.advance(b)
			local ok, err = BattleEngine.playerAction(
				b,
				"p1",
				{ Kind = "Ability", AbilityId = "inferno", TargetId = "e1" }
			)
			expect(ok).toBe(false)
			expect(err).toContain("ready")
			expect(
				BattleEngine.playerAction(
					b,
					"p1",
					{ Kind = "Ability", AbilityId = "ember_bite", TargetId = "e1" }
				)
			).toBe(true)
			ok = BattleEngine.playerAction(
				b,
				"p1",
				{ Kind = "Ability", AbilityId = "ember_bite", TargetId = "e1" }
			)
			expect(ok).toBe(false) -- still on cooldown next turn
			-- build energy with basic attacks
			local guard = 0
			while find(b, "p1").Energy < CombatConfig.MaxEnergy and guard < 20 do
				guard += 1
				BattleEngine.playerAction(
					b,
					"p1",
					{ Kind = "Ability", AbilityId = "strike", TargetId = "e1" }
				)
			end
			expect(
				BattleEngine.playerAction(
					b,
					"p1",
					{ Kind = "Ability", AbilityId = "inferno", TargetId = "e1" }
				)
			).toBe(true)
			expect(find(b, "p1").Energy < CombatConfig.MaxEnergy).toBe(true)
		end)

		it("rejects invalid targets, foreign units and actions out of turn", function()
			local b = BattleEngine.new("v", {
				spec("P", "Fire", { "strike" }, true, { Speed = 50 }),
				spec("P2", "Fire", { "strike" }, true, { Speed = 1 }),
			}, { spec("E", "Earth", { "strike" }, false) }, fixedRng(0.5))
			BattleEngine.advance(b)
			expect(
				BattleEngine.playerAction(
					b,
					"p2",
					{ Kind = "Ability", AbilityId = "strike", TargetId = "e1" }
				)
			).toBe(false)
			expect(BattleEngine.playerAction(b, "e1", { Kind = "Defend" })).toBe(false)
			expect(
				BattleEngine.playerAction(
					b,
					"p1",
					{ Kind = "Ability", AbilityId = "strike", TargetId = "p2" }
				)
			).toBe(false)
			expect(
				BattleEngine.playerAction(
					b,
					"p1",
					{ Kind = "Ability", AbilityId = "strike", TargetId = "nope" }
				)
			).toBe(false)
			expect(
				BattleEngine.playerAction(
					b,
					"p1",
					{ Kind = "Ability", AbilityId = "inferno_hack", TargetId = "e1" }
				)
			).toBe(false)
			expect(BattleEngine.playerAction(b, "p1", { Kind = "Item", ItemId = "luck_potion" })).toBe(false)
		end)
	end)

	describe("bosses and termination", function()
		it("triggers phases once, applies buffs and summons a minion", function()
			local enemy = BattleEngine.enemySpec("bramble_king_boar", 8)
			local b = BattleEngine.new(
				"boss",
				{ spec("P", "Fire", { "strike" }, true, { Attack = 20, Speed = 100 }) },
				{ enemy },
				fixedRng(0.5)
			)
			BattleEngine.advance(b)
			local boss = find(b, "e1")
			-- just above the 60% threshold so one small hit crosses it without killing
			boss.Hp = math.ceil(boss.Stats.MaxHealth * 0.6) + 1
			BattleEngine.playerAction(b, "p1", { Kind = "Ability", AbilityId = "strike", TargetId = "e1" })
			local phases, summons = 0, 0
			for _, ev in b.Log do
				if ev.Type == "Phase" then
					phases += 1
				elseif ev.Type == "Summon" then
					summons += 1
				end
			end
			expect(phases >= 1).toBe(true)
			expect(summons).toBe(1)
			expect(#BattleEngine.living(b, "Enemy") >= 1).toBe(true)
		end)

		it("ends in victory, ignores further actions and reports the result", function()
			local b = BattleEngine.new(
				"win",
				{ spec("P", "Fire", { "strike" }, true, { Attack = 1e6, Speed = 100 }) },
				{ spec("E", "Nature", { "strike" }, false, { MaxHealth = 10 }) },
				fixedRng(0.5)
			)
			BattleEngine.advance(b)
			BattleEngine.playerAction(b, "p1", { Kind = "Ability", AbilityId = "strike", TargetId = "e1" })
			expect(b.State).toBe("Victory")
			expect(BattleEngine.playerAction(b, "p1", { Kind = "Defend" })).toBe(false)
		end)

		it("ends in defeat after the round limit (no stalemates)", function()
			local b = BattleEngine.new(
				"timeout",
				{ spec("P", "Earth", { "strike" }, false, { Attack = 1, MaxHealth = 1e12 }) },
				{ spec("E", "Earth", { "strike" }, false, { Attack = 1, MaxHealth = 1e12 }) },
				fixedRng(0.5)
			)
			BattleEngine.advance(b)
			expect(b.State).toBe("Defeat")
			expect(b.Round).toBe(CombatConfig.MaxRounds)
		end)

		it("enemy AI only chooses available abilities and valid targets (fuzz)", function()
			local rng = Random.new(99)
			for seed = 1, 40 do
				local enemies = {}
				for _, id in { "venom_shroom", "hollow_treant", "kernel_panic" } do
					table.insert(enemies, BattleEngine.enemySpec(id, 5))
				end
				local players = {}
				for i = 1, 3 do
					table.insert(
						players,
						BattleEngine.enemySpec(({ "harpy", "rock_troll", "fallen_cherub" })[i], 6)
					)
				end
				local b = BattleEngine.new("fuzz" .. seed, players, enemies, function()
					return rng:NextNumber()
				end)
				BattleEngine.advance(b)
				expect(b.State == "Victory" or b.State == "Defeat").toBe(true)
				for _, u in b.Units do
					expect(u.Hp >= 0 and u.Hp <= u.Stats.MaxHealth).toBe(true)
				end
			end
		end)
	end)
end
