-- Pure save-data rules: defaults, migrations, session-lock decisions. No Roblox services, so specs can require it.
local S = {}
S.VERSION = 3
S.LOCK_EXPIRE = 300 -- s; a live server refreshes its lock every autosave (60 s), so an older lock is from a dead server
S.MIGRATE_CAP = 300 -- v1 stack counts become at most this many monster instances; the rest are refunded as cash

--[[ v3 profile
	Version, Cash, LifetimeEarnings, Rebirths, AscensionPoints, Rolls, LastOnline (server os.time of last save)
	Dice = { [dieId] = true }, SelectedDie
	Monsters = { [iid] = { id, v (variant), lvl, fr (fusion rank), lock?, fav?, t (created) } }, NextMonsterId
	Placed = { [slot "1".."40"] = iid }
	Gear = { [uid] = { r (rarity), t (type), lvl, sec? = { stat, v }, m (wearer iid)? } }, NextGearId
	Skills = { [nodeId] = rank } (cash), SkillSpent, Ascension = { [nodeId] = rank } (AP)
	Discovered = { [monsterId] = { [variant] = true } }
	BattleProgress = { [stageId] = true }, BattleTeams = { { iid, iid, iid }, ... }, ActiveTeam, Materials = { [materialId] = n }
	Stats = { [counter] = n } (quest/leaderboard counters), Quests = { [questId] = true } (claimed),
	Milestones = { [milestoneId] = true }, Daily = { day, last (UTC day number) }, Boosts = { [effect] = { mult, ends } }
	Cosmetics = { [cosmeticId] = true }, Equipped = { title?, aura? }, Receipts = { [purchaseId] = true }
	LuckyRolls (banked 10x-luck rolls), Codes = { [CODE] = true }, Settings = { skipBelow?, useLucky? }
	_lock = { job, t } while a server holds the session
]]
function S.default()
	return {
		Version = S.VERSION, Cash = 0, LifetimeEarnings = 0, Rebirths = 0, AscensionPoints = 0, Rolls = 0,
		Dice = { grassland = true }, SelectedDie = "grassland",
		Monsters = {}, NextMonsterId = 1, Placed = {}, Gear = {}, NextGearId = 1,
		Skills = { start = 1 }, SkillSpent = 0, Ascension = {}, Discovered = {}, BattleProgress = {}, BattleTeams = {}, ActiveTeam = 1,
		Materials = {}, Stats = {}, Quests = {}, Milestones = {}, Daily = { day = 0, last = -1 }, Boosts = {},
		Cosmetics = {}, Equipped = {}, Receipts = {}, LuckyRolls = 0, Codes = {}, Settings = {},
	}
end

-- v1 kept stacks: Owned["id|Variant"] = count, Placed[slot] = "id|Variant", gear followed a slot (g.slot)
local function v1to2(d, refund)
	d.Monsters, d.NextMonsterId = {}, 1
	local stacks = {}
	for k, n in d.Owned or {} do
		local id, v = string.match(k, "^(.-)|(.+)$")
		if id and typeof(n) == "number" and n >= 1 then table.insert(stacks, { id = id, v = v, n = math.floor(n), rank = refund(id, v) }) end
	end
	table.sort(stacks, function(a, b) return a.rank > b.rank end) -- most valuable first survive the cap
	local made, byKey = 0, {}
	for _, st in stacks do
		local keep = math.min(st.n, S.MIGRATE_CAP - made)
		for _ = 1, keep do
			local iid = "m" .. d.NextMonsterId
			d.NextMonsterId += 1
			d.Monsters[iid] = { id = st.id, v = st.v, lvl = 1, fr = 0, t = 0 }
			byKey[st.id .. "|" .. st.v] = byKey[st.id .. "|" .. st.v] or {}
			table.insert(byKey[st.id .. "|" .. st.v], iid)
		end
		made += keep
		d.Cash = (d.Cash or 0) + (st.n - keep) * st.rank
	end
	local placed = {}
	for sk, k in d.Placed or {} do
		local list = byKey[k]
		if list and #list > 0 then placed[sk] = table.remove(list, 1) end
	end
	for _, g in d.Gear or {} do
		g.m = g.slot and placed[g.slot] or nil
		g.slot = nil
	end
	d.Placed, d.Owned = placed, nil
end

-- v2 had a 23-node tree with { [id] = true }; v3 replaced it, so old nodes are refunded at what they cost
S.OLD_TREE_COST = {
	money1 = 100, money2 = 1000, money3 = 10000, money4 = 2e6, money5 = 2e7, sell1 = 5e5, luck1 = 250, luck2 = 2500,
	luck3 = 25000, luck4 = 250000, rollspeed1 = 1e6, rollspeed2 = 1e7, dmg1 = 500, dmg2 = 5000, dmg3 = 50000, hp1 = 1000,
	hp2 = 10000, storage1 = 300, storage2 = 3000, storage3 = 1e6, walk1 = 250000, walk2 = 2500000,
}
local function v2to3(d)
	local refund = 0
	for id, v in d.Skills or {} do
		if v == true then refund += S.OLD_TREE_COST[id] or 0 end
	end
	if refund > 0 or (d.Skills and d.Skills.start == true) then
		d.Skills = { start = 1 }
		d.Cash = (d.Cash or 0) + refund
	end
	for _, g in d.Gear or {} do g.lvl = g.lvl or 1 end
end

-- refund(monsterId, variant) -> cash value of one extra copy (also used to rank stacks)
function S.migrate(d, refund: ((string, string) -> number)?)
	refund = refund or function() return 0 end
	d.Version = d.Version or 1
	if d.Version < 2 then v1to2(d, refund) end
	if d.Version < 3 then v2to3(d) end
	for k, v in S.default() do
		if d[k] == nil then d[k] = v end
	end
	d.Version = S.VERSION
	return d
end

-- may this server (job) take the session? lock = saved _lock or nil
function S.canTake(lock, job: string, now: number): boolean
	return lock == nil or lock.job == job or typeof(lock.t) ~= "number" or now - lock.t >= S.LOCK_EXPIRE
end

return S
