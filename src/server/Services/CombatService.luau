--!strict
-- Battle orchestration: teams/loadouts, starting PvE encounters and arena
-- fights, validating every player action, turn timeouts, rewards and
-- cleanup. All combat math lives in Modules/BattleEngine; the client never
-- decides damage, health, outcomes or rewards.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Util = Shared:WaitForChild("Util")
local CombatConfig = require(Config:WaitForChild("CombatConfig"))
local EnemyConfig = require(Config:WaitForChild("EnemyConfig"))
local MonsterConfig = require(Config:WaitForChild("MonsterConfig"))
local CraftingConfig = require(Config:WaitForChild("CraftingConfig"))
local RegionConfig = require(Config:WaitForChild("RegionConfig"))
local StatMath = require(Util:WaitForChild("StatMath"))
local EquipMath = require(Util:WaitForChild("EquipMath"))
local Modifiers = require(Util:WaitForChild("Modifiers"))
local Guard = require(Util:WaitForChild("Guard"))
local Types = require(Shared:WaitForChild("Types"))
local Modules = script.Parent.Parent:WaitForChild("Modules")
local BattleEngine = require(Modules:WaitForChild("BattleEngine"))
local NetServer = require(Modules:WaitForChild("NetServer"))
local GameEvents = require(Modules:WaitForChild("GameEvents"))
local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))
local EconomyService = require(script.Parent:WaitForChild("EconomyService"))
local InventoryService = require(script.Parent:WaitForChild("InventoryService"))
local MonsterService = require(script.Parent:WaitForChild("MonsterService"))
local TycoonService = require(script.Parent:WaitForChild("TycoonService"))
local AnalyticsService = require(script.Parent:WaitForChild("AnalyticsService"))

type Profile = Types.Profile

type Session = {
	Battle: BattleEngine.Battle,
	Kind: "PvE" | "Arena",
	EncounterId: string?,
	OpponentName: string?,
	OpponentRating: number?,
	TeamIds: { string },
	Deadline: number,
	Finished: boolean,
	Rewards: { [string]: any }?,
	FinishedAt: number,
}

local CombatService = {}

local sessions: { [Player]: Session } = {}
local lastArena: { [Player]: number } = {}
local battleCounter = 0
local rng = Random.new()

function CombatService.setRng(seeded: Random)
	rng = seeded
end

function CombatService.session(player: Player): Session?
	return sessions[player]
end

local function nextFloat(): number
	return rng:NextNumber()
end

-- Unit specs ---------------------------------------------------------------------------

local function monsterSpec(
	profile: Profile,
	inst: Types.MonsterInstance,
	mods: Modifiers.Mods,
	controlled: boolean
): BattleEngine.UnitSpec?
	local def = MonsterConfig.Monsters[inst.MonsterId]
	if not def then
		return nil
	end
	return {
		Name = def.DisplayName,
		MonsterId = def.MonsterId,
		InstanceId = inst.Id,
		Element = def.Element,
		ModelKey = def.ModelKey,
		Archetype = def.Archetype,
		Rarity = def.Rarity,
		Level = inst.Level,
		Stats = StatMath.monsterStats(inst, EquipMath.itemsOn(profile, inst.Id), mods),
		Abilities = def.Abilities,
		Controlled = controlled,
		AiProfile = "Balanced",
	}
end

local function teamSpecs(
	profile: Profile,
	mods: Modifiers.Mods,
	controlled: boolean
): { BattleEngine.UnitSpec }
	local specs = {}
	for _, id in profile.Battle.Team do
		local inst = profile.Inventory.Monsters[id]
		if inst then
			local spec = monsterSpec(profile, inst, mods, controlled)
			if spec then
				table.insert(specs, spec)
			end
		end
	end
	return specs
end

-- Sessions ---------------------------------------------------------------------------

local function push(player: Player, session: Session)
	local snapshot = BattleEngine.snapshot(session.Battle)
	snapshot.Kind = session.Kind
	snapshot.EncounterId = session.EncounterId
	snapshot.OpponentName = session.OpponentName
	snapshot.Deadline = session.Deadline
	snapshot.Rewards = session.Rewards
	NetServer.push(player, "BattleUpdate", snapshot, BattleEngine.takeEvents(session.Battle))
end

local function lockTeam(player: Player, ids: { string }, locked: boolean)
	for _, id in ids do
		InventoryService.setTransientLock(player, id, if locked then "Battle" else nil)
	end
end

local function rollDrops(player: Player, encounter: EnemyConfig.EncounterDef): { [string]: number }
	local drops: { [string]: number } = {}
	for _, drop in encounter.Drops do
		if nextFloat() < drop.Chance then
			local amount = rng:NextInteger(drop.Min, drop.Max)
			if drop.Kind == "Material" then
				EconomyService.grantMaterial(player, drop.Id, amount)
			elseif drop.Kind == "Chest" then
				InventoryService.addChest(player, drop.Id, amount)
			elseif drop.Kind == "Consumable" then
				InventoryService.addConsumable(player, drop.Id, amount)
			elseif drop.Kind == "Equipment" then
				InventoryService.addEquipment(player, drop.Id, 0)
			end
			drops[drop.Kind .. ":" .. drop.Id] = (drops[drop.Kind .. ":" .. drop.Id] or 0) + amount
		end
	end
	return drops
end

local function finish(player: Player, session: Session)
	if session.Finished then
		return
	end
	session.Finished = true
	session.FinishedAt = os.clock()
	lockTeam(player, session.TeamIds, false)
	local profile = PlayerDataService.get(player)
	if not profile then
		return
	end
	local battle = session.Battle
	local victory = battle.State == "Victory"
	local mods = PlayerDataService.mods(player)
	local rewards: { [string]: any } = { Victory = victory, Xp = {} }
	if session.Kind == "PvE" and session.EncounterId then
		local encounter = EnemyConfig.Encounters[session.EncounterId]
		if victory and encounter then
			local coins = math.floor(encounter.RewardCoins * Modifiers.battleCoinMultiplier(mods))
			EconomyService.grant(player, "Coins", coins, "Battle")
			rewards.Coins = coins
			local firstClear = (profile.Progression.EncounterClears[encounter.Id] or 0) == 0
			local gems = encounter.RewardGems + (if firstClear then encounter.FirstClearGems else 0)
			if gems > 0 then
				EconomyService.grant(player, "Gems", gems, "Battle")
				rewards.Gems = gems
			end
			rewards.FirstClear = firstClear
			rewards.Drops = rollDrops(player, encounter)
			profile.Progression.EncounterClears[encounter.Id] = (
				profile.Progression.EncounterClears[encounter.Id] or 0
			) + 1
			if encounter.CooldownSeconds > 0 then
				profile.Progression.EncounterCooldowns[encounter.Id] = os.time() + encounter.CooldownSeconds
			end
			local xp = math.floor(encounter.RewardXp * (1 + (mods.XpGain or 0)))
			for _, unit in battle.Units do
				if unit.Side == "Player" and unit.InstanceId then
					local levels = MonsterService.addXp(player, unit.InstanceId, xp)
					rewards.Xp[unit.InstanceId] = { Xp = xp, Levels = levels }
				end
			end
			profile.Statistics.BattlesWon += 1
			if encounter.IsBoss then
				profile.Progression.BossesDefeated[encounter.Region] = (
					profile.Progression.BossesDefeated[encounter.Region] or 0
				) + 1
				profile.Statistics.BossesDefeated += 1
				GameEvents.fire(player, "DefeatBoss", { Region = encounter.Region, Encounter = encounter.Id })
			end
			PlayerDataService.changed(player, "Progression")
			GameEvents.fire(
				player,
				"WinBattle",
				{ Region = encounter.Region, Encounter = encounter.Id, IsBoss = encounter.IsBoss }
			)
			TycoonService.refreshIncome(player)
		elseif encounter then
			profile.Statistics.BattlesLost += 1
			-- defeated monsters still learn a little
			local xp = math.floor(encounter.RewardXp * 0.2)
			for _, unit in battle.Units do
				if unit.Side == "Player" and unit.InstanceId and xp > 0 then
					MonsterService.addXp(player, unit.InstanceId, xp)
					rewards.Xp[unit.InstanceId] = { Xp = xp, Levels = 0 }
				end
			end
		end
	elseif session.Kind == "Arena" then
		local rating = profile.Battle.BattleRating
		local opponentRating = session.OpponentRating or CombatConfig.ArenaStartingRating
		local expected = 1 / (1 + 10 ^ ((opponentRating - rating) / 400))
		local delta = math.floor(CombatConfig.ArenaKFactor * ((if victory then 1 else 0) - expected) + 0.5)
		profile.Battle.BattleRating = math.max(CombatConfig.ArenaMinRating, rating + delta)
		rewards.RatingChange = delta
		rewards.Rating = profile.Battle.BattleRating
		if victory then
			profile.Battle.ArenaWins += 1
			local coins = math.floor(
				math.max(
					EconomyService.regionScale(profile) * 200,
					TycoonService.rate(player) * CombatConfig.ArenaRewardCoinsSeconds
				) * Modifiers.battleCoinMultiplier(mods)
			)
			EconomyService.grant(player, "Coins", coins, "Arena")
			EconomyService.grant(player, "Gems", CombatConfig.ArenaRewardGems, "Arena")
			rewards.Coins = coins
			rewards.Gems = CombatConfig.ArenaRewardGems
			profile.Statistics.BattlesWon += 1
			GameEvents.fire(player, "ArenaWin", {})
			GameEvents.fire(player, "WinBattle", { Arena = true })
		else
			profile.Battle.ArenaLosses += 1
			profile.Statistics.BattlesLost += 1
		end
		PlayerDataService.changed(player, "Battle")
	end
	PlayerDataService.changed(player, "Statistics")
	session.Rewards = rewards
	AnalyticsService.count(if victory then "BattleWin" else "BattleLoss")
end

local function afterAction(player: Player, session: Session)
	local battle = session.Battle
	if battle.State == "Victory" or battle.State == "Defeat" then
		finish(player, session)
	else
		session.Deadline = os.time() + CombatConfig.TurnTimeoutSeconds
	end
	push(player, session)
end

local function begin(
	player: Player,
	kind: "PvE" | "Arena",
	enemies: { BattleEngine.UnitSpec },
	encounterId: string?,
	opponentName: string?,
	opponentRating: number?
): (Session?, string?)
	local profile = PlayerDataService.get(player)
	if not profile then
		return nil, "Not ready"
	end
	local existing = sessions[player]
	if existing and not existing.Finished then
		return nil, "You're already in a battle."
	end
	local mods = PlayerDataService.mods(player)
	local team = teamSpecs(profile, mods, true)
	if #team == 0 then
		return nil, "Pick a team first (Battle > Team)."
	end
	for _, id in profile.Battle.Team do
		if InventoryService.transientLock(player, id) == "Trade" then
			return nil, "A team member is in a trade."
		end
	end
	battleCounter += 1
	local battle = BattleEngine.new("b" .. battleCounter, team, enemies, nextFloat)
	local session: Session = {
		Battle = battle,
		Kind = kind,
		EncounterId = encounterId,
		OpponentName = opponentName,
		OpponentRating = opponentRating,
		TeamIds = table.clone(profile.Battle.Team),
		Deadline = os.time() + CombatConfig.TurnTimeoutSeconds,
		Finished = false,
		Rewards = nil,
		FinishedAt = 0,
	}
	sessions[player] = session
	lockTeam(player, session.TeamIds, true)
	GameEvents.fire(player, "StartBattle", { Kind = kind, Encounter = encounterId })
	BattleEngine.advance(battle)
	afterAction(player, session)
	return session, nil
end

function CombatService.startEncounter(player: Player, encounterId: string): (Session?, string?)
	local profile = PlayerDataService.get(player)
	local encounter = EnemyConfig.Encounters[encounterId]
	if not profile or not encounter then
		return nil, "Unknown encounter."
	end
	if not profile.Progression.UnlockedRegions[encounter.Region] then
		local region = RegionConfig.Regions[encounter.Region]
		return nil, "Unlock " .. (if region then region.DisplayName else encounter.Region) .. " first."
	end
	local cooldown = profile.Progression.EncounterCooldowns[encounterId]
	if cooldown and os.time() < cooldown then
		return nil, string.format("Available again in %ds.", cooldown - os.time())
	end
	local enemies = {}
	for _, entry in encounter.Enemies do
		local spec = BattleEngine.enemySpec(entry.Enemy, entry.Level)
		if spec then
			table.insert(enemies, spec)
		end
	end
	if #enemies == 0 then
		return nil, "This encounter has no enemies."
	end
	return begin(player, "PvE", enemies, encounterId, nil, nil)
end

-- Arena: an AI-controlled copy of another player's team (or a training bot).
function CombatService.startArena(player: Player): (Session?, string?)
	local profile = PlayerDataService.get(player)
	if not profile then
		return nil, "Not ready"
	end
	local last = lastArena[player]
	if last and os.clock() - last < CombatConfig.ArenaCooldownSeconds then
		return nil, "The arena is being prepared. Try again shortly."
	end
	local candidates: { Player } = {}
	for _, other in PlayerDataService.players() do
		local otherProfile = PlayerDataService.get(other)
		if other ~= player and otherProfile and #otherProfile.Battle.Team > 0 then
			table.insert(candidates, other)
		end
	end
	local enemies: { BattleEngine.UnitSpec } = {}
	local opponentName = "Training Bot"
	local opponentRating = CombatConfig.ArenaStartingRating
	if #candidates > 0 then
		-- prefer the closest rating
		table.sort(candidates, function(a, b)
			local ra = (PlayerDataService.get(a) :: Profile).Battle.BattleRating
			local rb = (PlayerDataService.get(b) :: Profile).Battle.BattleRating
			return math.abs(ra - profile.Battle.BattleRating) < math.abs(rb - profile.Battle.BattleRating)
		end)
		local opponent = candidates[1]
		local opponentProfile = PlayerDataService.get(opponent) :: Profile
		enemies = teamSpecs(opponentProfile, PlayerDataService.mods(opponent), false)
		for _, spec in enemies do
			spec.AiProfile = "Smart"
		end
		opponentName = opponent.DisplayName
		opponentRating = opponentProfile.Battle.BattleRating
	else
		-- bot mirrors the player's own team composition at slightly lower power
		local mods = PlayerDataService.mods(player)
		for _, spec in teamSpecs(profile, mods, false) do
			local s = table.clone(spec.Stats)
			s.MaxHealth = math.floor(s.MaxHealth * 0.9)
			s.Attack = math.floor(s.Attack * 0.9)
			spec.Stats = s
			spec.Name = "Bot " .. spec.Name
			table.insert(enemies, spec)
		end
		opponentRating = math.max(0, profile.Battle.BattleRating - 100)
	end
	if #enemies == 0 then
		return nil, "Pick a team first (Battle > Team)."
	end
	lastArena[player] = os.clock()
	return begin(player, "Arena", enemies, nil, opponentName, opponentRating)
end

function CombatService.act(player: Player, battleId: string, action: BattleEngine.Action): (boolean, string?)
	local session = sessions[player]
	if not session or session.Battle.Id ~= battleId then
		return false, "That battle doesn't exist."
	end
	if session.Finished then
		return false, "The battle is over."
	end
	local battle = session.Battle
	local unitId = battle.Active
	if battle.State ~= "PlayerTurn" or not unitId then
		return false, "It's not your turn."
	end
	if action.Kind == "Item" then
		local itemId = action.ItemId
		if not itemId or (PlayerDataService.get(player) :: Profile).Inventory.Consumables[itemId] == nil then
			return false, "You don't have that item."
		end
	end
	local ok, err = BattleEngine.playerAction(battle, unitId, action)
	if not ok then
		return false, err
	end
	if action.Kind == "Item" and action.ItemId then
		InventoryService.takeConsumable(player, action.ItemId, 1)
	end
	afterAction(player, session)
	return true, nil
end

-- Re-evaluates a session after external changes (QA tooling).
function CombatService.refresh(player: Player)
	local session = sessions[player]
	if session and not session.Finished then
		afterAction(player, session)
	end
end

function CombatService.forfeit(player: Player)
	local session = sessions[player]
	if session and not session.Finished then
		BattleEngine.forfeit(session.Battle)
		finish(player, session)
		push(player, session)
	end
end

-- Teams ---------------------------------------------------------------------------------

function CombatService.setTeam(player: Player, ids: { string }): (boolean, string?)
	local profile = PlayerDataService.get(player)
	if not profile then
		return false, "Not ready"
	end
	local session = sessions[player]
	if session and not session.Finished then
		return false, "You can't change your team during a battle."
	end
	if #ids > CombatConfig.TeamSize then
		return false, "A team has at most " .. CombatConfig.TeamSize .. " monsters."
	end
	for _, id in ids do
		if not profile.Inventory.Monsters[id] then
			return false, "invalid"
		end
		if InventoryService.transientLock(player, id) == "Trade" then
			return false, "That monster is in a trade."
		end
	end
	profile.Battle.Team = table.clone(ids)
	PlayerDataService.changed(player, "Battle")
	return true, nil
end

function CombatService.init()
	NetServer.handle("SetTeam", { Rate = 4, Burst = 8 }, function(player, rawIds)
		local ids = Guard.stringArray(rawIds, CombatConfig.TeamSize)
		if not ids then
			return NetServer.invalid(player, "SetTeam")
		end
		local ok, err = CombatService.setTeam(player, ids)
		if not ok then
			if err == "invalid" then
				return NetServer.invalid(player, "SetTeam")
			end
			return NetServer.fail(err or "Can't set team.")
		end
		return NetServer.ok()
	end)

	NetServer.handle("SaveLoadout", { Rate = 3, Burst = 6 }, function(player, rawIndex)
		local profile = PlayerDataService.get(player)
		local slots = Modifiers.loadoutSlots(PlayerDataService.mods(player))
		local index = Guard.integer(rawIndex, 1, slots)
		if not profile or not index then
			return NetServer.fail("That loadout slot is locked.")
		end
		while #profile.Battle.Loadouts < index do
			table.insert(profile.Battle.Loadouts, {})
		end
		profile.Battle.Loadouts[index] = table.clone(profile.Battle.Team)
		PlayerDataService.changed(player, "Battle")
		return NetServer.ok()
	end)

	NetServer.handle("LoadLoadout", { Rate = 3, Burst = 6 }, function(player, rawIndex)
		local profile = PlayerDataService.get(player)
		local index = Guard.integer(rawIndex, 1, 10)
		local loadout = profile and index and profile.Battle.Loadouts[index]
		if not loadout then
			return NetServer.fail("That loadout is empty.")
		end
		local ok, err = CombatService.setTeam(player, loadout)
		if not ok then
			return NetServer.fail(
				if err == "invalid" then "That loadout is out of date." else err or "Can't load."
			)
		end
		return NetServer.ok()
	end)

	NetServer.handle("StartBattle", { Rate = 1, Burst = 3 }, function(player, rawEncounter)
		local encounterId = Guard.string(rawEncounter)
		if not encounterId or not EnemyConfig.Encounters[encounterId] then
			return NetServer.invalid(player, "StartBattle")
		end
		local session, err = CombatService.startEncounter(player, encounterId)
		if not session then
			return NetServer.fail(err or "Can't start.")
		end
		return NetServer.ok({ BattleId = session.Battle.Id })
	end)

	NetServer.handle("StartArena", { Rate = 1, Burst = 2 }, function(player)
		local session, err = CombatService.startArena(player)
		if not session then
			return NetServer.fail(err or "Can't start.")
		end
		return NetServer.ok({ BattleId = session.Battle.Id, Opponent = session.OpponentName })
	end)

	NetServer.handle(
		"BattleAction",
		{ Rate = 6, Burst = 10 },
		function(player, rawBattle, rawKind, rawAbility, rawTarget, rawItem)
			local battleId = Guard.string(rawBattle)
			local kind = Guard.string(rawKind)
			if not battleId or (kind ~= "Ability" and kind ~= "Defend" and kind ~= "Item") then
				return NetServer.invalid(player, "BattleAction")
			end
			local action: BattleEngine.Action = { Kind = kind :: any }
			if rawAbility ~= nil then
				action.AbilityId = Guard.string(rawAbility)
			end
			if rawTarget ~= nil then
				action.TargetId = Guard.string(rawTarget)
			end
			if rawItem ~= nil then
				local itemId = Guard.string(rawItem)
				if not itemId or not CraftingConfig.Consumables[itemId] then
					return NetServer.invalid(player, "BattleAction")
				end
				action.ItemId = itemId
			end
			local ok, err = CombatService.act(player, battleId, action)
			if not ok then
				return NetServer.fail(err or "Invalid action.")
			end
			return NetServer.ok()
		end
	)

	NetServer.handle("ForfeitBattle", { Rate = 2, Burst = 3 }, function(player)
		CombatService.forfeit(player)
		return NetServer.ok()
	end)
end

function CombatService.start()
	-- turn timeouts and finished-session cleanup
	task.spawn(function()
		while true do
			task.wait(1)
			local now = os.time()
			for player, session in sessions do
				if session.Finished then
					if os.clock() - session.FinishedAt > CombatConfig.ResultLingerSeconds then
						sessions[player] = nil
					end
				elseif session.Battle.State == "PlayerTurn" and now >= session.Deadline then
					local unit = session.Battle.Active
						and BattleEngine.unit(session.Battle, session.Battle.Active)
					if unit then
						BattleEngine.playerAction(
							session.Battle,
							unit.Id,
							BattleEngine.defaultAction(session.Battle, unit)
						)
						afterAction(player, session)
					end
				end
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		sessions[player] = nil
		lastArena[player] = nil
	end)
end

-- Leaving mid-battle counts as a forfeit (no rewards); locks are released.
function CombatService.onPlayerRemoving(player: Player, _profile: Profile)
	local session = sessions[player]
	if session and not session.Finished then
		BattleEngine.forfeit(session.Battle)
		finish(player, session)
	end
	sessions[player] = nil
	lastArena[player] = nil
end

return CombatService
