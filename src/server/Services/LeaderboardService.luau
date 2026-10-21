--!strict
-- Global leaderboards backed by OrderedDataStores, uploaded and refreshed on
-- slow timers (DataStore budgets are limited). If the service is unavailable
-- the boards fall back to players in this server. Lifetime coins are stored
-- log-scaled because OrderedDataStore values must be integers below 2^63.

local CollectionService = game:GetService("CollectionService")
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("Config"):WaitForChild("GameConfig"))
local Codex = require(Shared:WaitForChild("Util"):WaitForChild("Codex"))
local Format = require(Shared:WaitForChild("Util"):WaitForChild("Format"))
local Types = require(Shared:WaitForChild("Types"))
local Modules = script.Parent.Parent:WaitForChild("Modules")
local NetServer = require(Modules:WaitForChild("NetServer"))
local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))

type Profile = Types.Profile
type Entry = { Rank: number, UserId: number, Name: string, Value: number }

local LB = GameConfig.Leaderboards

local LeaderboardService = {}

local stores: { [string]: any } = {}
local cache: { [string]: { Entry } } = {}
local names: { [number]: string } = {}
local available = false
local LOG_SCALE = 1e6

local function statValue(profile: Profile, stat: string): number
	if stat == "RebirthCount" then
		return profile.Progression.RebirthCount
	elseif stat == "Discoveries" then
		return Codex.discoveredCount(profile)
	elseif stat == "LifetimeCoins" then
		return profile.Statistics.LifetimeCoinsEarned
	elseif stat == "BattleRating" then
		return profile.Battle.BattleRating
	end
	return 0
end

function LeaderboardService.encode(value: number, logScale: boolean): number
	if logScale then
		return math.floor(math.log10(math.max(0, value) + 1) * LOG_SCALE)
	end
	return math.floor(math.clamp(value, 0, 2 ^ 53))
end

function LeaderboardService.decode(value: number, logScale: boolean): number
	if logScale then
		return 10 ^ (value / LOG_SCALE) - 1
	end
	return value
end

local function nameOf(userId: number): string
	local cached = names[userId]
	if cached then
		return cached
	end
	local player = Players:GetPlayerByUserId(userId)
	if player then
		names[userId] = player.DisplayName
		return player.DisplayName
	end
	local ok, result = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	local name = if ok and typeof(result) == "string" then result else ("Player " .. userId)
	names[userId] = name
	return name
end

function LeaderboardService.upload(player: Player)
	local profile = PlayerDataService.get(player)
	if not profile or not available then
		return
	end
	for _, board in LB.Boards do
		local store = stores[board.Id]
		if store then
			local value = LeaderboardService.encode(statValue(profile, board.Stat), board.LogScale)
			pcall(function()
				store:SetAsync(tostring(player.UserId), value)
			end)
		end
	end
end

local function localBoard(board: { Id: string, Stat: string, LogScale: boolean }): { Entry }
	local rows: { Entry } = {}
	for _, player in PlayerDataService.players() do
		local profile = PlayerDataService.get(player)
		if profile then
			table.insert(rows, {
				Rank = 0,
				UserId = player.UserId,
				Name = player.DisplayName,
				Value = statValue(profile, board.Stat),
			})
		end
	end
	table.sort(rows, function(a, b)
		return a.Value > b.Value
	end)
	for i, row in rows do
		row.Rank = i
	end
	while #rows > LB.TopCount do
		table.remove(rows)
	end
	return rows
end

function LeaderboardService.refresh()
	for _, board in LB.Boards do
		local rows: { Entry }? = nil
		local store = stores[board.Id]
		if available and store then
			local ok, pages = pcall(function()
				return store:GetSortedAsync(false, LB.TopCount)
			end)
			if ok and pages then
				local list: { Entry } = {}
				local okPage, page = pcall(function()
					return pages:GetCurrentPage()
				end)
				if okPage and page then
					for i, item in page do
						local userId = tonumber(item.key) or 0
						table.insert(list, {
							Rank = i,
							UserId = userId,
							Name = nameOf(userId),
							Value = LeaderboardService.decode(item.value, board.LogScale),
						})
					end
					rows = list
				end
			end
		end
		cache[board.Id] = rows or localBoard(board)
	end
	-- world boards
	for _, screen in CollectionService:GetTagged("LeaderboardScreen") do
		local boardId = screen:GetAttribute("BoardId")
		local def = nil
		for _, b in LB.Boards do
			if b.Id == boardId then
				def = b
			end
		end
		if def and screen:IsA("BasePart") then
			local lines = { "🏆 " .. def.DisplayName }
			local rows = cache[def.Id]
			if rows then
				for _, row in rows do
					table.insert(
						lines,
						string.format("%d. %s  %s", row.Rank, row.Name, Format.number(row.Value))
					)
				end
			end
			if #lines == 1 then
				table.insert(lines, "No entries yet")
			end
			local gui = screen:FindFirstChild("Label")
			local label = gui and gui:FindFirstChild("Text")
			if not label then
				local surface = Instance.new("SurfaceGui")
				surface.Name = "Label"
				surface.Face = Enum.NormalId.Front
				surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
				surface.PixelsPerStud = 25
				surface.LightInfluence = 0
				surface.Parent = screen
				local text = Instance.new("TextLabel")
				text.Name = "Text"
				text.Size = UDim2.fromScale(1, 1)
				text.BackgroundTransparency = 1
				text.TextColor3 = Color3.new(1, 1, 1)
				text.Font = Enum.Font.GothamBold
				text.TextScaled = true
				text.TextXAlignment = Enum.TextXAlignment.Left
				text.TextYAlignment = Enum.TextYAlignment.Top
				text.Parent = surface
				label = text
			end
			if label and label:IsA("TextLabel") then
				label.Text = table.concat(lines, "\n")
			end
		end
	end
end

function LeaderboardService.init()
	if LB.Enabled then
		local ok = pcall(function()
			for _, board in LB.Boards do
				stores[board.Id] = DataStoreService:GetOrderedDataStore("MonsterRoll_LB_" .. board.Id)
			end
		end)
		available = ok and not PlayerDataService.isMock()
	end
	NetServer.handle("GetLeaderboards", { Rate = 1, Burst = 3 }, function(_player)
		return NetServer.ok(cache)
	end)
end

function LeaderboardService.onPlayerRemoving(player: Player, _profile: Profile)
	task.spawn(LeaderboardService.upload, player)
end

function LeaderboardService.start()
	if not LB.Enabled then
		return
	end
	task.spawn(function()
		while true do
			task.wait(LB.UploadSeconds)
			for _, player in PlayerDataService.players() do
				LeaderboardService.upload(player)
				task.wait(0.5)
			end
		end
	end)
	task.wait(5)
	while true do
		LeaderboardService.refresh()
		task.wait(LB.RefreshSeconds)
	end
end

return LeaderboardService
