-- Pure save-data rules: defaults, migrations, session-lock decisions. No Roblox services, so specs can require it.
local S = {}
S.VERSION = 2
S.LOCK_EXPIRE = 300 -- s; a live server refreshes its lock every autosave (60 s), so an older lock is from a dead server
S.MIGRATE_CAP = 300 -- v1 stack counts become at most this many monster instances; the rest are refunded as cash

--[[ v2 profile
	Version, Cash, LifetimeEarnings, Rebirths, AscensionPoints, Rolls, LastOnline (server os.time of last save)
	Dice = { [dieId] = true }, SelectedDie
	Monsters = { [iid] = { id, v (variant), lvl, fr (fusion rank), lock?, fav?, t (created) } }, NextMonsterId
	Placed = { [slot "1".."40"] = iid }
	Gear = { [uid] = { r (rarity), t (type), m (wearer iid)? } }, NextGearId
	Skills = { [nodeId] = true }, Discovered = { [monsterId] = { [variant] = true } }
	BattleProgress = { [stageId] = true }, BattleTeams = { { iid, iid, iid } }, Materials = { [materialId] = n }
	_lock = { job, t } while a server holds the session
]]
function S.default()
	return {
		Version = S.VERSION, Cash = 0, LifetimeEarnings = 0, Rebirths = 0, AscensionPoints = 0, Rolls = 0,
		Dice = { grassland = true }, SelectedDie = "grassland",
		Monsters = {}, NextMonsterId = 1, Placed = {}, Gear = {}, NextGearId = 1,
		Skills = { start = true }, Discovered = {}, BattleProgress = {}, BattleTeams = {}, Materials = {},
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

-- refund(monsterId, variant) -> cash value of one extra copy (also used to rank stacks)
function S.migrate(d, refund: ((string, string) -> number)?)
	refund = refund or function() return 0 end
	d.Version = d.Version or 1
	if d.Version < 2 then v1to2(d, refund) end
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
