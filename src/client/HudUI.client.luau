-- Main HUD: cash, cash/s, save status, offline-earnings summary and server notices.
local Players = game:GetService("Players")
local Http = game:GetService("HttpService")
local player = Players.LocalPlayer

local function short(n)
	for _, u in { { 1e12, "t" }, { 1e9, "b" }, { 1e6, "m" }, { 1e3, "k" } } do
		if n >= u[1] then return (("%.1f"):format(n / u[1]):gsub("%.0$", "")) .. u[2] end
	end
	return tostring(math.floor(n))
end
local function text(parent, size, pos, color)
	local l = Instance.new("TextLabel") l.Size = size l.Position = pos l.AnchorPoint = Vector2.new(0.5, 0) l.BackgroundTransparency = 1
	l.Font = Enum.Font.FredokaOne l.TextScaled = true l.Text = "" l.TextColor3 = color l.TextStrokeTransparency = 0 l.Parent = parent
	return l
end

local gui = Instance.new("ScreenGui") gui.Name = "HudUI" gui.ResetOnSpawn = false gui.Parent = player:WaitForChild("PlayerGui")
local cash = text(gui, UDim2.fromOffset(320, 40), UDim2.new(0.5, 0, 0, 6), Color3.fromRGB(120, 255, 120))
local status = text(gui, UDim2.fromOffset(520, 30), UDim2.new(0.5, 0, 0, 48), Color3.fromRGB(255, 220, 120))
local toast = text(gui, UDim2.fromScale(0.6, 0.06), UDim2.fromScale(0.5, 0.2), Color3.new(1, 1, 1))
local lim = Instance.new("UISizeConstraint") lim.MaxSize = Vector2.new(640, 54) lim.Parent = toast

local shown = 0
local function show(msg, color, secs)
	toast.Text, toast.TextColor3 = msg, color or Color3.new(1, 1, 1)
	shown += 1
	local mine = shown
	task.delay(secs or 3, function() if shown == mine then toast.Text = "" end end)
end

local function refreshStatus()
	local ds, ps = player:GetAttribute("DataStatus"), player:GetAttribute("PlotStatus")
	status.Text = ds == "loading" and "Loading your save..." or ds == "unsaved" and "Studio test session: progress is NOT saved"
		or ps == "full" and "All plots are taken. You'll get one as soon as a player leaves." or ""
end
player:GetAttributeChangedSignal("DataStatus"):Connect(refreshStatus)
player:GetAttributeChangedSignal("PlotStatus"):Connect(refreshStatus)
refreshStatus()

local state = player:WaitForChild("PlayerGui"):WaitForChild("State")
local function refreshCash()
	cash.Text = "$" .. short(state:GetAttribute("Cash") or 0) .. "   (+" .. short(state:GetAttribute("CashPerSec") or 0) .. "/s)"
end
state:GetAttributeChangedSignal("Cash"):Connect(refreshCash)
state:GetAttributeChangedSignal("CashPerSec"):Connect(refreshCash)
refreshCash()

local function offline()
	local ok, o = pcall(Http.JSONDecode, Http, state:GetAttribute("OfflineEarnings") or "")
	if ok and o.amount then
		show(("Welcome back! Your monsters earned $%s while you were away (%dh %dm)"):format(short(o.amount), o.secs // 3600, o.secs % 3600 // 60),
			Color3.fromRGB(120, 255, 120), 6)
	end
end
state:GetAttributeChangedSignal("OfflineEarnings"):Connect(offline)
offline()
state:GetAttributeChangedSignal("Notice"):Connect(function()
	local ok, n = pcall(Http.JSONDecode, Http, state:GetAttribute("Notice") or "")
	if ok and n.text then show(n.text, Color3.fromRGB(255, 200, 120)) end
end)
