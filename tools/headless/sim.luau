-- End-to-end walk through spec §24 against the real server scripts on the mock runtime (see mockrbx.luau).
-- Run from the repo root: tools/headless/target/release/headless tools/headless/sim.luau
local DIR = "tools/headless/"
local R = compile(readfile(DIR .. "mockrbx.luau"), "mockrbx")()
local I, V3, CF, C3 = R.Instance, R.Vector3, R.CFrame, R.Color3
local SRC = "src/server/"
local pass, fail = 0, 0
local function check(cond, what)
	if cond then pass += 1 else fail += 1 print("  FAIL: " .. what) end
end

-- world: Hub.Shops.SummonArea.SummonCore + 2 plots (floor 1 like HubBuildKit.Plot)
local hub = I.new("Folder") hub.Name = "Hub" hub.Parent = R.game.Workspace
local shops = I.new("Folder") shops.Name = "Shops" shops.Parent = hub
local area = I.new("Model") area.Name = "SummonArea" area.Parent = shops
local core = I.new("Part") core.Name = "SummonCore" core.Parent = area
local summon = I.new("ProximityPrompt") summon.Parent = core
local plots = I.new("Folder") plots.Name = "Plots" plots.Parent = hub
for id = 1, 2 do
	local m = I.new("Model") m.Name = "Plot" .. id
	m:SetAttribute("PlotId", id) m:SetAttribute("Owner", "") m:SetAttribute("Color", C3.fromRGB(70, 120, 230))
	local base = I.new("Part") base.Name = "Base" base.Size = V3.new(78, 3, 62) base.CFrame = CF.new(id * 200, 21.5, 0) base.Parent = m
	local sign = I.new("Part") sign.Name = "OwnerSign" sign.Parent = m
	local sg = I.new("SurfaceGui") sg.Parent = sign
	local lab = I.new("TextLabel") lab.Name = "Label" lab.Parent = sg
	local sp = I.new("Part") sp.Name = "SpawnPoint" sp.Parent = m
	for i = 1, 10 do
		local s = I.new("Part") s.Name = "Slot" .. i s.Size = V3.new(8, 1, 8) s.CFrame = CF.new(id * 200, 25, i * 12) s:SetAttribute("SlotIndex", i) s.Parent = m
		local pad = I.new("Part") pad.Name = "Collect" .. i pad.Parent = m
		local g = I.new("SurfaceGui") g.Parent = pad
		local l = I.new("TextLabel") l.Name = "Label" l.Parent = g
	end
	m.Parent = plots
end

R.stubs = { MonsterModel = { build = function(def, v)
	local m = I.new("Model") m.Name = def.id
	local p = I.new("Part") p.Parent = m
	m.PrimaryPart = p
	return m
end } }
for _, s in { "PlotAssigner", "MonsterService", "ChestService", "BattleService", "ProgressService", "LeaderboardService", "MonetizationService" } do R.runScript(SRC .. s .. ".server.luau", s) end
R.run(1)
local Game = R.req(R.SSS.Game)
local F = R.req(R.RS.Monster.Formulas)
local Config = R.req(R.RS.Monster.MonsterConfig)

print("1-3. join, profile, plot, Grassland die")
local A = R.join(1, "Alice")
R.run(2)
check(A:GetAttribute("DataStatus") == "ready", "DataStatus ready, got " .. tostring(A:GetAttribute("DataStatus")))
check(R.state(A) ~= nil, "private State created")
check(A:GetAttribute("PlotId") == 1, "plot assigned")
check(plots.Plot1:GetAttribute("Owner") == "1", "plot owner set")
check(R.attr(A, "Dice").grassland == true and R.attr(A, "SelectedDie") == "grassland", "starts with grassland die")
check(R.store.u_1 ~= nil and R.decode(R.store.u_1)._lock.job == "server-A", "profile created and session-locked")

print("4-5. roll -> backpack + index")
summon.Triggered:Fire(A)
R.run(0.1)
local mons = R.attr(A, "Monsters")
local iid, inst = next(mons)
check(iid ~= nil, "monster awarded")
check(R.attr(A, "Index").D[inst.id] ~= nil, "discovered in index")
check(R.attr(A, "LastRoll").iid == iid, "roll result published")
summon.Triggered:Fire(A) -- spam inside cooldown
R.run(0.05)
local n = 0 for _ in R.attr(A, "Monsters") do n += 1 end
check(n == 1, "roll cooldown enforced")

print("6-7. place -> income")
local ok, err = R.invoke("PlaceMonster", A, 1, iid)
check(ok, "place: " .. tostring(err))
check(R.attr(A, "Placed")["1"] == iid, "placement recorded")
local ips = R.attr(A, "CashPerSec")
check(ips > 0, "earning income")
check(plots.Plot1.Placed and plots.Plot1.Placed:FindFirstChild("Slot1") ~= nil, "monster model on pedestal")
check(select(1, R.invoke("PlaceMonster", A, 2, iid)) == false, "same monster can't take two slots")
check(select(1, R.invoke("PlaceMonster", A, 7, nil)) == false, "locked slot 7 rejected")
local c0 = R.attr(A, "Cash")
R.run(10)
local gained = R.attr(A, "Cash") - c0
check(math.abs(gained - ips * 10) <= ips * 1.01, ("10s income %.1f vs %.1f"):format(gained, ips * 10))

print("8-9. upgrade -> income up")
local p = Game.get(A)
Game.addCash(p, 1e6)
local before = Game.income(p, iid)
ok, err = R.invoke("InventoryAction", A, "upgrade", iid)
check(ok, "upgrade: " .. tostring(err))
check(p.data.Monsters[iid].lvl == 2, "level 2")
check(math.abs(Game.income(p, iid) / before - F.levelMult(2)) < 1e-9, "income x levelMult(2)")
check(select(1, R.invoke("InventoryAction", A, "upgrade", "m999")) == false, "forged iid rejected")

print("10-11. buy + equip die, roll again")
ok, err = R.invoke("DiceAction", A, "buy", "forest")
check(ok and p.data.Dice.forest and p.data.SelectedDie == "forest", "bought forest: " .. tostring(err))
local cash1 = p.data.Cash
check(select(1, R.invoke("DiceAction", A, "buy", "forest")) == false and p.data.Cash >= cash1, "no double charge")
check(select(1, R.invoke("DiceAction", A, "buy", "volcano")) == false, "can't skip dice")
check(select(1, R.invoke("DiceAction", A, "equip", "glitch")) == false, "can't equip unowned")
R.run(1)
summon.Triggered:Fire(A)
R.run(0.1)
n = 0 for _ in p.data.Monsters do n += 1 end
check(n == 2 and p.data.Rolls == 2, "second roll with forest die")

print("12-13. skill node applies exactly once")
local ips0 = Game.incomePerSec(p)
ok, err = R.invoke("BuySkill", A, "coin_collector")
check(ok, "buy coin_collector: " .. tostring(err))
check(math.abs(Game.incomePerSec(p) / ips0 - 1.1) < 1e-9, "income x1.1 exactly")
check(math.abs(R.attr(A, "CashPerSec") / ips0 - 1.1) < 1e-9, "published once too")
ok, err = R.invoke("BuySkill", A, "coin_collector")
check(ok and p.data.Skills.coin_collector == 2 and math.abs(Game.incomePerSec(p) / ips0 - 1.2) < 1e-9, "rank 2 stacks additively once")
check(select(1, R.invoke("BuySkill", A, "golden_pedestals")) == false, "prereq enforced")
check(select(1, R.invoke("BuySkill", A, "nope")) == false, "unknown node rejected")
local spent = p.data.SkillSpent
check(spent == 100 + 300, "skill spend tracked: " .. spent)

print("14-15. chest -> gear -> equip -> stats")
ok, err = R.invoke("ChestAction", A, "open", "wooden")
check(ok and type(err) == "table" and err[1].uid, "chest opened")
local uid = ok and err[1].uid
local st0, inc0 = Game.combat(p, iid), Game.income(p, iid)
ok, err = R.invoke("ChestAction", A, "equip", uid, iid)
check(ok, "equip: " .. tostring(err))
local g = p.data.Gear[uid]
local st1 = Game.combat(p, iid)
local bonus = R.req(R.RS.Monster.GearConfig).RarityById[g.r].income
check(math.abs(Game.income(p, iid) / inc0 - (1 + bonus)) < 1e-9, "gear income bonus")
local statKey = g.t == "weapon" and "dmg" or g.t == "armor" and "hp" or "spd"
check(st1[statKey] >= st0[statKey], "gear stat applied (" .. statKey .. ")")
check(select(1, R.invoke("ChestAction", A, "open", "forest", 0)) == false, "bad batch size")
check(select(1, R.invoke("ChestAction", A, "open", "crystal")) == false, "chest needs die")

print("16-18. team -> battle -> rewards once")
ok, err = R.invoke("BattleAction", A, "team", { iid })
check(ok, "team set: " .. tostring(err))
check(select(1, R.invoke("BattleAction", A, "team", { iid, iid })) == false, "duplicate team member rejected")
check(select(1, R.invoke("BattleAction", A, "team", { "m999" })) == false, "unowned team member rejected")
-- make the team strong enough so the outcome is deterministic
p.data.Monsters[iid].lvl = 50
local snap
ok, snap = R.invoke("BattleAction", A, "start", "grass1")
check(ok, "battle start: " .. tostring(snap))
local guard = 0
local cashB = p.data.Cash
while ok and not snap.over and guard < 60 do
	guard += 1
	local target
	for i, u in snap.units do if u.side == "enemy" and u.alive then target = i break end end
	R.run(0.25)
	ok, snap = R.invoke("BattleAction", A, "act", "attack", target)
end
check(snap and snap.over and snap.winner == "player", "won the battle")
check(p.data.BattleProgress.grass1 == true and (p.data.Materials.forest_essence or 0) >= 1, "progress + materials")
check(math.abs(p.data.Cash - cashB - 500) < 1e-6 + Game.incomePerSec(p) * 20, "cash reward")
local mats = p.data.Materials.forest_essence
R.run(0.25)
check(select(1, R.invoke("BattleAction", A, "act", "attack", 3)) == false and p.data.Materials.forest_essence == mats, "no second payout")
check(select(1, R.invoke("BattleAction", A, "start", "grass3")) == false, "stage gating")
check(select(1, R.invoke("BattleAction", A, "start", "forest1")) == false, "region gating")

print("19-21. rebirth -> slot + floor milestones")
local cost = R.req(R.RS.Monster.RebirthConfig).cost(0)
p.data.Cash = cost
R.run(1.1)
local okNo, errNo = R.invoke("Rebirth", A)
check(not okNo and tostring(errNo):find("Own 2"), "rebirth needs rare monsters: " .. tostring(errNo))
p.data.Cash = cost
for _ = 1, 2 do Game.addMonster(p, Config.ById.solarius, "Normal") end -- 2 Mythics cover the early monster requirements
R.run(1.1)
ok, err = R.invoke("Rebirth", A)
check(ok, "rebirth: " .. tostring(err))
check(p.data.Rebirths == 1 and p.data.Cash < Game.incomePerSec(p) * 2 and Game.slotCount(p) == 6, "rebirth 1: cash reset, 6 slots")
check(p.data.Placed["1"] == iid and p.data.Monsters[iid] and p.data.Gear[uid].m == iid, "monsters/gear/placement kept")
check(p.data.AscensionPoints == 1, "AP awarded")
p.data.Rebirths = 5
p.data.BattleProgress.grass3 = true
p.data.Cash = R.req(R.RS.Monster.RebirthConfig).cost(5)
R.run(1.1)
ok, err = R.invoke("Rebirth", A)
check(ok and p.data.Rebirths == 6 and Game.slotCount(p) == 11, "rebirth 6: 11 slots " .. tostring(err))
check(plots.Plot1:FindFirstChild("Floor2") ~= nil and plots.Plot1.Floor2:FindFirstChild("Slot11") ~= nil, "floor 2 generated with slot 11")
check(plots.Plot1:FindFirstChild("Floor3") == nil, "no floor 3 yet")
-- second monster onto the new floor
local iid2 for k in p.data.Monsters do if k ~= iid then iid2 = k end end
ok, err = R.invoke("PlaceMonster", A, 11, iid2)
check(ok, "place on floor 2: " .. tostring(err))
local okc, errc = R.invoke("PlaceMonster", A, 3, nil)
check(okc == true, "clearing an empty unlocked slot is fine: " .. tostring(errc))
local okd, errd = R.invoke("PlaceMonster", A, 3, iid)
check(okd == false and errd:find("Already placed"), "already placed elsewhere")
check(select(1, R.invoke("PlaceMonster", A, 12, iid2)) == false, "slot 12 locked at rebirth 6")

print("24. another player can't touch Alice")
local B = R.join(2, "Bob")
R.run(2)
check(B:GetAttribute("PlotId") == 2, "Bob gets his own plot")
check(select(1, R.invoke("PlaceMonster", B, 1, iid)) == false, "Bob can't place Alice's monster")
check(select(1, R.invoke("ChestAction", B, "equip", uid, iid)) == false, "Bob can't use Alice's gear")
check(select(1, R.invoke("InventoryAction", B, "sell", { iid })) == false, "Bob can't sell Alice's monster")
check(p.data.Placed["1"] == iid, "Alice's base untouched")
check(B.PlayerGui:FindFirstChild("State") ~= R.state(A), "states are per player")
local C = R.join(3, "Carol")
R.run(2)
check(C:GetAttribute("PlotStatus") == "full" and C:GetAttribute("PlotId") == nil, "third player told plots are full")

print("spam / validation")
local denied = 0
for _ = 1, 30 do
	local ok2 = R.RS.Monster.InventoryAction.OnServerInvoke(A, "fav", iid, true)
	if not ok2 then denied += 1 end
end
check(denied >= 25, "rate limit denies spam (" .. denied .. "/30)")
R.run(2)
check(select(1, R.invoke("InventoryAction", A, "sell", "notatable")) == false, "bad sell args")
check(select(1, R.invoke("InventoryAction", A, "sell", { iid })) == false, "can't sell a placed monster")
check(select(1, R.invoke("PlaceMonster", A, 0 / 0, iid)) == false, "NaN slot rejected")
check(select(1, R.invoke("PlaceMonster", A, 1.5, iid)) == false, "fractional slot rejected")
check(select(1, R.invoke("DiceAction", A, "buy", { "x" })) == false, "table die id rejected")

print("fusion + selling + last-copy protection")
local frost = Config.ById.frostfang
local f1 = Game.addMonster(p, frost, "Normal")
local f2 = Game.addMonster(p, frost, "Normal")
local f3 = Game.addMonster(p, frost, "Normal")
Game.addCash(p, 1e7)
R.run(0.5)
check(select(1, R.invoke("InventoryAction", A, "fuse", f1, { f2, f2 })) == false, "same copy twice rejected")
R.run(0.3)
check(select(1, R.invoke("InventoryAction", A, "fuse", f1, { f1, f2 })) == false, "target as material rejected")
R.run(0.3)
p.data.Monsters[f3].lock = true
check(select(1, R.invoke("InventoryAction", A, "fuse", f1, { f2, f3 })) == false and p.data.Monsters[f2], "locked copy rejected, nothing consumed")
p.data.Monsters[f3].lock = nil
R.run(0.3)
ok, err = R.invoke("InventoryAction", A, "fuse", f1, { f2, f3 })
check(ok and p.data.Monsters[f1].fr == 1 and not p.data.Monsters[f2] and not p.data.Monsters[f3], "fused: " .. tostring(err))
R.run(0.3)
local ok3, msg3, flag = R.invoke("InventoryAction", A, "sell", { f1 })
check(not ok3 and flag == "confirm", "last Epic copy needs confirmation")
R.run(0.3)
local cashS = p.data.Cash
ok, err = R.invoke("InventoryAction", A, "sell", { f1 }, true)
check(ok and not p.data.Monsters[f1] and p.data.Cash > cashS, "confirmed sell pays")
check(p.data.Discovered.frostfang ~= nil, "codex keeps the discovery after selling")

print("progress: quests, milestones, daily, events, boosts")
local P = R.req(R.RS.Monster.ProgressConfig)
local T = R.req(R.RS.Monster.SkillTree)
p.data.Rolls = 10
local cq = p.data.Cash
Game.Changed:Fire(A)
R.run(0.5)
check(p.data.Quests.roll10 == true and p.data.Cash >= cq + 500, "roll10 quest auto-completed with its reward")
for i = 1, 12 do p.data.Discovered[Config.Monsters[i].id] = { Normal = true } end
Game.Changed:Fire(A)
R.run(0.5)
check(p.data.Milestones.unique10 == true, "unique-10 milestone awarded")
local m25 = Game.capacity(p)
for i = 13, 30 do p.data.Discovered[Config.Monsters[i].id] = { Normal = true } end
Game.Changed:Fire(A)
R.run(0.5)
check(p.data.Milestones.unique25 and Game.capacity(p) == m25 + 25, "milestone effect stacks through Game.stat")
local okd, res = R.invoke("ProgressAction", A, "daily")
check(okd and res.day == 1 and p.data.Daily.day == 1, "daily day 1 claimed")
R.run(0.6)
check(select(1, R.invoke("ProgressAction", A, "daily")) == false, "no second claim the same day")
for day = 2, 4 do
	R.timeOffset += 86400
	R.run(0.6)
	okd, res = R.invoke("ProgressAction", A, "daily")
	check(okd and res.day == day, "daily streak day " .. day)
end
check(p.data.Boosts.luck and p.data.Boosts.luck.mult == 2, "day 4 luck boost")
local luckBoosted = Game.luck(p)
p.data.Boosts.luck.ends = os.time and 0 or 0
check(Game.luck(p) < luckBoosted, "boost expires")
local ipsEv = Game.incomePerSec(p)
Game.events = { P.EventById.weekend_income }
check(math.abs(Game.incomePerSec(p) / ipsEv - 2) < 1e-9 and math.abs(Game.incomePerSec(p, true) - ipsEv) < 1e-9, "event doubles live income, not offline")
Game.events = {}
R.run(0.6)
check(select(1, R.invoke("ProgressAction", A, "travel", "DiceShop")) == false, "travel needs Portal Mastery")

print("evolution tree ranks, ascension, respec")
p.data.Cash = 1e6
R.run(0.3)
check(select(1, R.invoke("BuySkill", A, "lucky_charm")) == true, "buy luck node")
local skillSpent = p.data.SkillSpent
R.run(0.3)
check(select(1, R.invoke("BuySkill", A, "eternal_wealth", "ascension")) == true, "ascension node bought with AP")
check(p.data.Ascension.eternal_wealth == 1 and p.data.AscensionPoints == 6, "AP spent: " .. p.data.AscensionPoints)
local ipsA = Game.incomePerSec(p)
R.run(5.5)
local cashR = p.data.Cash
local okR, refund = R.invoke("BuySkill", A, "respec")
check(okR and refund == math.floor(skillSpent * 0.75) and p.data.Skills.coin_collector == nil and p.data.SkillSpent == 0, "respec refunds 75%")
check(p.data.Ascension.eternal_wealth == 1, "respec keeps the Ascension Tree")

print("gear levels, relics, batch chests")
local gu = uid
local lvl0 = p.data.Gear[gu].lvl
local pow0 = R.req(R.RS.Monster.GearConfig).power(p.data.Gear[gu])
Game.addCash(p, 1e7)
R.run(0.3)
check(select(1, R.invoke("ChestAction", A, "upgrade", gu)) and p.data.Gear[gu].lvl == lvl0 + 1, "gear upgraded")
check(R.req(R.RS.Monster.GearConfig).power(p.data.Gear[gu]) > pow0, "gear power up")
local relic = Game.addGear(p, "Epic", "relic")
R.run(0.3)
check(select(1, R.invoke("ChestAction", A, "equip", relic, iid)) == false, "relic slot locked without Equipment Slots")
p.data.Skills.equipment_slots = 1
R.run(0.3)
check(select(1, R.invoke("ChestAction", A, "equip", relic, iid)) == true, "relic equips once unlocked")
local before10 = Game.count(p.data.Gear)
R.run(0.3)
local ok10, got10 = R.invoke("ChestAction", A, "open", "wooden", 10)
check(ok10 and #got10 == 10 and Game.count(p.data.Gear) >= before10 + 10 and p.data.Stats.chests >= 11, "batch of 10: " .. tostring(ok10 and p.data.Stats.chests or got10))

print("team presets + arena")
p.data.Skills.extra_team_preset = 1
R.run(0.3)
check(select(1, R.invoke("BattleAction", A, "team", { iid2 }, 2)) == true and p.data.BattleTeams[2][1] == iid2, "preset 2 saved")
check(select(1, R.invoke("BattleAction", A, "team", { iid2 }, 3)) == false, "preset 3 locked")
R.run(0.3)
check(select(1, R.invoke("BattleAction", A, "preset", 2)) == true and Game.team(p)[1] == iid2, "preset 2 active")
R.run(0.3)
check(select(1, R.invoke("BattleAction", A, "preset", 1)) == true, "back to preset 1")
R.run(0.3)
local okA = R.invoke("BattleAction", A, "start", "grass1")
local arenas = R.game.Workspace:FindFirstChild("Arenas")
check(okA and arenas and #arenas:GetChildren() == 1, "arena built for the battle")
R.run(0.3)
R.invoke("BattleAction", A, "leave")
check(#arenas:GetChildren() == 0, "arena cleaned up on leave")

print("cosmetics + leaderboard")
R.run(0.4)
check(select(1, R.invoke("ShopAction", A, "equip", "title_rookie")) == false, "can't equip unowned")
R.run(0.4)
check(select(1, R.invoke("ShopAction", A, "buy", "title_rookie")) == true and p.data.Cosmetics.title_rookie, "bought title")
R.run(0.4)
check(select(1, R.invoke("ShopAction", A, "equip", "title_rookie")) == true and p.data.Equipped.title == "title_rookie", "equipped title")
R.run(0.4)
check(select(1, R.invoke("ShopAction", A, "buy", "title_weekly")) == false, "earned-only title not for sale")
check(select(1, R.invoke("ShopAction", A, "premium", "title_vip")) == false, "paid item without an id is not on sale")
R.run(12)
local lb = R.RS:GetAttribute("Leaderboards")
check(lb and R.decode(lb).boards[1].entries[1] ~= nil, "leaderboard published (server fallback)")
check(R.decode(R.encode(p.data)) ~= nil, "profile still JSON-serializable")

print("roll-and-earn pass: traits + gems, mutations, fuse machine, die gates, friends")
local Traits = R.req(R.RS.Monster.TraitConfig)
p.data.Gems = 0
R.run(0.3)
check(select(1, R.invoke("InventoryAction", A, "trait", iid)) == false, "trait reroll needs a Gem")
p.data.Gems = 3
local incT = Game.income(p, iid)
R.run(0.3)
local okT, tr = R.invoke("InventoryAction", A, "trait", iid)
check(okT and Traits.TraitById[tr] and p.data.Monsters[iid].tr == tr and p.data.Gems == 2, "trait rerolled for 1 Gem")
check(math.abs(Game.income(p, iid) / incT - Traits.TraitById[tr].income) < 1e-9, "trait multiplies income exactly once")
p.data.Monsters[iid].mu = "golden"
check(math.abs(Game.income(p, iid) / incT - Traits.TraitById[tr].income * 1.5) < 1e-9, "Golden mutation x1.5")
local five = {}
for _ = 1, 5 do table.insert(five, (Game.addMonster(p, Config.ById.rockling, "Normal"))) end
R.run(0.3)
local four = { five[1], five[2], five[3], five[4] }
check(select(1, R.invoke("InventoryAction", A, "upfuse", four)) == false, "fuse machine needs exactly 5")
R.run(0.3)
local okF, outF = R.invoke("InventoryAction", A, "upfuse", five)
check(okF and Config.ById[outF.id].rarity == "Uncommon" and p.data.Monsters[five[1]] == nil, "5 Commons -> 1 Uncommon")
local mixed = {}
for _ = 1, 4 do table.insert(mixed, (Game.addMonster(p, Config.ById.rockling, "Normal"))) end
table.insert(mixed, (Game.addMonster(p, Config.ById.frostfang, "Normal")))
R.run(0.3)
check(select(1, R.invoke("InventoryAction", A, "upfuse", mixed)) == false and p.data.Monsters[mixed[1]] ~= nil, "mixed rarities rejected, nothing consumed")
local ipsF = Game.incomePerSec(p)
p.friends = 2
check(math.abs(Game.incomePerSec(p) / ipsF - 1.2) < 1e-9 and math.abs(Game.incomePerSec(p, true) - Game.incomePerSec(p) / 1.2) < 1e-6 * ipsF, "2 friends: +20% live income, not offline")
p.friends = 0
local savedDice = table.clone(p.data.Dice)
for _, dd in { "desert", "mountain", "volcano", "cave", "heaven", "cosmic" } do p.data.Dice[dd] = true end
R.run(0.3)
local okH, errH = R.invoke("DiceAction", A, "buy", "glitch")
check(not okH and tostring(errH):find("Rebirth 8"), "Glitch Die is rebirth-gated: " .. tostring(errH))
p.data.Dice = savedDice

print("onboarding/retention: auto-place, place best, playtime gifts")
check(next(p.data.Placed) ~= nil, "first roll was auto-placed")
R.run(0.3)
check(select(1, R.invoke("PlaceMonster", A, "best")) == true, "place best")
local bestInc, inc1 = 0, Game.income(p, p.data.Placed["1"])
for id in p.data.Monsters do bestInc = math.max(bestInc, Game.income(p, id)) end
check(math.abs(inc1 - bestInc) < 1e-9 and Game.count(p.data.Placed) == math.min(Game.count(p.data.Monsters), Game.slotCount(p)), "best earners fill every slot")
p.sessionStart = os.time and (R.timeOffset + R.now()) or 0
R.run(0.6)
check(select(1, R.invoke("ProgressAction", A, "gift", 1)) == false, "gift not ready at 0 min")
p.sessionStart -= 125
R.run(0.6)
local okGf, gotGf = R.invoke("ProgressAction", A, "gift", 1)
check(okGf, "2-minute gift claimed: " .. tostring(gotGf))
R.run(0.6)
check(select(1, R.invoke("ProgressAction", A, "gift", 1)) == false, "gift only once per session")

print("robux shop: passes, products, receipts, region policy, rolls")
local Mon = R.req(R.RS.Monster.MonetizationConfig)
local MPS = R.services.MarketplaceService
Mon.PassById.lucky.gamepass, Mon.PassById.triple_roll.gamepass, Mon.ProductById.lucky_10.product, Mon.ProductById.server_luck.product = 222, 333, 111, 444
R.run(1.1)
check(select(2, R.invoke("RobuxAction", A, "pass", "super_lucky")) == "Coming soon", "pass without an id isn't sold")
local base = Game.luck(p)
MPS.PromptGamePassPurchaseFinished:Fire(A, 222, true)
R.run(0.2)
check(p.passes.lucky and math.abs(Game.luck(p) / base - 2) < 1e-9, "Lucky pass: exactly 2x luck")
R.run(1.1)
check(select(2, R.invoke("RobuxAction", A, "pass", "lucky")) == "Already owned", "owned pass not re-sold")
local function receipt(pid, product) return MPS.ProcessReceipt({ PlayerId = A.UserId, PurchaseId = pid, ProductId = product }) end
local lr0 = p.data.LuckyRolls
local dec
R.task.spawn(function() dec = receipt("r-1", 111) end)
R.run(1)
check(tostring(dec):find("PurchaseGranted") and p.data.LuckyRolls == lr0 + 10, "10 Lucky Rolls granted after the save")
R.task.spawn(function() dec = receipt("r-1", 111) end)
R.run(1)
check(tostring(dec):find("PurchaseGranted") and p.data.LuckyRolls == lr0 + 10, "same receipt never grants twice")
local bLuck = Game.luck(Game.get(B))
R.task.spawn(function() receipt("r-2", 444) end)
R.run(1)
check(math.abs(Game.luck(Game.get(B)) / bLuck - 2) < 1e-9, "Server Luck doubles everyone's luck")
Game.serverLuck = { mult = 1, ends = 0 }
p.restricted = true
check(math.abs(Game.luck(p) / base - 1) < 1e-9, "restricted region: paid luck not applied")
R.run(1.1)
check(select(1, R.invoke("RobuxAction", A, "product", "lucky_10")) == false, "restricted region: can't buy luck items")
p.restricted = false
-- rolls: lucky roll consumed, golden every 10th, triple roll pass
p.data.Rolls = 18
local lr1 = p.data.LuckyRolls
local n0 = Game.count(p.data.Monsters)
local lucky0 = p.data.LuckyRolls
p.data.Settings.useLucky = true
R.run(1)
summon.Triggered:Fire(A)
R.run(0.1)
local last = R.attr(A, "LastRoll")
check(p.data.LuckyRolls == lucky0 - 1 and last.special and last.special:find("lucky"), "a Lucky Roll is used up")
R.run(1)
summon.Triggered:Fire(A)
R.run(0.1)
check(R.attr(A, "LastRoll").special and R.attr(A, "LastRoll").special:find("golden"), "20th roll is Golden")
MPS.PromptGamePassPurchaseFinished:Fire(A, 333, true)
R.run(1)
local n1 = Game.count(p.data.Monsters)
summon.Triggered:Fire(A)
R.run(0.1)
check(Game.count(p.data.Monsters) >= n1 + 3 and #R.attr(A, "LastRoll").more >= 2, "Triple Roll rolls 3")
p.data.Settings.useLucky = false
local lucky2 = p.data.LuckyRolls
R.run(1)
summon.Triggered:Fire(A)
R.run(0.1)
check(p.data.LuckyRolls == lucky2, "Lucky Rolls saved when turned off")
-- universal ROLL button: works anywhere, not just at the station
R.run(1)
local nU = Game.count(p.data.Monsters)
check(select(1, R.invoke("RollAction", A, "roll")) == true and Game.count(p.data.Monsters) > nU, "ROLL button rolls from anywhere")
-- codes
R.run(0.6)
local okc2, resc = R.invoke("ProgressAction", A, "code", "  release ")
check(okc2 and p.data.Codes.RELEASE, "code redeemed (case/space-insensitive): " .. tostring(resc))
R.run(0.6)
check(select(1, R.invoke("ProgressAction", A, "code", "RELEASE")) == false, "code only once")
R.run(0.6)
check(select(1, R.invoke("ProgressAction", A, "code", "NOPE")) == false, "bad code")
R.run(0.6)
check(select(1, R.invoke("ProgressAction", A, "setting", "skipBelow", 4)) == true and p.data.Settings.skipBelow == 4, "setting saved")
R.run(0.6)
check(select(1, R.invoke("ProgressAction", A, "setting", "skipBelow", 99)) == false, "bad setting value")

print("22-23. leave + rejoin: everything persists, offline earnings capped")
local saved = { cash = p.data.Cash, mons = Game.count(p.data.Monsters), placed1 = p.data.Placed["1"], gear = Game.count(p.data.Gear), reb = p.data.Rebirths }
local ipsLeave = Game.incomePerSec(p)
R.leave(A)
R.run(3)
local blob = R.decode(R.store.u_1)
check(blob._lock == nil, "lock released on leave")
check(blob.LastOnline ~= nil, "LastOnline stamped by server")
check(plots.Plot1:GetAttribute("Owner") == "" or plots.Plot1:GetAttribute("Owner") == "3", "plot released")
check(C:GetAttribute("PlotId") == 1, "waiting player got the freed plot")
R.timeOffset += 2 * 3600 -- 2 hours offline
local A2 = R.join(1, "Alice")
R.run(3)
local p2 = Game.get(A2)
check(p2 and A2:GetAttribute("DataStatus") == "ready", "rejoined")
check(Game.count(p2.data.Monsters) == saved.mons and p2.data.Placed["1"] == saved.placed1 and Game.count(p2.data.Gear) == saved.gear
	and p2.data.Rebirths == saved.reb and p2.data.Gear[uid].m == iid, "inventory/base/gear/progression restored")
local off = R.attr(A2, "OfflineEarnings")
check(off and math.abs(off.amount - ipsLeave * off.secs) <= ipsLeave * 2 and off.secs >= 7200 and off.secs <= 7210, "offline earnings for ~2h: " .. tostring(off and off.secs))
check(p2.data.Cash >= saved.cash + off.amount - 1, "offline cash awarded")
R.leave(A2)
R.run(3)
R.timeOffset += 48 * 3600
local A3 = R.join(1, "Alice")
R.run(3)
check(R.attr(A3, "OfflineEarnings").secs == F.OFFLINE_CAP, "offline capped at 8h")

print("persistence safety: session lock, outage, migration")
R.store.u_50 = R.encode({ Version = 2, Cash = 777, Rebirths = 0, Monsters = {}, _lock = { job = "server-B", t = R.timeOffset + R.now() } })
local L = R.join(50, "Locked")
R.run(40)
check(L.kicked ~= nil, "kicked while another live server holds the lock")
check(R.decode(R.store.u_50).Cash == 777 and R.decode(R.store.u_50)._lock.job == "server-B", "foreign-locked save untouched")
R.store.u_51 = R.encode({ Version = 2, Cash = 5, Rebirths = 0, _lock = { job = "server-B", t = R.timeOffset + R.now() - 3600 } })
local S1 = R.join(51, "Stale")
R.run(3)
check(Game.get(S1) and Game.get(S1).data.Cash == 5, "expired lock taken over, data kept")
R.failNext = 99
R.store.u_52 = R.encode({ Version = 2, Cash = 999, Rebirths = 3 })
local O = R.join(52, "Outage")
R.run(60)
R.failNext = 0
check(O.kicked ~= nil and R.decode(R.store.u_52).Cash == 999, "load failure kicks, never overwrites with defaults")
R.store.u_53 = R.encode({ Version = 1, Cash = 10, Owned = { ["moss_goblin|Normal"] = 2 }, Placed = { ["1"] = "moss_goblin|Normal" }, Discovered = { moss_goblin = { Normal = true } }, Skills = { start = true }, Rebirths = 0, Dice = { grassland = true }, SelectedDie = "grassland", Gear = {}, NextGearId = 1, BattleProgress = {} })
local Mg = R.join(53, "Migrant")
R.run(3)
local pm = Game.get(Mg)
check(pm and pm.data.Version == 3 and pm.data.Skills.start == 1 and Game.count(pm.data.Monsters) == 2 and pm.data.Monsters[pm.data.Placed["1"]] ~= nil, "v1 save migrated on load")
R.store.u_54 = R.encode({ Version = 99, Cash = 1 })
local Nw = R.join(54, "Future")
R.run(3)
check(Nw.kicked ~= nil and R.decode(R.store.u_54).Version == 99, "newer schema refused")
-- someone else steals the lock mid-session: this server must stop writing
local stolen = R.decode(R.store.u_51)
stolen._lock = { job = "server-C", t = R.timeOffset + R.now() }
stolen.Cash = 4242
R.store.u_51 = R.encode(stolen)
R.run(70) -- autosave
check(R.decode(R.store.u_51).Cash == 4242, "lost lock: no overwrite")
check(S1.kicked ~= nil, "lost lock: player removed")

print("shutdown")
for _, fn in R.closers do R.task.spawn(fn) end
R.run(30)
check(R.decode(R.store.u_53)._lock == nil, "BindToClose saved + released")

local seen = {}
for _, w in R.warnings or {} do local k = w:gsub("%d+", "#") if not seen[k] then seen[k] = true print("WARN " .. w) end end
for _, e in R.errors or {} do print(e) end
print(("\n%d passed, %d failed, %d script errors"):format(pass, fail, R.errors and #R.errors or 0))
if fail > 0 or R.errors then error("simulation failed") end
