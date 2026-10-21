-- End-to-end: join -> profile -> plot -> roll -> place -> income -> upgrade -> leave -> rejoin.
return function(ctx)
	local T = ctx.Test
	local describe, it, expect = T.describe, T.it, T.expect
	local G = require("../harness/GameHarness")
	G.boot()

	describe("core loop", function()
		local player
		it("boots every service without errors", function()
			for _, line in G.warnings() do
				assert(not string.find(line, "%[Bootstrap%]"), "bootstrap warning: " .. line)
			end
		end)

		it("loads a new player with defaults and a plot", function()
			player = G.join(1001, "Alice")
			local profile = G.profile(player)
			expect(profile).notToBeNil()
			expect(profile.Currencies.Coins).toBe(100)
			local PlotService = G.service("PlotService")
			expect(PlotService.plotIndex(player)).toBe(1)
			local plot = PlotService.plotModel(1)
			expect(plot:GetAttribute("OwnerUserId")).toBe(1001)
			expect(#plot.Slots:GetChildren()).toBe(5)
		end)

		it("rolls a monster selected by the server", function()
			local result = G.invoke(player, "Roll", "grassland_dice", 1, false)
			expect(result.ok).toBe(true)
			expect(#result.data.Results).toBe(1)
			local profile = G.profile(player)
			expect(profile.Currencies.Coins).toBe(75)
			expect(profile.Discovery.TotalRolls).toBe(1)
			local count = 0
			for _ in profile.Inventory.Monsters do
				count += 1
			end
			expect(count).toBe(1)
		end)

		it("places the monster and earns income", function()
			local profile = G.profile(player)
			local instanceId = next(profile.Inventory.Monsters)
			local result = G.invoke(player, "PlaceMonster", instanceId, 1)
			expect(result.ok).toBe(true)
			expect(profile.Base.PlacedMonsters["1"]).toBe(instanceId)
			local Tycoon = G.service("TycoonService")
			local before = profile.Currencies.Coins
			Tycoon.tick(10)
			local rate = Tycoon.rate(player)
			expect(rate > 0).toBeTruthy()
			expect(profile.Currencies.Coins >= before + math.floor(rate * 10) - 1).toBeTruthy()
		end)

		it("upgrades the placed monster and income rises", function()
			local profile = G.profile(player)
			profile.Currencies.Coins = 10000
			local Tycoon = G.service("TycoonService")
			Tycoon.refreshIncome(player)
			local before = Tycoon.rate(player)
			local instanceId = profile.Base.PlacedMonsters["1"]
			local result = G.invoke(player, "UpgradeMonster", instanceId, 1)
			expect(result.ok).toBe(true)
			Tycoon.refreshIncome(player)
			expect(Tycoon.rate(player) > before).toBeTruthy()
		end)

		it("removes the monster and income drops to zero", function()
			local result = G.invoke(player, "RemoveMonster", 1)
			expect(result.ok).toBe(true)
			local Tycoon = G.service("TycoonService")
			Tycoon.refreshIncome(player)
			expect(Tycoon.rate(player)).toBe(0)
		end)

		it("persists progress across leave and rejoin", function()
			local profile = G.profile(player)
			local coins = profile.Currencies.Coins
			local rolls = profile.Discovery.TotalRolls
			G.leave(player)
			expect(G.profile(player)).toBeNil()
			local again = G.join(1001, "Alice")
			local reloaded = G.profile(again)
			expect(reloaded).notToBeNil()
			expect(reloaded.Discovery.TotalRolls).toBe(rolls)
			expect(math.abs(reloaded.Currencies.Coins - coins) < 1).toBeTruthy()
			player = again
		end)
	end)
end
