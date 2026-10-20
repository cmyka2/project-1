-- Owns persistent player data: session-locked loads, UpdateAsync saves with retries, autosave, release on leave,
-- best-effort saves on shutdown. Nothing else touches DataStoreService.
-- player attribute DataStatus: "loading" -> "ready" | "unsaved" (Studio without API access) | kicked on failure.
local DSS = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Http = game:GetService("HttpService")
local Schema = require(script.Parent.DataSchema)
local Config = require(game:GetService("ReplicatedStorage").Monster.MonsterConfig)

local STORE, AUTOSAVE, SAVE_SOON = "MonsterRoll_v1", 60, 5
local TRIES = RunService:IsStudio() and 1 or 4 -- Studio without API access fails fast instead of waiting ~30 s
local JOB = game.JobId ~= "" and game.JobId or "studio-" .. Http:GenerateGUID(false)
local storeOk, store = pcall(DSS.GetDataStore, DSS, STORE) -- errors in unpublished places
if not storeOk then warn("DataStore unavailable:", store) store = nil end

local D = {}
local profiles = {} -- [Player] = { data, saveable, userId }
local releasing = {} -- [userId] = true while the leave-save is in flight on this server
local loadedCallbacks = {}

local function key(userId) return "u_" .. userId end
-- extra stacked copies from v1 saves are refunded at their sell value
local function refund(id, v)
	local def = Config.ById[id]
	return def and Config.Income[def.rarity] * (Config.VariantIncome[v] or 1) * 20 or 0
end

-- one UpdateAsync with retries; transform(old) returns the value to write, or nil to cancel
local function update(userId, transform)
	for i = 1, TRIES do
		local ok, err = pcall(store.UpdateAsync, store, key(userId), transform)
		if ok then return true end
		warn(("DataStore UpdateAsync failed for %d (try %d): %s"):format(userId, i, tostring(err)))
		if i < TRIES then task.wait(2 ^ i) end
	end
	return false
end

function D.get(player: Player) return profiles[player] end
function D.all() return profiles end
-- fn(player, profile) runs for every profile once loaded, including ones loaded before fn was registered
function D.onLoaded(fn)
	table.insert(loadedCallbacks, fn)
	for player, p in profiles do task.spawn(fn, player, p) end
end

local function load(player: Player)
	player:SetAttribute("DataStatus", "loading")
	local userId = player.UserId
	while releasing[userId] do task.wait(0.2) end -- quick rejoin: let our own leave-save land first
	local data, status
	if store then
		for attempt = 1, 6 do
			status = nil
			local ok = update(userId, function(old)
				local now = os.time()
				if old and (old.Version or 1) > Schema.VERSION then status = "newer" return nil end
				local studioLock = RunService:IsStudio() and old and old._lock and string.sub(tostring(old._lock.job), 1, 7) == "studio-"
				if old and not studioLock and not Schema.canTake(old._lock, JOB, now) then status = "locked" return nil end -- a crashed Studio test never blocks the next one
				local d = old and Schema.migrate(old, refund) or Schema.default()
				d._lock = { job = JOB, t = now }
				data, status = d, "ok"
				return d
			end)
			if not ok then status = "error" break end
			if status ~= "locked" or not player.Parent then break end
			task.wait(5) -- another server still holds it (usually a server hop that is saving right now)
		end
	end
	if not player.Parent then
		if status == "ok" then update(userId, function(old) if old and old._lock and old._lock.job == JOB then old._lock = nil return old end return nil end) end
		return
	end
	local p
	if status == "ok" then
		p = { data = data, saveable = true, userId = userId, player = player }
	elseif RunService:IsStudio() and status ~= "locked" and status ~= "newer" then
		warn("DataStore unavailable in Studio; playing without saving (publish + enable Studio API access to test saves)")
		p = { data = Schema.default(), saveable = false, userId = userId, player = player }
	else
		-- never start a session that could overwrite a real save with defaults
		warn("Load refused for", player.Name, status)
		player:Kick(status == "locked" and "Your save is still open on another server. Please rejoin in a minute."
			or status == "newer" and "This server is out of date for your save. Please rejoin."
			or "Couldn't load your save. Your data is safe, please rejoin.")
		return
	end
	profiles[player] = p
	player:SetAttribute("DataStatus", p.saveable and "ready" or "unsaved")
	for _, fn in loadedCallbacks do task.spawn(fn, player, p) end
end

-- writes the live table; refuses if another server took the lock (then this session stops saving)
local function save(player: Player, release: boolean?)
	local p = profiles[player]
	if not p or not p.saveable or p.released then return end
	if release then p.released = true end
	local lost = false
	local ok = update(p.userId, function(old)
		if p.released and not release then return nil end -- an autosave racing the leave-save must not re-lock
		if old and old._lock and old._lock.job ~= JOB then lost = true return nil end
		local now = os.time()
		p.data.LastOnline = now
		p.data._lock = not release and { job = JOB, t = now } or nil
		return p.data
	end)
	if lost then
		p.saveable = false
		warn("Session lock lost for", p.userId, "- this server stops saving them")
		if player.Parent then player:Kick("Your save was opened on another server.") end
	elseif not ok then
		warn("Save gave up for", p.userId, "(will retry on next autosave)")
	end
end

-- debounced save after important changes (purchases, rebirth, rewards)
function D.saveSoon(player: Player)
	local p = profiles[player]
	if not p or p.pending then return end
	p.pending = true
	task.delay(SAVE_SOON, function()
		p.pending = false
		if profiles[player] == p then save(player) end
	end)
end

Players.PlayerAdded:Connect(load)
for _, pl in Players:GetPlayers() do task.spawn(load, pl) end
Players.PlayerRemoving:Connect(function(player)
	local p = profiles[player]
	if not p then return end
	releasing[p.userId] = true
	save(player, true)
	profiles[player] = nil
	releasing[p.userId] = nil
end)
task.spawn(function()
	while true do
		task.wait(AUTOSAVE)
		for player in profiles do
			task.spawn(save, player)
			task.wait(0.5) -- spread writes
		end
	end
end)
game:BindToClose(function()
	local left = 0
	for player in profiles do
		left += 1
		task.spawn(function() save(player, true) left -= 1 end)
	end
	local deadline = os.clock() + 25
	while (left > 0 or next(releasing)) and os.clock() < deadline do task.wait() end -- includes leave-saves already running
end)

return D
