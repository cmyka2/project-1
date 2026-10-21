--!strict
-- UI construction kit. Every screen is built from these helpers so spacing,
-- typography, colors and button behavior stay consistent. Layouts use Scale
-- sizes and layout objects so they adapt from phones to desktops.

local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent.Theme)

export type Props = { [string]: any }

local Kit = {}

local C = Theme.Colors

local function apply(inst: Instance, props: Props?, children: { Instance }?)
	if props then
		local parent = props.Parent
		for key, value in props do
			if key ~= "Parent" then
				(inst :: any)[key] = value
			end
		end
		if children then
			for _, child in children do
				child.Parent = inst
			end
		end
		if parent then
			inst.Parent = parent
		end
	elseif children then
		for _, child in children do
			child.Parent = inst
		end
	end
end

function Kit.new(className: string, props: Props?, children: { Instance }?): Instance
	local inst = Instance.new(className)
	apply(inst, props, children)
	return inst
end

function Kit.frame(props: Props?, children: { Instance }?): Frame
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	f.BackgroundColor3 = C.Panel
	apply(f, props, children)
	return f
end

function Kit.text(props: Props?, children: { Instance }?): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.BorderSizePixel = 0
	t.Font = Theme.Fonts.Body
	t.TextColor3 = C.Text
	t.TextScaled = true
	t.TextWrapped = true
	t.RichText = true
	t.Size = UDim2.fromScale(1, 1)
	local maxText = 28
	local cleaned = props
	if props and props.MaxTextSize then
		maxText = props.MaxTextSize
		local copy = table.clone(props)
		copy.MaxTextSize = nil
		cleaned = copy
	end
	apply(t, cleaned, children)
	if t.TextScaled and not t:FindFirstChildOfClass("UITextSizeConstraint") then
		local constraint = Instance.new("UITextSizeConstraint")
		constraint.MaxTextSize = maxText
		constraint.MinTextSize = 8
		constraint.Parent = t
	end
	return t
end

function Kit.image(props: Props?, children: { Instance }?): ImageLabel
	local i = Instance.new("ImageLabel")
	i.BackgroundTransparency = 1
	i.BorderSizePixel = 0
	i.ScaleType = Enum.ScaleType.Fit
	apply(i, props, children)
	return i
end

function Kit.scroll(props: Props?, children: { Instance }?): ScrollingFrame
	local s = Instance.new("ScrollingFrame")
	s.BackgroundTransparency = 1
	s.BorderSizePixel = 0
	s.ScrollBarThickness = 6
	s.ScrollBarImageColor3 = C.Stroke
	s.CanvasSize = UDim2.new()
	s.AutomaticCanvasSize = Enum.AutomaticSize.Y
	s.ScrollingDirection = Enum.ScrollingDirection.Y
	s.Size = UDim2.fromScale(1, 1)
	apply(s, props, children)
	return s
end

function Kit.textbox(props: Props?): TextBox
	local t = Instance.new("TextBox")
	t.BackgroundColor3 = C.PanelDark
	t.BorderSizePixel = 0
	t.Font = Theme.Fonts.Body
	t.TextColor3 = C.Text
	t.PlaceholderColor3 = C.Muted
	t.TextScaled = true
	t.ClearTextOnFocus = false
	t.Text = ""
	apply(t, props)
	Kit.corner(t, Theme.SmallCorner)
	Kit.padding(t, 6)
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MaxTextSize = 20
	constraint.Parent = t
	return t
end

-- Decorators ---------------------------------------------------------------------------

function Kit.corner(parent: Instance, radius: number?): UICorner
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or Theme.Corner)
	c.Parent = parent
	return c
end

function Kit.stroke(parent: Instance, color: Color3?, thickness: number?, transparency: number?): UIStroke
	local s = Instance.new("UIStroke")
	s.Color = color or C.Stroke
	s.Thickness = thickness or 2
	s.Transparency = transparency or 0
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

function Kit.textStroke(parent: Instance, color: Color3?, thickness: number?): UIStroke
	local s = Instance.new("UIStroke")
	s.Color = color or Color3.new(0, 0, 0)
	s.Thickness = thickness or 1.5
	s.Transparency = 0.2
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	s.Parent = parent
	return s
end

function Kit.padding(parent: Instance, px: number?, py: number?): UIPadding
	local p = Instance.new("UIPadding")
	local x = UDim.new(0, px or Theme.Padding)
	local y = UDim.new(0, py or px or Theme.Padding)
	p.PaddingLeft = x
	p.PaddingRight = x
	p.PaddingTop = y
	p.PaddingBottom = y
	p.Parent = parent
	return p
end

function Kit.list(
	parent: Instance,
	direction: Enum.FillDirection?,
	spacing: number?,
	halign: Enum.HorizontalAlignment?,
	valign: Enum.VerticalAlignment?
): UIListLayout
	local l = Instance.new("UIListLayout")
	l.FillDirection = direction or Enum.FillDirection.Vertical
	l.Padding = UDim.new(0, spacing or 6)
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.HorizontalAlignment = halign or Enum.HorizontalAlignment.Left
	l.VerticalAlignment = valign or Enum.VerticalAlignment.Top
	l.Parent = parent
	return l
end

function Kit.grid(parent: Instance, cellSize: UDim2, spacing: number?): UIGridLayout
	local g = Instance.new("UIGridLayout")
	g.CellSize = cellSize
	g.CellPadding = UDim2.fromOffset(spacing or 8, spacing or 8)
	g.SortOrder = Enum.SortOrder.LayoutOrder
	g.Parent = parent
	return g
end

function Kit.gradient(parent: Instance, top: Color3, bottom: Color3, rotation: number?): UIGradient
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(top, bottom)
	g.Rotation = rotation or 90
	g.Parent = parent
	return g
end

function Kit.aspect(parent: Instance, ratio: number): UIAspectRatioConstraint
	local a = Instance.new("UIAspectRatioConstraint")
	a.AspectRatio = ratio
	a.Parent = parent
	return a
end

function Kit.scale(parent: Instance): UIScale
	local existing = parent:FindFirstChildOfClass("UIScale")
	if existing then
		return existing
	end
	local s = Instance.new("UIScale")
	s.Parent = parent
	return s
end

-- Animation ----------------------------------------------------------------------------

local liveTweens: { [Instance]: Tween } = {}

function Kit.tween(inst: Instance, info: TweenInfo, goals: { [string]: any }): Tween
	local previous = liveTweens[inst]
	if previous then
		previous:Cancel()
	end
	local tween = TweenService:Create(inst, info, goals)
	liveTweens[inst] = tween
	tween.Completed:Once(function()
		if liveTweens[inst] == tween then
			liveTweens[inst] = nil
		end
	end)
	tween:Play()
	return tween
end

-- Quick scale "pop" for feedback.
function Kit.pop(inst: GuiObject, amount: number?)
	local s = Kit.scale(inst)
	s.Scale = 1 + (amount or 0.08)
	Kit.tween(s, Theme.Tween.Bouncy, { Scale = 1 })
end

-- Components ---------------------------------------------------------------------------

export type ButtonStyle = "Primary" | "Good" | "Bad" | "Gold" | "Gem" | "Dark" | "Ghost"

function Kit.setEnabled(button: GuiButton, enabled: boolean)
	button:SetAttribute("Enabled", enabled)
	button.AutoButtonColor = false
	local styleName = button:GetAttribute("Style")
	local style = (Theme.ButtonStyles :: any)[styleName or "Primary"] or Theme.ButtonStyles.Primary
	button.BackgroundColor3 = if enabled then style.Bg else C.Disabled
	local label = button:FindFirstChild("Label")
	if label and label:IsA("TextLabel") then
		label.TextTransparency = if enabled then 0 else 0.35
	end
end

function Kit.isEnabled(button: GuiButton): boolean
	return button:GetAttribute("Enabled") ~= false
end

function Kit.setText(button: GuiButton, text: string)
	local label = button:FindFirstChild("Label")
	if label and label:IsA("TextLabel") then
		label.Text = text
	end
end

-- Rounded button with press feedback. `onClick` is ignored while disabled.
function Kit.button(text: string, style: ButtonStyle?, onClick: (() -> ())?, props: Props?): TextButton
	local styleName = style or "Primary"
	local s = (Theme.ButtonStyles :: any)[styleName]
	local b = Instance.new("TextButton")
	b.Text = ""
	b.AutoButtonColor = false
	b.BorderSizePixel = 0
	b.BackgroundColor3 = s.Bg
	b.Size = UDim2.new(1, 0, 0, 40)
	b:SetAttribute("Style", styleName)
	b:SetAttribute("Enabled", true)
	Kit.corner(b, Theme.SmallCorner)
	local stroke = Kit.stroke(b, s.Bg2, 2)
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	Kit.gradient(b, Color3.new(1, 1, 1), Color3.fromRGB(205, 205, 215), 90)
	local label = Kit.text({
		Name = "Label",
		Text = text,
		Font = Theme.Fonts.Title,
		TextColor3 = s.Text,
		Size = UDim2.fromScale(1, 1),
		MaxTextSize = 22,
		Parent = b,
	})
	Kit.padding(label, 8, 4)
	if s.Text == Color3.fromRGB(255, 255, 255) then
		Kit.textStroke(label, Color3.new(0, 0, 0), 1)
	end
	b.MouseButton1Down:Connect(function()
		if Kit.isEnabled(b) then
			local sc = Kit.scale(b)
			Kit.tween(sc, Theme.Tween.Fast, { Scale = 0.94 })
		end
	end)
	local function release()
		local sc = Kit.scale(b)
		Kit.tween(sc, Theme.Tween.Bouncy, { Scale = 1 })
	end
	b.MouseButton1Up:Connect(release)
	b.MouseLeave:Connect(release)
	if onClick then
		b.Activated:Connect(function()
			if Kit.isEnabled(b) then
				onClick()
			end
		end)
	end
	apply(b, props)
	return b
end

-- Small square icon button (e.g. HUD navigation).
function Kit.iconButton(
	glyph: string,
	caption: string,
	color: Color3,
	onClick: () -> (),
	props: Props?
): TextButton
	local b = Instance.new("TextButton")
	b.Text = ""
	b.AutoButtonColor = false
	b.BorderSizePixel = 0
	b.BackgroundColor3 = color
	b.Size = UDim2.fromOffset(64, 64)
	Kit.corner(b, 14)
	Kit.stroke(b, color:Lerp(Color3.new(0, 0, 0), 0.35), 3)
	Kit.gradient(b, Color3.new(1, 1, 1), Color3.fromRGB(190, 190, 205), 90)
	Kit.text({
		Name = "Glyph",
		Text = glyph,
		Size = UDim2.fromScale(1, 0.68),
		Position = UDim2.fromScale(0, 0.04),
		MaxTextSize = 34,
		Parent = b,
	})
	local cap = Kit.text({
		Name = "Caption",
		Text = caption,
		Font = Theme.Fonts.Title,
		Size = UDim2.fromScale(1, 0.3),
		Position = UDim2.fromScale(0, 0.68),
		MaxTextSize = 14,
		Parent = b,
	})
	Kit.textStroke(cap, Color3.new(0, 0, 0), 1.2)
	b.Activated:Connect(function()
		Kit.pop(b)
		onClick()
	end)
	apply(b, props)
	return b
end

-- Horizontal progress bar. Returns the bar frame and a setter(fraction, text?).
function Kit.progress(parent: Instance, color: Color3, props: Props?): (Frame, (number, string?) -> ())
	local bar = Kit.frame({ BackgroundColor3 = C.PanelDark, Size = UDim2.new(1, 0, 0, 18), Parent = parent })
	Kit.corner(bar, 9)
	local fill =
		Kit.frame({ Name = "Fill", BackgroundColor3 = color, Size = UDim2.fromScale(0, 1), Parent = bar })
	Kit.corner(fill, 9)
	Kit.gradient(fill, Color3.new(1, 1, 1), Color3.fromRGB(180, 180, 190), 90)
	local label = Kit.text({
		Name = "Text",
		Text = "",
		Font = Theme.Fonts.Bold,
		MaxTextSize = 14,
		ZIndex = 3,
		Parent = bar,
	})
	Kit.textStroke(label)
	apply(bar, props)
	local function set(fraction: number, text: string?)
		local f = if fraction ~= fraction then 0 else math.clamp(fraction, 0, 1)
		Kit.tween(fill, Theme.Tween.Normal, { Size = UDim2.fromScale(f, 1) })
		label.Text = text or ""
	end
	return bar, set
end

-- Tab bar: returns the bar and a selectTab(index) function.
function Kit.tabs(
	parent: Instance,
	names: { string },
	onSelect: (number, string) -> (),
	props: Props?
): (Frame, (number) -> ())
	local bar = Kit.frame({ BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 38), Parent = parent })
	Kit.list(bar, Enum.FillDirection.Horizontal, 6)
	local buttons: { TextButton } = {}
	local function selectTab(index: number)
		for i, b in buttons do
			b.BackgroundColor3 = if i == index then C.Accent else C.PanelLight
		end
		onSelect(index, names[index])
	end
	for i, name in names do
		local b = Kit.button(name, "Dark", function()
			selectTab(i)
		end, {
			Size = UDim2.new(1 / #names, -6, 1, 0),
			LayoutOrder = i,
			Parent = bar,
		})
		table.insert(buttons, b)
	end
	apply(bar, props)
	return bar, selectTab
end

-- A section header label.
function Kit.header(text: string, props: Props?): TextLabel
	local t = Kit.text({
		Text = text,
		Font = Theme.Fonts.Title,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, 28),
		MaxTextSize = 24,
	})
	Kit.textStroke(t)
	apply(t, props)
	return t
end

-- Rounded card container.
function Kit.card(props: Props?, children: { Instance }?): Frame
	local f = Kit.frame({ BackgroundColor3 = C.PanelLight })
	Kit.corner(f, Theme.SmallCorner)
	apply(f, props, children)
	return f
end

function Kit.clear(container: Instance)
	for _, child in container:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

return Kit
