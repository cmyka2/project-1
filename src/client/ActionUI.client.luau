-- Action buttons: ROLL (always on screen, bottom centre; R key too) and AUTO, DASH (Q) once Longer Dash is owned,
-- TRAVEL with Portal Mastery.
-- Rolling and travel are validated on the server; dashing is plain character movement (client-owned in Roblox).
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")
local RollAction = RS:WaitForChild("Monster"):WaitForChild("RollAction")
local ProgressAction = RS.Monster:WaitForChild("ProgressAction")
local player = Players.LocalPlayer
local state = player:WaitForChild("PlayerGui"):WaitForChild("State") -- private mirror of my save, written by the server

local function btn(parent, str, size, pos, color)
	local b = Instance.new("TextButton") b.Size = size b.Position = pos b.BackgroundColor3 = color b.Font = Enum.Font.FredokaOne
	b.TextScaled = true b.Text = str b.TextColor3 = Color3.new(1, 1, 1) b.TextStrokeTransparency = 0 b.Parent = parent
	Instance.new("UICorner", b)
	local st = Instance.new("UIStroke", b) st.Thickness = 3 st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	return b
end
local gui = Instance.new("ScreenGui") gui.Name = "ActionUI" gui.ResetOnSpawn = false gui.Parent = player:WaitForChild("PlayerGui")
-- big ROLL button bottom centre (the genre's main button), AUTO next to it; the rest in a bottom-right column
local roll = btn(gui, "🎲 ROLL", UDim2.fromOffset(200, 72), UDim2.new(0.5, -100, 1, -92), Color3.fromRGB(230, 170, 40))
roll.TextColor3 = Color3.new(1, 1, 1)
local autoB = btn(gui, "AUTO: OFF", UDim2.fromOffset(110, 44), UDim2.new(0.5, 110, 1, -78), Color3.fromRGB(90, 90, 110))
local dash = btn(gui, "DASH (Q)", UDim2.fromOffset(130, 40), UDim2.new(1, -142, 1, -156), Color3.fromRGB(150, 80, 230))
local travelB = btn(gui, "🌀 TRAVEL", UDim2.fromOffset(130, 40), UDim2.new(1, -142, 1, -310), Color3.fromRGB(40, 140, 200))
local menu = Instance.new("Frame") menu.AnchorPoint = Vector2.new(1, 1) menu.Position = UDim2.new(1, -150, 1, -150) menu.Size = UDim2.fromOffset(180, 360)
menu.BackgroundColor3 = Color3.fromRGB(25, 30, 45) menu.Visible = false menu.Parent = gui
Instance.new("UICorner", menu)
local ml = Instance.new("UIListLayout") ml.Padding = UDim.new(0, 4) ml.HorizontalAlignment = Enum.HorizontalAlignment.Center ml.Parent = menu
local msg = Instance.new("TextLabel") msg.AnchorPoint = Vector2.new(1, 1) msg.Position = UDim2.new(1, -150, 1, -320) msg.Size = UDim2.fromOffset(300, 26)
msg.BackgroundTransparency = 1 msg.Font = Enum.Font.FredokaOne msg.TextScaled = true msg.Text = "" msg.TextColor3 = Color3.fromRGB(255, 160, 160)
msg.TextStrokeTransparency = 0 msg.TextXAlignment = Enum.TextXAlignment.Right msg.Parent = gui
local function say(t) msg.Text = t or "" task.delay(3, function() if msg.Text == t then msg.Text = "" end end) end

local autoOn = false
local function doRoll()
	local ok, err = RollAction:InvokeServer("roll")
	if not ok then say(err) end
end
roll.MouseButton1Click:Connect(doRoll)
autoB.MouseButton1Click:Connect(function()
	local ok, err = RollAction:InvokeServer("auto", not autoOn)
	if ok then autoOn = not autoOn else say(err) end
	autoB.Text = autoOn and "AUTO: ON" or "AUTO: OFF"
	autoB.BackgroundColor3 = autoOn and Color3.fromRGB(60, 170, 80) or Color3.fromRGB(90, 90, 110)
end)

-- dash: a short burst along the camera-facing ground direction
local lastDash = 0
local function doDash()
	local studs = state:GetAttribute("Dash") or 0
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if studs <= 0 or not root or os.clock() - lastDash < (state:GetAttribute("DashCooldown") or 3) then return end
	lastDash = os.clock()
	local look = workspace.CurrentCamera.CFrame.LookVector
	local dir = Vector3.new(look.X, 0, look.Z)
	if dir.Magnitude < 0.1 then return end
	local att = Instance.new("Attachment") att.Parent = root
	local lv = Instance.new("LinearVelocity") lv.Attachment0 = att lv.MaxForce = 1e6 lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	lv.PrimaryTangentAxis, lv.SecondaryTangentAxis = Vector3.xAxis, Vector3.zAxis
	local v = dir.Unit * (studs / 0.2)
	lv.PlaneVelocity = Vector2.new(v.X, v.Z) lv.RelativeTo = Enum.ActuatorRelativeTo.World lv.Parent = root
	task.delay(0.2, function() lv:Destroy() att:Destroy() end)
end
dash.MouseButton1Click:Connect(doDash)
UIS.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.Q then doDash() end
	if input.KeyCode == Enum.KeyCode.R then doRoll() end
end)

local DEST = {
	{ "base", "My Base" }, { "SummonArea", "Summon" }, { "DiceShop", "Dice Shop" }, { "ChestShop", "Chest Shop" },
	{ "UpgradeTree", "Evolution Tree" }, { "RebirthAltar", "Rebirth Altar" }, { "Index", "Monster Index" },
	{ "DailyRewards", "Daily Rewards" }, { "Leaderboard", "Leaderboard" }, { "CosmeticShop", "Cosmetics" },
}
for _, d in DEST do
	local b = btn(menu, d[2], UDim2.new(0.92, 0, 0, 30), UDim2.new(), Color3.fromRGB(50, 70, 110))
	b.MouseButton1Click:Connect(function()
		menu.Visible = false
		local ok, err = ProgressAction:InvokeServer("travel", d[1])
		if not ok then say(err) end
	end)
end
travelB.MouseButton1Click:Connect(function() menu.Visible = not menu.Visible end)

-- show only what's usable (4x a second)
task.spawn(function()
	while true do
		task.wait(0.25)
		autoB.Visible = state:GetAttribute("AutoRoll") == true
		dash.Visible = (state:GetAttribute("Dash") or 0) > 0
		dash.BackgroundColor3 = os.clock() - lastDash < (state:GetAttribute("DashCooldown") or 3) and Color3.fromRGB(80, 70, 100) or Color3.fromRGB(150, 80, 230)
		travelB.Visible = state:GetAttribute("Travel") == true
		if not travelB.Visible then menu.Visible = false end
	end
end)
