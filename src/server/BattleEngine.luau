-- Pure turn-based battle rules (no Roblox state): the server owns a state and feeds it actions.
-- Damage: atk * actionMult * 100/(100+def) * element * crit(10%, x1.5) * (0.5 if defending), min 1.
-- ponytail: Defend is the only status; add burn/freeze/etc. as data on units when regions need them.
local B = require(game:GetService("ReplicatedStorage").Monster.BattleConfig)
local E = {}
E.ACTIONS = { attack = true, skill = true, defend = true, ultimate = true }
local SKILL_CD, ULT_COST, CRIT = 2, 100, 0.1

function E.elementMult(a, d)
	if B.Strong[a] and B.Strong[a][d] then return B.STRONG_MULT end
	if B.Strong[d] and B.Strong[d][a] then return B.WEAK_MULT end
	return 1
end

local function log(s, line)
	table.insert(s.log, line)
	if #s.log > 8 then table.remove(s.log, 1) end
end
local function alive(s, side)
	local out = {}
	for i, u in s.units do if u.alive and u.side == side then table.insert(out, i) end end
	return out
end
local function startTurn(s)
	local u = s.units[s.order[s.turn]]
	u.defending = false
	u.cd = math.max(0, u.cd - 1)
end
local function newRound(s)
	s.round += 1
	s.order = {}
	for i, u in s.units do if u.alive then table.insert(s.order, i) end end
	table.sort(s.order, function(a, b) -- speed, then players first, then slot order
		local ua, ub = s.units[a], s.units[b]
		if ua.spd ~= ub.spd then return ua.spd > ub.spd end
		if ua.side ~= ub.side then return ua.side == "player" end
		return a < b
	end)
	s.turn = 1
	startTurn(s)
end
local function checkEnd(s)
	if #alive(s, "enemy") == 0 then s.over, s.winner = true, "player"
	elseif #alive(s, "player") == 0 then s.over, s.winner = true, "enemy" end
end
local function advance(s)
	repeat
		s.turn += 1
		if s.turn > #s.order then newRound(s) return end
	until s.units[s.order[s.turn]].alive
	startTurn(s)
end

local function unit(side, st)
	return { side = side, name = st.name, element = st.element, hp = st.hp, maxHp = st.hp, dmg = st.dmg, def = st.def, spd = st.spd,
		skill = B.SkillName[st.element] or "Skill", energy = 0, cd = 0, defending = false, alive = true }
end
function E.new(team, enemies, rng: Random)
	local s = { units = {}, round = 0, log = {}, over = false, rng = rng }
	for _, st in team do table.insert(s.units, unit("player", st)) end
	for _, st in enemies do table.insert(s.units, unit("enemy", st)) end
	newRound(s)
	return s
end
function E.current(s) return s.units[s.order[s.turn]], s.order[s.turn] end

function E.hit(s, a, t, mult)
	local dmg = a.dmg * mult * 100 / (100 + t.def) * E.elementMult(a.element, t.element)
	local crit = s.rng:NextNumber() < CRIT
	if crit then dmg *= 1.5 end
	if t.defending then dmg *= 0.5 end
	dmg = math.max(1, math.floor(dmg))
	t.hp = math.max(0, t.hp - dmg)
	if t.hp == 0 then t.alive = false end
	return dmg, crit
end

-- acts for the current unit; returns ok, err
function E.act(s, action, target)
	if s.over then return false, "Battle is over" end
	local a = E.current(s)
	if not E.ACTIONS[action] then return false, "Unknown action" end
	local foeSide = a.side == "player" and "enemy" or "player"
	local t = typeof(target) == "number" and s.units[target]
	local needsTarget = action == "attack" or action == "skill"
	if needsTarget and not (t and t.alive and t.side == foeSide) then return false, "Pick a living enemy" end
	if action == "skill" and a.cd > 0 then return false, a.skill .. " recharging (" .. a.cd .. ")" end
	if action == "ultimate" and a.energy < ULT_COST then return false, "Ultimate needs full energy" end

	if action == "attack" then
		local d, c = E.hit(s, a, t, 1)
		a.energy = math.min(ULT_COST, a.energy + 25)
		log(s, a.name .. " hits " .. t.name .. " for " .. d .. (c and " (CRIT!)" or ""))
	elseif action == "skill" then
		local d, c = E.hit(s, a, t, 1.6)
		a.cd, a.energy = SKILL_CD + 1, math.min(ULT_COST, a.energy + 15) -- +1: ticks down at the start of its own next turn
		log(s, a.name .. " uses " .. a.skill .. " on " .. t.name .. " for " .. d .. (c and " (CRIT!)" or ""))
	elseif action == "defend" then
		a.defending, a.energy = true, math.min(ULT_COST, a.energy + 20)
		log(s, a.name .. " defends")
	else
		a.energy = 0
		local total = 0
		for _, i in alive(s, foeSide) do total += E.hit(s, a, s.units[i], 1.3) end
		log(s, a.name .. " unleashes its ULTIMATE for " .. total .. " total damage!")
	end
	checkEnd(s)
	if not s.over then advance(s) end
	return true
end

-- simple enemy brain: ult when full, defend when low (sometimes), skill when ready, hit the weakest player monster
function E.ai(s)
	local a = E.current(s)
	local foes = alive(s, a.side == "enemy" and "player" or "enemy")
	table.sort(foes, function(x, y) return s.units[x].hp < s.units[y].hp end)
	if a.energy >= ULT_COST then return "ultimate" end
	if a.hp < a.maxHp * 0.3 and s.rng:NextNumber() < 0.35 then return "defend" end
	return a.cd == 0 and "skill" or "attack", foes[1]
end
function E.runEnemies(s)
	while not s.over and E.current(s).side == "enemy" do E.act(s, E.ai(s)) end
end

function E.snapshot(s)
	local units = {}
	for _, u in s.units do
		table.insert(units, { name = u.name, side = u.side, element = u.element, hp = u.hp, maxHp = u.maxHp, energy = u.energy,
			cd = u.cd, skill = u.skill, defending = u.defending, alive = u.alive })
	end
	local _, idx = E.current(s)
	local order = {}
	for k = s.turn, #s.order do if s.units[s.order[k]].alive then table.insert(order, s.order[k]) end end
	return { units = units, active = idx, order = order, round = s.round, log = s.log, over = s.over, winner = s.winner }
end
return E
