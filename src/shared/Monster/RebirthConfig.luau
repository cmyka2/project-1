-- Rebirth rules. Each rebirth: pay the cost, cash resets, +1 base slot. Everything else is kept.
local Rebirth = {}
Rebirth.Resets = { "Cash" }
Rebirth.Keeps = { "Monsters", "Index", "Placed monsters", "Upgrade tree" }
function Rebirth.cost(rebirths: number)
	return math.floor(25000 * 3 ^ rebirths)
end
return Rebirth
