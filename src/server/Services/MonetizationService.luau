--!strict
-- Optional Robux purchases. Developer products are granted only from
-- ProcessReceipt, idempotently: each PurchaseId is recorded in the profile and
-- PurchaseGranted is returned only after a save containing the grant
-- succeeded. Game pass ownership is always verified with
-- MarketplaceService, never taken from a client claim.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local MonetizationConfig = require(Config:WaitForChild("MonetizationConfig"))
local GameConfig = require(Config:WaitForChild("GameConfig"))
local Types = require(Shared:WaitForChild("Types"))
local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))
local EconomyService = require(script.Parent:WaitForChild("EconomyService"))
local InventoryService = require(script.Parent:WaitForChild("InventoryService"))
local TycoonService = require(script.Parent:WaitForChild("TycoonService"))

type Profile = Types.Profile

local MonetizationService = {}

local unsaved: { [Player]: { [string]: boolean } } = {}

local function productById(productId: number): MonetizationConfig.ProductDef?
	if productId == 0 then
		return nil
	end
	for _, product in MonetizationConfig.Products do
		if product.ProductId == productId then
			return product
		end
	end
	return nil
end

-- Exposed for tests: the ProcessReceipt implementation.
function MonetizationService.processReceipt(receipt: { [string]: any }): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	local profile = player and PlayerDataService.get(player)
	local product = productById(receipt.ProductId)
	if not player or not profile or not product then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local purchaseId = tostring(receipt.PurchaseId)
	local pending = unsaved[player]
	if not pending then
		pending = {}
		unsaved[player] = pending
	end
	if table.find(profile.Purchases.Receipts, purchaseId) then
		if not pending[purchaseId] then
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
	else
		-- grant exactly once, recording the receipt in the same profile mutation
		if product.Grant.Gems then
			EconomyService.grant(player, "Gems", product.Grant.Gems, "Purchase:" .. product.Key)
		end
		if product.Grant.Consumables then
			for id, amount in product.Grant.Consumables do
				InventoryService.addConsumable(player, id, amount)
			end
		end
		table.insert(profile.Purchases.Receipts, purchaseId)
		while #profile.Purchases.Receipts > GameConfig.Data.MaxReceiptHistory do
			table.remove(profile.Purchases.Receipts, 1)
		end
		pending[purchaseId] = true
		PlayerDataService.changed(player, "Purchases")
	end
	if PlayerDataService.saveNow(player) then
		pending[purchaseId] = nil
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	return Enum.ProductPurchaseDecision.NotProcessedYet
end

local function refreshPasses(player: Player)
	local profile = PlayerDataService.get(player)
	if not profile then
		return
	end
	local changed = false
	for _, pass in MonetizationConfig.Passes do
		if pass.GamePassId ~= 0 then
			local ok, owns = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, pass.GamePassId)
			end)
			if ok and (owns == true) ~= (profile.Purchases.GamePasses[pass.Key] == true) then
				if owns then
					profile.Purchases.GamePasses[pass.Key] = true
				else
					profile.Purchases.GamePasses[pass.Key] = nil
				end
				changed = true
			end
		end
	end
	if changed then
		PlayerDataService.changed(player, "Purchases")
		PlayerDataService.invalidateMods(player)
		TycoonService.refreshIncome(player)
	end
end

function MonetizationService.init()
	MarketplaceService.ProcessReceipt = MonetizationService.processReceipt
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(
		function(player: Player, _passId: number, purchased: boolean)
			if purchased then
				refreshPasses(player)
			end
		end
	)
end

function MonetizationService.onPlayerReady(player: Player, _profile: Profile)
	task.spawn(refreshPasses, player)
end

function MonetizationService.onPlayerRemoving(player: Player, _profile: Profile)
	unsaved[player] = nil
end

return MonetizationService
