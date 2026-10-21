--!strict
-- Equipment bonus aggregation (pure): per-item level scaling and set bonuses.

local EquipmentConfig = require(script.Parent.Parent.Config.EquipmentConfig)
local RarityConfig = require(script.Parent.Parent.Config.RarityConfig)
local Types = require(script.Parent.Parent.Types)

export type Bonuses = {
	AttackPct: number,
	HealthPct: number,
	DefensePct: number,
	SpeedPct: number,
	CritChance: number,
	CritDamage: number,
	ElementDamagePct: number,
	ElementResistPct: number,
	HealingPct: number,
	IncomePct: number,
	LuckPct: number,
}

local EquipMath = {}

local STAT_KEYS = {
	"AttackPct",
	"HealthPct",
	"DefensePct",
	"SpeedPct",
	"CritChance",
	"CritDamage",
	"ElementDamagePct",
	"ElementResistPct",
	"HealingPct",
	"IncomePct",
	"LuckPct",
}
EquipMath.STAT_KEYS = STAT_KEYS

function EquipMath.empty(): Bonuses
	return {
		AttackPct = 0,
		HealthPct = 0,
		DefensePct = 0,
		SpeedPct = 0,
		CritChance = 0,
		CritDamage = 0,
		ElementDamagePct = 0,
		ElementResistPct = 0,
		HealingPct = 0,
		IncomePct = 0,
		LuckPct = 0,
	}
end

function EquipMath.maxLevel(def: EquipmentConfig.EquipmentDef): number
	return EquipmentConfig.MaxLevelBase + RarityConfig.tierOf(def.Rarity)
end

function EquipMath.levelScale(level: number): number
	return 1 + math.max(0, level) * EquipmentConfig.UpgradeStatPerLevel
end

local function addStats(into: Bonuses, stats: EquipmentConfig.EquipStats, scale: number)
	local src = stats :: { [string]: number? }
	local dst = into :: any
	for _, key in STAT_KEYS do
		local v = src[key]
		if v then
			dst[key] += v * scale
		end
	end
end

-- Stats of a single item at its level (no set bonuses).
function EquipMath.itemBonuses(item: Types.EquipmentInstance): Bonuses
	local out = EquipMath.empty()
	local def = EquipmentConfig.Items[item.ItemId]
	if def then
		addStats(out, def.Stats, EquipMath.levelScale(item.Level))
	end
	return out
end

-- All equipment worn by one monster, including set bonuses.
function EquipMath.monsterBonuses(items: { Types.EquipmentInstance }): Bonuses
	local out = EquipMath.empty()
	local setCounts: { [string]: number } = {}
	for _, item in items do
		local def = EquipmentConfig.Items[item.ItemId]
		if def then
			addStats(out, def.Stats, EquipMath.levelScale(item.Level))
			if def.SetId then
				setCounts[def.SetId] = (setCounts[def.SetId] or 0) + 1
			end
		end
	end
	for setId, count in setCounts do
		local set = EquipmentConfig.Sets[setId]
		if set then
			for _, tier in set.Tiers do
				if count >= tier.Pieces then
					addStats(out, tier.Stats, 1)
				end
			end
		end
	end
	return out
end

-- Equipment worn by a monster instance id.
function EquipMath.itemsOn(profile: Types.Profile, monsterInstanceId: string): { Types.EquipmentInstance }
	local out = {}
	for _, item in profile.Inventory.Equipment do
		if item.EquippedTo == monsterInstanceId then
			table.insert(out, item)
		end
	end
	return out
end

-- Can this item be equipped on this monster?
function EquipMath.isCompatible(
	def: EquipmentConfig.EquipmentDef,
	element: string,
	monsterLevel: number
): (boolean, string?)
	if monsterLevel < def.RequiredLevel then
		return false, "Requires monster level " .. def.RequiredLevel
	end
	local elements = def.CompatibleElements
	if elements and not table.find(elements, element) then
		return false, "Only for " .. table.concat(elements, "/") .. " monsters"
	end
	return true, nil
end

return EquipMath
