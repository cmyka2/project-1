--!strict
-- Small table helpers shared by server and client.

local TableUtil = {}

function TableUtil.deepCopy<T>(value: T): T
	if typeof(value) ~= "table" then
		return value
	end
	local out = {}
	for k, v in value :: any do
		out[TableUtil.deepCopy(k)] = TableUtil.deepCopy(v)
	end
	return (out :: any) :: T
end

function TableUtil.count(t: { [any]: any }): number
	local n = 0
	for _ in t do
		n += 1
	end
	return n
end

function TableUtil.keys<K, V>(t: { [K]: V }): { K }
	local out = {}
	for k in t do
		table.insert(out, k)
	end
	return out
end

function TableUtil.sortedKeys(t: { [string]: any }): { string }
	local out = {}
	for k in t do
		table.insert(out, k)
	end
	table.sort(out)
	return out
end

return TableUtil
