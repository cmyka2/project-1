-- Gives each joining player a free plot, names the sign, paints it in the player's color.
local Players = game:GetService("Players")
local plots = workspace:WaitForChild("Hub"):WaitForChild("Plots")

local LIGHT = { Frame = true, Step = true, Landing = true, OwnerSign = true, ChestPad = true }

local function paint(plot, c)
	local light, dark = c:Lerp(Color3.new(1, 1, 1), 0.55), c:Lerp(Color3.new(0, 0, 0), 0.25)
	for _, p in plot:GetChildren() do
		if not p:IsA("BasePart") then continue end
		if p.Name == "Base" then
			p.Color = c
		elseif LIGHT[p.Name] or p.Name:match("^SlotBase") then
			p.Color = light
		elseif p.Name == "Wall" or p.Name:match("^Slot%d+$") then
			p.Color = dark
		end
	end
	return dark
end

local function setSign(plot, text, color)
	for _, g in plot.OwnerSign:GetChildren() do
		local t = g:FindFirstChild("Label")
		if t then t.Text = text t.TextColor3 = color end
	end
end

local function assign(player)
	for _, plot in plots:GetChildren() do
		if plot:GetAttribute("Owner") == "" then
			plot:SetAttribute("Owner", tostring(player.UserId))
			player:SetAttribute("PlotId", plot:GetAttribute("PlotId"))
			local dark = paint(plot, Color3.fromHSV((player.UserId * 0.618) % 1, 0.55, 0.75))
			setSign(plot, player.DisplayName .. "'s Base", dark)
			local function toPlot(char)
				char:WaitForChild("HumanoidRootPart")
				task.wait() -- let the default spawn finish first
				char:PivotTo(plot.SpawnPoint.CFrame + Vector3.new(0, 4, 0))
			end
			player.CharacterAdded:Connect(toPlot)
			if player.Character then task.spawn(toPlot, player.Character) end
			return
		end
	end
	warn("No free plot for", player.Name)
end

Players.PlayerAdded:Connect(assign)
for _, p in Players:GetPlayers() do assign(p) end

Players.PlayerRemoving:Connect(function(player)
	for _, plot in plots:GetChildren() do
		if plot:GetAttribute("Owner") == tostring(player.UserId) then
			plot:SetAttribute("Owner", "")
			local dark = paint(plot, plot:GetAttribute("Color"))
			setSign(plot, "#" .. plot:GetAttribute("PlotId") .. "\nUnclaimed", dark)
		end
	end
end)
