--!strict
-- Fusion lab: deterministic star fusion, rarity fusion (guaranteed next
-- rarity, random monster within it, odds shown in the UI), special recipes,
-- and evolution. Every input is validated before anything is consumed, and
-- protected monsters are only consumed with explicit confirmation.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Util = Shared:WaitForChild("Util")
local CraftingConfig = require(Config:WaitForChild("CraftingConfig"))
local MonsterConfig = require(Config:WaitForChild("MonsterConfig"))
local RarityConfig = require(Config:WaitForChild("RarityConfig"))
local RegionConfig = require(Config:WaitForChild("RegionConfig"))
local EconomyConfig = require(Config:WaitForChild("EconomyConfig"))
local Modifiers = require(Util:WaitForChild("Modifiers"))
local StatMath = require(Util:WaitForChild("StatMath"))
local RollMath = require(Util:WaitForChild("RollMath"))
local Guard = require(Util:WaitForChild("Guard"))
local Types = require(Shared:WaitForChild("Types"))
local Modules = script.Parent.Parent:WaitForChild("Modules")
local NetServer = require(Modules:WaitForChild("NetServer"))
local GameEvents = require(Modules:WaitForChild("GameEvents"))
local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))
local EconomyService = require(script.Parent:WaitForChild("EconomyService"))
local InventoryService = require(script.Parent:WaitForChild("InventoryService"))
local MonsterService = require(script.Parent:WaitForChild("MonsterService"))
local TycoonService = require(script.Parent:WaitForChild("TycoonService"))

type Profile = Types.Profile
type MonsterInstance = Types.MonsterInstance

local FusionService = {}

local rng = Random.new()

function FusionService.setRng(seeded: Random)
	rng = seeded
end

local function collect(
	player: Player,
	profile: Profile,
	ids: { string },
	confirmProtected: boolean
): ({ MonsterInstance }?, string?)
	local list: { MonsterInstance } = {}
	for _, id in ids do
		local inst = profile.Inventory.Monsters[id]
		if not inst then
			return nil, "invalid"
		end
		local ok, reason = InventoryService.canConsume(player, inst, { AllowProtected = confirmProtected })
		if not ok then
			local def = MonsterConfig.Monsters[inst.MonsterId]
			return nil, (if def then def.DisplayName .. ": " else "") .. (reason or "unavailable")
		end
		table.insert(list, inst)
	end
	return list, nil
end

-- Star fusion ---------------------------------------------------------------------

function FusionService.starCost(inst: MonsterInstance, mods: Modifiers.Mods): (number, number)
	local nextStar = inst.Stars + 1
	local duplicates = CraftingConfig.StarFusion.DuplicatesPerStar[nextStar] or math.huge
	local coins = Modifiers.serviceCost(
		StatMath.sellValue(inst, {}) * CraftingConfig.StarFusion.CoinsPerStarMultiplier * nextStar,
		mods
	)
	return duplicates, coins
end

function FusionService.starFuse(
	player: Player,
	targetId: string,
	fodderIds: { string },
	confirm: boolean
): (boolean, string?)
	local profile = PlayerDataService.get(player)
	if not profile then
		return false, "Not ready"
	end
	local target = profile.Inventory.Monsters[targetId]
	if not target or table.find(fodderIds, targetId) then
		return false, "invalid"
	end
	if InventoryService.transientLock(player, targetId) then
		return false, "That monster is busy."
	end
	if target.Stars >= EconomyConfig.MaxStars then
		return false, "Already at max stars."
	end
	local needed, coins = FusionService.starCost(target, PlayerDataService.mods(player))
	if #fodderIds ~= needed then
		return false, "Select exactly " .. needed .. " duplicate(s)."
	end
	local fodder, err = collect(player, profile, fodderIds, confirm)
	if not fodder then
		return false, err
	end
	for _, inst in fodder do
		if inst.MonsterId ~= target.MonsterId then
			return false, "Star fusion needs copies of the same monster."
		end
	end
	if not EconomyService.spend(player, "Coins", coins, "StarFusion") then
		return false, "Not enough Coins."
	end
	for _, inst in fodder do
		InventoryService.removeMonster(player, inst.Id)
	end
	target.Stars += 1
	PlayerDataService.monsterChanged(player, targetId)
	profile.Statistics.MonstersFused += 1
	PlayerDataService.changed(player, "Statistics")
	TycoonService.refreshIncome(player)
	GameEvents.fire(player, "Fuse", { Kind = "Star", Count = 1 })
	return true, nil
end

-- Rarity fusion ---------------------------------------------------------------------

-- Returns the result pool (next rarity, same region) as weighted entries.
function FusionService.rarityResultPool(
	regionId: string,
	rarityId: string
): ({ RollMath.WeightedEntry<string> }, string?)
	local tier = RarityConfig.tierOf(rarityId)
	local nextRarity = RarityConfig.Order[tier + 1]
	if not nextRarity then
		return {}, nil
	end
	local pool: { RollMath.WeightedEntry<string> } = {}
	for _, id in MonsterConfig.Order do
		local def = MonsterConfig.Monsters[id]
		if def.Region == regionId and def.Rarity == nextRarity and MonsterConfig.isRollable(def) then
			table.insert(pool, { Value = id, Weight = def.RollWeight })
		end
	end
	return pool, nextRarity
end

function FusionService.rarityFuse(
	player: Player,
	ids: { string },
	confirm: boolean
): (MonsterInstance?, string?, number?)
	local profile = PlayerDataService.get(player)
	local cfg = CraftingConfig.RarityFusion
	if not profile then
		return nil, "Not ready", nil
	end
	if #ids ~= cfg.InputCount then
		return nil, "Select exactly " .. cfg.InputCount .. " monsters.", nil
	end
	local inputs, err = collect(player, profile, ids, confirm)
	if not inputs then
		return nil, err, nil
	end
	local first = MonsterConfig.Monsters[inputs[1].MonsterId]
	for _, inst in inputs do
		local def = MonsterConfig.Monsters[inst.MonsterId]
		if def.Rarity ~= first.Rarity or def.Region ~= first.Region then
			return nil, "All monsters must share one rarity and one region.", nil
		end
	end
	local pool, nextRarity = FusionService.rarityResultPool(first.Region, first.Rarity)
	if #pool == 0 or not nextRarity then
		return nil, "There is no higher rarity to fuse into for this region.", nil
	end
	local region = RegionConfig.Regions[first.Region]
	local tier = RarityConfig.tierOf(first.Rarity)
	local mods = PlayerDataService.mods(player)
	local costs: { EconomyService.Cost } = {
		{
			Kind = "Coins",
			Id = "Coins",
			Amount = Modifiers.serviceCost(
				StatMath.regionDiceCost(first.Region) * cfg.CoinsDiceCostMultiplier * tier,
				mods
			),
		},
		{ Kind = "Material", Id = region.MaterialId, Amount = tier * cfg.MaterialPerTier },
	}
	if InventoryService.freeMonsterSlots(player) + #inputs < 1 then
		return nil, "No storage space.", nil
	end
	local paid, payErr = EconomyService.pay(player, costs, "RarityFusion")
	if not paid then
		return nil, payErr, nil
	end
	for _, inst in inputs do
		InventoryService.removeMonster(player, inst.Id)
	end
	local resultId = RollMath.pickWeighted(pool, function()
		return rng:NextNumber()
	end) :: string
	local result = InventoryService.addMonster(player, resultId, "Fusion", { IgnoreCapacity = true })
	local bonus = 0
	if rng:NextNumber() < cfg.BonusMaterialChance then
		bonus = cfg.BonusMaterialAmount
		EconomyService.grantMaterial(player, region.MaterialId, bonus)
	end
	profile.Statistics.MonstersFused += 1
	PlayerDataService.changed(player, "Statistics")
	GameEvents.fire(player, "Fuse", { Kind = "Rarity", Count = 1 })
	return result, nil, bonus
end

-- Special recipes -------------------------------------------------------------------

function FusionService.specialFuse(
	player: Player,
	recipeId: string,
	ids: { string },
	confirm: boolean
): (MonsterInstance?, string?)
	local profile = PlayerDataService.get(player)
	local recipe = CraftingConfig.SpecialFusions[recipeId]
	if not profile or not recipe then
		return nil, "Unknown recipe."
	end
	if #ids ~= #recipe.Inputs then
		return nil, "Select one of each required monster."
	end
	local inputs, err = collect(player, profile, ids, confirm)
	if not inputs then
		return nil, err
	end
	local remaining = table.clone(recipe.Inputs)
	for _, inst in inputs do
		local i = table.find(remaining, inst.MonsterId)
		if not i then
			return nil, "Those monsters don't match the recipe."
		end
		table.remove(remaining, i)
	end
	local costs: { EconomyService.Cost } = {
		{
			Kind = "Coins",
			Id = "Coins",
			Amount = Modifiers.serviceCost(recipe.Coins, PlayerDataService.mods(player)),
		},
	}
	for materialId, amount in recipe.Materials do
		table.insert(costs, { Kind = "Material", Id = materialId, Amount = amount })
	end
	local paid, payErr = EconomyService.pay(player, costs, "SpecialFusion:" .. recipeId)
	if not paid then
		return nil, payErr
	end
	for _, inst in inputs do
		InventoryService.removeMonster(player, inst.Id)
	end
	local result =
		InventoryService.addMonster(player, recipe.Result, "Fusion:" .. recipeId, { IgnoreCapacity = true })
	profile.Statistics.MonstersFused += 1
	PlayerDataService.changed(player, "Statistics")
	GameEvents.fire(player, "Fuse", { Kind = "Special", Count = 1 })
	return result, nil
end

-- Evolution ----------------------------------------------------------------------

function FusionService.evolve(
	player: Player,
	instanceId: string,
	duplicateIds: { string },
	confirm: boolean
): (MonsterInstance?, string?)
	local profile = PlayerDataService.get(player)
	if not profile then
		return nil, "Not ready"
	end
	local inst = profile.Inventory.Monsters[instanceId]
	local def = inst and MonsterConfig.Monsters[inst.MonsterId]
	if not inst or not def or table.find(duplicateIds, instanceId) then
		return nil, "invalid"
	end
	local evolvedId = def.EvolvesTo
	local req = def.EvolutionRequirements
	if not evolvedId or not req or not MonsterConfig.Monsters[evolvedId] then
		return nil, "This monster can't evolve."
	end
	if InventoryService.transientLock(player, instanceId) then
		return nil, "That monster is busy."
	end
	if inst.Level < req.Level then
		return nil, "Requires level " .. req.Level .. "."
	end
	if #duplicateIds ~= req.Duplicates then
		return nil, "Select exactly " .. req.Duplicates .. " duplicate(s)."
	end
	local dupes, err = collect(player, profile, duplicateIds, confirm)
	if not dupes then
		return nil, err
	end
	for _, d in dupes do
		if d.MonsterId ~= inst.MonsterId then
			return nil, "Duplicates must be the same monster."
		end
	end
	local costs: { EconomyService.Cost } = {
		{
			Kind = "Coins",
			Id = "Coins",
			Amount = Modifiers.serviceCost(req.Coins, PlayerDataService.mods(player)),
		},
	}
	for materialId, amount in req.Materials do
		table.insert(costs, { Kind = "Material", Id = materialId, Amount = amount })
	end
	local paid, payErr = EconomyService.pay(player, costs, "Evolve")
	if not paid then
		return nil, payErr
	end
	for _, d in dupes do
		InventoryService.removeMonster(player, d.Id)
	end
	inst.EvolvedFrom = inst.MonsterId
	inst.MonsterId = evolvedId
	MonsterService.discover(player, profile, evolvedId, "Evolution")
	PlayerDataService.monsterChanged(player, instanceId)
	TycoonService.refreshIncome(player)
	-- refresh the base display if it is placed
	if InventoryService.slotOf(profile, instanceId) then
		TycoonService.rebuildDisplays(player)
	end
	GameEvents.fire(player, "Evolve", { MonsterId = evolvedId })
	GameEvents.fire(player, "Fuse", { Kind = "Evolve", Count = 1 })
	return inst, nil
end

function FusionService.init()
	NetServer.handle("StarFuse", { Rate = 3, Burst = 6 }, function(player, rawTarget, rawFodder, rawConfirm)
		local target = Guard.string(rawTarget)
		local fodder = Guard.stringArray(rawFodder, 10)
		if not target or not fodder then
			return NetServer.invalid(player, "StarFuse")
		end
		local ok, err = FusionService.starFuse(player, target, fodder, Guard.boolean(rawConfirm) == true)
		if not ok then
			if err == "invalid" then
				return NetServer.invalid(player, "StarFuse")
			end
			return NetServer.fail(err or "Can't fuse.")
		end
		return NetServer.ok()
	end)

	NetServer.handle("RarityFuse", { Rate = 3, Burst = 6 }, function(player, rawIds, rawConfirm)
		local ids = Guard.stringArray(rawIds, 10)
		if not ids then
			return NetServer.invalid(player, "RarityFuse")
		end
		local result, err, bonus = FusionService.rarityFuse(player, ids, Guard.boolean(rawConfirm) == true)
		if not result then
			if err == "invalid" then
				return NetServer.invalid(player, "RarityFuse")
			end
			return NetServer.fail(err or "Can't fuse.")
		end
		return NetServer.ok({ MonsterId = result.MonsterId, InstanceId = result.Id, BonusMaterials = bonus })
	end)

	NetServer.handle("SpecialFuse", { Rate = 3, Burst = 6 }, function(player, rawRecipe, rawIds, rawConfirm)
		local recipeId = Guard.string(rawRecipe)
		local ids = Guard.stringArray(rawIds, 10)
		if not recipeId or not ids then
			return NetServer.invalid(player, "SpecialFuse")
		end
		local result, err =
			FusionService.specialFuse(player, recipeId, ids, Guard.boolean(rawConfirm) == true)
		if not result then
			if err == "invalid" then
				return NetServer.invalid(player, "SpecialFuse")
			end
			return NetServer.fail(err or "Can't fuse.")
		end
		return NetServer.ok({ MonsterId = result.MonsterId, InstanceId = result.Id })
	end)

	NetServer.handle("Evolve", { Rate = 3, Burst = 6 }, function(player, rawId, rawDupes, rawConfirm)
		local id = Guard.string(rawId)
		local dupes = if rawDupes == nil then {} else Guard.stringArray(rawDupes, 10)
		if not id or not dupes then
			return NetServer.invalid(player, "Evolve")
		end
		local result, err = FusionService.evolve(player, id, dupes, Guard.boolean(rawConfirm) == true)
		if not result then
			if err == "invalid" then
				return NetServer.invalid(player, "Evolve")
			end
			return NetServer.fail(err or "Can't evolve.")
		end
		return NetServer.ok({ MonsterId = result.MonsterId, InstanceId = result.Id })
	end)
end

return FusionService
