-- run from the command bar: require(game.ServerStorage.Tests.BattleSpec)()
return function(E)
	E = E or require(game.ServerScriptService.BattleEngine)
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
	-- huge defense never zeroes damage
	local wall = { name = "Wall", element = "Cosmic", hp = 10, dmg = 1, def = 1e9, spd = 0 }
	local s2 = E.new({ hero }, { wall }, rng)
	assert(E.hit(s2, s2.units[1], s2.units[2], 1) >= 1, "min damage is 1")
	-- a full battle ends with the strong side winning
	local rounds = 0
	while not s.over and rounds < 200 do
		rounds += 1
		if E.current(s).side == "player" then
			local t for i, u in s.units do if u.side == "enemy" and u.alive then t = i break end end
			assert(E.act(s, "attack", t))
		else
			E.runEnemies(s)
		end
	end
	assert(s.over and s.winner == "player", "hero should win")
	assert(not E.act(s, "attack", 2), "no actions after the end")
	return "battle ok in " .. rounds .. " actions"
end
