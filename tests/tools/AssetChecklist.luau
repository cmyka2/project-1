-- Writes docs/ASSET_CHECKLIST.md: every asset key the game asks the
-- AssetRegistry for, generated from the config so it never goes stale.
--   lune run tests/run tests/tools/AssetChecklist.luau
return function(ctx)
	local Loader = ctx.Loader
	local fs = require("@lune/fs")
	local MonsterConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.MonsterConfig")
	local EnemyConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.EnemyConfig")
	local EquipmentConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.EquipmentConfig")
	local RegionConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.RegionConfig")
	local RarityConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.RarityConfig")
	local AssetConfig = Loader.requirePath("ReplicatedStorage.Shared.Config.AssetConfig")

	-- NPC keys used by Server/Modules/WorldBuilder (shopkeepers and station hosts).
	local NPC_KEYS = {
		{ "DiceMerchant", "Dice Shop (hub)" },
		{ "FusionScientist", "Fusion Lab (hub)" },
		{ "Blacksmith", "Equipment Forge (hub)" },
		{ "Craftsman", "Crafting Workshop (hub)" },
		{ "VaultKeeper", "Chest Vault (hub)" },
		{ "StorageKeeper", "Monster Storage (hub)" },
		{ "Trader", "Trading Post (east avenue)" },
		{ "SkillSage", "Skill Shrine (west district)" },
		{ "RebirthPriest", "Rebirth Temple (west district)" },
		{ "AscensionOracle", "Ascension Altar (west district)" },
	}

	local lines = {}
	local function w(s)
		table.insert(lines, s or "")
	end
	local function check()
		return "☐"
	end

	local monsterCount = #MonsterConfig.Order
	local enemyIds = {}
	for id in EnemyConfig.Enemies do
		table.insert(enemyIds, id)
	end
	table.sort(enemyIds, function(a, b)
		local ea, eb = EnemyConfig.Enemies[a], EnemyConfig.Enemies[b]
		local ra, rb = RegionConfig.indexOf(ea.Region), RegionConfig.indexOf(eb.Region)
		if ra ~= rb then
			return ra < rb
		end
		if ea.IsBoss ~= eb.IsBoss then
			return not ea.IsBoss
		end
		return a < b
	end)

	w("# Asset import checklist")
	w()
	w("Generated from the config by `tests/tools/AssetChecklist.luau`. Regenerate after adding content:")
	w()
	w("```")
	w("lune run tests/run tests/tools/AssetChecklist.luau")
	w("```")
	w()
	w("Everything below already works with generated placeholders. Importing an asset is a")
	w("matter of naming it exactly as listed and dropping it in the listed folder; see")
	w("[ASSET_IMPORT.md](ASSET_IMPORT.md) for the step-by-step guide. Keys are case-sensitive.")
	w()
	w(
		string.format(
			"Totals: %d monsters, %d enemies (%d bosses), %d equipment icons, %d NPCs, %d sound keys.",
			monsterCount,
			#enemyIds,
			(function()
				local n = 0
				for _, id in enemyIds do
					if EnemyConfig.Enemies[id].IsBoss then
						n += 1
					end
				end
				return n
			end)(),
			(function()
				local n = 0
				for _ in EquipmentConfig.Items do
					n += 1
				end
				return n
			end)(),
			#NPC_KEYS,
			(function()
				local n = 0
				for _ in AssetConfig.Sounds do
					n += 1
				end
				return n
			end)()
		)
	)
	w()
	w("## 1. Monster models")
	w()
	w("Folder: `ReplicatedStorage/Assets/MonsterModels` (Model named by **ModelKey**).")
	w(
		'Icons go in `AssetConfig.Icons[IconKey]`; animations in `AssetConfig.Animations["<ModelKey>_Idle"]` etc.'
	)
	w("The **MonsterId** is the permanent save-data id: never rename it.")
	w()
	w("| ✓ | MonsterId | Name | Rarity | Region | Element | ModelKey | IconKey | Notes |")
	w("|---|---|---|---|---|---|---|---|---|")
	for _, id in MonsterConfig.Order do
		local def = MonsterConfig.Monsters[id]
		local region = RegionConfig.Regions[def.Region]
		local notes = {}
		if def.EvolutionOnly then
			table.insert(notes, "evolution only")
		end
		if def.FusionOnly then
			table.insert(notes, "special fusion only")
		end
		if def.EventId then
			table.insert(notes, "event: " .. def.EventId)
		end
		if def.EvolvesTo then
			table.insert(notes, "evolves → " .. def.EvolvesTo)
		end
		w(
			string.format(
				"| %s | `%s` | %s | %s | %s | %s | `%s` | `%s` | %s |",
				check(),
				id,
				def.DisplayName,
				RarityConfig.Rarities[def.Rarity].DisplayName,
				if region then region.DisplayName else def.Region,
				def.Element,
				def.ModelKey,
				def.IconKey,
				table.concat(notes, ", ")
			)
		)
	end
	w()
	w("## 2. Enemy and boss models")
	w()
	w("Folder: `ReplicatedStorage/Assets/EnemyModels` (falls back to MonsterModels with the same key).")
	w()
	w("| ✓ | EnemyId | Name | Region | Element | Boss | ModelKey |")
	w("|---|---|---|---|---|---|---|")
	for _, id in enemyIds do
		local def = EnemyConfig.Enemies[id]
		local region = RegionConfig.Regions[def.Region]
		w(
			string.format(
				"| %s | `%s` | %s | %s | %s | %s | `%s` |",
				check(),
				id,
				def.DisplayName,
				if region then region.DisplayName else def.Region,
				def.Element,
				if def.IsBoss then "★" else "",
				def.ModelKey
			)
		)
	end
	w()
	w("## 3. Equipment icons")
	w()
	w('`AssetConfig.Icons[IconKey] = "rbxassetid://..."`. Without one, the item\'s glyph is shown.')
	w()
	w("| ✓ | ItemId | Name | Category | Rarity | IconKey |")
	w("|---|---|---|---|---|---|")
	local itemIds = {}
	for id in EquipmentConfig.Items do
		table.insert(itemIds, id)
	end
	table.sort(itemIds, function(a, b)
		local ia, ib = EquipmentConfig.Items[a], EquipmentConfig.Items[b]
		if ia.Category ~= ib.Category then
			return ia.Category < ib.Category
		end
		return RarityConfig.tierOf(ia.Rarity) < RarityConfig.tierOf(ib.Rarity)
	end)
	for _, id in itemIds do
		local def = EquipmentConfig.Items[id]
		w(
			string.format(
				"| %s | `%s` | %s | %s | %s | `%s` |",
				check(),
				id,
				def.DisplayName,
				def.Category,
				def.Rarity,
				def.IconKey
			)
		)
	end
	w()
	w("## 4. NPC models")
	w()
	w(
		"Folder: `ReplicatedStorage/Assets/NPCModels` (Model named by key). Fitted to ~6 studs tall at the shop counter."
	)
	w()
	w("| ✓ | Key | Where |")
	w("|---|---|---|")
	for _, row in NPC_KEYS do
		w(string.format("| %s | `%s` | %s |", check(), row[1], row[2]))
	end
	w()
	w("## 5. Sounds")
	w()
	w('`AssetConfig.Sounds[SoundKey] = "rbxassetid://..."`. Empty keys are silent.')
	w()
	local soundKeys = {}
	for key in AssetConfig.Sounds do
		table.insert(soundKeys, key)
	end
	table.sort(soundKeys)
	w("| ✓ | SoundKey |")
	w("|---|---|")
	for _, key in soundKeys do
		w(string.format("| %s | `%s` |", if AssetConfig.Sounds[key] ~= "" then "☑" else "☐", key))
	end
	w()
	fs.writeFile(ctx.Root .. "/docs/ASSET_CHECKLIST.md", table.concat(lines, "\n"))
	print("  wrote docs/ASSET_CHECKLIST.md")
end
