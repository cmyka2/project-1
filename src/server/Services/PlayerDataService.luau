--!strict
-- Player data persistence. One server owns a player's profile at a time
-- (session lock stored next to the profile and claimed atomically with
-- UpdateAsync). Gameplay code never touches DataStores: it mutates the
-- in-memory profile from PlayerDataService.get() and then calls changed().
--
-- Lifecycle:
--   PlayerAdded   -> claim lock + migrate + sanitize + settle offline income (one UpdateAsync)
--   autosave      -> every Data.AutosaveInterval (staggered per player), refreshes the lock
--   PlayerRemoving-> services clean up, final save + lock release
--   BindToClose   -> final save + release for everyone, in parallel, bounded by ShutdownTimeout
-- If a load fails the player is kicked; a default profile is NEVER used in place
-- of stored data that failed to load.

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("Config"):WaitForChild("GameConfig"))
local Modifiers = require(Shared:WaitForChild("Util"):WaitForChild("Modifiers"))
local Types = require(Shared:WaitForChild("Types"))
local Modules = script.Parent.Parent:WaitForChild("Modules")
local DataSchema = require(Modules:WaitForChild("DataSchema"))
local OfflineIncome = require(Modules:WaitForChild("OfflineIncome"))
local NetServer = require(Modules:WaitForChild("NetServer"))

type Profile = Types.Profile

export type LoadInfo = {
	IsNew: boolean,
	Offline: OfflineIncome.OfflineResult?,
	Issues: { string },
}

type Session = {
	Key: string,
	LoadedAt: number,
	NextAutosave: number,
	Saving: boolean,
	SaveQueued: boolean,
	LastSaveOk: boolean,
	LastSaveTime: number,
	FailedSaves: number,
	Released: boolean,
	Stolen: boolean,
	LastSeenOverride: number?, -- QA only: pretend the player left at this time
}

type Store = {
	UpdateAsync: (self: any, key: string, transform: (any, any) -> any) -> any,
}

local DATA = GameConfig.Data

local PlayerDataService = {}

local SESSION_ID = if game.JobId ~= "" then game.JobId else HttpService:GenerateGUID(false)
PlayerDataService.SessionId = SESSION_ID

local store: Store? = nil
local usingMock = false
local profiles: { [Player]: Profile } = {}
local sessions: { [Player]: Session } = {}
local loading: { [Player]: boolean } = {}
local releasing: { [number]: boolean } = {} -- userId -> final save in progress on this server
local dirtyKeys: { [Player]: { [string]: boolean } } = {}
local dirtyMonsters: { [Player]: { [string]: boolean } } = {}
local dirtyEquipment: { [Player]: { [string]: boolean } } = {}
local modsCache: { [Player]: { mods: Modifiers.Mods, at: number } } = {}

local onReady: (Player, Profile, LoadInfo) -> ...any = function(
	_player: Player,
	_profile: Profile,
	_info: LoadInfo
)
end
local onRemoving: (Player, Profile) -> ...any = function(_player: Player, _profile: Profile) end

-- Keys whose change can alter aggregated modifiers.
local MOD_KEYS: { [string]: boolean } = {
	Skills = true,
	Progression = true,
	Purchases = true,
	Inventory = true,
	Battle = true,
	Boosts = true,
}

-- In-memory store used only in Studio when API access is disabled.
local function makeMockStore(): Store
	local data: { [string]: string } = {}
	local mock = {}
	function mock.UpdateAsync(_: any, key: string, transform: (any, any) -> any): any
		local raw = data[key]
		local old = if raw then HttpService:JSONDecode(raw) else nil
		local new = transform(old, nil)
		if new ~= nil then
			data[key] = HttpService:JSONEncode(new)
		end
		local stored = data[key]
		return if stored then HttpService:JSONDecode(stored) else nil
	end
	return mock :: any
end

local function retryDelay(attempt: number): number
	return math.min(DATA.RetryBaseDelay * 2 ^ (attempt - 1), DATA.RetryMaxDelay)
end

local function keyFor(player: Player): string
	return DATA.KeyPrefix .. tostring(player.UserId)
end

-- Loading --------------------------------------------------------------------------

local function load(player: Player): (Profile?, LoadInfo?, string?)
	local activeStore = store
	if not activeStore then
		return nil, nil, "DataStores unavailable"
	end
	local key = keyFor(player)
	-- Rejoined this same server before the previous session finished saving.
	local waited = 0
	while releasing[player.UserId] and waited < DATA.ShutdownTimeout do
		waited += task.wait(0.5)
	end

	local lastReason = "unknown error"
	for attempt = 1, DATA.LoadAttempts do
		local now = os.time()
		local captured: { profile: Profile, info: LoadInfo }? = nil
		local lockedBy: string? = nil
		local ok, err = pcall(function()
			activeStore:UpdateAsync(key, function(old: any)
				captured = nil
				lockedBy = nil
				if old ~= nil and typeof(old) ~= "table" then
					error("stored record is not a table")
				end
				local record = old or {}
				local lock = record.Lock
				if
					typeof(lock) == "table"
					and lock.SessionId ~= SESSION_ID
					and typeof(lock.Time) == "number"
					and now - lock.Time < DATA.LockStaleSeconds
				then
					lockedBy = tostring(lock.SessionId)
					return nil -- abort: another server owns this profile
				end
				local isNew = record.Profile == nil
				local profile: Profile
				local issues: { string } = {}
				if isNew then
					profile = DataSchema.default(now)
				else
					local migrated = DataSchema.migrate(record.Profile)
					profile, issues = DataSchema.sanitize(migrated, now)
				end
				local offline: OfflineIncome.OfflineResult? = nil
				if not isNew then
					local result = OfflineIncome.compute(profile, now)
					if result.Coins > 0 then
						profile.Currencies.Coins += result.Coins
						profile.Statistics.LifetimeCoinsEarned += result.Coins
					end
					offline = result
				end
				-- Settling offline income and moving LastSeen happen in the same
				-- atomic write as the lock claim, so the same interval can never be paid twice.
				profile.Timestamps.LastSeen = now
				record.Profile = profile
				record.Lock = { SessionId = SESSION_ID, Time = now, PlaceId = game.PlaceId }
				captured = { profile = profile, info = { IsNew = isNew, Offline = offline, Issues = issues } }
				return record
			end)
		end)
		local result = captured :: { profile: Profile, info: LoadInfo }?
		if ok and result then
			return result.profile, result.info, nil
		end
		if not ok then
			lastReason = tostring(err)
			warn(
				string.format(
					"[Data] load attempt %d/%d failed for %d: %s",
					attempt,
					DATA.LoadAttempts,
					player.UserId,
					lastReason
				)
			)
			if string.find(lastReason, "newer than this server") then
				return nil, nil, "Your data was saved by a newer version of the game. Please rejoin."
			end
		elseif lockedBy then
			lastReason = "locked"
			warn(
				string.format(
					"[Data] profile %d locked by session %s (attempt %d)",
					player.UserId,
					lockedBy,
					attempt
				)
			)
		end
		if attempt < DATA.LoadAttempts then
			if not player.Parent then
				return nil, nil, "left"
			end
			task.wait(if lastReason == "locked" then DATA.LockWaitSeconds else retryDelay(attempt))
		end
	end
	if lastReason == "locked" then
		return nil, nil, "Your data is still being saved by another server. Please rejoin in a moment."
	end
	return nil, nil, "We couldn't load your data right now. Please rejoin. (Nothing was lost.)"
end

-- Saving ---------------------------------------------------------------------------

local function save(player: Player, release: boolean): boolean
	local session = sessions[player]
	local profile = profiles[player]
	local activeStore = store
	if not session or not profile or not activeStore or session.Released then
		return false
	end
	if session.Stolen then
		return false
	end
	if session.Saving then
		-- Another save is in flight; wait for it, then save again so the latest data lands.
		session.SaveQueued = true
		local waited = 0
		while session.Saving and waited < DATA.ShutdownTimeout do
			waited += task.wait(0.25)
		end
		if session.Released then
			return true
		end
	end
	session.Saving = true
	session.SaveQueued = false
	local success = false
	for attempt = 1, DATA.SaveAttempts do
		local now = os.time()
		profile.Timestamps.LastSaved = now
		profile.Timestamps.LastSeen = session.LastSeenOverride or now
		local stolen = false
		local ok, err = pcall(function()
			activeStore:UpdateAsync(session.Key, function(old: any)
				stolen = false
				if
					typeof(old) == "table"
					and typeof(old.Lock) == "table"
					and old.Lock.SessionId ~= SESSION_ID
				then
					stolen = true
					return nil -- never overwrite a profile owned by another server
				end
				return {
					Profile = profile,
					Lock = if release
						then nil
						else { SessionId = SESSION_ID, Time = now, PlaceId = game.PlaceId },
				}
			end)
		end)
		if ok and stolen then
			warn(
				string.format(
					"[Data] session for %d was taken over by another server; not saving",
					player.UserId
				)
			)
			session.Stolen = true
			break
		elseif ok then
			success = true
			break
		end
		warn(
			string.format(
				"[Data] save attempt %d/%d failed for %d: %s",
				attempt,
				DATA.SaveAttempts,
				player.UserId,
				tostring(err)
			)
		)
		if attempt < DATA.SaveAttempts then
			task.wait(retryDelay(attempt))
		end
	end
	session.Saving = false
	if session.Stolen then
		-- Playing on in a session that can no longer save would silently lose progress.
		if player.Parent then
			player:Kick("Your data was opened on another server. Please rejoin.")
		end
		return false
	end
	session.LastSaveOk = success
	session.LastSaveTime = os.time()
	if success then
		session.FailedSaves = 0
		if release then
			session.Released = true
		end
	else
		session.FailedSaves += 1
		if player.Parent then
			NetServer.notify(
				player,
				"error",
				"Saving is having trouble. Your progress will be retried automatically."
			)
		end
	end
	return success
end

-- Public API -------------------------------------------------------------------------

function PlayerDataService.setLifecycle(
	ready: (Player, Profile, LoadInfo) -> ...any,
	removing: (Player, Profile) -> ...any
)
	onReady = ready
	onRemoving = removing
end

function PlayerDataService.get(player: Player): Profile?
	return profiles[player]
end

function PlayerDataService.isReady(player: Player): boolean
	return profiles[player] ~= nil
end

function PlayerDataService.players(): { Player }
	local out = {}
	for player in profiles do
		table.insert(out, player)
	end
	return out
end

function PlayerDataService.isMock(): boolean
	return usingMock
end

-- Marks a top-level profile key as changed (replicated to the client in the next batch).
function PlayerDataService.changed(player: Player, key: string)
	if not profiles[player] then
		return
	end
	local keys = dirtyKeys[player]
	if not keys then
		keys = {}
		dirtyKeys[player] = keys
	end
	keys[key] = true
	keys.__Derived = true
	if MOD_KEYS[key] then
		modsCache[player] = nil
	end
end

function PlayerDataService.monsterChanged(player: Player, instanceId: string)
	local set = dirtyMonsters[player]
	if not set then
		set = {}
		dirtyMonsters[player] = set
	end
	set[instanceId] = true
	PlayerDataService.changed(player, "__Monsters")
end

function PlayerDataService.equipmentChanged(player: Player, instanceId: string)
	local set = dirtyEquipment[player]
	if not set then
		set = {}
		dirtyEquipment[player] = set
	end
	set[instanceId] = true
	PlayerDataService.changed(player, "__Equipment")
	modsCache[player] = nil
end

-- Returns and clears pending replication work for a player.
function PlayerDataService.takeDirty(
	player: Player
): ({ [string]: boolean }?, { [string]: boolean }?, { [string]: boolean }?)
	local keys, monsters, equipment = dirtyKeys[player], dirtyMonsters[player], dirtyEquipment[player]
	dirtyKeys[player] = nil
	dirtyMonsters[player] = nil
	dirtyEquipment[player] = nil
	return keys, monsters, equipment
end

-- Aggregated modifiers, cached briefly (boosts and events are time-based).
function PlayerDataService.mods(player: Player): Modifiers.Mods
	local profile = profiles[player]
	if not profile then
		return {}
	end
	local now = os.time()
	local cached = modsCache[player]
	if cached and now - cached.at < 2 then
		return cached.mods
	end
	local mods = Modifiers.compute(profile, now)
	modsCache[player] = { mods = mods, at = now }
	return mods
end

function PlayerDataService.invalidateMods(player: Player)
	modsCache[player] = nil
end

-- Next unique instance id ("m12", "e7") for monsters/equipment.
function PlayerDataService.nextId(profile: Profile, prefix: string): string
	local n = profile.Inventory.NextId
	profile.Inventory.NextId = n + 1
	return prefix .. tostring(n)
end

function PlayerDataService.saveNow(player: Player): boolean
	return save(player, false)
end

-- QA ("SimulateOffline" cheat): saves from now on record `lastSeen` instead
-- of the current time, so the next join pays offline income for the gap.
function PlayerDataService.setLastSeenOverride(player: Player, lastSeen: number?)
	local session = sessions[player]
	if session then
		session.LastSeenOverride = lastSeen
	end
end

function PlayerDataService.saveStatus(
	player: Player
): { LastSaveOk: boolean, LastSaveTime: number, FailedSaves: number }?
	local session = sessions[player]
	if not session then
		return nil
	end
	return {
		LastSaveOk = session.LastSaveOk,
		LastSaveTime = session.LastSaveTime,
		FailedSaves = session.FailedSaves,
	}
end

-- Replaces a profile wholesale (QA "reset profile" cheat only).
function PlayerDataService.resetProfile(player: Player)
	if not profiles[player] then
		return
	end
	profiles[player] = DataSchema.default(os.time())
	modsCache[player] = nil
	for _, key in
		{
			"Currencies",
			"Progression",
			"Inventory",
			"Base",
			"Skills",
			"Battle",
			"Discovery",
			"Quests",
			"Achievements",
			"DailyRewards",
			"Statistics",
			"Timestamps",
			"Boosts",
			"Crafting",
			"Tutorial",
			"Settings",
			"Exploration",
			"Purchases",
		}
	do
		PlayerDataService.changed(player, key)
	end
	PlayerDataService.changed(player, "__Full")
end

-- Lifecycle --------------------------------------------------------------------------

local function onPlayerAdded(player: Player)
	if loading[player] or profiles[player] then
		return
	end
	loading[player] = true
	local profile, info, reason = load(player)
	loading[player] = nil
	if not profile or not info then
		if player.Parent and reason ~= "left" then
			player:Kick(reason or "Data failed to load.")
		end
		return
	end
	local now = os.time()
	local interval = DATA.AutosaveInterval
	sessions[player] = {
		Key = keyFor(player),
		LoadedAt = now,
		NextAutosave = now + interval + (player.UserId % interval),
		Saving = false,
		SaveQueued = false,
		LastSaveOk = true,
		LastSaveTime = now,
		FailedSaves = 0,
		Released = false,
		Stolen = false,
	}
	profiles[player] = profile
	if #info.Issues > 0 then
		warn(
			string.format(
				"[Data] repaired %d issue(s) in profile %d: %s",
				#info.Issues,
				player.UserId,
				table.concat(info.Issues, "; ")
			)
		)
	end
	if not player.Parent then
		-- Left while loading: release the lock immediately.
		releasing[player.UserId] = true
		save(player, true)
		releasing[player.UserId] = nil
		profiles[player] = nil
		sessions[player] = nil
		return
	end
	onReady(player, profile, info)
end

local finalizing: { [Player]: boolean } = {}

-- Runs exactly once per session: service cleanup, final save, lock release.
local function finalize(player: Player)
	local profile = profiles[player]
	if not profile or finalizing[player] then
		return
	end
	finalizing[player] = true
	releasing[player.UserId] = true
	local ok, err = pcall(onRemoving, player, profile)
	if not ok then
		warn("[Data] cleanup error for " .. player.Name .. ": " .. tostring(err))
	end
	local session = sessions[player]
	if session then
		profile.Statistics.PlayTimeSeconds += math.max(0, os.time() - session.LoadedAt)
	end
	save(player, true)
	releasing[player.UserId] = nil
	profiles[player] = nil
	sessions[player] = nil
	dirtyKeys[player] = nil
	dirtyMonsters[player] = nil
	dirtyEquipment[player] = nil
	modsCache[player] = nil
	finalizing[player] = nil
end

function PlayerDataService.init()
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(DATA.StoreName)
	end)
	if ok and result then
		store = result :: any
		-- Probe: in Studio without API access every request errors.
		if RunService:IsStudio() and DATA.UseMockInStudio then
			local probeOk = pcall(function()
				(result :: any):GetAsync("__probe")
			end)
			if not probeOk then
				warn(
					"[Data] DataStores unavailable in Studio (enable API access to test real saves). Using an in-memory store."
				)
				store = makeMockStore()
				usingMock = true
			end
		end
	elseif RunService:IsStudio() and DATA.UseMockInStudio then
		warn("[Data] DataStoreService unavailable in Studio. Using an in-memory store.")
		store = makeMockStore()
		usingMock = true
	else
		warn("[Data] DataStoreService unavailable: " .. tostring(result))
	end
	NetServer.setReadyCheck(PlayerDataService.isReady)
end

function PlayerDataService.start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(finalize)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	game:BindToClose(function()
		local pending = 0
		for player in profiles do
			pending += 1
			task.spawn(function()
				finalize(player)
				pending -= 1
			end)
		end
		local waited = 0
		local limit = if RunService:IsStudio() then 5 else DATA.ShutdownTimeout
		while pending > 0 and waited < limit do
			waited += task.wait(0.25)
		end
	end)

	-- Staggered autosave loop
	task.spawn(function()
		while true do
			task.wait(5)
			local now = os.time()
			for player, session in sessions do
				if now >= session.NextAutosave and not session.Saving and not session.Released then
					session.NextAutosave = now + DATA.AutosaveInterval
					task.spawn(save, player, false)
				end
			end
		end
	end)
end

return PlayerDataService
