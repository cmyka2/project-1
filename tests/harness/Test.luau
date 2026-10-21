-- Minimal BDD-style test framework for Lune specs.

local Test = {}

local results = { passed = 0, failed = 0, failures = {} }
local prefix = {}

local function fmt(v)
	if type(v) == "string" then
		return string.format("%q", v)
	end
	return tostring(v)
end

function Test.describe(name, fn)
	table.insert(prefix, name)
	fn()
	table.remove(prefix)
end

local pump = nil

-- Called with no arguments to advance virtual time while a test is yielded.
function Test.setPump(fn)
	pump = fn
end

-- Runs fn in its own coroutine so tests may yield (task.wait, remotes...).
local function runYieldable(fn)
	local done, ok, err = false, true, nil
	local thread = coroutine.create(function()
		local success, message = xpcall(fn, debug.traceback)
		ok, err = success, message
		done = true
	end)
	local resumed, resumeErr = coroutine.resume(thread)
	if not resumed then
		return false, resumeErr
	end
	local guard = 0
	while not done do
		guard += 1
		if guard > 20000 or not pump then
			return false, "test never finished (yielded without a pump or ran too long)"
		end
		pump()
	end
	return ok, err
end

function Test.it(name, fn)
	local full = table.concat(prefix, " > ") .. " > " .. name
	local ok, err = runYieldable(fn)
	if ok then
		results.passed += 1
		print("  ✓ " .. full)
	else
		results.failed += 1
		table.insert(results.failures, { name = full, err = err })
		print("  ✗ " .. full .. "\n      " .. tostring(err))
	end
end

function Test.expect(actual)
	local e = {}
	function e.toBe(expected)
		if actual ~= expected then
			error("expected " .. fmt(expected) .. ", got " .. fmt(actual), 2)
		end
	end
	function e.toEqual(expected)
		e.toBe(expected)
	end
	function e.toBeTruthy()
		if not actual then
			error("expected truthy, got " .. fmt(actual), 2)
		end
	end
	function e.toBeFalsy()
		if actual then
			error("expected falsy, got " .. fmt(actual), 2)
		end
	end
	function e.toBeNil()
		if actual ~= nil then
			error("expected nil, got " .. fmt(actual), 2)
		end
	end
	function e.notToBeNil()
		if actual == nil then
			error("expected a value, got nil", 2)
		end
	end
	function e.toBeNear(expected, tolerance)
		if type(actual) ~= "number" or math.abs(actual - expected) > (tolerance or 1e-9) then
			error(
				"expected " .. fmt(expected) .. " ± " .. fmt(tolerance or 1e-9) .. ", got " .. fmt(actual),
				2
			)
		end
	end
	function e.toBeGreaterThan(expected)
		if not (actual > expected) then
			error("expected > " .. fmt(expected) .. ", got " .. fmt(actual), 2)
		end
	end
	function e.toBeAtLeast(expected)
		if not (actual >= expected) then
			error("expected >= " .. fmt(expected) .. ", got " .. fmt(actual), 2)
		end
	end
	function e.toBeLessThan(expected)
		if not (actual < expected) then
			error("expected < " .. fmt(expected) .. ", got " .. fmt(actual), 2)
		end
	end
	function e.toBeAtMost(expected)
		if not (actual <= expected) then
			error("expected <= " .. fmt(expected) .. ", got " .. fmt(actual), 2)
		end
	end
	function e.toContain(item)
		if type(actual) == "string" then
			if not string.find(actual, item, 1, true) then
				error("expected string to contain " .. fmt(item) .. ", got " .. fmt(actual), 2)
			end
			return
		end
		if not table.find(actual, item) then
			error("expected table to contain " .. fmt(item), 2)
		end
	end
	function e.toThrow()
		local ok = pcall(actual)
		if ok then
			error("expected function to throw", 2)
		end
	end
	return e
end

function Test.results()
	return results
end

return Test
