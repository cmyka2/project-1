-- Test runner.
--   lune run tests/run                 -> runs every spec in its own process
--   lune run tests/run <path/to/spec>  -> runs one spec
-- Each spec runs in a fresh process so integration tests get a clean world.

local fs = require("@lune/fs")
local process = require("@lune/process")
local stdio = require("@lune/stdio")

local ROOT = process.cwd
if string.sub(ROOT, -1) == "/" then
	ROOT = string.sub(ROOT, 1, -2)
end

local args = process.args
if #args >= 1 then
	local specPath = args[1]
	local Mock = require("./harness/MockRoblox")
	local Loader = require("./harness/Loader")
	local Scheduler = require("./harness/Scheduler")
	local Test = require("./harness/Test")
	local luau = require("@lune/luau")
	Mock.echo = process.env.TEST_ECHO == "1"
	Test.setPump(function()
		Mock.advance(0.1)
	end)
	Loader.build(ROOT)
	local chunk = luau.load(fs.readFile(specPath), { debugName = specPath })
	local spec = chunk()
	print("▶ " .. specPath)
	local ok, err = xpcall(function()
		spec({ Test = Test, Loader = Loader, Mock = Mock, Scheduler = Scheduler, Root = ROOT })
	end, debug.traceback)
	local r = Test.results()
	if not ok then
		r.failed += 1
		print("  ✗ spec crashed: " .. tostring(err))
	end
	local schedulerErrors = Scheduler.errors()
	if #schedulerErrors > 0 then
		print("  ✗ " .. #schedulerErrors .. " background thread error(s) (see above)")
		r.failed += #schedulerErrors
	end
	print(string.format("  %d passed, %d failed", r.passed, r.failed))
	process.exit(if r.failed == 0 then 0 else 1)
end

local specs = {}
for _, dir in { "tests/unit", "tests/integration", "tests/balance" } do
	if fs.isDir(ROOT .. "/" .. dir) then
		local entries = fs.readDir(ROOT .. "/" .. dir)
		table.sort(entries)
		for _, entry in entries do
			if string.find(entry, "%.spec%.luau$") then
				table.insert(specs, dir .. "/" .. entry)
			end
		end
	end
end

local lune = process.env.LUNE_BIN or "lune"
local failedSpecs = {}
local totalPassed, totalFailed = 0, 0
for _, spec in specs do
	local result = process.spawn(lune, { "run", "tests/run", spec }, { cwd = ROOT, env = process.env })
	stdio.write(result.stdout)
	if result.stderr ~= "" then
		stdio.ewrite(result.stderr)
	end
	local p, f = string.match(result.stdout, "(%d+) passed, (%d+) failed")
	totalPassed += tonumber(p) or 0
	totalFailed += tonumber(f) or 0
	if not result.ok then
		table.insert(failedSpecs, spec)
		if not p then
			totalFailed += 1
		end
	end
end
print(string.rep("=", 60))
print(string.format("TOTAL: %d passed, %d failed across %d specs", totalPassed, totalFailed, #specs))
if #failedSpecs > 0 then
	print("Failed specs:\n  " .. table.concat(failedSpecs, "\n  "))
	process.exit(1)
end
process.exit(0)
