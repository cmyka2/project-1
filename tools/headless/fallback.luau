-- Empty workspace: HubFallback must build every piece the gameplay scripts wait for, then a roll must work.
-- Run from the repo root: tools/headless/target/release/headless tools/headless/fallback.luau
local R = compile(readfile("tools/headless/mockrbx.luau"), "mockrbx")()
local kit = R.newInst("ModuleScript", "HubBuildKit")
rawset(kit, "_path", "src/serverstorage/HubBuildKit.luau")
kit.Parent = R.SS
R.stubs = { MonsterModel = { build = function(def)
	local m = R.Instance.new("Model") m.Name = def.id
	m.PrimaryPart = R.Instance.new("Part", m)
	return m
end } }
for _, s in { "HubFallback", "PlotAssigner", "MonsterService" } do R.runScript("src/server/" .. s .. ".server.luau", s) end
R.run(1)
local hub = R.game.Workspace:FindFirstChild("Hub")
local ok = true
local function check(c, what) if not c then ok = false print("FAIL " .. what) end end
check(hub and hub:FindFirstChild("PlaceholderIsland"), "placeholder island")
check(#hub.Plots:GetChildren() == 8, "8 placeholder plots")
for _, n in { "DiceShop", "ChestShop", "UpgradeTree", "RebirthAltar", "Index" } do
	local m = hub:FindFirstChild(n, true)
	check(m and m:FindFirstChildWhichIsA("ProximityPrompt", true), n .. " placeholder with a prompt")
end
local core = hub.Shops.SummonArea.SummonCore
check(core:FindFirstChildOfClass("ProximityPrompt"), "summon prompt")
local A = R.join(1, "Alice")
R.run(2)
check(A:GetAttribute("PlotId") ~= nil, "plot from generated plots")
core:FindFirstChildOfClass("ProximityPrompt").Triggered:Fire(A)
R.run(0.2)
local n = 0 for _ in R.attr(A, "Monsters") do n += 1 end
check(n == 1, "roll works on the placeholder station")
for _, e in R.errors or {} do ok = false print(e) end
for _, w in R.warnings or {} do print("WARN " .. w) end
print(ok and "fallback ok" or "fallback FAILED")
if not ok then error("fallback failed") end
