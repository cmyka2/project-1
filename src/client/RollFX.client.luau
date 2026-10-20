-- Roll reveal, genre-style (Sol's RNG / Pets Go): a rarity spinner that slows down, then the reveal with a
-- rarity-colored flash; Legendary+ shakes the camera, Divine+ gets a short cutscene (blur, letterbox, banner).
-- Golden / Rainbow / Lucky rolls are tagged. Purely visual: the server already awarded the monster.
-- Rolls below Settings.skipBelow show a quick toast instead. Also tints the world while a biome is active.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local Http = game:GetService("HttpService")
local M = RS:WaitForChild("Monster")
local Config = require(M:WaitForChild("MonsterConfig"))
local P = require(M:WaitForChild("ProgressConfig"))
local Assets = require(M:WaitForChild("AssetRegistry"))
local Traits = require(M:WaitForChild("TraitConfig"))
local player = Players.LocalPlayer
local state = player:WaitForChild("PlayerGui"):WaitForChild("State") -- private mirror of my save, written by the server

local function decode(s)
	local ok, v = pcall(Http.JSONDecode, Http, s or "")
	return ok and v or {}
end
local function text(parent, size, pos, color)
	local l = Instance.new("TextLabel") l.Size = size l.Position = pos l.AnchorPoint = Vector2.new(0.5, 0.5) l.BackgroundTransparency = 1
	l.Font = Enum.Font.FredokaOne l.TextScaled = true l.Text = "" l.TextColor3 = color or Color3.new(1, 1, 1) l.TextStrokeTransparency = 0 l.Parent = parent
	return l
end
-- imported sounds (AssetRegistry Sounds/roll_tick, roll_reveal, roll_rare) win over the built-in fallbacks
local FALLBACK = { roll_tick = "rbxasset://sounds/electronicpingshort.wav", roll_reveal = "rbxasset://sounds/electronicpingshort.wav", roll_rare = "rbxasset://sounds/electronicpingshort.wav" }
local function play(id, pitch)
	local src = Assets.GetAsset("Sounds", id)
	local s = src and src:IsA("Sound") and src:Clone() or Instance.new("Sound")
	if not src then s.SoundId = FALLBACK[id] s.Volume = 0.4 end
	s.PlaybackSpeed = pitch or 1
	s.Parent = workspace.CurrentCamera
	s:Play()
	s.Ended:Connect(function() s:Destroy() end)
	task.delay(5, function() if s.Parent then s:Destroy() end end)
end

local gui = Instance.new("ScreenGui") gui.Name = "RollFX" gui.ResetOnSpawn = false gui.IgnoreGuiInset = true gui.DisplayOrder = 20 gui.Parent = player:WaitForChild("PlayerGui")
local flash = Instance.new("Frame") flash.Size = UDim2.fromScale(1, 1) flash.BackgroundTransparency = 1 flash.BorderSizePixel = 0 flash.Parent = gui
local bars = {}
for k, y in { 0, 1 } do
	local b = Instance.new("Frame") b.AnchorPoint = Vector2.new(0, y) b.Position = UDim2.fromScale(0, y) b.Size = UDim2.fromScale(1, 0) b.BackgroundColor3 = Color3.new(0, 0, 0)
	b.BorderSizePixel = 0 b.Parent = gui
	bars[k] = b
end
local spin = text(gui, UDim2.fromScale(0.6, 0.09), UDim2.fromScale(0.5, 0.38))
local name = text(gui, UDim2.fromScale(0.7, 0.1), UDim2.fromScale(0.5, 0.38))
local sub = text(gui, UDim2.fromScale(0.6, 0.05), UDim2.fromScale(0.5, 0.46), Color3.fromRGB(230, 230, 240))
local tag = text(gui, UDim2.fromScale(0.5, 0.05), UDim2.fromScale(0.5, 0.31), Color3.fromRGB(255, 220, 90))
for _, l in { spin, name, sub, tag } do
	local c = Instance.new("UISizeConstraint") c.MaxSize = Vector2.new(900, 90) c.Parent = l
end
local SPECIAL = { golden = "✨ GOLDEN ROLL x2", rainbow = "🌈 RAINBOW ROLL x5", lucky = "🍀 LUCKY ROLL x10" }

local function shake(secs, power)
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not hum then return end
	local t0 = os.clock()
	while os.clock() - t0 < secs do
		hum.CameraOffset = Vector3.new((math.random() - 0.5) * power, (math.random() - 0.5) * power, 0)
		task.wait()
	end
	hum.CameraOffset = Vector3.zero
end
local function doFlash(color, strength)
	flash.BackgroundColor3 = color
	flash.BackgroundTransparency = 1 - strength
	TweenService:Create(flash, TweenInfo.new(0.6), { BackgroundTransparency = 1 }):Play()
end

local busy, queued = false, nil
local function reveal(r)
	local def = Config.ById[r.id]
	if not def then return end
	local rar, var = Config.RarityById[def.rarity], Config.VariantById[r.v]
	local tier = Config.Tier[def.rarity]
	local color = r.v ~= "Normal" and var.color or rar.color
	local mut = r.mu and Traits.MutationById[r.mu]
	local title = (mut and mut.name .. " " or "") .. (r.v ~= "Normal" and r.v:upper() .. " " or "") .. def.name
	local specials = {}
	for key, label in SPECIAL do if r.special and r.special:find(key) then table.insert(specials, label) end end
	if mut then table.insert(specials, "🧬 " .. mut.name:upper() .. " MUTATION x" .. mut.mult) end
	local extra = r.more and #r.more > 0 and ("  +" .. #r.more .. " more") or ""
	local skip = decode(state:GetAttribute("Settings")).skipBelow or 0
	if tier < skip then -- quick toast
		name.Text, name.TextColor3 = (r.new and "NEW! " or "") .. title .. extra, color
		sub.Text, tag.Text = def.rarity, table.concat(specials, "  ")
		task.delay(1.4, function() if not busy then name.Text, sub.Text, tag.Text = "", "", "" end end)
		return
	end
	busy = true
	name.Text, sub.Text = "", ""
	tag.Text = table.concat(specials, "  ")
	-- spinner: random rarities flick by, slowing down; rarer results spin longer
	local steps = math.clamp(8 + tier * 2, 10, 32)
	for k = 1, steps do
		local fake = Config.Rarities[math.random(1, math.min(#Config.Rarities, tier + 2))]
		spin.Text, spin.TextColor3 = fake.id, fake.color
		play("roll_tick", 1 + k / steps)
		task.wait(0.03 + 0.012 * k)
	end
	spin.Text = ""
	if tier >= 7 then -- cutscene: blur + letterbox + long flash
		local blur = Instance.new("BlurEffect") blur.Size = 0 blur.Parent = Lighting
		TweenService:Create(blur, TweenInfo.new(0.4), { Size = 18 }):Play()
		for _, b in bars do TweenService:Create(b, TweenInfo.new(0.4), { Size = UDim2.fromScale(1, 0.12) }):Play() end
		sub.Text, sub.TextColor3 = "A " .. def.rarity:upper() .. " APPROACHES...", rar.color
		play("roll_rare", 0.8)
		task.wait(1.2)
		doFlash(rar.color, 0.9)
		task.spawn(shake, 0.8, 1.6)
		task.delay(2.6, function()
			TweenService:Create(blur, TweenInfo.new(0.4), { Size = 0 }):Play()
			for _, b in bars do TweenService:Create(b, TweenInfo.new(0.4), { Size = UDim2.fromScale(1, 0) }):Play() end
			task.delay(0.5, function() blur:Destroy() end)
		end)
	elseif tier >= 4 then
		doFlash(color, tier >= 5 and 0.7 or 0.4)
		if tier >= 5 then task.spawn(shake, 0.35, 0.8) end
		play("roll_rare", 1)
	else
		play("roll_reveal", 1.2)
	end
	name.Text, name.TextColor3 = (r.new and "NEW! " or "") .. title .. extra, color
	sub.Text, sub.TextColor3 = def.rarity .. (r.new and "  •  added to your Index" or ""), rar.color
	name.Size = UDim2.fromScale(0.35, 0.05)
	TweenService:Create(name, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Size = UDim2.fromScale(0.7, 0.1) }):Play()
	task.wait(tier >= 7 and 2.8 or 1.4)
	name.Text, sub.Text, tag.Text = "", "", ""
	busy = false
	if queued then
		local nextRoll = queued
		queued = nil
		reveal(nextRoll)
	end
end
state:GetAttributeChangedSignal("LastRoll"):Connect(function()
	local r = decode(state:GetAttribute("LastRoll"))
	if not r.id then return end
	if busy then queued = r return end -- keep only the latest while an animation plays
	task.spawn(reveal, r)
end)

-- biome tint (local-only ColorCorrection)
local cc = Instance.new("ColorCorrectionEffect") cc.Name = "BiomeTint" cc.Enabled = false cc.Parent = Lighting
local function refreshBiome()
	local b = decode(RS:GetAttribute("Biome"))
	local def = b.id and P.BiomeById[b.id]
	cc.Enabled = def ~= nil
	if def then
		cc.TintColor = Color3.new(1, 1, 1)
		TweenService:Create(cc, TweenInfo.new(3), { TintColor = def.tint }):Play()
	end
end
RS:GetAttributeChangedSignal("Biome"):Connect(refreshBiome)
refreshBiome()
