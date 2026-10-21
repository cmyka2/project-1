--!strict
-- Offline earnings (pure). Computed from timestamps on join; temporary
-- multipliers (potions, events) never apply while offline.
--   elapsed  = clamp(now - LastSeen, 0, cap)          (cap from Modifiers.offlineCapSeconds)
--   coins    = permanentIncomePerSecond * elapsed * efficiency
-- Absences shorter than EconomyConfig.OfflineMinSeconds grant nothing.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Util = Shared:WaitForChild("Util")
local EconomyConfig = require(Shared:WaitForChild("Config"):WaitForChild("EconomyConfig"))
local Modifiers = require(Util:WaitForChild("Modifiers"))
local StatMath = require(Util:WaitForChild("StatMath"))
local Types = require(Shared:WaitForChild("Types"))

export type OfflineResult = {
	Coins: number,
	ElapsedSeconds: number,
	CountedSeconds: number,
	RatePerSecond: number,
	Efficiency: number,
}

local OfflineIncome = {}

function OfflineIncome.compute(profile: Types.Profile, now: number): OfflineResult
	local elapsed = now - profile.Timestamps.LastSeen
	if elapsed ~= elapsed or elapsed < 0 then
		elapsed = 0
	end
	local mods = Modifiers.compute(profile, now)
	local cap = Modifiers.offlineCapSeconds(mods)
	local efficiency = Modifiers.offlineEfficiency(mods)
	local rate = StatMath.totalIncome(profile, mods, Modifiers.incomeMultiplier(mods, false))
	local counted = if elapsed < EconomyConfig.OfflineMinSeconds then 0 else math.min(elapsed, cap)
	local coins = math.floor(rate * counted * efficiency)
	if coins ~= coins or coins < 0 then
		coins = 0
	end
	return {
		Coins = math.min(coins, EconomyConfig.MaxCurrency),
		ElapsedSeconds = elapsed,
		CountedSeconds = counted,
		RatePerSecond = rate,
		Efficiency = efficiency,
	}
end

return OfflineIncome
