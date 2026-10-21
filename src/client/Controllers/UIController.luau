--!strict
-- Root UI: HUD (currencies, navigation, quick roll, quest tracker), panel
-- windows (one open at a time), toasts, confirmation dialogs, server popups
-- and announcements. Feature controllers register their panels here.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Format = require(Shared:WaitForChild("Util"):WaitForChild("Format"))
local EventConfig = require(Shared:WaitForChild("Config"):WaitForChild("EventConfig"))
local Types = require(Shared:WaitForChild("Types"))
local UI = script.Parent.Parent:WaitForChild("UI")
local Kit = require(UI:WaitForChild("Kit"))
local Theme = require(UI:WaitForChild("Theme"))
local StateController = require(script.Parent:WaitForChild("StateController"))

local C = Theme.Colors
local player = Players.LocalPlayer

export type PanelDef = {
	Id: string,
	Title: string,
	Glyph: string,
	Build: (body: Frame) -> ...any,
	OnOpen: ((args: any) -> ...any)?,
	OnClose: (() -> ...any)?,
	Wide: boolean?,
}

local UIController = {}

local screen: ScreenGui
local hud: Frame
local overlayLayer: Frame
local panelLayer: Frame
local toastStack: Frame
local slots: { [string]: Frame } = {}
local panels: { [string]: PanelDef } = {}
local windows: { [string]: Frame } = {}
local openId: string? = nil
local backdrop: TextButton
local listeners: { [string]: { (any) -> () } } = {}
local currencyLabels: { [string]: TextLabel } = {}
local incomeLabel: TextLabel
local tokenChip: Frame
local apChip: Frame

UIController.PanelOpened = nil :: any

-- Pub/sub for cross-controller UI events ("PanelOpened", "BattleStarted", ...)
function UIController.on(eventName: string, fn: (any) -> ())
	listeners[eventName] = listeners[eventName] or {}
	table.insert(listeners[eventName], fn)
end

function UIController.emit(eventName: string, payload: any)
	local fns = listeners[eventName]
	if fns then
		for _, fn in fns do
			task.spawn(fn, payload)
		end
	end
end

function UIController.screen(): ScreenGui
	return screen
end

function UIController.overlay(): Frame
	return overlayLayer
end

function UIController.slot(name: string): Frame
	return slots[name]
end

function UIController.isSmallScreen(): boolean
	local camera = Workspace.CurrentCamera
	local size = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	return size.X < 900 or UserInputService.TouchEnabled and size.X < 1200
end

-- Toasts ---------------------------------------------------------------------------------

local TOAST_COLORS = {
	info = C.Accent,
	success = C.Good,
	error = C.Bad,
	reward = C.Gold,
}

function UIController.toast(kind: string, text: string)
	if not toastStack then
		return
	end
	local color = (TOAST_COLORS :: any)[kind] or C.Accent
	local toast = Kit.frame({
		BackgroundColor3 = C.PanelDark,
		Size = UDim2.new(1, 0, 0, 44),
		BackgroundTransparency = 0.05,
		Parent = toastStack,
	})
	Kit.corner(toast, 10)
	Kit.stroke(toast, color, 2)
	local bar = Kit.frame({ BackgroundColor3 = color, Size = UDim2.new(0, 6, 1, 0), Parent = toast })
	Kit.corner(bar, 3)
	local label = Kit.text({
		Text = text,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -20, 1, 0),
		Position = UDim2.fromOffset(14, 0),
		MaxTextSize = 17,
		Parent = toast,
	})
	Kit.textStroke(label)
	Kit.pop(toast, 0.06)
	local children = toastStack:GetChildren()
	local count = 0
	for _, child in children do
		if child:IsA("Frame") then
			count += 1
		end
	end
	if count > 5 then
		for _, child in children do
			if child:IsA("Frame") then
				child:Destroy()
				break
			end
		end
	end
	task.delay(if kind == "error" then 4 else 3, function()
		if toast.Parent then
			Kit.tween(toast, Theme.Tween.Normal, { BackgroundTransparency = 1 })
			Kit.tween(label, Theme.Tween.Normal, { TextTransparency = 1 })
			task.wait(0.25)
			toast:Destroy()
		end
	end)
end

-- Request wrapper: shows errors as toasts and returns the result.
function UIController.call(name: string, ...: any): Types.RemoteResult
	local result = Net.request(name, ...)
	if not result.ok and result.err then
		UIController.toast("error", result.err)
	end
	return result
end

-- Confirm dialog -----------------------------------------------------------------------------

function UIController.confirm(title: string, body: string, confirmText: string?, danger: boolean?): boolean
	local done = false
	local answer = false
	local shade = Instance.new("TextButton")
	shade.Text = ""
	shade.AutoButtonColor = false
	shade.BackgroundColor3 = C.Backdrop
	shade.BackgroundTransparency = 0.35
	shade.Size = UDim2.fromScale(1, 1)
	shade.ZIndex = 200
	shade.Parent = overlayLayer
	local box = Kit.frame({
		BackgroundColor3 = C.Panel,
		Size = UDim2.fromScale(0.36, 0.3),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		ZIndex = 201,
		Parent = shade,
	})
	Kit.corner(box)
	Kit.stroke(box, if danger then C.Bad else C.Stroke, 3)
	local sizeConstraint = Instance.new("UISizeConstraint")
	sizeConstraint.MinSize = Vector2.new(300, 190)
	sizeConstraint.MaxSize = Vector2.new(560, 320)
	sizeConstraint.Parent = box
	Kit.padding(box, 14)
	local t = Kit.text({
		Text = title,
		Font = Theme.Fonts.Title,
		Size = UDim2.new(1, 0, 0.24, 0),
		ZIndex = 202,
		MaxTextSize = 26,
		Parent = box,
	})
	Kit.textStroke(t)
	Kit.text({
		Text = body,
		Size = UDim2.new(1, 0, 0.46, 0),
		Position = UDim2.fromScale(0, 0.26),
		TextColor3 = C.Muted,
		ZIndex = 202,
		MaxTextSize = 18,
		Parent = box,
	})
	local function finish(value: boolean)
		answer = value
		done = true
		shade:Destroy()
	end
	local yes = Kit.button(confirmText or "Confirm", if danger then "Bad" else "Good", function()
		finish(true)
	end, {
		Size = UDim2.new(0.47, 0, 0.22, 0),
		Position = UDim2.fromScale(0.53, 0.78),
		ZIndex = 202,
		Parent = box,
	})
	local no = Kit.button("Cancel", "Dark", function()
		finish(false)
	end, {
		Size = UDim2.new(0.47, 0, 0.22, 0),
		Position = UDim2.fromScale(0, 0.78),
		ZIndex = 202,
		Parent = box,
	})
	for _, b in { yes, no } do
		for _, d in b:GetDescendants() do
			if d:IsA("GuiObject") then
				d.ZIndex = 203
			end
		end
	end
	Kit.pop(box, 0.1)
	while not done do
		task.wait()
	end
	return answer
end

-- Panels ----------------------------------------------------------------------------------

function UIController.registerPanel(def: PanelDef)
	panels[def.Id] = def
end

local function buildWindow(def: PanelDef): Frame
	local small = UIController.isSmallScreen()
	local window = Kit.frame({
		Name = "Panel_" .. def.Id,
		BackgroundColor3 = C.Panel,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = if small
			then UDim2.fromScale(0.96, 0.84)
			elseif def.Wide then UDim2.fromScale(0.82, 0.8)
			else UDim2.fromScale(0.66, 0.76),
		Visible = false,
		Parent = panelLayer,
	})
	Kit.corner(window, 16)
	Kit.stroke(window, C.Stroke, 3)
	local constraint = Instance.new("UISizeConstraint")
	constraint.MaxSize = if def.Wide then Vector2.new(1400, 860) else Vector2.new(1100, 780)
	constraint.Parent = window
	local header = Kit.frame({
		Name = "Header",
		BackgroundColor3 = C.Header,
		Size = UDim2.new(1, 0, 0, 52),
		Parent = window,
	})
	Kit.corner(header, 16)
	Kit.gradient(header, C.Header:Lerp(Color3.new(1, 1, 1), 0.12), C.Header, 90)
	local title = Kit.text({
		Text = def.Glyph .. "  " .. def.Title,
		Font = Theme.Fonts.Title,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -80, 1, -12),
		Position = UDim2.fromOffset(16, 6),
		MaxTextSize = 30,
		Parent = header,
	})
	Kit.textStroke(title, Color3.new(0, 0, 0), 2)
	Kit.button("✕", "Bad", function()
		UIController.close()
	end, { Size = UDim2.fromOffset(40, 40), Position = UDim2.new(1, -48, 0, 6), Parent = header })
	local body = Kit.frame({
		Name = "Body",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -24, 1, -68),
		Position = UDim2.fromOffset(12, 60),
		Parent = window,
	})
	local ok, err = pcall(def.Build, body)
	if not ok then
		warn("[UI] panel " .. def.Id .. " failed to build: " .. tostring(err))
		Kit.text({ Text = "This panel failed to load.", Parent = body })
	end
	return window
end

function UIController.open(id: string, args: any?)
	local def = panels[id]
	if not def then
		warn("[UI] unknown panel " .. id)
		return
	end
	if openId and openId ~= id then
		UIController.close()
	end
	local window = windows[id]
	if not window then
		window = buildWindow(def)
		windows[id] = window
	end
	openId = id
	backdrop.Visible = true
	window.Visible = true
	local s = Kit.scale(window)
	s.Scale = 0.85
	Kit.tween(s, Theme.Tween.Bouncy, { Scale = 1 })
	if def.OnOpen then
		task.spawn(def.OnOpen, args)
	end
	UIController.emit("PanelOpened", id)
end

function UIController.close()
	local id = openId
	if not id then
		return
	end
	openId = nil
	local window = windows[id]
	if window then
		window.Visible = false
	end
	backdrop.Visible = false
	local def = panels[id]
	if def and def.OnClose then
		task.spawn(def.OnClose)
	end
	UIController.emit("PanelClosed", id)
end

function UIController.toggle(id: string, args: any?)
	if openId == id then
		UIController.close()
	else
		UIController.open(id, args)
	end
end

function UIController.openId(): string?
	return openId
end

-- HUD ------------------------------------------------------------------------------------------

local function currencyChip(parent: Instance, key: string, glyph: string, color: Color3, order: number): Frame
	local chip = Kit.frame({
		BackgroundColor3 = C.PanelDark,
		BackgroundTransparency = 0.15,
		Size = UDim2.new(0, 170, 1, 0),
		LayoutOrder = order,
		Parent = parent,
	})
	Kit.corner(chip, 20)
	Kit.stroke(chip, color, 2)
	Kit.text({
		Text = glyph,
		Size = UDim2.new(0, 34, 1, -6),
		Position = UDim2.fromOffset(6, 3),
		MaxTextSize = 26,
		Parent = chip,
	})
	local value = Kit.text({
		Text = "0",
		Font = Theme.Fonts.Title,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -48, 1, -8),
		Position = UDim2.fromOffset(42, 4),
		TextColor3 = color,
		MaxTextSize = 24,
		Parent = chip,
	})
	Kit.textStroke(value, Color3.new(0, 0, 0), 1.5)
	currencyLabels[key] = value
	return chip
end

local displayed: { [string]: number } = {}

local function refreshCurrencies()
	local profile = StateController.Profile
	local derived = StateController.Derived
	if not profile then
		return
	end
	for key, label in currencyLabels do
		local target = (profile.Currencies :: any)[key] or 0
		local from = displayed[key] or target
		displayed[key] = target
		if from ~= target and math.abs(target - from) > 0 then
			Kit.pop(label, 0.05)
		end
		label.Text = Format.number(target)
	end
	if derived then
		incomeLabel.Text = "+" .. Format.number(derived.TotalIncome) .. "/s"
		local eventActive = false
		for _, id in derived.ActiveEvents do
			local event = EventConfig.Events[id]
			if event and event.ChestId then
				eventActive = true
			end
		end
		tokenChip.Visible = eventActive or profile.Currencies.EventTokens > 0
	end
	apChip.Visible = profile.Currencies.AscensionPoints > 0 or profile.Progression.RebirthCount > 0
end

local NAV = {
	{ Id = "Roll", Glyph = "🎲", Caption = "Roll", Color = Color3.fromRGB(110, 210, 100) },
	{ Id = "Inventory", Glyph = "🎒", Caption = "Monsters", Color = Color3.fromRGB(110, 150, 255) },
	{ Id = "Base", Glyph = "🏠", Caption = "Base", Color = Color3.fromRGB(255, 190, 70) },
	{ Id = "Battle", Glyph = "⚔", Caption = "Battle", Color = Color3.fromRGB(240, 90, 90) },
	{ Id = "Quests", Glyph = "📜", Caption = "Quests", Color = Color3.fromRGB(120, 200, 255) },
	{ Id = "Skills", Glyph = "🌳", Caption = "Skills", Color = Color3.fromRGB(90, 220, 140) },
	{ Id = "Rebirth", Glyph = "♻", Caption = "Rebirth", Color = Color3.fromRGB(240, 110, 190) },
	{ Id = "Regions", Glyph = "🗺", Caption = "Map", Color = Color3.fromRGB(80, 200, 200) },
}

local MORE = {
	{ Id = "Codex", Glyph = "📖", Caption = "Codex" },
	{ Id = "Chests", Glyph = "🎁", Caption = "Chests" },
	{ Id = "Fusion", Glyph = "🧬", Caption = "Fusion" },
	{ Id = "Crafting", Glyph = "🔧", Caption = "Crafting" },
	{ Id = "Equipment", Glyph = "⚒", Caption = "Gear" },
	{ Id = "Ascension", Glyph = "🌟", Caption = "Ascend" },
	{ Id = "Daily", Glyph = "🗓", Caption = "Daily" },
	{ Id = "Achievements", Glyph = "🏆", Caption = "Trophies" },
	{ Id = "Events", Glyph = "🎉", Caption = "Events" },
	{ Id = "Trade", Glyph = "🤝", Caption = "Trade" },
	{ Id = "Leaderboards", Glyph = "📊", Caption = "Ranks" },
	{ Id = "Settings", Glyph = "⚙", Caption = "Settings" },
}

local navButtons: { [string]: TextButton } = {}

function UIController.navButton(id: string): TextButton?
	return navButtons[id]
end

-- Pulses a HUD button (used by the tutorial).
function UIController.highlight(id: string?)
	for key, button in navButtons do
		local stroke = button:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = if key == id
				then C.Gold
				else button.BackgroundColor3:Lerp(Color3.new(0, 0, 0), 0.35)
			stroke.Thickness = if key == id then 5 else 3
		end
	end
end

local function buildHud()
	hud =
		Kit.frame({ Name = "HUD", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = screen })
	local hudScale = Kit.scale(hud)
	local function rescale()
		local camera = Workspace.CurrentCamera
		local size = if camera then camera.ViewportSize else Vector2.new(1280, 720)
		hudScale.Scale = math.clamp(math.min(size.X / 1280, size.Y / 720), 0.55, 1.15)
	end
	rescale()
	if Workspace.CurrentCamera then
		(Workspace.CurrentCamera :: Camera):GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
	end

	-- top: currencies
	local top = Kit.frame({
		Name = "Currencies",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 8),
		Size = UDim2.fromOffset(760, 40),
		Parent = hud,
	})
	Kit.list(top, Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Center)
	local coinChip = currencyChip(top, "Coins", "💰", C.Gold, 1)
	coinChip.Size = UDim2.new(0, 240, 1, 0)
	incomeLabel = Kit.text({
		Text = "+0/s",
		Font = Theme.Fonts.Bold,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = C.Good,
		Size = UDim2.new(0, 90, 1, -10),
		Position = UDim2.new(1, -96, 0, 5),
		MaxTextSize = 16,
		Parent = coinChip,
	})
	Kit.textStroke(incomeLabel)
	currencyChip(top, "Gems", "💎", C.Gem, 2)
	apChip = currencyChip(top, "AscensionPoints", "🌟", C.Ascension, 3)
	apChip.Size = UDim2.new(0, 120, 1, 0)
	tokenChip = currencyChip(top, "EventTokens", "🎟", C.Warn, 4)
	tokenChip.Size = UDim2.new(0, 120, 1, 0)

	-- left: navigation
	local nav = Kit.frame({
		Name = "Nav",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 10, 0.5, 0),
		Size = UDim2.fromOffset(140, 300),
		Parent = hud,
	})
	Kit.grid(nav, UDim2.fromOffset(64, 64), 8)
	for i, entry in NAV do
		navButtons[entry.Id] = Kit.iconButton(entry.Glyph, entry.Caption, entry.Color, function()
			UIController.toggle(entry.Id)
		end, { LayoutOrder = i, Parent = nav })
	end
	local moreOpen = false
	local moreFrame = Kit.frame({
		Name = "More",
		BackgroundColor3 = C.PanelDark,
		BackgroundTransparency = 0.1,
		Visible = false,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 160, 0.5, 0),
		Size = UDim2.fromOffset(296, 230),
		Parent = hud,
	})
	Kit.corner(moreFrame)
	Kit.stroke(moreFrame)
	Kit.padding(moreFrame, 8)
	Kit.grid(moreFrame, UDim2.fromOffset(64, 64), 8)
	for i, entry in MORE do
		navButtons[entry.Id] = Kit.iconButton(entry.Glyph, entry.Caption, C.PanelLight, function()
			moreFrame.Visible = false
			moreOpen = false
			UIController.toggle(entry.Id)
		end, { LayoutOrder = i, Parent = moreFrame })
	end
	Kit.iconButton("☰", "More", C.Header, function()
		moreOpen = not moreOpen
		moreFrame.Visible = moreOpen
	end, { LayoutOrder = #NAV + 1, Parent = nav })
	nav.Size = UDim2.fromOffset(140, 64 * 5 + 8 * 4)

	-- slots other controllers fill
	slots.BottomCenter = Kit.frame({
		Name = "BottomCenter",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12),
		Size = UDim2.fromOffset(520, 96),
		Parent = hud,
	})
	slots.Right = Kit.frame({
		Name = "Right",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.45, 0),
		Size = UDim2.fromOffset(280, 320),
		Parent = hud,
	})
	Kit.list(slots.Right, Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Right)
	slots.TopCenter = Kit.frame({
		Name = "TopCenter",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 56),
		Size = UDim2.fromOffset(620, 90),
		Parent = hud,
	})
	slots.TopLeft = Kit.frame({
		Name = "TopLeft",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(10, 8),
		Size = UDim2.fromOffset(200, 40),
		Parent = hud,
	})
	Kit.list(slots.TopLeft, Enum.FillDirection.Horizontal, 6)

	toastStack = Kit.frame({
		Name = "Toasts",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 54),
		Size = UDim2.fromOffset(340, 300),
		Parent = hud,
	})
	Kit.list(toastStack, Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Right)
end

-- Announcements & popups -------------------------------------------------------------------

local function announce(text: string, color: Color3?, loud: boolean?)
	local banner = Kit.frame({
		BackgroundColor3 = C.PanelDark,
		BackgroundTransparency = 0.1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, -60),
		Size = UDim2.fromOffset(if loud then 640 else 520, if loud then 54 else 42),
		Parent = overlayLayer,
	})
	Kit.corner(banner, 20)
	Kit.stroke(banner, color or C.Gold, if loud then 4 else 2)
	local label = Kit.text({
		Text = (if loud then "✨ " else "") .. text,
		Font = Theme.Fonts.Title,
		TextColor3 = color or C.Gold,
		Size = UDim2.new(1, -20, 1, -8),
		Position = UDim2.fromOffset(10, 4),
		MaxTextSize = if loud then 26 else 20,
		Parent = banner,
	})
	Kit.textStroke(label, Color3.new(0, 0, 0), 2)
	Kit.tween(banner, Theme.Tween.Bouncy, { Position = UDim2.new(0.5, 0, 0, 100) })
	task.delay(if loud then 5 else 3.5, function()
		Kit.tween(banner, Theme.Tween.Normal, { Position = UDim2.new(0.5, 0, 0, -70) })
		task.wait(0.3)
		banner:Destroy()
	end)
end
UIController.announce = announce

-- Generic "info" modal with a list of lines and a single OK button.
function UIController.popup(title: string, lines: { string }, color: Color3?)
	local shade = Instance.new("TextButton")
	shade.Text = ""
	shade.AutoButtonColor = false
	shade.BackgroundColor3 = C.Backdrop
	shade.BackgroundTransparency = 0.4
	shade.Size = UDim2.fromScale(1, 1)
	shade.ZIndex = 150
	shade.Parent = overlayLayer
	local box = Kit.frame({
		BackgroundColor3 = C.Panel,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(440, 120 + #lines * 30),
		ZIndex = 151,
		Parent = shade,
	})
	Kit.corner(box)
	Kit.stroke(box, color or C.Gold, 3)
	Kit.padding(box, 14)
	Kit.list(box, Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Center)
	local t = Kit.text({
		Text = title,
		Font = Theme.Fonts.Title,
		TextColor3 = color or C.Gold,
		Size = UDim2.new(1, 0, 0, 36),
		ZIndex = 152,
		MaxTextSize = 30,
		Parent = box,
	})
	Kit.textStroke(t, Color3.new(0, 0, 0), 2)
	for i, line in lines do
		Kit.text({
			Text = line,
			Size = UDim2.new(1, 0, 0, 24),
			LayoutOrder = i,
			ZIndex = 152,
			MaxTextSize = 20,
			Parent = box,
		})
	end
	local ok = Kit.button("Awesome!", "Gold", function()
		shade:Destroy()
	end, { Size = UDim2.new(0.6, 0, 0, 42), LayoutOrder = #lines + 1, Parent = box })
	for _, d in ok:GetDescendants() do
		if d:IsA("GuiObject") then
			d.ZIndex = 153
		end
	end
	ok.ZIndex = 152
	Kit.pop(box, 0.12)
end

local function onPopup(kind: string, payload: any)
	if kind == "Rebirth" and typeof(payload) == "table" then
		local lines = {
			"Rebirth #" .. tostring(payload.NewCount) .. " complete!",
			"🌟 +" .. tostring(payload.AscensionPoints) .. " Ascension Points",
			"💎 +" .. tostring(payload.Gems) .. " Gems",
			"🏠 Base slots: " .. tostring(payload.TotalSlots),
		}
		if payload.FloorUnlocked then
			table.insert(lines, "🏢 Floor " .. tostring(payload.Floors) .. " unlocked!")
		end
		UIController.popup("♻ Reborn!", lines, C.Ascension)
	elseif kind == "Offline" and typeof(payload) == "table" then
		UIController.popup("💤 Welcome back!", {
			"You were away for " .. Format.duration(payload.ElapsedSeconds or 0),
			"Your monsters earned 💰 " .. Format.number(payload.Coins or 0),
			"("
				.. Format.percent(payload.Efficiency or 0, 0)
				.. " efficiency, capped at "
				.. Format.duration(payload.CountedSeconds or 0)
				.. ")",
		}, C.Gold)
	elseif kind == "DailyAvailable" then
		UIController.toast("reward", "🎁 Your daily reward is ready! Open Daily Rewards.")
	end
	UIController.emit("Popup:" .. kind, payload)
end

function UIController.init()
	local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui
	screen = Instance.new("ScreenGui")
	screen.Name = "GameUI"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = false
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screen.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	screen.Parent = playerGui

	buildHud()
	backdrop = Instance.new("TextButton")
	backdrop.Name = "Backdrop"
	backdrop.Text = ""
	backdrop.AutoButtonColor = false
	backdrop.BackgroundColor3 = C.Backdrop
	backdrop.BackgroundTransparency = 0.45
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.Visible = false
	backdrop.Parent = screen
	backdrop.Activated:Connect(function()
		UIController.close()
	end)
	panelLayer = Kit.frame({
		Name = "Panels",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Parent = screen,
	})
	overlayLayer = Kit.frame({
		Name = "Overlay",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 100,
		Parent = screen,
	})

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.ButtonB then
			UIController.close()
		end
	end)
	GuiService.MenuOpened:Connect(function()
		UIController.close()
	end)

	Net.on("Notify", function(kind: string, text: string)
		UIController.toast(kind, text)
	end)
	Net.on("Announce", function(text: string, color: Color3?, loud: boolean?)
		announce(text, color, loud)
	end)
	Net.on("Popup", onPopup)
	StateController.Changed:Connect(function(key)
		if key == "*" or key == "Currencies" or key == "Derived" or key == "Progression" then
			refreshCurrencies()
		end
	end)
end

function UIController.start()
	StateController.waitForReady()
	refreshCurrencies()
end

return UIController
