--!strict
-- Server side of the network boundary. Creates every remote listed in
-- Shared/Net, wraps every request handler with: profile-ready check, rate
-- limiting, an exclusive in-flight lock, error isolation and a uniform
-- RemoteResult reply. Handlers receive raw `unknown` arguments and must
-- validate them (see Shared/Util/Guard).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Types = require(Shared:WaitForChild("Types"))
local GameConfig = require(Shared:WaitForChild("Config"):WaitForChild("GameConfig"))
local RateLimiter = require(script.Parent.RateLimiter)

export type Result = Types.RemoteResult
export type Handler = (player: Player, ...any) -> Result
export type HandlerOptions = {
	Rate: number?,
	Burst: number?,
	RequireReady: boolean?, -- default true
	Exclusive: boolean?, -- default true: one in-flight request per player per handler
}

local NetServer = {}

local folder: Folder? = nil
local remotes: { [string]: Instance } = {}
local handlers: { [string]: boolean } = {}
local busy: { [Player]: { [string]: boolean } } = {}

local readyCheck: (Player) -> boolean = function(_player: Player)
	return true
end
local rejectHook: (Player, string, string) -> () = function(
	_player: Player,
	_what: string,
	_reason: string
)
end

function NetServer.ok(data: any?): Result
	return { ok = true, err = nil, data = data }
end

function NetServer.fail(message: string, data: any?): Result
	return { ok = false, err = message, data = data }
end

-- For malformed / impossible requests (wrong types, ids the player does not
-- own, forged values). Logged for anti-exploit telemetry; never punishes alone.
function NetServer.invalid(player: Player, what: string): Result
	rejectHook(player, what, "invalid")
	return { ok = false, err = "Invalid request.", data = nil }
end

function NetServer.init()
	if folder then
		return
	end
	local existing = ReplicatedStorage:FindFirstChild(Net.FOLDER_NAME)
	if existing then
		existing:Destroy() -- remotes are always created fresh by this server
	end
	local f = Instance.new("Folder")
	f.Name = Net.FOLDER_NAME
	for _, name in Net.Requests do
		local rf = Instance.new("RemoteFunction")
		rf.Name = name
		rf.Parent = f
		remotes[name] = rf
	end
	for _, name in Net.Events do
		local re = Instance.new("RemoteEvent")
		re.Name = name
		re.Parent = f
		remotes[name] = re
	end
	f.Parent = ReplicatedStorage
	folder = f
	Players.PlayerRemoving:Connect(function(player)
		busy[player] = nil
		RateLimiter.clear(player)
	end)
end

function NetServer.setReadyCheck(fn: (Player) -> boolean)
	readyCheck = fn
end

function NetServer.setRejectHook(fn: (Player, string, string) -> ())
	rejectHook = fn
end

-- Registers the handler for a request. Exactly one handler per request name.
function NetServer.handle(name: string, options: HandlerOptions, handler: Handler)
	assert(folder, "NetServer.init must run first")
	local remote = remotes[name]
	assert(remote and remote:IsA("RemoteFunction"), "unknown request " .. name)
	assert(not handlers[name], "duplicate handler for " .. name)
	handlers[name] = true
	local rate = options.Rate or GameConfig.AntiExploit.DefaultRate
	local burst = options.Burst or GameConfig.AntiExploit.DefaultBurst
	local requireReady = options.RequireReady ~= false
	local exclusive = options.Exclusive ~= false

	remote.OnServerInvoke = function(player: Player, ...: any): Result
		if not RateLimiter.allow(player, name, rate, burst) then
			rejectHook(player, name, "rate")
			return NetServer.fail("Slow down!")
		end
		if requireReady and not readyCheck(player) then
			return NetServer.fail("Your data is still loading...")
		end
		local playerBusy = busy[player]
		if exclusive then
			if not playerBusy then
				playerBusy = {}
				busy[player] = playerBusy
			end
			if playerBusy[name] then
				rejectHook(player, name, "busy")
				return NetServer.fail("Please wait...")
			end
			playerBusy[name] = true
		end
		local results = table.pack(pcall(handler, player, ...))
		if exclusive and playerBusy then
			playerBusy[name] = nil
		end
		if not results[1] then
			warn(
				string.format(
					"[Net] %s handler error for %s (%d): %s",
					name,
					player.Name,
					player.UserId,
					tostring(results[2])
				)
			)
			return NetServer.fail("Something went wrong. Please try again.")
		end
		local result = results[2]
		if typeof(result) ~= "table" then
			warn("[Net] handler " .. name .. " returned no result")
			return NetServer.fail("Something went wrong.")
		end
		return result
	end
end

function NetServer.push(player: Player, eventName: string, ...: any)
	local remote = remotes[eventName]
	if remote and remote:IsA("RemoteEvent") and player.Parent then
		remote:FireClient(player, ...)
	end
end

function NetServer.pushAll(eventName: string, ...: any)
	local remote = remotes[eventName]
	if remote and remote:IsA("RemoteEvent") then
		remote:FireAllClients(...)
	end
end

function NetServer.notify(player: Player, kind: "info" | "success" | "error" | "reward", text: string)
	NetServer.push(player, "Notify", kind, text)
end

-- Test/diagnostic helper: list request names without handlers.
function NetServer.unhandled(): { string }
	local out = {}
	for _, name in Net.Requests do
		if not handlers[name] then
			table.insert(out, name)
		end
	end
	return out
end

-- Test helper: the raw RemoteFunction for a request.
function NetServer.remote(name: string): Instance?
	return remotes[name]
end

return NetServer
