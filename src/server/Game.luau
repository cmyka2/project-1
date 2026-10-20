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
local Progress = require(M.ProgressConfig)
local Mon = require(M.MonetizationConfig)
local Traits = require(M.TraitConfig)
local Data = require(script.Parent.DataService)

local Game = {}
Game.MAX_CASH = 1e15 -- ponytail: plain numbers; switch to a big-number format before costs pass ~1e15
Game.BASE_CAPACITY, Game.MAX_GEAR, Game.TEAM_SIZE = 100, 200, 3
Game.BaseChanged = Instance.new("BindableEvent") -- (player) that player's plot needs a re-render
Game.Changed = Instance.new("BindableEvent") -- (player) progress counters moved: quests/milestones re-check
Game.events = {} -- active ProgressConfig events, kept current by ProgressService
Game.biome = nil -- active ProgressConfig biome (server-wide weather), kept current by ProgressService
Game.serverLuck = { mult = 1, ends = 0 } -- bought Server Luck, kept by MonetizationService
Game.rng = Random.new()
Game.get = Data.get

function Game.count(t) local n = 0 for _ in t do n += 1 end return n end
-- every permanent bonus source in one sum: Evolution Tree ranks + Ascension ranks + collection milestones + gamepasses
-- (p.passes = gamepasses owned this session; Roblox, not our save, is the source of truth for those)
function Game.stat(p, effect)
	local d = p.data
	local s = Tree.stat(d.Skills, effect) + Tree.stat(d.Ascension, effect, Tree.AscById) + Mon.passStat(p.passes or {}, effect)
	for _, m in Progress.Milestones do
		if m.effects and m.effects[effect] and d.Milestones[m.id] then s += m.effects[effect] end
	end
	return s
end
-- temporary multipliers (events x personal boosts); never used for offline earnings
function Game.boost(p, effect)
	local b = p.data.Boosts[effect]
	return Progress.eventMult(Game.events, effect) * (b and b.ends > os.time() and b.mult or 1)
end
function Game.die(p) return DiceConfig.ById[p.data.SelectedDie] or DiceConfig.List[1] end
-- additive luck (skills, ascension, milestones, rebirths); shown in the dice shop to preview every die
function Game.luckAdd(p) return Game.stat(p, "luck") + p.data.Rebirths * Rebirth.LUCK_BONUS end
-- every luck multiplier, applied after diminishing returns: events and personal boosts (daily, potions),
-- Server Luck, Premium, and luck gamepasses (not for players whose region restricts paid random items)
function Game.luckMult(p)
	local m = Game.boost(p, "luck")
	if Game.serverLuck.ends > os.time() then m *= Game.serverLuck.mult end
	if p.premium then m *= Mon.PREMIUM_LUCK end
	if not p.restricted then m *= Mon.passStat(p.passes or {}, "luckMult") end
	return m
end
-- effective luck for a roll; extra = per-roll multiplier (Golden / Rainbow / Lucky roll)
function Game.luck(p, extra: number?) return Luck.combine(Game.die(p).luck, Game.luckAdd(p), Game.luckMult(p) * (extra or 1)) end
-- the active biome as the roll pool expects it
function Game.biomeBoost() return Game.biome and { element = Game.biome.element, mult = Game.biome.mult } or nil end
function Game.capacity(p) return Game.BASE_CAPACITY + Game.stat(p, "storage") end
function Game.slotCount(p) return F.slots(p.data.Rebirths) end
local function cut(p, effect) return 1 - math.min(0.5, Game.stat(p, effect)) end -- discounts cap at 50%
function Game.upgradeCost(p, inst) return math.floor(F.upgradeCost(Game.baseIncome(inst), inst.lvl) * cut(p, "upgradecost")) end
function Game.fuseCost(p, inst) return math.floor(F.fuseCost(Game.baseIncome(inst), inst.fr) * cut(p, "fusecost")) end
function Game.fuseCopies(p) return math.max(2, F.FUSE_COPIES - Game.stat(p, "fusecopies")) end
function Game.chestCost(p, chest) return math.floor(chest.cost * cut(p, "chestcost")) end
function Game.offlineCap(p) return F.OFFLINE_CAP + math.floor(Game.stat(p, "offline")) * 3600 end
function Game.presets(p) return 1 + math.floor(Game.stat(p, "presets")) end
function Game.team(p) return p.data.BattleTeams[math.min(p.data.ActiveTeam, Game.presets(p))] or {} end
function Game.unique(p)
	local n = 0
	for _, vs in p.data.Discovered do for _ in vs do n += 1 end end
	return n
end
-- counters for quests/leaderboards (rolls and discoveries are derived elsewhere)
function Game.bump(p, key: string, n: number?)
	p.data.Stats[key] = (p.data.Stats[key] or 0) + (n or 1)
	if p.player then Game.Changed:Fire(p.player) end
end

function Game.baseIncome(inst)
	local def = inst and Config.ById[inst.id]
	return def and Config.Income[def.rarity] * (Config.VariantIncome[inst.v] or 1) or 0
end
-- summed gear power on a monster instance. gtype = nil: everything (income); a type: that type + relics (combat)
function Game.gearBonus(p, iid, gtype: string?)
	local b = 0
	for _, g in p.data.Gear do
		if g.m == iid and (not gtype or g.t == gtype or g.t == "relic") then b += GearConfig.power(g) end
	end
	return b
end
function Game.gearSec(p, iid, stat: string)
	local b = 0
	for _, g in p.data.Gear do
		if g.m == iid and g.sec and g.sec.stat == stat then b += g.sec.v end
	end
	return b
end
-- playing with friends: +10% income per friend in the server, up to +50% (live income only, like Steal a Brainrot)
function Game.friendMult(p) return 1 + math.min(0.5, 0.1 * (p.friends or 0)) end
-- income per second of one instance (lvl overrides its level for upgrade previews; offline drops temporary boosts)
function Game.income(p, iid, lvl: number?, offline: boolean?)
	local inst = p.data.Monsters[iid]
	if not inst then return 0 end
	return Game.baseIncome(inst) * F.levelMult(lvl or inst.lvl) * F.fusionMult(inst.fr) * Traits.incomeMult(inst)
		* (1 + Game.stat(p, "income")) * (1 + Game.gearBonus(p, iid) + Game.gearSec(p, iid, "income"))
		* (1 + p.data.Rebirths * Rebirth.INCOME_BONUS) * (offline and 1 or Game.boost(p, "income") * Game.friendMult(p))
end
-- only monsters placed on unlocked base slots earn
function Game.incomePerSec(p, offline: boolean?)
	local total, slots = 0, Game.slotCount(p)
	for sk, iid in p.data.Placed do
		if (tonumber(sk) or math.huge) <= slots then total += Game.income(p, iid, nil, offline) end
	end
	return total
end
function Game.slotOf(p, iid)
	for sk, v in p.data.Placed do if v == iid then return sk end end
	return nil
end
-- battle stats, one pass: base (role) -> level/fusion -> gear -> skill tree; mods feed BattleEngine
function Game.combat(p, iid)
	local inst = p.data.Monsters[iid]
	local def = inst and Config.ById[inst.id]
	if not def then return nil end
	local st = BattleConfig.monsterStats(def, inst.v)
	local cm = F.combatMult(inst.lvl, inst.fr) * Traits.combatMult(inst)
	st.dmg = math.floor(st.dmg * cm * (1 + Game.gearBonus(p, iid, "weapon")) * (1 + Game.stat(p, "damage")))
	st.hp = math.floor(st.hp * cm * (1 + Game.gearBonus(p, iid, "armor")) * (1 + Game.stat(p, "health")))
	st.def = math.floor(st.def * (1 + Game.stat(p, "defense")))
	st.spd = math.floor(st.spd * (1 + Game.gearBonus(p, iid, "accessory")))
	st.mods = {
		crit = Game.stat(p, "crit") + Game.gearSec(p, iid, "crit"), energy = Game.stat(p, "energy") + Game.gearSec(p, iid, "energy"),
		elemental = Game.stat(p, "elemental"), boss = Game.stat(p, "boss"), skillamp = Game.stat(p, "skillamp"),
		ultamp = Game.stat(p, "ultamp"), regen = Game.stat(p, "regen"), laststand = Game.stat(p, "laststand"),
		protect = Game.stat(p, "protect"), resist = Game.stat(p, "resist"), guard = Game.stat(p, "guard"),
	}
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
-- mu = mutation id (TraitConfig) or nil
function Game.addMonster(p, def, variant: string, mu: string?)
	local d = p.data
	local iid = "m" .. d.NextMonsterId
	d.NextMonsterId += 1
	d.Monsters[iid] = { id = def.id, v = variant, lvl = 1, fr = 0, t = os.time(), mu = mu }
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
-- new gear piece (level 1, maybe a secondary stat); nil when the bag is full
function Game.addGear(p, rarity: string, gtype: string)
	local d = p.data
	if Game.count(d.Gear) >= Game.MAX_GEAR then return nil end
	local uid = "g" .. d.NextGearId
	d.NextGearId += 1
	d.Gear[uid] = { r = rarity, t = gtype, lvl = 1, sec = GearConfig.rollSecondary(rarity, Game.rng) }
	return uid
end
-- drops relics from monsters when the relic slot is gone (respec)
function Game.dropRelics(p)
	if Game.stat(p, "relic") > 0 then return end
	for _, g in p.data.Gear do if g.t == "relic" then g.m = nil end end
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
			id = m.id, v = m.v, lvl = m.lvl, fr = m.fr, lock = m.lock, fav = m.fav, t = m.t, role = cs and cs.role, mu = m.mu, tr = m.tr,
			inc = Game.income(p, iid), nxt = not maxed and Game.income(p, iid, m.lvl + 1) or nil,
			cost = not maxed and Game.upgradeCost(p, m) or nil, fuse = Game.fuseCost(p, m),
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
	Team = function(p) return Game.team(p) end,
	Teams = function(p) return { list = p.data.BattleTeams, active = p.data.ActiveTeam, presets = Game.presets(p) } end,
	Materials = function(p) return p.data.Materials end,
	Ascension = function(p) return p.data.Ascension end,
	Progress = function(p)
		local d = p.data
		return { stats = d.Stats, quests = d.Quests, milestones = d.Milestones, daily = d.Daily, unique = Game.unique(p),
			placed = Game.count(d.Placed), earned = d.LifetimeEarnings, rolls = d.Rolls }
	end,
	Cosmetics = function(p) return { owned = p.data.Cosmetics, equipped = p.data.Equipped } end,
	Boosts = function(p)
		local out = {}
		for effect, b in p.data.Boosts do if b.ends > os.time() then out[effect] = b end end
		return out
	end,
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
	s:SetAttribute("LuckAdd", Game.luckAdd(p))
	s:SetAttribute("SkillSpent", d.SkillSpent)
	s:SetAttribute("Dash", Game.stat(p, "dash"))
	s:SetAttribute("DashCooldown", 3 * (1 - math.min(0.6, Game.stat(p, "dashcd"))))
	s:SetAttribute("AutoRoll", Game.stat(p, "autoroll") > 0)
	s:SetAttribute("Travel", Game.stat(p, "travel") > 0)
	s:SetAttribute("RelicSlot", Game.stat(p, "relic") > 0)
	s:SetAttribute("FuseCopies", Game.fuseCopies(p))
	s:SetAttribute("ChestLuck", Game.stat(p, "chestluck"))
	s:SetAttribute("ChestDiscount", 1 - cut(p, "chestcost"))
	s:SetAttribute("OfflineCap", Game.offlineCap(p))
	s:SetAttribute("LuckyRolls", d.LuckyRolls)
	s:SetAttribute("Gems", d.Gems)
	s:SetAttribute("Friends", p.friends or 0)
	s:SetAttribute("Settings", Http:JSONEncode(d.Settings))
	s:SetAttribute("Passes", Http:JSONEncode(p.passes or {}))
	s:SetAttribute("Restricted", p.restricted == true)
	s:SetAttribute("MultiRoll", math.max(1, Mon.passStat(p.passes or {}, "multiRoll")))
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
	s:SetAttribute("LifetimeEarnings", p.data.LifetimeEarnings)
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
