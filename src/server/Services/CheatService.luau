--!strict
-- QA cheat commands for reaching any game state quickly. Gated on the server
-- in every call: always allowed in Studio, otherwise only for UserIds listed
-- in GameConfig.Cheats.AllowedUserIds. Commands go through the same service
-- APIs real gameplay uses.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Util = Shared:WaitForChild("Util")
local GameConfig = require(Config:WaitForChild("GameConfig"))
local RegionConfig = require(Config:WaitForChild("RegionConfig"))
local MonsterConfig = require(Config:WaitForChild("MonsterConfig"))
local EquipmentConfig = require(Config:WaitForChild("EquipmentConfig"))
local CraftingConfig = require(Config:WaitForChild("CraftingConfig"))
local RebirthConfig = require(Config:WaitForChild("RebirthConfig"))
local BaseLayout = require(Util:WaitForChild("BaseLayout"))
local Guard = require(Util:WaitForChild("Guard"))
local Types = require(Shared:WaitForChild("Types"))
local Modules = script.Parent.Parent:WaitForChild("Modules")
local NetServer = require(Modules:WaitForChild("NetServer"))
local BattleEngine = require(Modules:WaitForChild("BattleEngine"))
local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))
local EconomyService = require(script.Parent:WaitForChild("EconomyService"))
local InventoryService = require(script.Parent:WaitForChild("InventoryService"))
local PlotService = require(script.Parent:WaitForChild("PlotService"))
local TycoonService = require(script.Parent:WaitForChild("TycoonService"))
local CombatService = require(script.Parent:WaitForChild("CombatService"))
local ReplicationService = require(script.Parent:WaitForChild("ReplicationService"))

type Profile = Types.Profile

local CheatService = {}

function CheatService.isAuthorized(player: Player): boolean
	if RunService:IsStudio() then
		return true
	end
	return table.find(GameConfig.Cheats.AllowedUserIds, player.UserId) ~= nil
end

type Command = (player: Player, profile: Profile, arg: unknown) -> string

local COMMANDS: { [string]: Command } = {
	AddCoins = function(player, _profile, arg)
		local n = Guard.number(arg, 0, 1e30) or 1e6
		EconomyService.grant(player, "Coins", n, "Cheat")
		return "Added coins"
	end,
	AddGems = function(player, _profile, arg)
		EconomyService.grant(player, "Gems", Guard.number(arg, 0, 1e9) or 1000, "Cheat")
		return "Added gems"
	end,
	AddAscension = function(player, _profile, arg)
		EconomyService.grant(player, "AscensionPoints", Guard.number(arg, 0, 1e6) or 10, "Cheat")
		return "Added ascension points"
	end,
	AddMaterials = function(player, _profile, arg)
		local n = Guard.number(arg, 0, 1e9) or 100
		for id in CraftingConfig.Materials do
			EconomyService.grantMaterial(player, id, n)
		end
		return "Added materials"
	end,
	AddTokens = function(player, _profile, arg)
		EconomyService.grant(player, "EventTokens", Guard.number(arg, 0, 1e6) or 50, "Cheat")
		return "Added event tokens"
	end,
	AddRolls = function(player, profile, arg)
		profile.Discovery.TotalRolls += Guard.integer(arg, 0, 1e6) or 200
		PlayerDataService.changed(player, "Discovery")
		return "Roll counter increased (unlocks multi/auto roll)"
	end,
	SetRebirths = function(player, profile, arg)
		local n = Guard.integer(arg, 0, RebirthConfig.MaxRebirths) or 6
		profile.Progression.RebirthCount = n
		profile.Base.UnlockedFloors = BaseLayout.floorCount(n)
		-- drop placements that no longer fit the layout
		for slotKey in profile.Base.PlacedMonsters do
			if not BaseLayout.isValidSlot(tonumber(slotKey) or 0, n) then
				profile.Base.PlacedMonsters[slotKey] = nil
			end
		end
		PlayerDataService.changed(player, "Progression")
		PlayerDataService.changed(player, "Base")
		PlayerDataService.invalidateMods(player)
		PlotService.buildSlots(player)
		return "Rebirths set to " .. n
	end,
	UnlockAllRegions = function(player, profile, _arg)
		for _, id in RegionConfig.Order do
			profile.Progression.UnlockedRegions[id] = true
		end
		profile.Progression.HighestRegion = RegionConfig.Order[#RegionConfig.Order]
		PlayerDataService.changed(player, "Progression")
		return "All regions unlocked"
	end,
	DefeatAllBosses = function(player, profile, _arg)
		for _, id in RegionConfig.Order do
			profile.Progression.BossesDefeated[id] = math.max(1, profile.Progression.BossesDefeated[id] or 0)
		end
		PlayerDataService.changed(player, "Progression")
		return "All bosses marked defeated"
	end,
	GiveMonster = function(player, _profile, arg)
		local id = Guard.string(arg) or "moss_golem"
		if not MonsterConfig.Monsters[id] then
			return "Unknown monster " .. id
		end
		local inst = InventoryService.addMonster(player, id, "Cheat", { IgnoreCapacity = true })
		return if inst then "Gave " .. id else "Failed"
	end,
	GiveAllMonsters = function(player, _profile, _arg)
		for _, id in MonsterConfig.Order do
			InventoryService.addMonster(player, id, "Cheat", { IgnoreCapacity = true })
		end
		return "Gave one of every monster"
	end,
	GiveEquipment = function(player, _profile, arg)
		local id = Guard.string(arg) or "wooden_claws"
		if not EquipmentConfig.Items[id] then
			return "Unknown item " .. id
		end
		InventoryService.addEquipment(player, id, 0, { IgnoreCapacity = true })
		return "Gave " .. id
	end,
	GiveConsumables = function(player, _profile, arg)
		local n = Guard.integer(arg, 1, 1000) or 5
		for id in CraftingConfig.Consumables do
			InventoryService.addConsumable(player, id, n)
		end
		return "Gave consumables"
	end,
	MaxLevelTeam = function(player, profile, _arg)
		for _, id in profile.Battle.Team do
			local inst = profile.Inventory.Monsters[id]
			if inst then
				inst.Level = 50
				PlayerDataService.monsterChanged(player, id)
			end
		end
		return "Team set to level 50"
	end,
	WinBattle = function(player, _profile, _arg)
		local session = CombatService.session(player)
		if not session or session.Finished then
			return "No active battle"
		end
		for _, unit in session.Battle.Units do
			if unit.Side == "Enemy" then
				unit.Hp = 0
				unit.Alive = false
			end
		end
		session.Battle.State = "Running"
		session.Battle.Active = nil
		BattleEngine.advance(session.Battle)
		CombatService.refresh(player)
		return "Battle won"
	end,
	SkipCooldowns = function(player, profile, _arg)
		profile.Progression.EncounterCooldowns = {}
		profile.Timestamps.LastFreeRoll = 0
		profile.Progression.LastRespec = 0
		for _, job in profile.Crafting.Queue do
			job.ReadyAt = os.time()
		end
		PlayerDataService.changed(player, "Progression")
		PlayerDataService.changed(player, "Crafting")
		PlayerDataService.changed(player, "Timestamps")
		return "Cooldowns cleared"
	end,
	ResetDaily = function(player, profile, _arg)
		profile.DailyRewards.LastClaimDay = -1
		profile.Quests.DailyKey = -1
		PlayerDataService.changed(player, "DailyRewards")
		return "Daily reset (rejoin or wait a minute for new daily quests)"
	end,
	SimulateOffline = function(player, profile, arg)
		local seconds = Guard.number(arg, 0, 7 * 86400) or 3600
		local lastSeen = os.time() - seconds
		profile.Timestamps.LastSeen = lastSeen
		PlayerDataService.setLastSeenOverride(player, lastSeen)
		PlayerDataService.saveNow(player)
		return "LastSeen moved back " .. seconds .. "s. Rejoin to collect offline earnings."
	end,
	ResetProfile = function(player, _profile, _arg)
		PlayerDataService.resetProfile(player)
		PlotService.buildSlots(player)
		TycoonService.rebuildDisplays(player)
		return "Profile reset to defaults"
	end,
	Save = function(player, _profile, _arg)
		return if PlayerDataService.saveNow(player) then "Saved" else "Save failed"
	end,
}

function CheatService.commands(): { string }
	local out = {}
	for name in COMMANDS do
		table.insert(out, name)
	end
	table.sort(out)
	return out
end

function CheatService.init()
	NetServer.handle("Cheat", { Rate = 5, Burst = 10 }, function(player, rawCommand, rawArg)
		if not CheatService.isAuthorized(player) then
			return NetServer.invalid(player, "Cheat")
		end
		local profile = PlayerDataService.get(player)
		local name = Guard.string(rawCommand)
		local command = name and COMMANDS[name]
		if not profile or not command then
			return NetServer.fail(
				"Unknown command. Available: " .. table.concat(CheatService.commands(), ", ")
			)
		end
		local message = command(player, profile, rawArg)
		TycoonService.refreshIncome(player)
		ReplicationService.refreshDerived(player)
		return NetServer.ok({ Message = message })
	end)
end

function CheatService.onPlayerReady(player: Player, _profile: Profile)
	if CheatService.isAuthorized(player) then
		NetServer.push(player, "CheatAccess", true, CheatService.commands())
	end
end

return CheatService
