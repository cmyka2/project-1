-- High-level helpers for integration tests: boot the real server scripts in
-- the mock engine, join/leave players, call remotes exactly like a client.

local Mock = require("./MockRoblox")
local Loader = require("./Loader")
local Scheduler = require("./Scheduler")

local GameHarness = {}

local booted = false

function GameHarness.boot()
	if booted then
		return
	end
	booted = true
	local bootstrap = Loader.find("ServerScriptService.Server.Bootstrap")
	Loader.runScript(bootstrap)
	Mock.advance(1)
end

function GameHarness.service(name)
	return Loader.requirePath("ServerScriptService.Server.Services." .. name)
end

function GameHarness.module(path)
	return Loader.requirePath(path)
end

function GameHarness.join(userId, name)
	local player = Mock.addPlayer(userId, name)
	Mock.spawnCharacter(player)
	Mock.advance(1)
	return player
end

function GameHarness.leave(player)
	Mock.removePlayer(player)
	Mock.advance(2)
end

function GameHarness.profile(player)
	return GameHarness.service("PlayerDataService").get(player)
end

-- Invokes a request remote as the given client. Returns the RemoteResult table.
function GameHarness.invoke(player, name, ...)
	local remotes = Mock.game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")
	assert(remotes, "Remotes folder missing")
	local remote = remotes:FindFirstChild(name)
	assert(remote, "no remote " .. name)
	local handler = rawget(remote, "_props").OnServerInvoke
	assert(handler, "no OnServerInvoke for " .. name)
	local result
	local args = table.pack(...)
	local thread = coroutine.create(function()
		result = handler(player, table.unpack(args, 1, args.n))
	end)
	local ok, err = coroutine.resume(thread)
	if not ok then
		error(err)
	end
	-- let any yielding handler finish
	local guard = 0
	while coroutine.status(thread) ~= "dead" and guard < 200 do
		Mock.advance(0.25)
		guard += 1
	end
	return result
end

-- Clears per-request cooldowns/rate limits by advancing time.
function GameHarness.wait(seconds)
	Mock.advance(seconds)
end

-- Events pushed to a player since the last clear.
function GameHarness.pushed(player, eventName)
	local out = {}
	for _, entry in Mock.clientEvents[eventName] or {} do
		if entry.player == player then
			table.insert(out, entry.args)
		end
	end
	return out
end

function GameHarness.warnings()
	return Mock.logs.warn
end

GameHarness.Mock = Mock
GameHarness.Scheduler = Scheduler
GameHarness.Loader = Loader

return GameHarness
