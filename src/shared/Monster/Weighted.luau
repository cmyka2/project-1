-- Weighted random selection shared by monster rolls, chests and drops.
-- entries = { { value, weight }, ... } in a fixed order so a seeded Random gives repeatable results.
-- Invalid weights (non-numbers, NaN, negative, infinite) count as 0; an all-zero or empty pool picks nothing.
local W = {}

function W.clean(w: any): number
	if typeof(w) ~= "number" or w ~= w or w <= 0 or w == math.huge then return 0 end
	return w
end

-- probabilities in entry order, summing to 1; nil for an empty/zero pool
function W.odds(entries): { number }?
	local total = 0
	for _, e in entries do total += W.clean(e[2]) end
	if total <= 0 then return nil end
	local out = {}
	for i, e in entries do out[i] = W.clean(e[2]) / total end
	return out
end

function W.pick(entries, rng: Random): any
	local total = 0
	for _, e in entries do total += W.clean(e[2]) end
	if total <= 0 then return nil end
	local r, last = rng:NextNumber() * total, nil
	for _, e in entries do
		local w = W.clean(e[2])
		if w > 0 then
			last = e[1]
			r -= w
			if r < 0 then return e[1] end
		end
	end
	return last -- float rounding on the final entry
end

return W
