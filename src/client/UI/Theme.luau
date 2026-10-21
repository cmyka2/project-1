--!strict
-- Visual language for every screen: colors, fonts, sizes and animation timings.

local Theme = {}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

Theme.Colors = {
	Backdrop = rgb(8, 10, 20),
	Panel = rgb(28, 32, 54),
	PanelLight = rgb(40, 46, 76),
	PanelDark = rgb(18, 21, 38),
	Header = rgb(52, 60, 104),
	Stroke = rgb(90, 104, 170),
	Text = rgb(245, 247, 255),
	Muted = rgb(160, 170, 205),
	Accent = rgb(110, 140, 255),
	AccentDark = rgb(70, 92, 200),
	Good = rgb(90, 220, 120),
	GoodDark = rgb(50, 160, 80),
	Bad = rgb(255, 90, 100),
	BadDark = rgb(190, 50, 60),
	Warn = rgb(255, 196, 70),
	Gold = rgb(255, 210, 70),
	Gem = rgb(90, 220, 255),
	Ascension = rgb(255, 160, 255),
	Disabled = rgb(80, 84, 104),
	Shadow = rgb(0, 0, 0),
}

Theme.Fonts = {
	Title = Enum.Font.FredokaOne,
	Body = Enum.Font.GothamMedium,
	Bold = Enum.Font.GothamBold,
	Mono = Enum.Font.Code,
}

Theme.Corner = 12
Theme.SmallCorner = 8
Theme.Padding = 10

Theme.Tween = {
	Fast = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	Normal = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	Bouncy = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	Slow = TweenInfo.new(0.6, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
}

-- Button styles: background, hover/press shade, text color.
Theme.ButtonStyles = {
	Primary = { Bg = rgb(110, 140, 255), Bg2 = rgb(80, 104, 230), Text = rgb(255, 255, 255) },
	Good = { Bg = rgb(80, 210, 110), Bg2 = rgb(50, 170, 80), Text = rgb(255, 255, 255) },
	Bad = { Bg = rgb(240, 80, 90), Bg2 = rgb(190, 50, 60), Text = rgb(255, 255, 255) },
	Gold = { Bg = rgb(255, 200, 60), Bg2 = rgb(230, 160, 30), Text = rgb(60, 40, 0) },
	Gem = { Bg = rgb(80, 200, 255), Bg2 = rgb(40, 150, 220), Text = rgb(10, 30, 50) },
	Dark = { Bg = rgb(52, 60, 98), Bg2 = rgb(40, 46, 78), Text = rgb(235, 238, 255) },
	Ghost = { Bg = rgb(36, 41, 70), Bg2 = rgb(30, 34, 58), Text = rgb(200, 206, 240) },
}

return Theme
