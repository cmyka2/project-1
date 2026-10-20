-- Pure turn-based battle rules (no Roblox state): the server owns a state and feeds it actions.
-- Damage, in this order: atk x actionMult x (0.75 if Weakened) x 100/(100 + def x (0.5 if Exposed))
-- x element (strong: 1.25 + attacker's elemental bonus, then x (1 - target's resist)) x (1 + boss bonus vs bosses)
-- x crit(unit crit chance, x1.5) x (1.2 if Marked) x (1 - target protect) x defend (0.5 - guard, min 0.2), floored, min 1;
-- then a Shield absorbs what it can, and Last Stand turns one lethal hit into 1 HP.
-- Defense only divides, so it can never reduce damage to zero.
-- u.mods (player units, from the skill tree / gear): crit elemental energy boss skillamp ultamp regen laststand protect resist guard
local B = require(game:GetService("ReplicatedStorage").Monster.BattleConfig)
local E = {}
E.ACTIONS = { attack = true, skill = true, defend = true, ultimate = true }
local SKILL_CD, ULT_COST, CRIT = 2, 100, 0.1
E.CRIT = CRIT
local ORDER = {} -- statuses tick in a fixed (alphabetical) order
for name in B.Status do table.insert(ORDER, name) end
table.sort(ORDER)

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
	s.turn = 0
end
local function checkEnd(s)
	if #alive(s, "enemy") == 0 then s.over, s.winner = true, "player"
	elseif #alive(s, "player") == 0 then s.over, s.winner = true, "enemy" end
end

-- start-of-turn effects in a fixed order; true if the unit loses this turn
local function tick(s, u)
	u.defending = false
	u.cd = math.max(0, u.cd - 1)
	u.ccImmune = math.max(0, u.ccImmune - 1)
	if u.mods.regen and u.hp < u.maxHp then
		local h = math.min(u.maxHp - u.hp, math.floor(u.maxHp * u.mods.regen))
		u.hp += h
	end
	local skip = false
	for _, name in ORDER do
		local st, left = B.Status[name], u.status[name]
		if left then
			if st.dot then
				local d = math.max(1, math.floor(u.maxHp * st.dot))
				u.hp = math.max(0, u.hp - d)
				log(s, u.name .. " takes " .. d .. " from " .. st.name)
			elseif st.hot then
				local h = math.min(u.maxHp - u.hp, math.floor(u.maxHp * st.hot))
				u.hp += h
				if h > 0 then log(s, u.name .. " regenerates " .. h) end
			end
			if st.skip then skip = true end
			if left <= 1 then
				u.status[name] = nil
				if name == "shield" then u.shield = 0 end
				if st.skip then u.ccImmune = u.boss and B.BOSS_CONTROL_IMMUNE or B.CONTROL_IMMUNE end
			else
				u.status[name] = left - 1
			end
		end
	end
	if u.hp == 0 then u.alive = false log(s, u.name .. " is knocked out") end
	return skip or not u.alive
end
-- moves to the next unit that can act, running start-of-turn effects (and rounds) on the way
local function advance(s)
	for _ = 1, 1000 do
		s.turn += 1
		if s.turn > #s.order then newRound(s) s.turn = 1 end
		local u = s.units[s.order[s.turn]]
		if u.alive then
			local lost = tick(s, u)
			checkEnd(s)
			if s.over or not lost then return end
			if u.alive then log(s, u.name .. " can't move!") end
		end
	end
end

local function unit(side, st)
	local mods = st.mods or {}
	local role = B.Roles[st.role or ""]
	return { side = side, name = st.name, element = st.element, hp = st.hp, maxHp = st.hp, dmg = st.dmg, def = st.def, spd = st.spd,
		skill = B.SkillName[st.element] or "Skill", status = {}, shield = 0, ccImmune = 0, boss = st.boss == true,
		energy = 0, cd = 0, defending = false, alive = true, iid = st.iid, role = st.role, trait = role or {}, mods = mods,
		crit = CRIT + (mods.crit or 0) + (role and role.crit or 0), lastStand = (mods.laststand or 0) > 0 }
end
local function gain(u, n) u.energy = math.min(ULT_COST, u.energy + math.floor(n * (1 + (u.mods.energy or 0)))) end
function E.new(team, enemies, rng: Random)
	local s = { units = {}, round = 0, log = {}, over = false, rng = rng }
	for _, st in team do table.insert(s.units, unit("player", st)) end
	for _, st in enemies do table.insert(s.units, unit("enemy", st)) end
	newRound(s)
	checkEnd(s)
	if not s.over then advance(s) end
	return s
end
function E.current(s) return s.units[s.order[s.turn]], s.order[s.turn] end

function E.hit(s, a, t, mult)
	local dealt = a.status.weaken and B.Status.weaken.dealt or 1
	local def = t.def * (t.status.expose and B.Status.expose.armor or 1)
	local em = E.elementMult(a.element, t.element)
	if em > 1 then em = (em + (a.mods.elemental or 0)) * (1 - math.min(0.5, t.mods.resist or 0)) end
	local dmg = a.dmg * mult * dealt * 100 / (100 + def) * em
	if t.boss then dmg *= 1 + (a.mods.boss or 0) end
	local crit = s.rng:NextNumber() < a.crit
	if crit then dmg *= 1.5 end
	if t.status.mark then dmg *= B.Status.mark.taken end
	dmg *= 1 - math.min(0.5, t.mods.protect or 0)
	if t.defending then dmg *= math.max(0.2, 0.5 - (t.mods.guard or 0)) end
	dmg = math.max(1, math.floor(dmg))
	local absorbed = math.min(t.shield, dmg)
	t.shield -= absorbed
	t.hp = math.max(0, t.hp - (dmg - absorbed))
	if t.hp == 0 and t.lastStand then
		t.hp, t.lastStand = 1, false
		log(s, t.name .. " refuses to fall! (Last Stand)")
	end
	if t.hp == 0 then t.alive = false end
	return dmg, crit
end

-- the element status a skill applies; returns a log suffix
local function applyStatus(a, t)
	local name = B.SkillStatus[a.element]
	local st = name and B.Status[name]
	if not st then return "" end
	local who = st.self and a or t
	if not who.alive then return "" end
	if st.skip and (who.ccImmune > 0 or who.status.freeze or who.status.stun) then return " (" .. who.name .. " resists " .. st.name .. ")" end
	who.status[name] = st.dur + (a.trait.extend or 0)
	if st.absorb then who.shield = math.floor(who.maxHp * st.absorb) end
	if st.cleanse then
		for n in who.status do if not B.Status[n].self then who.status[n] = nil end end
	end
	return " +" .. st.name .. (st.self and "" or " on " .. who.name)
end
-- role traits on skill use: Healer heals the most-hurt ally, Support gives every ally energy
local function roleTrait(s, a)
	local mates = alive(s, a.side)
	if a.trait.heal then
		table.sort(mates, function(x, y) return s.units[x].hp / s.units[x].maxHp < s.units[y].hp / s.units[y].maxHp end)
		local m = s.units[mates[1]]
		local h = math.min(m.maxHp - m.hp, math.floor(m.maxHp * a.trait.heal))
		m.hp += h
		return h > 0 and (", heals " .. m.name .. " " .. h) or ""
	elseif a.trait.energy then
		for _, i in mates do if s.units[i] ~= a then gain(s.units[i], a.trait.energy) end end
		return ", energizes the team"
	end
	return ""
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
		gain(a, 25)
		log(s, a.name .. " hits " .. t.name .. " for " .. d .. (c and " (CRIT!)" or ""))
	elseif action == "skill" then
		local d, c = E.hit(s, a, t, 1.6 * (1 + (a.mods.skillamp or 0)))
		a.cd = SKILL_CD + 1 -- +1: ticks down at the start of its own next turn
		gain(a, 15)
		log(s, a.name .. " uses " .. a.skill .. " on " .. t.name .. " for " .. d .. (c and " (CRIT!)" or "") .. applyStatus(a, t) .. roleTrait(s, a))
	elseif action == "defend" then
		a.defending = true
		gain(a, 20)
		log(s, a.name .. " defends")
	else
		a.energy = 0
		local total = 0
		for _, i in alive(s, foeSide) do
			local foe = s.units[i]
			total += E.hit(s, a, foe, 1.3 * (1 + (a.mods.ultamp or 0)))
			if foe.alive then foe.status.mark = B.Status.mark.dur end
		end
		log(s, a.name .. " unleashes its ULTIMATE for " .. total .. " total damage! Foes are Marked")
	end
	checkEnd(s)
	if not s.over then advance(s) end
	return true
end

-- enemy brain: ult when full; self-buff skills when hurt; defend when low (sometimes);
-- otherwise skill/attack the foe it hits hardest (element), breaking ties on lowest HP
function E.ai(s)
	local a = E.current(s)
	local foes = alive(s, a.side == "enemy" and "player" or "enemy")
	table.sort(foes, function(x, y)
		local ux, uy = s.units[x], s.units[y]
		local ex, ey = E.elementMult(a.element, ux.element), E.elementMult(a.element, uy.element)
		if ex ~= ey then return ex > ey end
		if ux.hp ~= uy.hp then return ux.hp < uy.hp end
		return x < y
	end)
	if a.energy >= ULT_COST then return "ultimate" end
	local st = B.Status[B.SkillStatus[a.element] or ""]
	if a.cd == 0 and st and st.self and a.hp < a.maxHp * 0.5 then return "skill", foes[1] end
	if a.hp < a.maxHp * 0.3 and s.rng:NextNumber() < 0.35 then return "defend" end
	return a.cd == 0 and "skill" or "attack", foes[1]
end
function E.runEnemies(s)
	while not s.over and E.current(s).side == "enemy" do E.act(s, E.ai(s)) end
end

function E.snapshot(s)
	local units = {}
	for _, u in s.units do
		units[#units + 1] = { name = u.name, side = u.side, element = u.element, hp = u.hp, maxHp = u.maxHp, energy = u.energy,
			cd = u.cd, skill = u.skill, defending = u.defending, alive = u.alive, status = table.clone(u.status), shield = u.shield, boss = u.boss, role = u.role }
	end
	local _, idx = E.current(s)
	local order = {}
	for k = s.turn, #s.order do if s.units[s.order[k]].alive then table.insert(order, s.order[k]) end end
	return { units = units, active = idx, order = order, round = s.round, log = s.log, over = s.over, winner = s.winner }
end
return E
