-- Runs the real client code against the real server code in one process:
-- every panel must build, the HUD must render state, and the main client
-- flows (roll, place, battle) must work end to end through the remotes.
return function(ctx)
	local T = ctx.Test
	local describe, it, expect = T.describe, T.it, T.expect
	local G = require("../harness/GameHarness")
	local Mock, Loader, Scheduler = G.Mock, G.Loader, G.Scheduler
	G.boot()

	local player = Mock.addPlayer(2001, "ClientTester")
	Mock.setLocalPlayer(player)
	Mock.spawnCharacter(player)
	Mock.advance(1)
	Loader.runScript(Loader.find("StarterPlayer.StarterPlayerScripts.Client.ClientBootstrap"))
	Mock.advance(5)

	local function controller(name)
		return Loader.requirePath("StarterPlayer.StarterPlayerScripts.Client.Controllers." .. name)
	end

	local function clientWarnings()
		local out = {}
		for _, line in Mock.logs.warn do
			if
				string.find(line, "%[UI%]")
				or string.find(line, "%[Client%]")
				or string.find(line, "%[Signal%]")
			then
				table.insert(out, line)
			end
		end
		return out
	end

	describe("client", function()
		it("boots every controller and receives state", function()
			local State = controller("StateController")
			expect(State.isReady()).toBe(true)
			expect(State.Profile.Currencies.Coins).toBe(100)
			expect(State.Derived.TotalSlots).toBe(5)
			local gui = player.PlayerGui:FindFirstChild("GameUI")
			expect(gui).notToBeNil()
			local warnings = clientWarnings()
			assert(#warnings == 0, table.concat(warnings, "\n"))
		end)

		it("builds every panel without errors", function()
			local UI = controller("UIController")
			local ids = {
				"Roll",
				"Inventory",
				"Equipment",
				"Codex",
				"Base",
				"Battle",
				"Skills",
				"Ascension",
				"Rebirth",
				"Regions",
				"Fusion",
				"Crafting",
				"Chests",
				"Quests",
				"Achievements",
				"Daily",
				"Events",
				"Trade",
				"Leaderboards",
				"Settings",
			}
			for _, id in ids do
				UI.open(id)
				Mock.advance(0.5)
				expect(UI.openId()).toBe(id)
				UI.close()
			end
			Mock.advance(1)
			local warnings = clientWarnings()
			assert(#warnings == 0, table.concat(warnings, "\n"))
			expect(#Scheduler.errors()).toBe(0)
		end)

		it("walks at 2x speed and sprints at 1.5x with Shift or the touch button", function()
			local Enum = require("@lune/roblox").Enum
			local Movement = controller("MovementController")
			local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
			local Begin, End = Enum.UserInputState.Begin, Enum.UserInputState.End
			local Keyboard, Touch = Enum.UserInputType.Keyboard, Enum.UserInputType.Touch
			expect(humanoid.WalkSpeed).toBe(32)
			-- Shift is hold-to-sprint
			Mock.fireAction("Sprint", Begin, Enum.KeyCode.LeftShift, Keyboard)
			expect(Movement.isSprinting()).toBe(true)
			expect(humanoid.WalkSpeed).toBe(48)
			Mock.fireAction("Sprint", End, Enum.KeyCode.LeftShift, Keyboard)
			expect(humanoid.WalkSpeed).toBe(32)
			-- the touch button toggles: releasing it keeps sprinting until the next tap
			Mock.fireAction("Sprint", Begin, Enum.KeyCode.Unknown, Touch)
			Mock.fireAction("Sprint", End, Enum.KeyCode.Unknown, Touch)
			expect(humanoid.WalkSpeed).toBe(48)
			-- a server re-apply (skills changed, respawn) does not cancel the sprint
			G.service("SettingsService").applyMovement(player)
			Mock.advance(0.5)
			expect(humanoid.WalkSpeed).toBe(48)
			Mock.fireAction("Sprint", Begin, Enum.KeyCode.Unknown, Touch)
			expect(Movement.isSprinting()).toBe(false)
			expect(humanoid.WalkSpeed).toBe(32)
			-- respawning ends a toggled sprint and the new character walks at base speed
			Mock.fireAction("Sprint", Begin, Enum.KeyCode.Unknown, Touch)
			Mock.spawnCharacter(player)
			Mock.advance(1)
			expect(Movement.isSprinting()).toBe(false)
			expect(player.Character:FindFirstChildOfClass("Humanoid").WalkSpeed).toBe(32)
		end)

		it("rolls through the real UI path and shows the reveal", function()
			local Roll = controller("RollController")
			local profile = G.profile(player)
			Roll.roll(1, false)
			Mock.advance(8)
			expect(profile.Discovery.TotalRolls).toBe(1)
			local overlay = player.PlayerGui.GameUI.Overlay
			expect(#overlay:GetChildren() > 0).toBeTruthy()
			-- the client replica received the new monster
			local State = controller("StateController")
			Mock.advance(1)
			expect(#State.monsters()).toBe(1)
		end)

		it("places from the inventory and the HUD shows income", function()
			local Inventory = controller("InventoryController")
			local State = controller("StateController")
			local inst = State.monsters()[1]
			Inventory.placeAnywhere(inst.Id)
			Mock.advance(6)
			expect(State.slotOf(inst.Id)).toBe(1)
			expect(State.Derived.TotalIncome > 0).toBeTruthy()
		end)

		it("plays a full battle through the battle screen", function()
			local State = controller("StateController")
			local Net = Loader.requirePath("ReplicatedStorage.Shared.Net")
			local inst = State.monsters()[1]
			expect(Net.request("SetTeam", { inst.Id }).ok).toBe(true)
			G.invoke(player, "Cheat", "MaxLevelTeam")
			Mock.advance(1)
			local result = Net.request("StartBattle", "grassland_1")
			expect(result.ok).toBe(true)
			Mock.advance(3)
			local screen = player.PlayerGui.GameUI.Overlay:FindFirstChild("BattleScreen")
			expect(screen).notToBeNil()
			local Combat = G.service("CombatService")
			for _ = 1, 60 do
				local session = Combat.session(player)
				if not session or session.Finished then
					break
				end
				local battle = session.Battle
				if battle.State == "PlayerTurn" then
					local unit
					for _, u in battle.Units do
						if u.Id == battle.Active then
							unit = u
						end
					end
					local target
					for _, u in battle.Units do
						if u.Side == "Enemy" and u.Alive then
							target = u.Id
						end
					end
					Net.request("BattleAction", battle.Id, "Ability", unit.Abilities[1], target, nil)
				end
				Mock.advance(2)
			end
			local session = Combat.session(player)
			expect(session.Finished).toBe(true)
			expect(session.Battle.State).toBe("Victory")
			Mock.advance(5)
			expect(screen:FindFirstChild("Result")).notToBeNil()
			local warnings = clientWarnings()
			assert(#warnings == 0, table.concat(warnings, "\n"))
		end)
	end)
end
