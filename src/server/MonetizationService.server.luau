-- Robux purchases. Gamepass ownership is checked with Roblox on join and when a purchase finishes (session state,
-- Roblox is the source of truth). Developer products are granted exactly once per receipt: the purchase id is
-- recorded in the save and the save must succeed before Roblox is told PurchaseGranted.
-- Paid luck (luck passes, lucky rolls, potions, server luck) is not offered to - and paid luck effects don't apply
-- for - players whose PolicyService says ArePaidRandomItemsRestricted. Free luck (codes, daily, quests) still works.
-- RobuxAction: ("pass", passId) | ("product", productId) -> prompts the Roblox purchase dialog
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local MPS = game:GetService("MarketplaceService")
local PolicyService = game:GetService("PolicyService")
local Http = game:GetService("HttpService")
local M = RS.Monster
local Mon = require(M.MonetizationConfig)
local P = require(M.ProgressConfig)
local Data = require(script.Parent.DataService)
local Game = require(script.Parent.Game)
local Guard = require(script.Parent.Guard)

local function refreshAll()
	for player, p in Data.all() do
		if not p.released then Game.publish(player, p) end
	end
end
local function publishServerLuck()
	local sl = Game.serverLuck
	RS:SetAttribute("ServerLuck", Http:JSONEncode({ mult = sl.mult, ends = sl.ends, by = sl.by }))
end

local function ownPass(player, p, pass)
	p.passes = p.passes or {}
	if p.passes[pass.id] then return end
	p.passes[pass.id] = true
	local c = pass.effects.cosmetic
	if c and P.CosmeticById[c] then p.data.Cosmetics[c] = true end
	Game.publish(player, p)
	Game.BaseChanged:Fire(player)
end

-- what a product gives; runs once per receipt
local function grantProduct(player, p, item)
	local d, g = p.data, item.grant
	if g.luckyRolls then d.LuckyRolls += g.luckyRolls end
	if g.potion then
		local b = d.Boosts.luck
		local now = os.time()
		local live = b and b.ends > now
		d.Boosts.luck = { mult = math.max(g.potion.mult, live and b.mult or 1), ends = (live and b.ends or now) + g.potion.secs }
	end
	if g.serverLuck then
		local sl, now = Game.serverLuck, os.time()
		Game.serverLuck = { mult = math.max(g.serverLuck.mult, sl.ends > now and sl.mult or 1), ends = math.max(sl.ends, now) + g.serverLuck.secs, by = player.DisplayName }
		publishServerLuck()
		M.Announce:FireAllClients(player.DisplayName .. " activated SERVER LUCK x" .. g.serverLuck.mult .. " for everyone! 🍀", "Divine")
		refreshAll()
	else
		Game.publish(player, p)
	end
	Game.notify(player, "Thanks! " .. item.name .. " received.")
end

Data.onLoaded(function(player, p)
	p.passes = p.passes or {}
	p.premium = player.MembershipType == Enum.MembershipType.Premium
	if Mon.GROUP_ID then
		local okG, inG = pcall(player.IsInGroup, player, Mon.GROUP_ID)
		p.inGroup = okG and inG or false
	end
	local ok, info = pcall(PolicyService.GetPolicyInfoForPlayerAsync, PolicyService, player)
	p.restricted = ok and info and info.ArePaidRandomItemsRestricted == true or false
	for _, pass in Mon.Passes do
		if pass.gamepass then
			local owned, has = pcall(MPS.UserOwnsGamePassAsync, MPS, player.UserId, pass.gamepass)
			if owned and has then ownPass(player, p, pass) end
		end
	end
	Game.publish(player, p)
end)
Players.PlayerMembershipChanged:Connect(function(player)
	local p = Game.get(player)
	if not p then return end
	p.premium = player.MembershipType == Enum.MembershipType.Premium
	Game.publish(player, p)
end)
MPS.PromptGamePassPurchaseFinished:Connect(function(player, passId, bought)
	local p = Game.get(player)
	if not (p and bought) then return end
	for _, pass in Mon.Passes do
		if pass.gamepass == passId then ownPass(player, p, pass) end
	end
end)

-- the one ProcessReceipt for the game: luck products and paid cosmetics (ProgressConfig)
MPS.ProcessReceipt = function(info)
	local player = Players:GetPlayerByUserId(info.PlayerId)
	local p = player and Game.get(player)
	if not p or not p.saveable then return Enum.ProductPurchaseDecision.NotProcessedYet end -- Roblox retries later
	local d = p.data
	if not d.Receipts[info.PurchaseId] then
		local product, cosmetic
		for _, item in Mon.Products do if item.product == info.ProductId then product = item end end
		for _, c in P.Cosmetics do if c.product == info.ProductId then cosmetic = c end end
		if not product and not cosmetic then
			warn("ProcessReceipt: unknown product", info.ProductId)
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		d.Receipts[info.PurchaseId] = true
		if product then grantProduct(player, p, product) end
		if cosmetic then d.Cosmetics[cosmetic.id] = true Game.publish(player, p, "Cosmetics") end
	end
	return Data.saveNow(player) and Enum.ProductPurchaseDecision.PurchaseGranted or Enum.ProductPurchaseDecision.NotProcessedYet
end

M.RobuxAction.OnServerInvoke = function(player, kind, id)
	local p = Game.get(player)
	if not p then return false, "Still loading" end
	if not Guard.rate(player, "robux", 1) then return false, "Too fast" end
	local item = Guard.str(id) and (kind == "pass" and Mon.PassById[id] or kind == "product" and Mon.ProductById[id])
	if not item then return false, "Unknown item" end
	if item.luck and p.restricted then return false, "Paid luck items aren't available in your region" end
	if kind == "pass" then
		if p.passes and p.passes[id] then return false, "Already owned" end
		if not item.gamepass then return false, "Coming soon" end
		MPS:PromptGamePassPurchase(player, item.gamepass)
	else
		if not item.product then return false, "Coming soon" end
		MPS:PromptProductPurchase(player, item.product)
	end
	return true
end

-- server luck expiry: republish once when it runs out
task.spawn(function()
	local wasOn = false
	while true do
		task.wait(5)
		local on = Game.serverLuck.ends > os.time()
		if wasOn and not on then publishServerLuck() refreshAll() end
		wasOn = on
	end
end)
publishServerLuck()

-- Studio QA (no Roblox ids needed): ServerStorage.DevGrantPass:Invoke(player, "lucky")
-- ServerStorage.DevGrantProduct:Invoke(player, "lucky_100")
if RunService:IsStudio() then
	local SS = game:GetService("ServerStorage")
	local bp = Instance.new("BindableFunction") bp.Name = "DevGrantPass"
	bp.OnInvoke = function(player, id)
		local p, pass = Game.get(player), Mon.PassById[id]
		if not (p and pass) then return false end
		ownPass(player, p, pass)
		return true
	end
	bp.Parent = SS
	local bd = Instance.new("BindableFunction") bd.Name = "DevGrantProduct"
	bd.OnInvoke = function(player, id)
		local p, item = Game.get(player), Mon.ProductById[id]
		if not (p and item) then return false end
		grantProduct(player, p, item)
		return true
	end
	bd.Parent = SS
end
