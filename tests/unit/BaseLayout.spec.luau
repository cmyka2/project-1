-- The core slot/floor rule: slots = 5 + rebirths, floors = min(3, 1 + floor(rebirths/6)).
return function(ctx)
	local T, Loader = ctx.Test, ctx.Loader
	local describe, it, expect = T.describe, T.it, T.expect
	local BaseLayout = Loader.requirePath("ReplicatedStorage.Shared.Util.BaseLayout")

	local function perFloor(r)
		return table.concat(BaseLayout.slotsPerFloor(r), "/")
	end

	describe("BaseLayout", function()
		it("matches every example in the design spec", function()
			expect(BaseLayout.totalSlots(0)).toBe(5)
			expect(BaseLayout.totalSlots(1)).toBe(6)
			expect(BaseLayout.totalSlots(5)).toBe(10)
			expect(BaseLayout.totalSlots(6)).toBe(11)
			expect(BaseLayout.totalSlots(12)).toBe(17)
			expect(BaseLayout.totalSlots(13)).toBe(18)
			expect(perFloor(6)).toBe("5/6")
			expect(perFloor(12)).toBe("5/6/6")
			expect(perFloor(13)).toBe("5/6/7")
		end)

		it("unlocks floor 2 at rebirth 6 and floor 3 at rebirth 12, never more than 3", function()
			for r = 0, 5 do
				expect(BaseLayout.floorCount(r)).toBe(1)
			end
			for r = 6, 11 do
				expect(BaseLayout.floorCount(r)).toBe(2)
			end
			for r = 12, 40 do
				expect(BaseLayout.floorCount(r)).toBe(3)
			end
			expect(BaseLayout.floorUnlockRebirth(2)).toBe(6)
			expect(BaseLayout.floorUnlockRebirth(3)).toBe(12)
		end)

		it("floor 1 always keeps its original five slots once more floors exist", function()
			for r = 6, 30 do
				expect(BaseLayout.slotsPerFloor(r)[1]).toBe(5)
			end
		end)

		it("each rebirth adds exactly one slot, on the highest unlocked floor", function()
			for r = 0, 29 do
				local before, after = BaseLayout.slotsPerFloor(r), BaseLayout.slotsPerFloor(r + 1)
				local totalBefore, totalAfter = 0, 0
				for _, n in before do
					totalBefore += n
				end
				for _, n in after do
					totalAfter += n
				end
				expect(totalAfter - totalBefore).toBe(1)
				-- the new slot id belongs to the top floor
				local layout = BaseLayout.layout(r + 1)
				expect(layout[#layout].Floor).toBe(BaseLayout.floorCount(r + 1))
			end
		end)

		it("slot ids are stable and unique, positions are dense per floor", function()
			for _, r in { 0, 5, 6, 11, 12, 30 } do
				local seen = {}
				local perFloorIndex = {}
				for i, info in BaseLayout.layout(r) do
					expect(info.SlotId).toBe(i)
					expect(seen[info.SlotId]).toBeNil()
					seen[info.SlotId] = true
					perFloorIndex[info.Floor] = (perFloorIndex[info.Floor] or 0) + 1
					expect(info.Index).toBe(perFloorIndex[info.Floor])
				end
			end
		end)

		it("validates slot ids against the layout", function()
			expect(BaseLayout.isValidSlot(1, 0)).toBe(true)
			expect(BaseLayout.isValidSlot(5, 0)).toBe(true)
			expect(BaseLayout.isValidSlot(6, 0)).toBe(false)
			expect(BaseLayout.isValidSlot(0, 0)).toBe(false)
			expect(BaseLayout.isValidSlot(1.5, 3)).toBe(false)
			expect(BaseLayout.isValidSlot(18, 13)).toBe(true)
			expect(BaseLayout.isValidSlot(19, 13)).toBe(false)
		end)

		it("sanitizes bad rebirth counts", function()
			expect(BaseLayout.totalSlots(-3)).toBe(5)
			expect(BaseLayout.totalSlots(0 / 0)).toBe(5)
			expect(BaseLayout.totalSlots(2.7)).toBe(7)
		end)
	end)
end
