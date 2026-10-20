-- Client UI smoke test: every client script runs against a real server session on the mock engine, then every
-- button gets clicked (a few rounds, as new panels appear) and every hub prompt triggered. Catches runtime errors
-- in UI code that otherwise only runs in Studio. Layout, visuals and feel still need a real playtest.
-- Run: tools/headless/target/release/headless tools/headless/smoke.luau
local R = compile(readfile("tools/headless/mockrbx.luau"), "mockrbx")()
local kit = R.newInst("ModuleScript", "HubBuildKit")
rawset(kit, "_path", "src/serverstorage/HubBuildKit.luau")
kit.Parent = R.SS
R.stubs = { MonsterModel = { build = function(def)
	local m = R.Instance.new("Model") m.Name = def.id
	m.PrimaryPart = R.Instance.new("Part", m)
	return m
end } }
for _, s in { "HubFallback", "PlotAssigner", "MonsterService", "ChestService", "BattleService", "ProgressService", "LeaderboardService", "MonetizationService" } do
	R.runScript("src/server/" .. s .. ".server.luau", s)
end
R.run(1)
local A = R.join(1, "Alice")
R.run(2)
local Game = R.req(R.SSS.Game)
local Config = R.req(R.RS.Monster.MonsterConfig)
local p = Game.get(A)
Game.addCash(p, 1e9)
p.data.Gems, p.data.LuckyRolls = 20, 5
for _, id in { "moss_goblin", "moss_goblin", "moss_goblin", "frostfang", "solarius", "rockling", "rockling", "rockling", "rockling", "rockling" } do
	Game.addMonster(p, Config.ById[id], "Normal")
end
Game.publish(A, p)
local clients = {}
for _, f in { "HudUI", "BaseUI", "IndexUI", "DiceUI", "ChestUI", "BattleUI", "RebirthUI", "SkillTreeUI", "BackpackUI", "ActionUI", "ExtrasUI", "ShopUI", "RollFX", "GuideUI", "BaseFX" } do
	R.runClient("src/client/" .. f .. ".client.luau", f, A)
	table.insert(clients, f)
end
R.run(3)
local errs0 = R.errors and #R.errors or 0
print(("loaded %d client scripts, %d errors"):format(#clients, errs0))
-- roll a few times so LastRoll / RollFX / toast paths run
local core = R.game.Workspace.Hub.Shops.SummonArea.SummonCore
for _ = 1, 3 do core:FindFirstChildOfClass("ProximityPrompt").Triggered:Fire(A) R.run(1) end
-- trigger every hub prompt (opens the shop/tree/rebirth/index/daily/leaderboard/cosmetic panels)
local PPS = R.services.ProximityPromptService
for _, d in R.game.Workspace.Hub:GetDescendants() do
	if d.ClassName == "ProximityPrompt" then PPS.PromptTriggered:Fire(d) R.run(0.2) end
end
-- click every button, a few rounds
local clicked = 0
for round = 1, 3 do
	for _, d in A.PlayerGui:GetDescendants() do
		if d.ClassName == "TextButton" then
			d.MouseButton1Click:Fire()
			clicked += 1
			R.run(0.25)
		end
	end
end
R.run(5)
print(("clicked %d buttons"):format(clicked))
local seen, n = {}, 0
for _, e in R.errors or {} do
	local key = e:match("^[^\n]*")
	if not seen[key] then seen[key] = true n += 1 print("ERROR " .. e:sub(1, 600)) end
end
print(("%d distinct runtime errors"):format(n))
if n > 0 then error("smoke test failed") end
