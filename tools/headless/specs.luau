-- Runs ServerStorage/Tests (the same specs Studio runs via require) on the mock runtime.
local R = compile(readfile("tools/headless/mockrbx.luau"), "mockrbx")()
local out
R.task.spawn(function() out = R.req(R.SS.Tests.RunAll)() end)
print(out)
if out:find("FAIL") then error("spec failures") end
