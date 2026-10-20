-- Global leaderboards on OrderedDataStores: online players' values are written every REFRESH seconds and the top 10
-- of each board is published on ReplicatedStorage attribute "Leaderboards" (names + values only, nothing private).
-- Boards are a display; player progression always comes from DataService.
-- Where OrderedDataStores are unavailable (unpublished Studio) the boards rank the players in this server instead.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local DSS = game:GetService("DataStoreService")
local Http = game:GetService("HttpService")
local Data = require(script.Parent.DataService)
local Game = require(script.Parent.Game)

local REFRESH, TOP = 120, 10
local BOARDS = {
	{ id = "earned", name = "Lifetime Earnings", value = function(p) return p.data.LifetimeEarnings end },
	{ id = "rebirths", name = "Rebirths", value = function(p) return p.data.Rebirths end },
	{ id = "unique", name = "Unique Monsters", value = function(p) return Game.unique(p) end },
	{ id = "stages", name = "Battle Progress", value = function(p) return Game.count(p.data.BattleProgress) end },
}
for _, b in BOARDS do
	local ok, store = pcall(DSS.GetOrderedDataStore, DSS, "LB_" .. b.id)
	b.store = ok and store or nil
end
local names = {}
local function nameOf(userId)
	if names[userId] then return names[userId] end
	local pl = Players:GetPlayerByUserId(userId)
	local ok, n = pcall(function() return pl and pl.DisplayName or Players:GetNameFromUserIdAsync(userId) end)
	names[userId] = ok and n or ("Player " .. userId)
	return names[userId]
end

local function refresh()
	local out = { boards = {}, live = true }
	for _, b in BOARDS do
		local entries, ok = {}, false
		if b.store then
			for player, p in Data.all() do
				if p.saveable and not p.released then pcall(b.store.SetAsync, b.store, tostring(p.userId), math.floor(math.min(b.value(p), 2 ^ 53))) end
			end
			local pages
			ok, pages = pcall(b.store.GetSortedAsync, b.store, false, TOP)
			if ok then
				for _, e in pages:GetCurrentPage() do
					table.insert(entries, { name = nameOf(tonumber(e.key)), value = e.value })
				end
			end
		end
		if not ok then -- this server only
			out.live = false
			for player, p in Data.all() do table.insert(entries, { name = player.DisplayName, value = math.floor(b.value(p)) }) end
			table.sort(entries, function(x, y) return x.value > y.value end)
			while #entries > TOP do table.remove(entries) end
		end
		table.insert(out.boards, { id = b.id, name = b.name, entries = entries })
	end
	RS:SetAttribute("Leaderboards", Http:JSONEncode(out))
end
task.spawn(function()
	task.wait(10)
	while true do
		refresh()
		task.wait(REFRESH)
	end
end)
