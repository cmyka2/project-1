-- New-player guide: a tip line plus a glowing 3D beam to wherever the current quest happens (no forced tutorial;
-- it simply points at the next goal and disappears after the first rebirth). Purely visual.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local Http = game:GetService("HttpService")
local P = require(RS:WaitForChild("Monster"):WaitForChild("ProgressConfig"))
local player = Players.LocalPlayer
local state = player:WaitForChild("PlayerGui"):WaitForChild("State") -- private mirror of my save, written by the server

-- what each quest stat asks the player to do: tip text + where in the world (hub child name, "base" or nil)
local GUIDE = {
	rolls = { "Press 🎲 ROLL (or R) to roll monsters", nil },
	discoveries = { "Keep rolling to discover new monsters (INDEX shows them all)", nil },
	placed = { "Monsters on your base earn cash. Tap ⭐ PLACE BEST", "base" },
	upgrades = { "Open BAG and upgrade your best monster", "base" },
	earned = { "Let your base earn, then buy a better die at the Dice Shop", "DiceShop" },
	chests = { "Open a chest at the Chest Shop for gear", "ChestShop" },
	wins = { "Press BATTLE and win a fight with your team", nil },
	bosses = { "Beat the Grassland boss in BATTLE", nil },
	fusions = { "BAG: fuse 3 copies of a monster to make it stronger", nil },
	rebirths = { "Rebirth at the Rebirth Altar for permanent bonuses", "RebirthAltar" },
}

local gui = Instance.new("ScreenGui") gui.Name = "GuideUI" gui.ResetOnSpawn = false gui.Parent = player:WaitForChild("PlayerGui")
local tip = Instance.new("TextLabel") tip.AnchorPoint = Vector2.new(0.5, 1) tip.Position = UDim2.new(0.5, 0, 1, -170) tip.Size = UDim2.fromScale(0.5, 0.045)
tip.BackgroundColor3 = Color3.fromRGB(20, 24, 34) tip.BackgroundTransparency = 0.25 tip.Font = Enum.Font.FredokaOne tip.TextScaled = true
tip.TextColor3 = Color3.fromRGB(255, 230, 120) tip.TextStrokeTransparency = 0 tip.Text = "" tip.Visible = false tip.Parent = gui
Instance.new("UICorner", tip)
local lim = Instance.new("UISizeConstraint") lim.MaxSize = Vector2.new(640, 40) lim.Parent = tip

local beam, a0, a1
local function clearBeam()
	for _, x in { beam, a0, a1 } do if x then x:Destroy() end end
	beam, a0, a1 = nil, nil, nil
end
local function targetPart(where)
	local hub = workspace:FindFirstChild("Hub")
	if not hub or not where then return nil end
	if where == "base" then
		local id = player:GetAttribute("PlotId")
		local plot = id and hub:FindFirstChild("Plots") and hub.Plots:FindFirstChild("Plot" .. id)
		return plot and (plot:FindFirstChild("SpawnPoint") or plot.PrimaryPart)
	end
	local m = hub:FindFirstChild(where, true)
	return m and (m:IsA("BasePart") and m or m:FindFirstChildWhichIsA("BasePart", true))
end

while true do
	local ok, pr = pcall(Http.JSONDecode, Http, state:GetAttribute("Progress") or "")
	local quests = ok and pr.quests or {}
	local current
	for _, q in P.Quests do if not quests[q.id] then current = q break end end
	local done = (state:GetAttribute("Rebirths") or 0) >= 1 or not current
	local g = current and GUIDE[current.stat]
	tip.Visible = not done and g ~= nil
	if tip.Visible then tip.Text = "➡ " .. g[1] .. "  (" .. current.text .. ")" end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local target = not done and g and targetPart(g[2])
	if target and root and (root.Position - target.Position).Magnitude > 20 then
		if not beam or a1.Parent ~= target or a0.Parent ~= root then
			clearBeam()
			a0 = Instance.new("Attachment") a0.Parent = root
			a1 = Instance.new("Attachment") a1.Position = Vector3.new(0, 4, 0) a1.Parent = target
			beam = Instance.new("Beam") beam.Attachment0, beam.Attachment1 = a0, a1
			beam.Color = ColorSequence.new(Color3.fromRGB(255, 230, 90)) beam.Width0, beam.Width1 = 0.6, 0.6 beam.FaceCamera = true
			beam.LightEmission = 1 beam.Transparency = NumberSequence.new(0.2) beam.Parent = root
		end
	else
		clearBeam()
	end
	task.wait(0.5)
end
