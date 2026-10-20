-- Hex upgrade tree. q/r = flat-top axial hex coords (Start at 0,0).
-- effect: summed per effect by Tree.stat, the single place skill bonuses are read from (each applies once).
local Tree = {}
local function n(id, name, icon, q, r, cost, requires, effect, value)
	return { id = id, name = name, icon = icon, q = q, r = r, cost = cost, requires = requires, effect = effect, value = value }
end
Tree.Nodes = {
	n("start", "Start", "🌳", 0, 0, 0),
	n("money1", "Money I", "💵", -1, 0, 100, "start", "income", 0.25),
	n("money2", "Money II", "💵", -2, 0, 1000, "money1", "income", 0.25),
	n("money3", "Money III", "💵", -2, -1, 10000, "money2", "income", 0.5),
	n("money4", "Money IV", "💵", -3, -1, 2000000, "money3", "income", 0.5),
	n("money5", "Money V", "💵", -4, -1, 20000000, "money4", "income", 1),
	n("sell1", "Sell I", "💰", -3, 0, 500000, "money2", "sell", 0.2),
	n("luck1", "Luck I", "🍀", 1, -1, 250, "start", "luck", 0.1),
	n("luck2", "Luck II", "🍀", 1, -2, 2500, "luck1", "luck", 0.15),
	n("luck3", "Luck III", "🍀", 2, -3, 25000, "luck2", "luck", 0.25),
	n("luck4", "Luck IV", "🍀", 3, -4, 250000, "luck3", "luck", 0.5),
	n("rollspeed1", "Roll Speed I", "🎲", 2, -2, 1000000, "luck2", "rollspeed", 0.15),
	n("rollspeed2", "Roll Speed II", "🎲", 3, -2, 10000000, "rollspeed1", "rollspeed", 0.15),
	n("dmg1", "Damage I", "🗡️", 0, 1, 500, "start", "damage", 0.1),
	n("dmg2", "Damage II", "🗡️", 1, 1, 5000, "dmg1", "damage", 0.1),
	n("dmg3", "Damage III", "🗡️", 1, 2, 50000, "dmg2", "damage", 0.2),
	n("hp1", "Health I", "❤️", 2, 1, 1000, "dmg2", "health", 0.1),
	n("hp2", "Health II", "❤️", 3, 1, 10000, "hp1", "health", 0.2),
	n("storage1", "Unit Storage I", "🎒", -1, 1, 300, "start", "storage", 25),
	n("storage2", "Unit Storage II", "🎒", -2, 2, 3000, "storage1", "storage", 25),
	n("storage3", "Unit Storage III", "🎒", -2, 3, 1000000, "storage2", "storage", 50),
	n("walk1", "Walkspeed I", "👟", -1, 2, 250000, "storage1", "walkspeed", 4),
	n("walk2", "Walkspeed II", "👟", -1, 3, 2500000, "walk1", "walkspeed", 4),
}
Tree.ById = {}
for _, node in Tree.Nodes do Tree.ById[node.id] = node end

Tree.Live = { income = true, luck = true, rollspeed = true, walkspeed = true, damage = true, health = true, storage = true, sell = true }
function Tree.describe(node)
	if not node.effect then return "The root of your tree." end
	local v = node.value
	local d = ({
		income = "+" .. v * 100 .. "% income", luck = "+" .. v * 100 .. "% luck", rollspeed = "-" .. v * 100 .. "% roll cooldown",
		walkspeed = "+" .. v .. " walk speed", sell = "+" .. v * 100 .. "% sell value", damage = "+" .. v * 100 .. "% damage",
		health = "+" .. v * 100 .. "% health", storage = "+" .. v .. " backpack space",
	})[node.effect]
	return Tree.Live[node.effect] and d or d .. " (not active yet)"
end

-- sum of an effect over owned nodes; owned = { [nodeId] = true }
function Tree.stat(owned, effect)
	local s = 0
	for id in owned do
		local node = Tree.ById[id]
		if node and node.effect == effect then s += node.value end
	end
	return s
end
return Tree
