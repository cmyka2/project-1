-- run from the command bar: print(require(game.ServerStorage.Tests.RunAll)())
return function()
	local out = {}
	for _, name in { "RollSpec", "BattleSpec", "ProgressionSpec" } do
		local ok, res = pcall(require(script.Parent[name]))
		table.insert(out, (ok and "PASS " or "FAIL ") .. name .. ": " .. tostring(res))
	end
	return table.concat(out, "\n")
end
