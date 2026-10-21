--!strict
-- Fusion Lab (star fusion, rarity fusion, special recipes, evolution),
-- Crafting Workshop (timed queue) and Chest Vault (odds shown before
-- buying; the reveal shows rewards the server already granted).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Util = Shared:WaitForChild("Util")
local CraftingConfig = require(Config:WaitForChild("CraftingConfig"))
local ChestConfig = require(Config:WaitForChild("ChestConfig"))
local MonsterConfig = require(Config:WaitForChild("MonsterConfig"))
local RarityConfig = require(Config:WaitForChild("RarityConfig"))
local RegionConfig = require(Config:WaitForChild("RegionConfig"))
local EquipmentConfig = require(Config:WaitForChild("EquipmentConfig"))
local EconomyConfig = require(Config:WaitForChild("EconomyConfig"))
local StatMath = require(Util:WaitForChild("StatMath"))
local Modifiers = require(Util:WaitForChild("Modifiers"))
local Format = require(Util:WaitForChild("Format"))
local Types = require(Shared:WaitForChild("Types"))
local UI = script.Parent.Parent:WaitForChild("UI")
local Kit = require(UI:WaitForChild("Kit"))
local Theme = require(UI:WaitForChild("Theme"))
local Icons = require(UI:WaitForChild("Icons"))
local StateController = require(script.Parent:WaitForChild("StateController"))
local UIController = require(script.Parent:WaitForChild("UIController"))
local AudioController = require(script.Parent:WaitForChild("AudioController"))
local EffectsController = require(script.Parent:WaitForChild("EffectsController"))

local C = Theme.Colors

local ShopController = {}

local renderers: { [string]: () -> () } = {}
local fusionTab = 1
local fusionTarget: string? = nil

type MonsterInstance = Types.MonsterInstance

local function mods(): { [string]: number }
	local d = StateController.Derived
	return if d then d.Modifiers else {}
end

local function consumable(inst: MonsterInstance): boolean
	return not StateController.slotOf(inst.Id)
		and not inst.Locked
		and not inst.Favorite
		and not StateController.inTeam(inst.Id)
end

local function haveText(have: number, need: number, label: string): string
	local color = if have >= need then C.Good else C.Bad
	return string.format(
		'<font color="#%s">%s %s/%s</font>',
		color:ToHex(),
		label,
		Format.number(have),
		Format.number(need)
	)
end

-- Fusion -------------------------------------------------------------------------------

local function renderStar(container: Frame)
	local profile = StateController.Profile
	if not profile then
		return
	end
	-- group duplicates
	local groups: { [string]: { MonsterInstance } } = {}
	for _, inst in StateController.monsters() do
		groups[inst.MonsterId] = groups[inst.MonsterId] or {}
		table.insert(groups[inst.MonsterId], inst)
	end
	local list = Kit.scroll({ Parent = container })
	Kit.list(list, Enum.FillDirection.Vertical, 6)
	Kit.text({
		Text = "Merge duplicate copies into one monster to give it a ★ star: +"
			.. Format.percent(EconomyConfig.StarIncomeBonus, 0)
			.. " income and +"
			.. Format.percent(EconomyConfig.StarStatBonus, 0)
			.. " stats per star. Always succeeds.",
		TextColor3 = C.Muted,
		Size = UDim2.new(1, -8, 0, 40),
		LayoutOrder = 0,
		MaxTextSize = 15,
		Parent = list,
	})
	local order = 0
	for monsterId, insts in groups do
		if #insts >= 2 then
			table.sort(insts, function(a, b)
				if a.Stars ~= b.Stars then
					return a.Stars > b.Stars
				end
				return a.Level > b.Level
			end)
			local target = insts[1]
			if fusionTarget then
				for _, inst in insts do
					if inst.Id == fusionTarget then
						target = inst
					end
				end
			end
			if target.Stars < EconomyConfig.MaxStars then
				order += 1
				local nextStar = target.Stars + 1
				local needed = CraftingConfig.StarFusion.DuplicatesPerStar[nextStar] or 99
				local fodder = {}
				for i = #insts, 1, -1 do
					local inst = insts[i]
					if inst.Id ~= target.Id and consumable(inst) and #fodder < needed then
						table.insert(fodder, inst.Id)
					end
				end
				local coins = Modifiers.serviceCost(
					StatMath.sellValue(target, {})
						* CraftingConfig.StarFusion.CoinsPerStarMultiplier
						* nextStar,
					mods()
				)
				local def = MonsterConfig.Monsters[monsterId]
				local row = Kit.card({ Size = UDim2.new(1, -8, 0, 70), LayoutOrder = order, Parent = list })
				local holder = Kit.frame({
					BackgroundTransparency = 1,
					Size = UDim2.fromOffset(60, 60),
					Position = UDim2.fromOffset(5, 5),
					Parent = row,
				})
				Icons.monster(monsterId, holder)
				Kit.text({
					Text = string.format(
						"%s  %s → %s",
						def.DisplayName,
						string.rep("★", target.Stars),
						string.rep("★", nextStar)
					),
					Font = Theme.Fonts.Bold,
					TextXAlignment = Enum.TextXAlignment.Left,
					Size = UDim2.new(1, -240, 0.5, 0),
					Position = UDim2.fromOffset(72, 4),
					MaxTextSize = 17,
					Parent = row,
				})
				Kit.text({
					Text = haveText(#fodder, needed, "Spare copies")
						.. "   "
						.. haveText(profile.Currencies.Coins, coins, "💰"),
					TextXAlignment = Enum.TextXAlignment.Left,
					Size = UDim2.new(1, -240, 0.45, 0),
					Position = UDim2.new(0, 72, 0.5, 0),
					MaxTextSize = 14,
					Parent = row,
				})
				local b = Kit.button("Fuse ★", "Gold", function()
					local result = UIController.call("StarFuse", target.Id, fodder, false)
					if result.ok then
						AudioController.play("Fusion")
						EffectsController.flash(C.Gold, 0.3)
						UIController.toast("success", def.DisplayName .. " reached " .. nextStar .. "★!")
					end
				end, {
					Size = UDim2.fromOffset(150, 50),
					Position = UDim2.new(1, -156, 0, 10),
					Parent = row,
				})
				Kit.setEnabled(b, #fodder >= needed and profile.Currencies.Coins >= coins)
			end
		end
	end
	if order == 0 then
		Kit.text({
			Text = "Roll duplicates of a monster to star-fuse it. (Locked, favorite, placed and team monsters are never used as material.)",
			TextColor3 = C.Muted,
			Size = UDim2.new(1, -8, 0, 50),
			LayoutOrder = 1,
			Parent = list,
		})
	end
end

local rarityRegion = 1
local rarityTier = 1

local function renderRarity(container: Frame)
	local profile = StateController.Profile
	if not profile then
		return
	end
	local cfg = CraftingConfig.RarityFusion
	local regionId = RegionConfig.Order[rarityRegion]
	local region = RegionConfig.Regions[regionId]
	local rarityId = RarityConfig.Order[rarityTier]
	local controls =
		Kit.frame({ BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 44), Parent = container })
	Kit.list(controls, Enum.FillDirection.Horizontal, 6)
	Kit.button("Region: " .. region.DisplayName, "Dark", function()
		rarityRegion = (rarityRegion % #RegionConfig.Order) + 1
		renderers.Fusion()
	end, { Size = UDim2.fromOffset(240, 40), Parent = controls })
	Kit.button("Rarity: " .. rarityId, "Dark", function()
		rarityTier = (rarityTier % (#RarityConfig.Order - 1)) + 1
		renderers.Fusion()
	end, { Size = UDim2.fromOffset(200, 40), Parent = controls })
	local candidates = {}
	for _, inst in StateController.monsters() do
		local def = MonsterConfig.Monsters[inst.MonsterId]
		if def.Region == regionId and def.Rarity == rarityId and consumable(inst) then
			table.insert(candidates, inst)
		end
	end
	table.sort(candidates, function(a, b)
		return a.Level < b.Level
	end)
	local nextRarity = RarityConfig.Order[rarityTier + 1]
	local pool = {}
	local total = 0
	for _, id in MonsterConfig.Order do
		local def = MonsterConfig.Monsters[id]
		if def.Region == regionId and def.Rarity == nextRarity and MonsterConfig.isRollable(def) then
			table.insert(pool, def)
			total += def.RollWeight
		end
	end
	local info = Kit.frame({
		BackgroundColor3 = C.PanelDark,
		Size = UDim2.new(1, 0, 1, -52),
		Position = UDim2.fromOffset(0, 52),
		Parent = container,
	})
	Kit.corner(info)
	Kit.padding(info, 10)
	Kit.list(info, Enum.FillDirection.Vertical, 6)
	Kit.text({
		Text = string.format(
			"Fuse %d %s %s monsters into 1 guaranteed %s monster from %s.",
			cfg.InputCount,
			region.DisplayName,
			rarityId,
			nextRarity or "?",
			region.DisplayName
		),
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, 24),
		MaxTextSize = 16,
		Parent = info,
	})
	if #pool == 0 then
		Kit.text({
			Text = "No higher rarity exists in this region's dice pool. Try another rarity/region.",
			TextColor3 = C.Warn,
			Size = UDim2.new(1, 0, 0, 24),
			MaxTextSize = 15,
			Parent = info,
		})
		return
	end
	local lines = {}
	for _, def in pool do
		table.insert(lines, def.DisplayName .. " " .. Format.percent(def.RollWeight / total, 1))
	end
	Kit.text({
		Text = "Possible results: " .. table.concat(lines, ", ") .. " · " .. Format.percent(
			cfg.BonusMaterialChance,
			0
		) .. " chance of bonus materials",
		TextColor3 = C.Muted,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, 40),
		MaxTextSize = 14,
		Parent = info,
	})
	local coins = Modifiers.serviceCost(
		StatMath.regionDiceCost(regionId) * cfg.CoinsDiceCostMultiplier * rarityTier,
		mods()
	)
	local mats = rarityTier * cfg.MaterialPerTier
	Kit.text({
		Text = haveText(#candidates, cfg.InputCount, "Eligible monsters") .. "   " .. haveText(
			profile.Currencies.Coins,
			coins,
			"💰"
		) .. "   " .. haveText(
			profile.Currencies.Materials[region.MaterialId] or 0,
			mats,
			CraftingConfig.Materials[region.MaterialId].Glyph
		),
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, 24),
		MaxTextSize = 16,
		Parent = info,
	})
	local chosen = {}
	for i = 1, math.min(cfg.InputCount, #candidates) do
		table.insert(chosen, candidates[i].Id)
	end
	local b = Kit.button("🧬 Fuse (uses your lowest-level copies)", "Gold", function()
		local result = UIController.call("RarityFuse", chosen, false)
		if result.ok then
			AudioController.play("Fusion")
			local def = MonsterConfig.Monsters[result.data.MonsterId]
			EffectsController.flash(C.Gem, 0.3)
			UIController.popup("🧬 Fusion complete!", {
				"You created " .. (if def then def.DisplayName else "?") .. "!",
				if result.data.BonusMaterials > 0
					then "Bonus: +" .. result.data.BonusMaterials .. " materials"
					else "",
			}, C.Gem)
		end
	end, { Size = UDim2.new(1, 0, 0, 50), Parent = info })
	Kit.setEnabled(
		b,
		#chosen == cfg.InputCount
			and profile.Currencies.Coins >= coins
			and (profile.Currencies.Materials[region.MaterialId] or 0) >= mats
	)
end

local function renderSpecial(container: Frame)
	local profile = StateController.Profile
	if not profile then
		return
	end
	local list = Kit.scroll({ Parent = container })
	Kit.list(list, Enum.FillDirection.Vertical, 8)
	local order = 0
	for id, recipe in CraftingConfig.SpecialFusions do
		order += 1
		local chosen: { string } = {}
		local missing = {}
		for _, inputId in recipe.Inputs do
			local found: string? = nil
			for _, inst in StateController.monsters() do
				if inst.MonsterId == inputId and consumable(inst) and not table.find(chosen, inst.Id) then
					found = inst.Id
					break
				end
			end
			if found then
				table.insert(chosen, found)
			else
				table.insert(missing, MonsterConfig.Monsters[inputId].DisplayName)
			end
		end
		local result = MonsterConfig.Monsters[recipe.Result]
		local card = Kit.card({ Size = UDim2.new(1, -8, 0, 120), LayoutOrder = order, Parent = list })
		Kit.stroke(card, RarityConfig.Rarities[result.Rarity].Color, 2)
		local holder = Kit.frame({
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(90, 90),
			Position = UDim2.fromOffset(8, 15),
			Parent = card,
		})
		Icons.monster(recipe.Result, holder, profile.Discovery.DiscoveredMonsters[recipe.Result] ~= nil)
		local inputs = {}
		for _, inputId in recipe.Inputs do
			table.insert(inputs, MonsterConfig.Monsters[inputId].DisplayName)
		end
		Kit.text({
			Text = recipe.DisplayName .. "  (" .. result.Rarity .. ")",
			Font = Theme.Fonts.Title,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(1, -280, 0, 26),
			Position = UDim2.fromOffset(108, 6),
			MaxTextSize = 20,
			Parent = card,
		})
		Kit.text({
			Text = "Inputs: " .. table.concat(inputs, " + "),
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(1, -280, 0, 22),
			Position = UDim2.fromOffset(108, 34),
			MaxTextSize = 14,
			Parent = card,
		})
		local matText = { haveText(profile.Currencies.Coins, recipe.Coins, "💰") }
		local affordable = profile.Currencies.Coins >= recipe.Coins
		for materialId, amount in recipe.Materials do
			local have = profile.Currencies.Materials[materialId] or 0
			table.insert(matText, haveText(have, amount, CraftingConfig.Materials[materialId].Glyph))
			affordable = affordable and have >= amount
		end
		Kit.text({
			Text = table.concat(matText, "  "),
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(1, -280, 0, 22),
			Position = UDim2.fromOffset(108, 58),
			MaxTextSize = 14,
			Parent = card,
		})
		if #missing > 0 then
			Kit.text({
				Text = "Missing (unprotected copies): " .. table.concat(missing, ", "),
				TextColor3 = C.Bad,
				TextXAlignment = Enum.TextXAlignment.Left,
				Size = UDim2.new(1, -280, 0, 22),
				Position = UDim2.fromOffset(108, 84),
				MaxTextSize = 13,
				Parent = card,
			})
		end
		local b = Kit.button("Fuse", "Gold", function()
			local r = UIController.call("SpecialFuse", id, chosen, false)
			if r.ok then
				AudioController.play("Fusion")
				EffectsController.flash(C.Gold, 0.5)
				UIController.popup(
					"✨ Special Fusion!",
					{ "You created " .. result.DisplayName .. "!" },
					C.Gold
				)
			end
		end, { Size = UDim2.fromOffset(150, 50), Position = UDim2.new(1, -158, 0.5, -25), Parent = card })
		Kit.setEnabled(b, #missing == 0 and affordable)
	end
end

local function renderEvolve(container: Frame)
	local profile = StateController.Profile
	if not profile then
		return
	end
	local list = Kit.scroll({ Parent = container })
	Kit.list(list, Enum.FillDirection.Vertical, 8)
	local order = 0
	for _, inst in StateController.monsters() do
		local def = MonsterConfig.Monsters[inst.MonsterId]
		local req = def.EvolutionRequirements
		if def.EvolvesTo and req and (fusionTarget == nil or fusionTarget == inst.Id or true) then
			order += 1
			local evolved = MonsterConfig.Monsters[def.EvolvesTo]
			local dupes: { string } = {}
			for _, other in StateController.monsters() do
				if
					other.Id ~= inst.Id
					and other.MonsterId == inst.MonsterId
					and consumable(other)
					and #dupes < req.Duplicates
				then
					table.insert(dupes, other.Id)
				end
			end
			local card = Kit.card({
				Size = UDim2.new(1, -8, 0, 100),
				LayoutOrder = if inst.Id == fusionTarget then -1 else order,
				Parent = list,
			})
			Kit.stroke(card, if inst.Id == fusionTarget then C.Gold else C.Stroke, 2)
			local a = Kit.frame({
				BackgroundTransparency = 1,
				Size = UDim2.fromOffset(70, 70),
				Position = UDim2.fromOffset(8, 15),
				Parent = card,
			})
			Icons.monster(inst.MonsterId, a)
			Kit.text({
				Text = "➜",
				Font = Theme.Fonts.Title,
				Size = UDim2.fromOffset(30, 70),
				Position = UDim2.fromOffset(80, 15),
				MaxTextSize = 30,
				Parent = card,
			})
			local b2 = Kit.frame({
				BackgroundTransparency = 1,
				Size = UDim2.fromOffset(70, 70),
				Position = UDim2.fromOffset(112, 15),
				Parent = card,
			})
			Icons.monster(def.EvolvesTo, b2)
			Kit.text({
				Text = def.DisplayName
					.. " Lv"
					.. inst.Level
					.. "  ➜  "
					.. evolved.DisplayName
					.. " ("
					.. evolved.Rarity
					.. ")",
				Font = Theme.Fonts.Bold,
				TextXAlignment = Enum.TextXAlignment.Left,
				Size = UDim2.new(1, -360, 0, 26),
				Position = UDim2.fromOffset(192, 8),
				MaxTextSize = 16,
				Parent = card,
			})
			local reqs = {
				haveText(inst.Level, req.Level, "Level"),
				haveText(profile.Currencies.Coins, req.Coins, "💰"),
			}
			local ok = inst.Level >= req.Level
				and profile.Currencies.Coins >= req.Coins
				and #dupes >= req.Duplicates
			if req.Duplicates > 0 then
				table.insert(reqs, haveText(#dupes, req.Duplicates, "Copies"))
			end
			for materialId, amount in req.Materials do
				local have = profile.Currencies.Materials[materialId] or 0
				table.insert(reqs, haveText(have, amount, CraftingConfig.Materials[materialId].Glyph))
				ok = ok and have >= amount
			end
			Kit.text({
				Text = table.concat(reqs, "  "),
				TextXAlignment = Enum.TextXAlignment.Left,
				Size = UDim2.new(1, -360, 0, 44),
				Position = UDim2.fromOffset(192, 38),
				MaxTextSize = 14,
				Parent = card,
			})
			local button = Kit.button("Evolve ✨", "Gem", function()
				local r = UIController.call("Evolve", inst.Id, dupes, false)
				if r.ok then
					AudioController.play("Fusion")
					EffectsController.flash(C.Gem, 0.5)
					UIController.popup(
						"✨ Evolution!",
						{ def.DisplayName .. " evolved into " .. evolved.DisplayName .. "!" },
						C.Gem
					)
				end
			end, {
				Size = UDim2.fromOffset(150, 50),
				Position = UDim2.new(1, -158, 0.5, -25),
				Parent = card,
			})
			Kit.setEnabled(button, ok)
		end
	end
	if order == 0 then
		Kit.text({
			Text = "None of your monsters can evolve yet. Look for monsters with an evolution in the Codex.",
			TextColor3 = C.Muted,
			Size = UDim2.new(1, -8, 0, 40),
			Parent = list,
		})
	end
end

local function buildFusion(body: Frame)
	local content = Kit.frame({
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, -46),
		Position = UDim2.fromOffset(0, 46),
		Parent = body,
	})
	local renderFns = { renderStar, renderRarity, renderSpecial, renderEvolve }
	local _, selectTab = Kit.tabs(
		body,
		{ "★ Star Fusion", "🧬 Rarity Fusion", "✨ Special", "🦋 Evolution" },
		function(index)
			fusionTab = index
			Kit.clear(content)
			renderFns[index](content)
		end
	)
	renderers.Fusion = function()
		selectTab(fusionTab)
	end
	selectTab(fusionTab)
end

-- Crafting ---------------------------------------------------------------------------------

local craftCategory = "Equipment"

local function buildCrafting(body: Frame)
	local queueFrame =
		Kit.frame({ BackgroundColor3 = C.PanelDark, Size = UDim2.new(1, 0, 0, 90), Parent = body })
	Kit.corner(queueFrame)
	Kit.padding(queueFrame, 8)
	Kit.list(queueFrame, Enum.FillDirection.Horizontal, 8)
	local content =
		Kit.scroll({ Size = UDim2.new(1, 0, 1, -146), Position = UDim2.fromOffset(0, 146), Parent = body })
	Kit.list(content, Enum.FillDirection.Vertical, 6)
	local render: () -> ()
	local _, selectTab = Kit.tabs(
		body,
		{ "⚔ Equipment", "🧪 Potions", "🪨 Materials" },
		function(_, name)
			craftCategory = if string.find(name, "Equipment")
				then "Equipment"
				elseif string.find(name, "Potions") then "Potion"
				else "Material"
			render()
		end,
		{ Position = UDim2.fromOffset(0, 98) }
	)
	-- queue only (refreshed every second for timers)
	local function renderQueue()
		local profile = StateController.Profile
		local derived = StateController.Derived
		if not profile or not derived then
			return
		end
		Kit.clear(queueFrame)
		local now = StateController.serverTime()
		for i, job in profile.Crafting.Queue do
			local recipe = CraftingConfig.Recipes[job.RecipeId]
			local slot = Kit.card({
				Size = UDim2.new(1 / math.max(derived.CraftQueueSize, 1), -8, 1, 0),
				LayoutOrder = i,
				Parent = queueFrame,
			})
			Kit.text({
				Text = (if recipe then recipe.DisplayName else job.RecipeId) .. " x" .. job.Count,
				Font = Theme.Fonts.Bold,
				Size = UDim2.new(1, -8, 0.4, 0),
				Position = UDim2.fromOffset(4, 2),
				MaxTextSize = 14,
				Parent = slot,
			})
			local ready = now >= job.ReadyAt
			if ready then
				Kit.button("Claim", "Good", function()
					local r = UIController.call("ClaimCraft", job.JobId)
					if r.ok then
						AudioController.play("Purchase")
						UIController.toast(
							"success",
							"Crafted " .. (if recipe then recipe.DisplayName else "item") .. "!"
						)
					end
				end, {
					Size = UDim2.new(1, -8, 0.5, 0),
					Position = UDim2.new(0, 4, 0.48, 0),
					Parent = slot,
				})
			else
				local _, set = Kit.progress(
					slot,
					C.Accent,
					{ Size = UDim2.new(1, -8, 0.36, 0), Position = UDim2.new(0, 4, 0.52, 0) }
				)
				local span = math.max(1, job.ReadyAt - job.StartedAt)
				set((now - job.StartedAt) / span, Format.duration(job.ReadyAt - now))
			end
		end
		for i = #profile.Crafting.Queue + 1, derived.CraftQueueSize do
			local slot = Kit.card({
				Size = UDim2.new(1 / math.max(derived.CraftQueueSize, 1), -8, 1, 0),
				LayoutOrder = i,
				BackgroundTransparency = 0.5,
				Parent = queueFrame,
			})
			Kit.text({ Text = "Empty slot", TextColor3 = C.Muted, MaxTextSize = 14, Parent = slot })
		end
	end
	render = function()
		local profile = StateController.Profile
		local derived = StateController.Derived
		if not profile or not derived then
			return
		end
		renderQueue()
		Kit.clear(content)
		local order = 0
		for _, id in CraftingConfig.RecipeOrder do
			local recipe = CraftingConfig.Recipes[id]
			if recipe.Category == craftCategory then
				order += 1
				local unlocked = profile.Progression.UnlockedRegions[recipe.RequiredRegion] == true
				local row =
					Kit.card({ Size = UDim2.new(1, -8, 0, 64), LayoutOrder = order, Parent = content })
				local holder = Kit.frame({
					BackgroundTransparency = 1,
					Size = UDim2.fromOffset(54, 54),
					Position = UDim2.fromOffset(5, 5),
					Parent = row,
				})
				local out = recipe.Output
				if out.Kind == "Equipment" then
					Icons.equipment(out.Id, holder)
				elseif out.Kind == "Consumable" then
					Icons.consumable(out.Id, holder)
				else
					Icons.material(out.Id, holder)
				end
				local affordable = unlocked
				local parts = {}
				for _, ing in recipe.Ingredients do
					local amount = ing.Amount
					if ing.Kind == "Coins" then
						amount = Modifiers.serviceCost(amount, derived.Modifiers)
					end
					local have = if ing.Kind == "Material"
						then profile.Currencies.Materials[ing.Id] or 0
						elseif ing.Kind == "Coins" then profile.Currencies.Coins
						else 0
					affordable = affordable and have >= amount
					local glyph = if ing.Kind == "Material"
						then CraftingConfig.Materials[ing.Id].Glyph
						else "💰"
					table.insert(parts, haveText(have, amount, glyph))
				end
				local outName = recipe.DisplayName
				if out.Kind == "Equipment" then
					local def = EquipmentConfig.Items[out.Id]
					if def then
						outName ..= " (" .. def.Rarity .. " " .. def.Category .. ")"
					end
				end
				Kit.text({
					Text = outName .. (if unlocked then "" else "  🔒 " .. recipe.RequiredRegion),
					Font = Theme.Fonts.Bold,
					TextXAlignment = Enum.TextXAlignment.Left,
					Size = UDim2.new(1, -260, 0.5, 0),
					Position = UDim2.fromOffset(66, 2),
					MaxTextSize = 16,
					Parent = row,
				})
				Kit.text({
					Text = table.concat(parts, "  ") .. "  ⏱ " .. Format.duration(
						Modifiers.craftSeconds(recipe.CraftSeconds, derived.Modifiers)
					),
					TextXAlignment = Enum.TextXAlignment.Left,
					Size = UDim2.new(1, -260, 0.45, 0),
					Position = UDim2.new(0, 66, 0.52, 0),
					MaxTextSize = 13,
					Parent = row,
				})
				local b = Kit.button("Craft", "Good", function()
					local r = UIController.call("StartCraft", id, 1)
					if r.ok then
						AudioController.play("UIClick")
					end
				end, {
					Size = UDim2.fromOffset(110, 46),
					Position = UDim2.new(1, -232, 0, 9),
					Parent = row,
				})
				Kit.setEnabled(b, affordable and #profile.Crafting.Queue < derived.CraftQueueSize)
				local b5 = Kit.button("x5", "Primary", function()
					UIController.call("StartCraft", id, 5)
				end, {
					Size = UDim2.fromOffset(110, 46),
					Position = UDim2.new(1, -116, 0, 9),
					Parent = row,
				})
				Kit.setEnabled(b5, unlocked and #profile.Crafting.Queue < derived.CraftQueueSize)
			end
		end
	end
	renderers.Crafting = render
	renderers.CraftingQueue = renderQueue
	selectTab(1)
end

-- Chests ------------------------------------------------------------------------------------

local function showChestRewards(rewards: { any })
	local lines = {}
	for _, reward in rewards do
		local key = if reward.Kind == "Coins" or reward.Kind == "Gems"
			then reward.Kind
			elseif reward.Kind == "Monster" then "Monster:" .. reward.Id
			else reward.Kind .. ":" .. reward.Id
		local text: string
		if reward.Kind == "Monster" then
			local def = MonsterConfig.Monsters[reward.Id]
			text = "🐾 " .. (if def then def.DisplayName .. " (" .. def.Rarity .. ")" else reward.Id)
		else
			text = Icons.rewardLabel(key, reward.Amount, Format.number)
		end
		if reward.Note then
			text ..= " (" .. reward.Note .. ")"
		end
		table.insert(lines, text)
	end
	AudioController.play("ChestOpen")
	EffectsController.flash(C.Gold, 0.25)
	UIController.popup("🎁 Chest opened!", lines, C.Gold)
end

local function buildChests(body: Frame)
	local scroll = Kit.scroll({ Parent = body })
	Kit.list(scroll, Enum.FillDirection.Vertical, 8)
	local render = function()
		local profile = StateController.Profile
		local derived = StateController.Derived
		if not profile or not derived then
			return
		end
		Kit.clear(scroll)
		Kit.header("Buy chests", { LayoutOrder = 0, Parent = scroll })
		local scale = 1
		local region = RegionConfig.Regions[profile.Progression.HighestRegion]
		if region then
			scale = region.IncomeScale
		end
		local order = 0
		local function chestRow(chestId: string, owned: number?)
			local chest = ChestConfig.Chests[chestId]
			order += 1
			local row = Kit.card({ Size = UDim2.new(1, -8, 0, 74), LayoutOrder = order, Parent = scroll })
			Kit.stroke(row, chest.Color, 2)
			local holder = Kit.frame({
				BackgroundTransparency = 1,
				Size = UDim2.fromOffset(62, 62),
				Position = UDim2.fromOffset(6, 6),
				Parent = row,
			})
			Icons.chest(chestId, holder)
			Kit.text({
				Text = chest.DisplayName .. (if owned then "  x" .. owned else ""),
				Font = Theme.Fonts.Title,
				TextXAlignment = Enum.TextXAlignment.Left,
				Size = UDim2.new(1, -420, 0.5, 0),
				Position = UDim2.fromOffset(76, 4),
				MaxTextSize = 18,
				Parent = row,
			})
			Kit.text({
				Text = chest.Description .. "  · " .. chest.Rolls .. " reward(s)",
				TextColor3 = C.Muted,
				TextXAlignment = Enum.TextXAlignment.Left,
				Size = UDim2.new(1, -420, 0.42, 0),
				Position = UDim2.new(0, 76, 0.52, 0),
				MaxTextSize = 13,
				Parent = row,
			})
			Kit.button("Odds ⓘ", "Ghost", function()
				local total = 0
				for _, r in chest.Rewards do
					total += r.Weight
				end
				local lines = {}
				for _, r in chest.Rewards do
					local name = r.Kind
					if r.Kind == "Equipment" then
						name = (EquipmentConfig.Items[r.Id] or { DisplayName = r.Id } :: any).DisplayName
					elseif r.Kind == "Monster" then
						name = MonsterConfig.Monsters[r.Id].DisplayName
					elseif r.Kind == "Material" then
						name = if r.Id == "@region"
							then "Region material"
							else CraftingConfig.Materials[r.Id].DisplayName
					elseif r.Kind == "Consumable" then
						name = CraftingConfig.Consumables[r.Id].DisplayName
					end
					table.insert(
						lines,
						string.format(
							"%s (%d-%d): %s",
							name,
							r.Min,
							r.Max,
							Format.percent(r.Weight / total, 2)
						)
					)
				end
				UIController.popup(chest.DisplayName .. " odds (per reward)", lines, chest.Color)
			end, { Size = UDim2.fromOffset(90, 44), Position = UDim2.new(1, -330, 0, 15), Parent = row })
			if owned then
				Kit.button("Open", "Good", function()
					local r = UIController.call("OpenChest", chestId, 1, true)
					if r.ok then
						showChestRewards(r.data.Rewards)
					end
				end, {
					Size = UDim2.fromOffset(110, 44),
					Position = UDim2.new(1, -232, 0, 15),
					Parent = row,
				})
				Kit.button("Open All", "Primary", function()
					local r = UIController.call(
						"OpenChest",
						chestId,
						math.min(owned, ChestConfig.MaxOpenPerRequest),
						true
					)
					if r.ok then
						showChestRewards(r.data.Rewards)
					end
				end, {
					Size = UDim2.fromOffset(110, 44),
					Position = UDim2.new(1, -116, 0, 15),
					Parent = row,
				})
			elseif chest.Cost and chest.CostCurrency then
				local cost = if chest.ScaleCost then math.floor(chest.Cost * scale) else chest.Cost
				local glyph = Icons.currencyGlyph(chest.CostCurrency)
				local balance = (profile.Currencies :: any)[chest.CostCurrency] or 0
				local b1 = Kit.button(
					glyph .. Format.number(cost),
					if chest.CostCurrency == "Gems" then "Gem" else "Gold",
					function()
						local r = UIController.call("OpenChest", chestId, 1, false)
						if r.ok then
							showChestRewards(r.data.Rewards)
						end
					end,
					{ Size = UDim2.fromOffset(110, 44), Position = UDim2.new(1, -232, 0, 15), Parent = row }
				)
				Kit.setEnabled(b1, balance >= cost)
				local b10 = Kit.button("x10", "Primary", function()
					local r = UIController.call("OpenChest", chestId, 10, false)
					if r.ok then
						showChestRewards(r.data.Rewards)
					end
				end, {
					Size = UDim2.fromOffset(110, 44),
					Position = UDim2.new(1, -116, 0, 15),
					Parent = row,
				})
				Kit.setEnabled(b10, balance >= cost * 10)
			end
		end
		for _, chestId in ChestConfig.ShopOrder do
			local chest = ChestConfig.Chests[chestId]
			if not chest.EventId or table.find(derived.ActiveEvents, chest.EventId) then
				chestRow(chestId, nil)
			end
		end
		order += 1
		Kit.header("Your chests", { LayoutOrder = order, Parent = scroll })
		local any = false
		for chestId, count in profile.Inventory.Chests do
			if count > 0 then
				any = true
				chestRow(chestId, count)
			end
		end
		if not any then
			order += 1
			Kit.text({
				Text = "Win battles and defeat bosses to earn Region and Boss chests.",
				TextColor3 = C.Muted,
				Size = UDim2.new(1, -8, 0, 30),
				LayoutOrder = order,
				Parent = scroll,
			})
		end
	end
	renderers.Chests = render
	render()
end

function ShopController.init()
	UIController.registerPanel({
		Id = "Fusion",
		Title = "Fusion Lab",
		Glyph = "🧬",
		Wide = true,
		Build = buildFusion,
		OnOpen = function(args)
			if typeof(args) == "table" then
				fusionTarget = args.TargetId
				if args.Tab then
					fusionTab = args.Tab
				end
			else
				fusionTarget = nil
			end
			if renderers.Fusion then
				renderers.Fusion()
			end
		end,
	})
	UIController.registerPanel({
		Id = "Crafting",
		Title = "Crafting Workshop",
		Glyph = "🔧",
		Wide = true,
		Build = buildCrafting,
		OnOpen = function()
			if renderers.Crafting then
				renderers.Crafting()
			end
		end,
	})
	UIController.registerPanel({
		Id = "Chests",
		Title = "Chest Vault",
		Glyph = "🎁",
		Build = buildChests,
		OnOpen = function(args)
			if renderers.Chests then
				renderers.Chests()
			end
			if typeof(args) == "table" and args.OpenOwned then
				local r = UIController.call("OpenChest", args.OpenOwned, 1, true)
				if r.ok then
					showChestRewards(r.data.Rewards)
				end
			end
		end,
	})
end

function ShopController.start()
	StateController.Changed:Connect(function(key)
		local open = UIController.openId()
		if not open or not renderers[open] then
			return
		end
		if
			key == "Monsters"
			or key == "Inventory"
			or key == "Crafting"
			or key == "Progression"
			or key == "*"
		then
			renderers[open]()
		end
	end)
	-- crafting timers
	while true do
		task.wait(1)
		if UIController.openId() == "Crafting" and renderers.CraftingQueue then
			renderers.CraftingQueue()
		end
	end
end

return ShopController
