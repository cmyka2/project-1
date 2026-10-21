--!strict
-- Monster instances: creation, discovery bookkeeping (codex) and battle XP.
-- Every way of obtaining a monster (roll, chest, fusion, evolution, trade)
-- goes through MonsterService.create so the codex is always correct.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local MonsterConfig = require(Config:WaitForChild("MonsterConfig"))
local RarityConfig = require(Config:WaitForChild("RarityConfig"))
local GameConfig = require(Config:WaitForChild("GameConfig"))
local StatMath = require(Shared:WaitForChild("Util"):WaitForChild("StatMath"))
local Types = require(Shared:WaitForChild("Types"))
local Modules = script.Parent.Parent:WaitForChild("Modules")
local GameEvents = require(Modules:WaitForChild("GameEvents"))
local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))

type Profile = Types.Profile
type MonsterInstance = Types.MonsterInstance

local MonsterService = {}

function MonsterService.newInstance(profile: Profile, monsterId: string, source: string): MonsterInstance
	return {
		Id = PlayerDataService.nextId(profile, "m"),
		MonsterId = monsterId,
		Level = 1,
		Xp = 0,
		Upgrade = 0,
		Stars = 0,
		Locked = false,
		Favorite = false,
		Source = source,
		Acquired = os.time(),
		Variant = nil,
		EvolvedFrom = nil,
	}
end

-- Records a codex discovery. Returns true when it was the first time.
function MonsterService.discover(player: Player, profile: Profile, monsterId: string, source: string): boolean
	local def = MonsterConfig.Monsters[monsterId]
	if not def then
		return false
	end
	local disc = profile.Discovery
	local rarity = RarityConfig.Rarities[def.Rarity]
	local isNew = disc.DiscoveredMonsters[monsterId] == nil
	if isNew then
		disc.DiscoveredMonsters[monsterId] = os.time()
	end
	if rarity.Tier > disc.HighestRarityTier then
		disc.HighestRarityTier = rarity.Tier
	end
	if rarity.IsRareDiscovery then
		table.insert(
			disc.RareDiscoveries,
			{ MonsterId = monsterId, Rarity = def.Rarity, Time = os.time(), Source = source }
		)
		while #disc.RareDiscoveries > GameConfig.Data.MaxRareDiscoveries do
			table.remove(disc.RareDiscoveries, 1)
		end
	end
	PlayerDataService.changed(player, "Discovery")
	if isNew then
		GameEvents.fire(player, "Discover", { MonsterId = monsterId, Rarity = def.Rarity })
	end
	GameEvents.fire(player, "ObtainRarity", { Tier = rarity.Tier, MonsterId = monsterId })
	return isNew
end

-- Grants XP to a monster; returns levels gained.
function MonsterService.addXp(player: Player, instanceId: string, xp: number): number
	local profile = PlayerDataService.get(player)
	local inst = profile and profile.Inventory.Monsters[instanceId]
	if not profile or not inst or xp <= 0 then
		return 0
	end
	local level, rest, gained = StatMath.applyXp(inst.Level, inst.Xp, xp)
	inst.Level = level
	inst.Xp = rest
	if level > profile.Statistics.HighestMonsterLevel then
		profile.Statistics.HighestMonsterLevel = level
		PlayerDataService.changed(player, "Statistics")
	end
	PlayerDataService.monsterChanged(player, instanceId)
	return gained
end

function MonsterService.def(inst: MonsterInstance): MonsterConfig.MonsterDef?
	return MonsterConfig.Monsters[inst.MonsterId]
end

function MonsterService.init() end

return MonsterService
