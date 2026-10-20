-- Remote request guards: per-player rate limits and argument checks. Every remote handler starts here.
local Players = game:GetService("Players")
local G = {}
local BURST, REFILL = 12, 8 -- token bucket across all remotes: 12 back-to-back, then 8/s
local last, bucket = {}, {}

-- true if this player may run `action` now (min `interval` s between calls of that action, plus the shared bucket)
function G.rate(player: Player, action: string, interval: number): boolean
	local now = os.clock()
	local b = bucket[player] or { n = BURST, t = now }
	b.n = math.min(BURST, b.n + (now - b.t) * REFILL)
	b.t = now
	bucket[player] = b
	local l = last[player] or {}
	last[player] = l
	if b.n < 1 or (l[action] and now - l[action] < interval) then return false end
	b.n -= 1
	l[action] = now
	return true
end

-- a short plain string id (nil for anything else)
function G.str(x: any): string?
	return typeof(x) == "string" and #x > 0 and #x <= 64 and x or nil
end
-- an integer in [lo, hi] (nil for anything else, including NaN/inf)
function G.int(x: any, lo: number, hi: number): number?
	return typeof(x) == "number" and x % 1 == 0 and x >= lo and x <= hi and x or nil
end
-- an array of 1..max distinct ids
function G.ids(x: any, max: number): { string }?
	if typeof(x) ~= "table" or #x < 1 or #x > max then return nil end
	local seen, n = {}, 0
	for i, v in x do
		if typeof(i) ~= "number" or not G.str(v) or seen[v] then return nil end
		seen[v], n = true, n + 1
	end
	return n == #x and x or nil
end

Players.PlayerRemoving:Connect(function(p) last[p] = nil bucket[p] = nil end)
return G
