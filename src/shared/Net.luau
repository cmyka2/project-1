--!strict
-- Network API boundary. The server creates every remote from these lists at
-- startup (server/Modules/NetServer); the client only looks them up.
--   Requests: RemoteFunctions, client -> server, always return a RemoteResult.
--   Events:   RemoteEvents, server -> client pushes.
-- The server never invokes the client.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Types = require(script.Parent.Types)

local Net = {}

Net.FOLDER_NAME = "Remotes"

Net.Requests = {
	-- rolling
	"Roll",
	"SetAutoRoll",
	-- inventory
	"ToggleLock",
	"ToggleFavorite",
	"SellMonsters",
	"MarkInspected",
	-- base / tycoon
	"PlaceMonster",
	"RemoveMonster",
	"AutoPlaceBest",
	"UpgradeMonster",
	"BuyCosmetic",
	"EquipCosmetic",
	"TeleportToPlot",
	-- progression
	"BuySkillNode",
	"RespecSkills",
	"BuyAscensionNode",
	"Rebirth",
	"UnlockRegion",
	"TravelToRegion",
	"TravelToHub",
	"ClaimCache",
	-- battle
	"SetTeam",
	"SaveLoadout",
	"LoadLoadout",
	"StartBattle",
	"StartArena",
	"BattleAction",
	"ForfeitBattle",
	-- items
	"EquipItem",
	"UnequipItem",
	"UpgradeEquipment",
	"SalvageEquipment",
	"StartCraft",
	"ClaimCraft",
	"StarFuse",
	"RarityFuse",
	"SpecialFuse",
	"Evolve",
	"OpenChest",
	"UseConsumable",
	-- meta
	"ClaimQuest",
	"ClaimAchievement",
	"ClaimDaily",
	"ClaimMilestone",
	"TutorialNext",
	"TutorialSkip",
	"UpdateSettings",
	"GetLeaderboards",
	"GetPlots",
	"RequestState",
	-- trading
	"TradeRequest",
	"TradeRespond",
	"TradeSetOffer",
	"TradeConfirm",
	"TradeCancel",
	-- QA (server-gated)
	"Cheat",
}

Net.Events = {
	"StateSync", -- (kind, ...) profile replica updates
	"Notify", -- (kind: "info"|"success"|"error"|"reward", text)
	"AutoRollResult", -- (results)
	"BattleUpdate", -- (snapshot, events)
	"TradeUpdate", -- (tradeState | nil)
	"Announce", -- (text, color) server-wide announcement
	"Popup", -- (kind, payload) modal popups (offline earnings, rebirth, level up...)
	"CheatAccess", -- (allowed)
}

local cachedFolder: Folder? = nil

local function folder(): Folder
	if cachedFolder and cachedFolder.Parent then
		return cachedFolder
	end
	local found = ReplicatedStorage:WaitForChild(Net.FOLDER_NAME, 60)
	assert(found and found:IsA("Folder"), "Remotes folder missing; is the server running?")
	cachedFolder = found
	return found
end

-- Client: invoke a request. Never throws; network or server errors become ok=false.
function Net.request(name: string, ...: any): Types.RemoteResult
	assert(RunService:IsClient(), "Net.request is client-only")
	local remote = folder():WaitForChild(name, 30)
	if not remote or not remote:IsA("RemoteFunction") then
		return { ok = false, err = "Unknown request " .. name, data = nil }
	end
	local args = table.pack(...)
	local ok, result = pcall(function()
		return remote:InvokeServer(table.unpack(args, 1, args.n))
	end)
	if not ok then
		return { ok = false, err = "Connection problem, please try again.", data = nil }
	end
	if typeof(result) ~= "table" then
		return { ok = false, err = "Unexpected server response.", data = nil }
	end
	return result :: Types.RemoteResult
end

-- Client: listen to a server push.
function Net.on(name: string, handler: (...any) -> ()): RBXScriptConnection
	assert(RunService:IsClient(), "Net.on is client-only")
	local remote = folder():WaitForChild(name, 30)
	assert(remote and remote:IsA("RemoteEvent"), "Unknown event " .. name)
	return remote.OnClientEvent:Connect(handler)
end

return Net
