--!strict
-- Base slot and floor progression (pure). This is the core rule:
--
--   total slots = 5 + rebirths
--   floors      = min(3, 1 + floor(rebirths / 6))
--
-- Slot ids are stable integers 1..total. Their floor is derived from the
-- rebirth count, so a slot can physically move to a higher floor when that
-- floor unlocks while keeping its id (and the monster placed on it):
--
--   1 floor  (0-5 rebirths):  floor 1 holds every slot (5..10)
--   2 floors (6-11 rebirths): floor 1 = slots 1-5, floor 2 = slots 6..total
--   3 floors (12+ rebirths):  floor 1 = 1-5, floor 2 = 6-11, floor 3 = 12..total
--
-- This satisfies every example in the design spec: 6 rebirths -> 5 + 6,
-- 12 rebirths -> 5 + 6 + 6, 13 rebirths -> 5 + 6 + 7.

export type SlotInfo = {
	SlotId: number,
	Floor: number,
	Index: number, -- 1-based position on its floor
}

local BaseLayout = {}

BaseLayout.BASE_SLOTS = 5
BaseLayout.FLOOR2_SLOTS = 6
BaseLayout.REBIRTHS_PER_FLOOR = 6
BaseLayout.MAX_FLOORS = 3

local function sanitize(rebirths: number): number
	if rebirths ~= rebirths or rebirths < 0 then
		return 0
	end
	return math.floor(rebirths)
end

function BaseLayout.totalSlots(rebirths: number): number
	return BaseLayout.BASE_SLOTS + sanitize(rebirths)
end

function BaseLayout.floorCount(rebirths: number): number
	return math.min(BaseLayout.MAX_FLOORS, 1 + math.floor(sanitize(rebirths) / BaseLayout.REBIRTHS_PER_FLOOR))
end

function BaseLayout.floorOfSlot(slotId: number, rebirths: number): number
	local floors = BaseLayout.floorCount(rebirths)
	if floors == 1 or slotId <= BaseLayout.BASE_SLOTS then
		return 1
	end
	if floors == 2 or slotId <= BaseLayout.BASE_SLOTS + BaseLayout.FLOOR2_SLOTS then
		return 2
	end
	return 3
end

-- Number of slots on each floor, e.g. {5, 6, 7} at 13 rebirths.
function BaseLayout.slotsPerFloor(rebirths: number): { number }
	local counts = {}
	for floor = 1, BaseLayout.floorCount(rebirths) do
		counts[floor] = 0
	end
	for slotId = 1, BaseLayout.totalSlots(rebirths) do
		local floor = BaseLayout.floorOfSlot(slotId, rebirths)
		counts[floor] += 1
	end
	return counts
end

function BaseLayout.layout(rebirths: number): { SlotInfo }
	local out: { SlotInfo } = {}
	local perFloorIndex: { [number]: number } = {}
	for slotId = 1, BaseLayout.totalSlots(rebirths) do
		local floor = BaseLayout.floorOfSlot(slotId, rebirths)
		local index = (perFloorIndex[floor] or 0) + 1
		perFloorIndex[floor] = index
		table.insert(out, { SlotId = slotId, Floor = floor, Index = index })
	end
	return out
end

function BaseLayout.isValidSlot(slotId: number, rebirths: number): boolean
	return slotId == math.floor(slotId) and slotId >= 1 and slotId <= BaseLayout.totalSlots(rebirths)
end

-- Rebirth count at which a given floor unlocks.
function BaseLayout.floorUnlockRebirth(floor: number): number
	return (floor - 1) * BaseLayout.REBIRTHS_PER_FLOOR
end

return BaseLayout
