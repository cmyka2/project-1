-- run from the command bar: require(game.ServerStorage.Tests.BattleSpec)()
return function(E)
	E = E or require(game.ServerScriptService.BattleEngine)
	local B = require(game.ReplicatedStorage.Monster.BattleConfig)
	assert(E.elementMult("Nature", "Earth") == 1.25 and E.elementMult("Nature", "Fire") == 0.8)
	assert(E.elementMult("Light", "Shadow") == 1.25 and E.elementMult("Shadow", "Light") == 1.25)
	assert(E.elementMult("Cosmic", "Fire") == 1 and E.elementMult("Fire", "Cosmic") == 1)
	local rng = Random.new(3)
	local hero = { name = "Hero", element = "Cosmic", hp = 500, dmg = 60, def = 10, spd = 20 }
	local slow = { name = "Slow", element = "Cosmic", hp = 50, dmg = 5, def = 0, spd = 1 }
	local s = E.new({ hero }, { slow, slow }, rng)
	assert(E.current(s).name == "Hero", "faster unit goes first")
	local ok = E.act(s, "attack", 1) assert(not ok, "can't target own side")
	ok = E.act(s, "skill", 99) assert(not ok, "bad target index")
	ok = E.act(s, "ultimate") assert(not ok, "no energy yet")
	ok = E.act(s, "dance", 2) assert(not ok, "unknown action")

	-- damage formula, no crit: atk x mult x 100/(100+def) x element, floored
	local noCrit = { NextNumber = function() return 0.99 end }
	local function duel(a, d) return E.new({ a }, { d }, noCrit) end
	local function u(el, dmg, def) return { name = el, element = el, hp = 1e6, dmg = dmg, def = def, spd = 10 } end
	local d1 = duel(u("Cosmic", 100, 0), u("Cosmic", 1, 100))
	assert(E.hit(d1, d1.units[1], d1.units[2], 1) == 50, "100 atk vs 100 def = 50")
	local d2 = duel(u("Nature", 100, 0), u("Earth", 1, 100))
	assert(E.hit(d2, d2.units[1], d2.units[2], 1) == 62, "strong element x1.25")
	local d3 = duel(u("Nature", 100, 0), u("Fire", 1, 100))
	assert(E.hit(d3, d3.units[1], d3.units[2], 1.6) == 64, "weak element x0.8 with skill x1.6")
	d1.units[2].defending = true
	assert(E.hit(d1, d1.units[1], d1.units[2], 1) == 25, "defending halves")
	local crit = { NextNumber = function() return 0 end }
	local d4 = E.new({ u("Cosmic", 100, 0) }, { u("Cosmic", 1, 100) }, crit)
	assert(E.hit(d4, d4.units[1], d4.units[2], 1) == 75, "crit x1.5")
	-- huge defense never zeroes damage
	local wall = { name = "Wall", element = "Cosmic", hp = 10, dmg = 1, def = 1e9, spd = 0 }
	local s2 = E.new({ hero }, { wall }, rng)
	assert(E.hit(s2, s2.units[1], s2.units[2], 1) >= 1, "min damage is 1")

	-- statuses: burn ticks on the target's turn; freeze skips one turn then grants immunity
	local fire = { name = "Pyro", element = "Fire", hp = 1000, dmg = 10, def = 0, spd = 30 }
	local dummy = { name = "Dummy", element = "Cosmic", hp = 1000, dmg = 1, def = 0, spd = 5 }
	local b = E.new({ fire }, { dummy }, noCrit)
	assert(E.act(b, "skill", 2)) -- the turn passes to the dummy, whose burn ticks first
	assert(E.current(b).name == "Dummy" and b.units[2].status.burn == B.Status.burn.dur - 1, "burn applied and ticked once")
	assert(b.units[2].hp == 1000 - 16 - math.floor(1000 * B.Status.burn.dot), "burn damage on its turn, got " .. b.units[2].hp)
	local water = { name = "Tide", element = "Water", hp = 1000, dmg = 10, def = 0, spd = 30 }
	local f = E.new({ water }, { dummy }, noCrit)
	assert(E.act(f, "skill", 2))
	assert(E.current(f).name == "Tide" and f.units[2].status.freeze == nil, "frozen enemy skipped its turn")
	assert(string.find(f.log[#f.log], "can't move"), "skip logged")
	assert(f.units[2].ccImmune > 0, "immune after a skip")
	E.act(f, "attack", 2) -- cooldown up: plain attack; dummy acts now
	assert(E.current(f).side == "enemy", "dummy acts after the freeze wore off")
	E.runEnemies(f)
	assert(not E.act(f, "skill", 2), "skill still on cooldown")
	-- self statuses: shield absorbs, regen heals and cleanses
	local earth = { name = "Golem", element = "Earth", hp = 1000, dmg = 10, def = 0, spd = 30 }
	local g = E.new({ earth }, { dummy }, noCrit)
	E.act(g, "skill", 2)
	assert(g.units[1].shield == 250 and g.units[1].status.shield, "shield on caster")
	g.units[1].hp = 500
	local hp0 = g.units[1].hp
	E.hit(g, g.units[2], g.units[1], 1)
	assert(g.units[1].hp == hp0 and g.units[1].shield < 250, "shield absorbed the hit")
	-- bosses resist chain control longer
	assert(B.BOSS_CONTROL_IMMUNE > B.CONTROL_IMMUNE)

	-- a full battle ends with the strong side winning
	local rounds = 0
	while not s.over and rounds < 200 do
		rounds += 1
		if E.current(s).side == "player" then
			local t for i, x in s.units do if x.side == "enemy" and x.alive then t = i break end end
			assert(E.act(s, "attack", t))
		else
			E.runEnemies(s)
		end
	end
	assert(s.over and s.winner == "player", "hero should win")
	assert(not E.act(s, "attack", 2), "no actions after the end")
	-- every configured stage has enemies and a valid unlock chain
	for id, st in B.StageById do
		assert(#st.enemies > 0, id .. " has no enemies")
		local prev = B.PrevStage[id]
		assert(prev == nil or B.StageById[prev], id .. " has a bad previous stage")
	end
	return "battle ok in " .. rounds .. " actions"
end
