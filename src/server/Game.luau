-- Shared server-side player state used by every gameplay script:
--   * the single modifier pipeline (income, luck, combat stats) so no bonus is applied twice,
--   * the economy (the only code that changes Cash),
--   * inventory helpers (monster instances, gear),
--   * publishing to the owning client through a private PlayerGui.State object (other players can't read it).
local RS = game:GetService("ReplicatedStorage")
local Http = game:GetService("HttpService")
local M = RS.Monster
local Config = require(M.MonsterConfig)
local Tree = require(M.SkillTree)
local DiceConfig = require(M.DiceConfig)
local GearConfig = require(M.GearConfig)
local BattleConfig = require(M.BattleConfig)
local Rebirth = require(M.RebirthConfig)
local Luck = require(M.LuckConfig)
local F = require(M.Formulas)
local Data = require(script.Parent.DataService)

local Game = {}
Game.MAX_CASH = 1e15 -- ponytail: plain numbers; switch to a big-number format before costs pass ~1e15
Game.BASE_CAPACITY, Game.MAX_GEAR, Game.TEAM_SIZE = 100, 200, 3
Game.BaseChanged = Instance.new("BindableEvent") -- (player) that player's plot needs a re-render
Game.get = Data.get

function Game.count(t) local n = 0 for _ in t do n += 1 end return n end
function Game.stat(p, effect) return Tree.stat(p.data.Skills, effect) end
function Game.die(p) return DiceConfig.ById[p.data.SelectedDie] or DiceConfig.List[1] end
function Game.luck(p) return Luck.combine(Game.die(p).luck, Game.stat(p, "luck") + p.data.Rebirths * Rebirth.LUCK_BONUS) end
function Game.capacity(p) return Game.BASE_CAPACITY + Game.stat(p, "storage") end
function Game.slotCount(p) return F.slots(p.data.Rebirths) end

function Game.baseIncome(inst)
	local def = inst and Config.ById[inst.id]
	return def and Config.Income[def.rarity] * (Config.VariantIncome[inst.v] or 1) or 0
end
-- summed gear power on a monster instance, optionally of one gear type
function Game.gearBonus(p, iid, gtype: string?)
	local b = 0
	for _, g in p.data.Gear do
		if g.m == iid and (not gtype or g.t == gtype) then b += GearConfig.RarityById[g.r].income end
	end
	return b
end
-- income per second of one instance (lvl overrides its level for upgrade previews)
function Game.income(p, iid, lvl: number?)
	local inst = p.data.Monsters[iid]
	if not inst then return 0 end
	return Game.baseIncome(inst) * F.levelMult(lvl or inst.lvl) * F.fusionMult(inst.fr)
		* (1 + Game.stat(p, "income")) * (1 + Game.gearBonus(p, iid)) * (1 + p.data.Rebirths * Rebirth.INCOME_BONUS)
end
-- only monsters placed on unlocked base slots earn
function Game.incomePerSec(p)
	local total, slots = 0, Game.slotCount(p)
	for sk, iid in p.data.Placed do
		if (tonumber(sk) or math.huge) <= slots then total += Game.income(p, iid) end
	end
	return total
end
function Game.slotOf(p, iid)
	for sk, v in p.data.Placed do if v == iid then return sk end end
	return nil
end
function Game.inTeam(p, iid)
	for _, team in p.data.BattleTeams do if table.find(team, iid) then return true end end
	return false
end
-- battle stats: base -> level/fusion -> gear -> skill tree, one pass
function Game.combat(p, iid)
	local inst = p.data.Monsters[iid]
	local def = inst and Config.ById[inst.id]
	if not def then return nil end
	local st = BattleConfig.monsterStats(def, inst.v)
	local cm = F.combatMult(inst.lvl, inst.fr)
	st.dmg = math.floor(st.dmg * cm * (1 + Game.gearBonus(p, iid, "weapon")) * (1 + Game.stat(p, "damage")))
	st.hp = math.floor(st.hp * cm * (1 + Game.gearBonus(p, iid, "armor")) * (1 + Game.stat(p, "health")))
	st.spd = math.floor(st.spd * (1 + Game.gearBonus(p, iid, "accessory")))
	st.iid = iid
	return st
end

-- ECONOMY: every authoritative cash change goes through these
function Game.addCash(p, amount: number)
	if typeof(amount) ~= "number" or amount ~= amount or amount <= 0 then return end
	amount = math.min(amount, Game.MAX_CASH)
	p.data.Cash = math.min(Game.MAX_CASH, p.data.Cash + amount)
	p.data.LifetimeEarnings = math.min(Game.MAX_CASH, p.data.LifetimeEarnings + amount)
end
function Game.spend(p, amount: number): boolean
	if typeof(amount) ~= "number" or amount ~= amount or amount < 0 or p.data.Cash < amount then return false end
	p.data.Cash -= amount
	return true
end

-- INVENTORY
function Game.addMonster(p, def, variant: string)
	local d = p.data
	local iid = "m" .. d.NextMonsterId
	d.NextMonsterId += 1
	d.Monsters[iid] = { id = def.id, v = variant, lvl = 1, fr = 0, t = os.time() }
	local disc = d.Discovered[def.id] or {}
	local isNew = not disc[variant]
	disc[variant] = true
	d.Discovered[def.id] = disc
	return iid, isNew
end
-- deletes an instance and everything pointing at it (slot, gear, teams). Caller validates first.
function Game.removeMonster(p, iid)
	local d = p.data
	local sk = Game.slotOf(p, iid)
	if sk then d.Placed[sk] = nil end
	for _, g in d.Gear do if g.m == iid then g.m = nil end end
	for _, team in d.BattleTeams do
		local i = table.find(team, iid)
		if i then table.remove(team, i) end
	end
	d.Monsters[iid] = nil
	return sk
end
function Game.addGear(p, rarity: string, gtype: string)
	local d = p.data
	if Game.count(d.Gear) >= Game.MAX_GEAR then return nil end
	local uid = "g" .. d.NextGearId
	d.NextGearId += 1
	d.Gear[uid] = { r = rarity, t = gtype }
	return uid
end

-- PUBLISHING (read-only mirror for the owning client; the server never reads these back)
function Game.state(player: Player)
	local pg = player:FindFirstChildOfClass("PlayerGui") or player:WaitForChild("PlayerGui", 10)
	if not pg then return nil end
	local s = pg:FindFirstChild("State")
	if not s then
		s = Instance.new("ScreenGui") s.Name = "State" s.ResetOnSpawn = false s.Enabled = false s.Parent = pg
	end
	return s
end
local function monsters(p)
	local out = {}
	for iid, m in p.data.Monsters do
		local base, cs = Game.baseIncome(m), Game.combat(p, iid)
		local maxed = m.lvl >= F.MAX_LEVEL
		out[iid] = {
			id = m.id, v = m.v, lvl = m.lvl, fr = m.fr, lock = m.lock, fav = m.fav, t = m.t,
			inc = Game.income(p, iid), nxt = not maxed and Game.income(p, iid, m.lvl + 1) or nil,
			cost = not maxed and F.upgradeCost(base, m.lvl) or nil, fuse = F.fuseCost(base, m.fr),
			sell = F.sellValue(base, m.lvl, Game.stat(p, "sell")), hp = cs and cs.hp, dmg = cs and cs.dmg, spd = cs and cs.spd,
		}
	end
	return out
end
local Sections = {
	Index = function(p)
		local owned = {}
		for _, m in p.data.Monsters do owned[m.id .. "|" .. m.v] = (owned[m.id .. "|" .. m.v] or 0) + 1 end
		return { D = p.data.Discovered, O = owned, R = p.data.Rolls }
	end,
	Monsters = monsters,
	Placed = function(p) return p.data.Placed end,
	Gear = function(p) return p.data.Gear end,
	Skills = function(p) return p.data.Skills end,
	Dice = function(p) return p.data.Dice end,
	BattleProgress = function(p) return p.data.BattleProgress end,
	Team = function(p) return p.data.BattleTeams[1] or {} end,
	Materials = function(p) return p.data.Materials end,
}
-- publish(player, p) sends everything; publish(player, p, "Monsters", "Placed") only those sections
function Game.publish(player: Player, p, ...)
	local s = Game.state(player)
	if not s then return end
	local only = select("#", ...) > 0 and { ... } or nil
	for name, fn in Sections do
		if not only or table.find(only, name) then s:SetAttribute(name, Http:JSONEncode(fn(p))) end
	end
	local d = p.data
	s:SetAttribute("Luck", Game.luck(p))
	s:SetAttribute("MaxTier", Game.die(p).maxTier)
	s:SetAttribute("SelectedDie", Game.die(p).id)
	s:SetAttribute("Slots", Game.slotCount(p))
	s:SetAttribute("Floors", F.floors(d.Rebirths))
	s:SetAttribute("Rebirths", d.Rebirths)
	s:SetAttribute("AscensionPoints", d.AscensionPoints)
	s:SetAttribute("Capacity", Game.capacity(p))
	s:SetAttribute("LifetimeEarnings", d.LifetimeEarnings)
	local ls = player:FindFirstChild("leaderstats")
	if ls and ls:FindFirstChild("Rebirths") then ls.Rebirths.Value = d.Rebirths end
	Game.publishCash(player, p)
end
function Game.publishCash(player: Player, p)
	local ls = player:FindFirstChild("leaderstats")
	if ls and ls:FindFirstChild("Cash") then ls.Cash.Value = math.floor(p.data.Cash) end
	local s = Game.state(player)
	if not s then return end
	s:SetAttribute("Cash", p.data.Cash)
	s:SetAttribute("CashPerSec", Game.incomePerSec(p))
end
-- short-lived message for the owner's HUD
function Game.notify(player: Player, text: string)
	local s = Game.state(player)
	if s then s:SetAttribute("Notice", Http:JSONEncode({ text = text, t = os.clock() })) end
end

function Game.short(n: number)
	for _, u in { { 1e12, "t" }, { 1e9, "b" }, { 1e6, "m" }, { 1e3, "k" } } do
		if n >= u[1] then return (("%.1f"):format(n / u[1]):gsub("%.0$", "")) .. u[2] end
	end
	return n < 100 and (("%.1f"):format(n):gsub("%.0$", "")) or tostring(math.floor(n))
end

return Game
