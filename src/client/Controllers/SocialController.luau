--!strict
-- Trading window (request / accept / offer / confirm / countdown) and the
-- leaderboards panel. The server owns every trade state transition.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Util = Shared:WaitForChild("Util")
local MonsterConfig = require(Config:WaitForChild("MonsterConfig"))
local GameConfig = require(Config:WaitForChild("GameConfig"))
local Format = require(Util:WaitForChild("Format"))
local Net = require(Shared:WaitForChild("Net"))
local UI = script.Parent.Parent:WaitForChild("UI")
local Kit = require(UI:WaitForChild("Kit"))
local Theme = require(UI:WaitForChild("Theme"))
local Icons = require(UI:WaitForChild("Icons"))
local Cards = require(UI:WaitForChild("Cards"))
local StateController = require(script.Parent:WaitForChild("StateController"))
local UIController = require(script.Parent:WaitForChild("UIController"))

local C = Theme.Colors
local localPlayer = Players.LocalPlayer

local SocialController = {}

local trade: any = nil
local renderTrade: (() -> ())? = nil
local renderBoards: (() -> ())? = nil

local function offerList(parent: Instance, offer: { any })
	Kit.clear(parent)
	for i, entry in offer do
		local def = MonsterConfig.Monsters[entry.MonsterId]
		local row = Kit.card({ Size = UDim2.new(1, -6, 0, 46), LayoutOrder = i, Parent = parent })
		local holder = Kit.frame({
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(40, 40),
			Position = UDim2.fromOffset(3, 3),
			Parent = row,
		})
		Icons.monster(entry.MonsterId, holder)
		Kit.text({
			Text = string.format(
				"%s  Lv%d +%d %s",
				if def then def.DisplayName else "?",
				entry.Level,
				entry.Upgrade,
				string.rep("★", entry.Stars)
			),
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(1, -54, 1, -8),
			Position = UDim2.fromOffset(50, 4),
			MaxTextSize = 15,
			Parent = row,
		})
	end
	if #offer == 0 then
		Kit.text({
			Text = "Nothing offered yet",
			TextColor3 = C.Muted,
			Size = UDim2.new(1, 0, 0, 30),
			Parent = parent,
		})
	end
end

local function chooseOffer()
	local profile = StateController.Profile
	if not profile or not trade then
		return
	end
	local candidates = {}
	for _, inst in StateController.monsters() do
		if
			not StateController.slotOf(inst.Id)
			and not inst.Locked
			and not inst.Favorite
			and not StateController.inTeam(inst.Id)
		then
			table.insert(candidates, inst)
		end
	end
	local pre = {}
	for _, entry in trade.MyOffer do
		table.insert(pre, entry.Id)
	end
	Cards.picker({
		Title = "Choose monsters to offer (unlocked, not placed, not in team)",
		Candidates = candidates,
		Max = GameConfig.Social.TradeMaxMonsters,
		Min = 0,
		Preselected = pre,
		ConfirmText = "Update Offer",
		Overlay = UIController.overlay(),
		OnConfirm = function(ids)
			UIController.call("TradeSetOffer", ids)
		end,
	})
end

local function buildTrade(body: Frame)
	local lobby = Kit.frame({ BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = body })
	local playersList =
		Kit.scroll({ Size = UDim2.new(1, 0, 1, -40), Position = UDim2.fromOffset(0, 40), Parent = lobby })
	Kit.list(playersList, Enum.FillDirection.Vertical, 6)
	Kit.header("Players in this server", { Parent = lobby })
	local window = Kit.frame({
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		Parent = body,
	})
	local status = Kit.header("", { Parent = window })
	local mine = Kit.frame({
		BackgroundColor3 = C.PanelDark,
		Size = UDim2.new(0.5, -6, 1, -110),
		Position = UDim2.fromOffset(0, 36),
		Parent = window,
	})
	Kit.corner(mine)
	Kit.padding(mine, 6)
	local mineTitle = Kit.text({
		Text = "Your offer",
		Font = Theme.Fonts.Bold,
		Size = UDim2.new(1, 0, 0, 24),
		MaxTextSize = 16,
		Parent = mine,
	})
	local mineList =
		Kit.scroll({ Size = UDim2.new(1, 0, 1, -28), Position = UDim2.fromOffset(0, 28), Parent = mine })
	Kit.list(mineList, Enum.FillDirection.Vertical, 4)
	local theirs = Kit.frame({
		BackgroundColor3 = C.PanelDark,
		Size = UDim2.new(0.5, -6, 1, -110),
		Position = UDim2.new(0.5, 6, 0, 36),
		Parent = window,
	})
	Kit.corner(theirs)
	Kit.padding(theirs, 6)
	local theirsTitle = Kit.text({
		Text = "Their offer",
		Font = Theme.Fonts.Bold,
		Size = UDim2.new(1, 0, 0, 24),
		MaxTextSize = 16,
		Parent = theirs,
	})
	local theirsList =
		Kit.scroll({ Size = UDim2.new(1, 0, 1, -28), Position = UDim2.fromOffset(0, 28), Parent = theirs })
	Kit.list(theirsList, Enum.FillDirection.Vertical, 4)
	local buttons = Kit.frame({
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 60),
		Position = UDim2.new(0, 0, 1, -64),
		Parent = window,
	})
	Kit.list(buttons, Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Center)
	local editButton = Kit.button(
		"Edit offer",
		"Primary",
		chooseOffer,
		{ Size = UDim2.fromOffset(170, 52), Parent = buttons }
	)
	local confirmButton = Kit.button("Confirm ✓", "Good", function()
		UIController.call("TradeConfirm")
	end, { Size = UDim2.fromOffset(170, 52), Parent = buttons })
	local acceptButton = Kit.button("Accept request", "Good", function()
		UIController.call("TradeRespond", true)
	end, { Size = UDim2.fromOffset(170, 52), Parent = buttons })
	Kit.button("Cancel ✕", "Bad", function()
		if trade and trade.State == "Pending" and not trade.IsRequester then
			UIController.call("TradeRespond", false)
		else
			UIController.call("TradeCancel")
		end
	end, { Size = UDim2.fromOffset(170, 52), Parent = buttons })

	local function doRender()
		lobby.Visible = trade == nil
		window.Visible = trade ~= nil
		if not trade then
			Kit.clear(playersList)
			local i = 0
			for _, p in Players:GetPlayers() do
				if p ~= localPlayer then
					i += 1
					local row =
						Kit.card({ Size = UDim2.new(1, -8, 0, 52), LayoutOrder = i, Parent = playersList })
					Kit.text({
						Text = p.DisplayName .. " (@" .. p.Name .. ")",
						TextXAlignment = Enum.TextXAlignment.Left,
						Size = UDim2.new(1, -170, 1, -8),
						Position = UDim2.fromOffset(10, 4),
						MaxTextSize = 17,
						Parent = row,
					})
					Kit.button("Request trade", "Primary", function()
						local r = UIController.call("TradeRequest", p.UserId)
						if r.ok then
							UIController.toast("info", "Trade request sent to " .. p.DisplayName)
						end
					end, {
						Size = UDim2.fromOffset(150, 40),
						Position = UDim2.new(1, -156, 0, 6),
						Parent = row,
					})
				end
			end
			if i == 0 then
				Kit.text({
					Text = "Nobody else is here yet. Invite a friend!",
					TextColor3 = C.Muted,
					Size = UDim2.new(1, 0, 0, 40),
					Parent = playersList,
				})
			end
			return
		end
		local stateText = trade.State
		if trade.State == "Pending" then
			stateText = if trade.IsRequester
				then "Waiting for " .. trade.Partner .. " to accept…"
				else trade.Partner .. " wants to trade with you!"
		elseif trade.State == "Countdown" then
			stateText = "Both confirmed! Completing in "
				.. math.max(0, trade.CountdownEnd - StateController.serverTime())
				.. "s…"
		else
			stateText = "Trading with " .. trade.Partner
		end
		status.Text = "🤝 " .. stateText
		mineTitle.Text = "Your offer" .. (if trade.MyConfirmed then " ✓ confirmed" else "")
		theirsTitle.Text = trade.Partner
			.. "'s offer"
			.. (if trade.TheirConfirmed then " ✓ confirmed" else "")
		offerList(mineList, trade.MyOffer)
		offerList(theirsList, trade.TheirOffer)
		editButton.Visible = trade.State == "Active" or trade.State == "Countdown"
		confirmButton.Visible = trade.State == "Active"
		Kit.setEnabled(confirmButton, not trade.MyConfirmed and (#trade.MyOffer > 0 or #trade.TheirOffer > 0))
		acceptButton.Visible = trade.State == "Pending" and not trade.IsRequester
	end
	renderTrade = doRender
	doRender()
end

local function buildBoards(body: Frame)
	local content = Kit.frame({
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, -46),
		Position = UDim2.fromOffset(0, 46),
		Parent = body,
	})
	local list = Kit.scroll({ Parent = content })
	Kit.list(list, Enum.FillDirection.Vertical, 4)
	local data: any = {}
	local boardIndex = 1
	local names = {}
	for _, b in GameConfig.Leaderboards.Boards do
		table.insert(names, b.DisplayName)
	end
	local function render()
		Kit.clear(list)
		local board = GameConfig.Leaderboards.Boards[boardIndex]
		local rows = data[board.Id] or {}
		for i, row in rows do
			local card = Kit.card({
				Size = UDim2.new(1, -8, 0, 40),
				LayoutOrder = i,
				BackgroundColor3 = if row.UserId == localPlayer.UserId
					then C.Accent:Lerp(C.PanelDark, 0.5)
					else C.PanelLight,
				Parent = list,
			})
			local medal = if row.Rank == 1
				then "🥇"
				elseif row.Rank == 2 then "🥈"
				elseif row.Rank == 3 then "🥉"
				else "#" .. row.Rank
			Kit.text({
				Text = medal .. "  " .. row.Name,
				TextXAlignment = Enum.TextXAlignment.Left,
				Size = UDim2.new(0.7, 0, 1, -6),
				Position = UDim2.fromOffset(10, 3),
				MaxTextSize = 17,
				Parent = card,
			})
			Kit.text({
				Text = Format.number(row.Value),
				Font = Theme.Fonts.Bold,
				TextXAlignment = Enum.TextXAlignment.Right,
				Size = UDim2.new(0.3, -16, 1, -6),
				Position = UDim2.new(0.7, 0, 0, 3),
				MaxTextSize = 17,
				Parent = card,
			})
		end
		if #rows == 0 then
			Kit.text({
				Text = "No entries yet (leaderboards refresh every couple of minutes).",
				TextColor3 = C.Muted,
				Size = UDim2.new(1, 0, 0, 40),
				Parent = list,
			})
		end
	end
	local _, selectTab = Kit.tabs(body, names, function(index)
		boardIndex = index
		render()
	end)
	renderBoards = function()
		local result = Net.request("GetLeaderboards")
		if result.ok then
			data = result.data
		end
		render()
	end
	selectTab(1)
end

function SocialController.init()
	UIController.registerPanel({
		Id = "Trade",
		Title = "Trading Post",
		Glyph = "🤝",
		Build = buildTrade,
		OnOpen = function()
			if renderTrade then
				renderTrade()
			end
		end,
	})
	UIController.registerPanel({
		Id = "Leaderboards",
		Title = "Leaderboards",
		Glyph = "📊",
		Build = buildBoards,
		OnOpen = function()
			if renderBoards then
				task.spawn(renderBoards)
			end
		end,
	})
	Net.on("TradeUpdate", function(state: any)
		local wasNil = trade == nil
		trade = state
		if state and wasNil and state.State == "Pending" and not state.IsRequester then
			UIController.toast("info", "🤝 " .. state.Partner .. " wants to trade! Open the Trading Post.")
			UIController.open("Trade")
		end
		if renderTrade and UIController.openId() == "Trade" then
			renderTrade()
		end
	end)
end

function SocialController.start()
	while true do
		task.wait(1)
		if trade and trade.State == "Countdown" and renderTrade and UIController.openId() == "Trade" then
			renderTrade()
		end
	end
end

return SocialController
