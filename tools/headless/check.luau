-- Syntax-checks (compiles) every .luau file passed on the command line.
local bad = 0
for _, f in ARGS do
	local ok, err = pcall(compile, readfile(f), f)
	if not ok then bad += 1 print("FAIL " .. tostring(err)) end
end
print(#ARGS .. " files, " .. bad .. " syntax errors")
if bad > 0 then error("syntax errors") end
