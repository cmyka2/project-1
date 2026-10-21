--!strict
-- The single server entry point. Services are initialized in a fixed order
-- (init: create remotes/handlers, no yielding), then started (loops,
-- connections). Player lifecycle hooks also run in this order on join and in
-- reverse order on leave, so dependencies are always ready.

local ServerScriptService = game:GetService("ServerScriptService")

local Server = ServerScriptService:WaitForChild("Server")
local Services = Server:WaitForChild("Services")
local Modules = Server:WaitForChild("Modules")

local NetServer = require(Modules:WaitForChild("NetServer"))

-- Order matters: each service may depend on those listed before it.
local ORDER = {
	"AnalyticsService",
	"PlayerDataService",
	"ReplicationService",
	"AntiExploitService",
	"WorldService",
	"EconomyService",
	"MonsterService",
	"InventoryService",
	"EventService",
	"PlotService",
	"TycoonService",
	"UpgradeService",
	"RollService",
	"RegionService",
	"SkillTreeService",
	"AscensionService",
	"RebirthService",
	"EquipmentService",
	"CraftingService",
	"FusionService",
	"ChestService",
	"CombatService",
	"QuestService",
	"AchievementService",
	"DailyRewardService",
	"TutorialService",
	"LeaderboardService",
	"TradingService",
	"MonetizationService",
	"SettingsService",
	"CheatService",
}

type Service = {
	init: (() -> ...any)?,
	start: (() -> ...any)?,
	onPlayerReady: ((Player, any, any) -> ...any)?,
	onPlayerRemoving: ((Player, any) -> ...any)?,
}

NetServer.init()

local loaded: { { name: string, service: Service } } = {}
for _, name in ORDER do
	local module = Services:FindFirstChild(name)
	if module and module:IsA("ModuleScript") then
		local ok, result = pcall(require, module)
		if ok then
			table.insert(loaded, { name = name, service = result :: Service })
		else
			warn(string.format("[Bootstrap] failed to load %s: %s", name, tostring(result)))
		end
	else
		warn("[Bootstrap] missing service " .. name)
	end
end

for _, entry in loaded do
	local init = entry.service.init
	if init then
		local ok, err = pcall(init)
		if not ok then
			warn(string.format("[Bootstrap] %s.init failed: %s", entry.name, tostring(err)))
		end
	end
end

local missingHandlers = NetServer.unhandled()
if #missingHandlers > 0 then
	warn("[Bootstrap] requests without handlers: " .. table.concat(missingHandlers, ", "))
end

local PlayerDataService = require(Services:WaitForChild("PlayerDataService")) :: any
PlayerDataService.setLifecycle(function(player: Player, profile: any, info: any)
	for _, entry in loaded do
		local hook = entry.service.onPlayerReady
		if hook then
			local ok, err = pcall(hook, player, profile, info)
			if not ok then
				warn(
					string.format(
						"[Bootstrap] %s.onPlayerReady failed for %s: %s",
						entry.name,
						player.Name,
						tostring(err)
					)
				)
			end
		end
	end
end, function(player: Player, profile: any)
	for i = #loaded, 1, -1 do
		local entry = loaded[i]
		local hook = entry.service.onPlayerRemoving
		if hook then
			local ok, err = pcall(hook, player, profile)
			if not ok then
				warn(
					string.format(
						"[Bootstrap] %s.onPlayerRemoving failed for %s: %s",
						entry.name,
						player.Name,
						tostring(err)
					)
				)
			end
		end
	end
end)

for _, entry in loaded do
	local start = entry.service.start
	if start then
		task.spawn(function()
			local ok, err = pcall(start)
			if not ok then
				warn(string.format("[Bootstrap] %s.start failed: %s", entry.name, tostring(err)))
			end
		end)
	end
end

local server = workspace:FindFirstChild("ServerReady")
if not server then
	local flag = Instance.new("BoolValue")
	flag.Name = "ServerReady"
	flag.Value = true
	flag.Parent = workspace
end
print(string.format("[MonsterRoll] server started with %d services", #loaded))
