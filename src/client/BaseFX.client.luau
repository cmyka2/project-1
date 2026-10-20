-- Floating "+$" popups over the monsters on your own base every few seconds (the money-pop feel of the
-- spin/brainrot games). Visual only: income is credited by the server every second regardless.
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Http = game:GetService("HttpService")
local player = Players.LocalPlayer
local state = player:WaitForChild("PlayerGui"):WaitForChild("State") -- private mirror of my save, written by the server
local EVERY = 3

local function short(n)
	for _, u in { { 1e12, "t" }, { 1e9, "b" }, { 1e6, "m" }, { 1e3, "k" } } do
		if n >= u[1] then return (("%.1f"):format(n / u[1]):gsub("%.0$", "")) .. u[2] end
	end
	return n < 100 and (("%.1f"):format(n):gsub("%.0$", "")) or tostring(math.floor(n))
end
local function decode(attr)
	local ok, v = pcall(Http.JSONDecode, Http, state:GetAttribute(attr) or "")
	return ok and v or {}
end
local function pop(model, amount)
	local part = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	if not part then return end
	local b = Instance.new("BillboardGui") b.Size = UDim2.fromOffset(120, 30) b.AlwaysOnTop = true b.MaxDistance = 60
	b.StudsOffsetWorldSpace = Vector3.new(0, 6, 0) b.Adornee = part
	local t = Instance.new("TextLabel") t.Size = UDim2.fromScale(1, 1) t.BackgroundTransparency = 1 t.TextScaled = true t.Font = Enum.Font.FredokaOne
	t.Text = "+$" .. short(amount) t.TextColor3 = Color3.fromRGB(120, 255, 120) t.TextStrokeTransparency = 0 t.Parent = b
	b.Parent = player:WaitForChild("PlayerGui")
	TweenService:Create(b, TweenInfo.new(1.2), { StudsOffsetWorldSpace = Vector3.new(0, 10, 0) }):Play()
	TweenService:Create(t, TweenInfo.new(1.2), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	task.delay(1.3, function() b:Destroy() end)
end

while true do
	task.wait(EVERY)
	local id = player:GetAttribute("PlotId")
	local hub = workspace:FindFirstChild("Hub")
	local plot = id and hub and hub:FindFirstChild("Plots") and hub.Plots:FindFirstChild("Plot" .. id)
	local shown = plot and plot:FindFirstChild("Placed")
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if shown and root and (root.Position - plot:GetPivot().Position).Magnitude < 150 then -- only when you are near your base
		local mons, placed = decode("Monsters"), decode("Placed")
		for sk, iid in placed do
			local m, model = mons[iid], shown:FindFirstChild("Slot" .. sk)
			if m and model and m.inc then pop(model, m.inc * EVERY) end
		end
	end
end
