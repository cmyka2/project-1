--!strict
-- Display formatting helpers (numbers, durations, percentages).

local Format = {}

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }

local function trim(s: string): string
	if string.find(s, "%.") then
		s = string.gsub(s, "0+$", "")
		s = string.gsub(s, "%.$", "")
	end
	return s
end

-- 1234 -> "1.23K", 1e15 -> "1Qa". Non-finite values show as "∞"/"0".
function Format.number(value: number, decimals: number?): string
	if value ~= value then
		return "0"
	end
	if value == math.huge or value == -math.huge then
		return if value > 0 then "∞" else "-∞"
	end
	local sign = if value < 0 then "-" else ""
	local n = math.abs(value)
	if n < 1000 then
		if n == math.floor(n) then
			return sign .. tostring(math.floor(n))
		end
		return sign .. trim(string.format("%.1f", n))
	end
	local tier = math.min(math.floor(math.log10(n) / 3), #SUFFIXES - 1)
	local scaled = n / 10 ^ (tier * 3)
	local d = decimals or (if scaled >= 100 then 0 elseif scaled >= 10 then 1 else 2)
	local text = trim(string.format("%." .. d .. "f", scaled))
	if tier >= #SUFFIXES - 1 and n >= 10 ^ (#SUFFIXES * 3) then
		return sign .. string.format("%.2e", n)
	end
	return sign .. text .. SUFFIXES[tier + 1]
end

function Format.commas(value: number): string
	local s = tostring(math.floor(math.abs(value)))
	local out = string.reverse((string.gsub(string.reverse(s), "(%d%d%d)", "%1,")))
	out = string.gsub(out, "^,", "")
	return (if value < 0 then "-" else "") .. out
end

function Format.percent(fraction: number, decimals: number?): string
	local pct = fraction * 100
	if pct ~= 0 and math.abs(pct) < 0.01 then
		return string.format("%.4f%%", pct)
	end
	return trim(string.format("%." .. (decimals or 2) .. "f", pct)) .. "%"
end

-- "1 in 2,500" style odds for rare chances
function Format.oneIn(fraction: number): string
	if fraction <= 0 then
		return "—"
	end
	return "1 in " .. Format.commas(math.floor(1 / fraction + 0.5))
end

function Format.duration(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	local h = math.floor(seconds / 3600)
	local m = math.floor((seconds % 3600) / 60)
	local s = seconds % 60
	if h > 0 then
		return string.format("%dh %02dm", h, m)
	elseif m > 0 then
		return string.format("%dm %02ds", m, s)
	end
	return string.format("%ds", s)
end

return Format
