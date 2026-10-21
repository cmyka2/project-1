--!strict
-- Timed crafting queue. Starting a craft atomically consumes every
-- ingredient; claiming a finished job grants the output exactly once (the job
-- is removed from the queue before the reward is granted).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Util = Shared:WaitForChild("Util")
local CraftingConfig = require(Config:WaitForChild("CraftingConfig"))
local Modifiers = require(Util:WaitForChild("Modifiers"))
local Guard = require(Util:WaitForChild("Guard"))
local Types = require(Shared:WaitForChild("Types"))
local Modules = script.Parent.Parent:WaitForChild("Modules")
local NetServer = require(Modules:WaitForChild("NetServer"))
local GameEvents = require(Modules:WaitForChild("GameEvents"))
local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))
local EconomyService = require(script.Parent:WaitForChild("EconomyService"))
local InventoryService = require(script.Parent:WaitForChild("InventoryService"))

type Profile = Types.Profile

local CraftingService = {}

function CraftingService.costsFor(
	recipe: CraftingConfig.RecipeDef,
	count: number,
	mods: Modifiers.Mods
): { EconomyService.Cost }
	local costs: { EconomyService.Cost } = {}
	for _, ingredient in recipe.Ingredients do
		local amount = ingredient.Amount * count
		if ingredient.Kind == "Coins" then
			amount = Modifiers.serviceCost(amount, mods)
		end
		table.insert(costs, { Kind = ingredient.Kind :: string, Id = ingredient.Id, Amount = amount })
	end
	return costs
end

function CraftingService.start(player: Player, recipeId: string, count: number): (Types.CraftJob?, string?)
	local profile = PlayerDataService.get(player)
	local recipe = CraftingConfig.Recipes[recipeId]
	if not profile or not recipe then
		return nil, "Unknown recipe."
	end
	if not profile.Progression.UnlockedRegions[recipe.RequiredRegion] then
		return nil, "Unlock " .. recipe.RequiredRegion .. " to craft this."
	end
	local mods = PlayerDataService.mods(player)
	if #profile.Crafting.Queue >= Modifiers.craftQueueSize(mods) then
		return nil, "Your crafting queue is full."
	end
	local paid, err =
		EconomyService.pay(player, CraftingService.costsFor(recipe, count, mods), "Craft:" .. recipeId)
	if not paid then
		return nil, err
	end
	local now = os.time()
	local job: Types.CraftJob = {
		JobId = "j" .. profile.Crafting.NextJob,
		RecipeId = recipeId,
		Count = count,
		StartedAt = now,
		ReadyAt = now + Modifiers.craftSeconds(recipe.CraftSeconds, mods) * count,
	}
	profile.Crafting.NextJob += 1
	table.insert(profile.Crafting.Queue, job)
	PlayerDataService.changed(player, "Crafting")
	return job, nil
end

function CraftingService.claim(player: Player, jobId: string): ({ [string]: number }?, string?)
	local profile = PlayerDataService.get(player)
	if not profile then
		return nil, "Not ready"
	end
	local index: number? = nil
	for i, job in profile.Crafting.Queue do
		if job.JobId == jobId then
			index = i
			break
		end
	end
	if not index then
		return nil, "That job doesn't exist."
	end
	local job = profile.Crafting.Queue[index]
	if os.time() < job.ReadyAt then
		return nil, "Not finished yet."
	end
	local recipe = CraftingConfig.Recipes[job.RecipeId]
	if not recipe then
		table.remove(profile.Crafting.Queue, index)
		PlayerDataService.changed(player, "Crafting")
		return nil, "Recipe no longer exists."
	end
	local output = recipe.Output
	-- capacity check before removing the job so nothing is lost
	if output.Kind == "Equipment" then
		local free = Modifiers.equipmentCapacity(PlayerDataService.mods(player))
			- InventoryService.equipmentCount(profile)
		if free < job.Count * output.Amount then
			return nil, "Your equipment storage is full."
		end
	end
	table.remove(profile.Crafting.Queue, index)
	PlayerDataService.changed(player, "Crafting")
	local total = job.Count * output.Amount
	if output.Kind == "Equipment" then
		for _ = 1, total do
			InventoryService.addEquipment(player, output.Id, 0, { IgnoreCapacity = true })
		end
	elseif output.Kind == "Consumable" then
		InventoryService.addConsumable(player, output.Id, total)
	else
		EconomyService.grantMaterial(player, output.Id, total)
	end
	profile.Statistics.ItemsCrafted += job.Count
	PlayerDataService.changed(player, "Statistics")
	GameEvents.fire(player, "Craft", { Count = job.Count, RecipeId = job.RecipeId })
	return { [output.Kind .. ":" .. output.Id] = total }, nil
end

function CraftingService.init()
	NetServer.handle("StartCraft", { Rate = 3, Burst = 6 }, function(player, rawRecipe, rawCount)
		local recipeId = Guard.string(rawRecipe)
		local count = Guard.integer(rawCount, 1, CraftingConfig.MaxCraftCount)
		if not recipeId or not count or not CraftingConfig.Recipes[recipeId] then
			return NetServer.invalid(player, "StartCraft")
		end
		local job, err = CraftingService.start(player, recipeId, count)
		if not job then
			return NetServer.fail(err or "Can't craft.")
		end
		return NetServer.ok(job)
	end)

	NetServer.handle("ClaimCraft", { Rate = 4, Burst = 8 }, function(player, rawJob)
		local jobId = Guard.string(rawJob)
		if not jobId then
			return NetServer.invalid(player, "ClaimCraft")
		end
		local granted, err = CraftingService.claim(player, jobId)
		if not granted then
			return NetServer.fail(err or "Can't claim.")
		end
		return NetServer.ok(granted)
	end)
end

return CraftingService
