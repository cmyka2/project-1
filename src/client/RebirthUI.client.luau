-- Rebirth confirmation panel, opened at the Rebirth Altar.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local PPS = game:GetService("ProximityPromptService")
local Rebirth = require(RS:WaitForChild("Monster"):WaitForChild("RebirthConfig"))
local RebirthRF = RS.Monster:WaitForChild("Rebirth")
local player = Players.LocalPlayer
local MAX_SLOTS = 10

local function short(n)
	for _, u in { { 1e12, "t" }, { 1e9, "b" }, { 1e6, "m" }, { 1e3, "k" } } do
		if n >= u[1] then return (("%.1f"):format(n / u[1]):gsub("%.0$", "")) .. u[2] end
	end
	return tostring(math.floor(n))
end
local function text(class, parent, str, size, pos, color)
	local l = Instance.new(class) l.Size = size l.Position = pos l.BackgroundTransparency = 1 l.Font = Enum.Font.FredokaOne l.TextScaled = true
	l.Text = str l.TextColor3 = color or Color3.new(1, 1, 1) l.TextStrokeTransparency = 0 l.Parent = parent
	return l
end

local gui = Instance.new("ScreenGui") gui.Name = "RebirthUI" gui.ResetOnSpawn = false gui.Parent = player:WaitForChild("PlayerGui")
local panel = Instance.new("Frame") panel.AnchorPoint = Vector2.new(0.5, 0.5) panel.Position = UDim2.fromScale(0.5, 0.5) panel.Size = UDim2.fromScale(0.6, 0.65)
panel.BackgroundColor3 = Color3.fromRGB(45, 30, 70) panel.Visible = false panel.Parent = gui
local lim = Instance.new("UISizeConstraint") lim.MaxSize = Vector2.new(560, 460) lim.Parent = panel
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 18)
local ps = Instance.new("UIStroke", panel) ps.Thickness = 4

text("TextLabel", panel, "REBIRTH", UDim2.fromScale(0.9, 0.13), UDim2.fromScale(0.05, 0.03), Color3.fromRGB(230, 160, 255))
local count = text("TextLabel", panel, "", UDim2.fromScale(0.9, 0.08), UDim2.fromScale(0.05, 0.17))
local slots = text("TextLabel", panel, "", UDim2.fromScale(0.9, 0.08), UDim2.fromScale(0.05, 0.27), Color3.fromRGB(120, 230, 255))
text("TextLabel", panel, "Resets: " .. table.concat(Rebirth.Resets, ", "), UDim2.fromScale(0.9, 0.07), UDim2.fromScale(0.05, 0.38), Color3.fromRGB(255, 120, 120))
text("TextLabel", panel, "Keeps: " .. table.concat(Rebirth.Keeps, ", "), UDim2.fromScale(0.9, 0.07), UDim2.fromScale(0.05, 0.46), Color3.fromRGB(120, 255, 120))
local costL = text("TextLabel", panel, "", UDim2.fromScale(0.9, 0.09), UDim2.fromScale(0.05, 0.56), Color3.fromRGB(255, 220, 90))
local msg = text("TextLabel", panel, "", UDim2.fromScale(0.9, 0.06), UDim2.fromScale(0.05, 0.66), Color3.fromRGB(255, 140, 140))

local function button(str, color, pos)
	local b = text("TextButton", panel, str, UDim2.fromScale(0.4, 0.15), pos)
	b.BackgroundTransparency = 0 b.BackgroundColor3 = color
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 12)
	local st = Instance.new("UIStroke", b) st.Thickness = 3 st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	return b
end
local confirm = button("Rebirth", Color3.fromRGB(170, 70, 255), UDim2.fromScale(0.07, 0.78))
local cancel = button("Cancel", Color3.fromRGB(220, 50, 50), UDim2.fromScale(0.53, 0.78))

local function refresh()
	local n = player:GetAttribute("Rebirths") or 0
	local cost, cash = Rebirth.cost(n), player:GetAttribute("Cash") or 0
	count.Text = "Rebirths: " .. n .. "  →  " .. n + 1
	local now, nextS = math.min(MAX_SLOTS, 5 + n), math.min(MAX_SLOTS, 6 + n)
	slots.Text = "Base slots: " .. now .. "  →  " .. nextS .. (nextS == now and " (max)" or "")
	costL.Text = "Cost: $" .. short(cost) .. "   (you have $" .. short(cash) .. ")"
	confirm.AutoButtonColor = cash >= cost
	confirm.BackgroundColor3 = cash >= cost and Color3.fromRGB(170, 70, 255) or Color3.fromRGB(90, 80, 100)
end
player:GetAttributeChangedSignal("Cash"):Connect(function() if panel.Visible then refresh() end end)
player:GetAttributeChangedSignal("Rebirths"):Connect(refresh)

confirm.MouseButton1Click:Connect(function()
	local ok, err = RebirthRF:InvokeServer()
	if ok then
		msg.TextColor3 = Color3.fromRGB(140, 255, 140)
		msg.Text = "Reborn! A new slot is unlocked on your base."
	else
		msg.TextColor3 = Color3.fromRGB(255, 140, 140)
		msg.Text = err
	end
end)
cancel.MouseButton1Click:Connect(function() panel.Visible = false end)
PPS.PromptTriggered:Connect(function(prompt)
	if prompt:FindFirstAncestor("RebirthAltar") then msg.Text = "" refresh() panel.Visible = true end
end)
