--!strict
-- Thin, failure-proof wrapper over Roblox's AnalyticsService plus in-memory
-- counters for the QA cheat panel. Analytics must never break gameplay, so
-- every call is pcall'd and rate-free.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig =
	require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("GameConfig"))

local RobloxAnalytics: any = nil
pcall(function()
	RobloxAnalytics = game:GetService("AnalyticsService")
end)

local AnalyticsService = {}

local counters: { [string]: number } = {}

function AnalyticsService.count(name: string, amount: number?)
	counters[name] = (counters[name] or 0) + (amount or 1)
end

function AnalyticsService.counters(): { [string]: number }
	return table.clone(counters)
end

function AnalyticsService.economy(
	player: Player,
	flow: "Source" | "Sink",
	currency: string,
	amount: number,
	balance: number,
	reason: string
)
	AnalyticsService.count(flow .. ":" .. currency, amount)
	if not GameConfig.Analytics.Enabled or not RobloxAnalytics or amount <= 0 then
		return
	end
	pcall(function()
		local flowType = if flow == "Source"
			then Enum.AnalyticsEconomyFlowType.Source
			else Enum.AnalyticsEconomyFlowType.Sink
		RobloxAnalytics:LogEconomyEvent(
			player,
			flowType,
			currency,
			math.floor(math.min(amount, 2 ^ 52)),
			math.floor(math.min(balance, 2 ^ 52)),
			Enum.AnalyticsEconomyTransactionType.Gameplay.Name,
			string.sub(reason, 1, 50)
		)
	end)
end

function AnalyticsService.event(player: Player, name: string, value: number?)
	AnalyticsService.count(name)
	if not GameConfig.Analytics.Enabled or not RobloxAnalytics then
		return
	end
	pcall(function()
		RobloxAnalytics:LogCustomEvent(player, string.sub(name, 1, 50), value or 1)
	end)
end

function AnalyticsService.init() end

return AnalyticsService
