--!strict
-- Settings panel: audio, roll animation, income labels, reduced effects,
-- auto-sell rarities and tutorial skip. All changes go through UpdateSettings.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RarityConfig = require(Shared:WaitForChild("Config"):WaitForChild("RarityConfig"))
local GameConfig = require(Shared:WaitForChild("Config"):WaitForChild("GameConfig"))
local UI = script.Parent.Parent:WaitForChild("UI")
local Kit = require(UI:WaitForChild("Kit"))
local Theme = require(UI:WaitForChild("Theme"))
local StateController = require(script.Parent:WaitForChild("StateController"))
local UIController = require(script.Parent:WaitForChild("UIController"))

local C = Theme.Colors

local SettingsController = {}

local render: (() -> ())? = nil

local function buildSettings(body: Frame)
	local scroll = Kit.scroll({ Parent = body })
	Kit.list(scroll, Enum.FillDirection.Vertical, 8)
	local function doRender()
		local profile = StateController.Profile
		if not profile then
			return
		end
		local s = profile.Settings
		Kit.clear(scroll)
		local order = 0
		local function row(
			label: string,
			value: string,
			onMinus: (() -> ())?,
			onPlus: (() -> ())?,
			onToggle: (() -> ())?
		)
			order += 1
			local r = Kit.card({ Size = UDim2.new(1, -8, 0, 52), LayoutOrder = order, Parent = scroll })
			Kit.text({
				Text = label,
				TextXAlignment = Enum.TextXAlignment.Left,
				Size = UDim2.new(0.5, 0, 1, -8),
				Position = UDim2.fromOffset(12, 4),
				MaxTextSize = 17,
				Parent = r,
			})
			if onToggle then
				Kit.button(
					value,
					if value == "ON" then "Good" else "Dark",
					onToggle,
					{ Size = UDim2.fromOffset(120, 40), Position = UDim2.new(1, -128, 0, 6), Parent = r }
				)
			else
				Kit.button(
					"−",
					"Dark",
					onMinus,
					{ Size = UDim2.fromOffset(44, 40), Position = UDim2.new(1, -200, 0, 6), Parent = r }
				)
				Kit.text({
					Text = value,
					Font = Theme.Fonts.Bold,
					Size = UDim2.fromOffset(100, 40),
					Position = UDim2.new(1, -152, 0, 6),
					MaxTextSize = 18,
					Parent = r,
				})
				Kit.button(
					"+",
					"Dark",
					onPlus,
					{ Size = UDim2.fromOffset(44, 40), Position = UDim2.new(1, -52, 0, 6), Parent = r }
				)
			end
		end
		local function set(key: string, value: any)
			UIController.call("UpdateSettings", { [key] = value })
		end
		local function onOff(b: boolean): string
			return if b then "ON" else "OFF"
		end
		Kit.header("Audio", { LayoutOrder = 0, Parent = scroll })
		row("🎵 Music volume", math.floor(s.MusicVolume * 100 + 0.5) .. "%", function()
			set("MusicVolume", math.max(0, s.MusicVolume - 0.1))
		end, function()
			set("MusicVolume", math.min(1, s.MusicVolume + 0.1))
		end)
		row("🔊 Sound effects", math.floor(s.SfxVolume * 100 + 0.5) .. "%", function()
			set("SfxVolume", math.max(0, s.SfxVolume - 0.1))
		end, function()
			set("SfxVolume", math.min(1, s.SfxVolume + 0.1))
		end)
		order += 1
		Kit.header("Gameplay", { LayoutOrder = order, Parent = scroll })
		row("⏩ Skip roll animations", onOff(s.SkipRollAnimation), nil, nil, function()
			set("SkipRollAnimation", not s.SkipRollAnimation)
		end)
		row("💰 Income labels over base monsters", onOff(s.ShowIncomeLabels), nil, nil, function()
			set("ShowIncomeLabels", not s.ShowIncomeLabels)
		end)
		row("🌙 Reduced effects (no flashes/shake)", onOff(s.ReducedEffects), nil, nil, function()
			set("ReducedEffects", not s.ReducedEffects)
		end)
		order += 1
		Kit.header("Auto-sell newly rolled duplicates", { LayoutOrder = order, Parent = scroll })
		order += 1
		Kit.text({
			Text = "Only monsters you already discovered are auto-sold. New discoveries are always kept.",
			TextColor3 = C.Muted,
			Size = UDim2.new(1, -8, 0, 22),
			LayoutOrder = order,
			MaxTextSize = 14,
			Parent = scroll,
		})
		for _, rarityId in RarityConfig.Order do
			local rarity = RarityConfig.Rarities[rarityId]
			if rarity.Tier <= 4 then
				row(
					rarity.Glyph .. " " .. rarity.DisplayName,
					onOff(s.AutoSell[rarityId] == true),
					nil,
					nil,
					function()
						local clean: { [string]: boolean } = {}
						for k, v in s.AutoSell do
							if v and k ~= rarityId then
								clean[k] = true
							end
						end
						if not s.AutoSell[rarityId] then
							clean[rarityId] = true
						end
						set("AutoSell", clean)
					end
				)
			end
		end
		order += 1
		Kit.header("Tutorial", { LayoutOrder = order, Parent = scroll })
		if not profile.Tutorial.Completed then
			order += 1
			Kit.button("Skip tutorial", "Dark", function()
				UIController.call("TutorialSkip")
			end, { Size = UDim2.new(1, -8, 0, 44), LayoutOrder = order, Parent = scroll })
		end
		order += 1
		Kit.text({
			Text = GameConfig.GameName .. " v" .. GameConfig.Version,
			TextColor3 = C.Muted,
			Size = UDim2.new(1, -8, 0, 24),
			LayoutOrder = order,
			MaxTextSize = 14,
			Parent = scroll,
		})
	end
	render = doRender
	doRender()
end

function SettingsController.init()
	UIController.registerPanel({
		Id = "Settings",
		Title = "Settings",
		Glyph = "⚙",
		Build = buildSettings,
		OnOpen = function()
			if render then
				render()
			end
		end,
	})
end

function SettingsController.start()
	StateController.Changed:Connect(function(key)
		if
			(key == "Settings" or key == "Tutorial" or key == "*")
			and UIController.openId() == "Settings"
			and render
		then
			render()
		end
	end)
end

return SettingsController
