--!strict
-- Remote argument validation. Every remote argument is `unknown` until one of
-- these returns a typed value. Each helper returns nil on any violation.

local Guard = {}

local MAX_STRING = 64
local MAX_ARRAY = 100

function Guard.string(value: unknown, maxLength: number?): string?
	if typeof(value) ~= "string" then
		return nil
	end
	local s = value :: string
	if #s == 0 or #s > (maxLength or MAX_STRING) then
		return nil
	end
	-- ids are plain ascii identifiers
	if string.find(s, "[^%w_%-%.:]") then
		return nil
	end
	return s
end

function Guard.number(value: unknown, min: number, max: number): number?
	if typeof(value) ~= "number" then
		return nil
	end
	local n = value :: number
	if n ~= n or n == math.huge or n == -math.huge then
		return nil
	end
	if n < min or n > max then
		return nil
	end
	return n
end

function Guard.integer(value: unknown, min: number, max: number): number?
	local n = Guard.number(value, min, max)
	if n == nil or n ~= math.floor(n) then
		return nil
	end
	return n
end

function Guard.boolean(value: unknown): boolean?
	if typeof(value) ~= "boolean" then
		return nil
	end
	return value :: boolean
end

-- Array of unique id strings (rejects sparse tables, non-string entries, duplicates).
function Guard.stringArray(value: unknown, maxCount: number?, maxLength: number?): { string }?
	if typeof(value) ~= "table" then
		return nil
	end
	local t = value :: { [any]: any }
	local limit = maxCount or MAX_ARRAY
	local count = 0
	for key in t do
		count += 1
		if typeof(key) ~= "number" or count > limit then
			return nil
		end
	end
	if count ~= #t then
		return nil
	end
	local out: { string } = {}
	local seen: { [string]: boolean } = {}
	for i = 1, count do
		local s = Guard.string(t[i], maxLength)
		if s == nil or seen[s] then
			return nil
		end
		seen[s] = true
		out[i] = s
	end
	return out
end

-- A flat dictionary of string keys with values validated by `check`.
function Guard.record<V>(value: unknown, check: (unknown) -> V?, maxKeys: number?): { [string]: V }?
	if typeof(value) ~= "table" then
		return nil
	end
	local out: { [string]: V } = {}
	local count = 0
	for key, v in value :: { [any]: any } do
		count += 1
		if count > (maxKeys or 32) then
			return nil
		end
		local k = Guard.string(key)
		local checked = check(v)
		if k == nil or checked == nil then
			return nil
		end
		out[k] = checked
	end
	return out
end

return Guard
