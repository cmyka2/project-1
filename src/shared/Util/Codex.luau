--!strict
-- Codex (monster collection) helpers shared by server and client.

local MonsterConfig = require(script.Parent.Parent.Config.MonsterConfig)
local RegionConfig = require(script.Parent.Parent.Config.RegionConfig)
local Types = require(script.Parent.Parent.Types)

local Codex = {}

function Codex.totalEntries(): number
	return #MonsterConfig.Order
end

function Codex.discoveredCount(profile: Types.Profile): number
	local n = 0
	for _, id in MonsterConfig.Order do
		if profile.Discovery.DiscoveredMonsters[id] then
			n += 1
		end
	end
	return n
end

function Codex.percent(profile: Types.Profile): number
	local total = Codex.totalEntries()
	if total == 0 then
		return 0
	end
	return math.floor(Codex.discoveredCount(profile) / total * 1000 + 0.5) / 10
end

-- Every rollable monster of a region discovered?
function Codex.regionComplete(profile: Types.Profile, regionId: string): boolean
	if not RegionConfig.Regions[regionId] then
		return false
	end
	local any = false
	for _, id in MonsterConfig.Order do
		local def = MonsterConfig.Monsters[id]
		if def.Region == regionId and MonsterConfig.isRollable(def) then
			any = true
			if not profile.Discovery.DiscoveredMonsters[id] then
				return false
			end
		end
	end
	return any
end

-- Every rollable monster of a rarity discovered?
function Codex.tierComplete(profile: Types.Profile, rarity: string): boolean
	local any = false
	for _, id in MonsterConfig.Order do
		local def = MonsterConfig.Monsters[id]
		if def.Rarity == rarity and MonsterConfig.isRollable(def) then
			any = true
			if not profile.Discovery.DiscoveredMonsters[id] then
				return false
			end
		end
	end
	return any
end

return Codex
