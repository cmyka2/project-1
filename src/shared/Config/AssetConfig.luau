--!strict
-- Asset registry. Gameplay never references assets directly; it asks the
-- AssetRegistry for a ModelKey/IconKey/SoundKey and falls back to a generated
-- placeholder when the asset is not registered or missing.
--
-- To connect an imported model: put a Model named exactly like the monster's
-- ModelKey (see MonsterConfig, e.g. "MossGolem") into
-- ReplicatedStorage/Assets/MonsterModels. No code changes are needed.
-- Optional per-model tweaks go in ModelOverrides below.

export type ModelOverride = {
	Scale: number?, -- extra multiplier on top of automatic height fitting
	YOffset: number?, -- studs, after ground alignment
	Rotation: number?, -- degrees around Y so the model faces forward
}

local AssetConfig = {
	-- Folders searched (in order) for monster/enemy models.
	MonsterModelFolders = {
		"ReplicatedStorage/Assets/MonsterModels",
		"ServerStorage/MonsterModels",
	},
	EnemyModelFolders = {
		"ReplicatedStorage/Assets/EnemyModels",
		"ServerStorage/EnemyModels",
		"ReplicatedStorage/Assets/MonsterModels",
	},

	ModelOverrides = {
		-- MossGolem = { Scale = 1.1, YOffset = 0, Rotation = 180 },
	} :: { [string]: ModelOverride },

	-- Animation asset ids by AnimationKey ("rbxassetid://123"). Missing keys simply
	-- do not play. AnimationKeys are "<ModelKey>_Idle", "_Attack", "_Cast", "_Hit", "_Ultimate".
	Animations = {} :: { [string]: string },

	-- Image ids by IconKey (MonsterDef.IconKey / EquipmentDef.IconKey / UI icons).
	-- Missing keys fall back to the glyph/initials placeholder.
	Icons = {} :: { [string]: string },

	-- Sound ids by SoundKey. Missing keys are silent (a debug warning is logged once).
	Sounds = {
		UIClick = "",
		UIOpen = "",
		UIError = "",
		Purchase = "",
		RollBasic = "",
		RollAdvanced = "",
		RollCosmic = "",
		RollGlitch = "",
		RevealCommon = "",
		RevealRare = "",
		RevealLegendary = "",
		RevealMythic = "",
		Place = "",
		Upgrade = "",
		Fusion = "",
		ChestOpen = "",
		HitBasic = "",
		HitHeavy = "",
		Critical = "",
		Heal = "",
		Shield = "",
		Buff = "",
		Ultimate = "",
		BossUltimate = "",
		Roar = "",
		Victory = "",
		Defeat = "",
		RegionTravel = "",
		Rebirth = "",
		Achievement = "",
		Coins = "",
		Nature = "",
		Fire = "",
		Water = "",
		Ice = "",
		Wind = "",
		Light = "",
		Dark = "",
		Cosmic = "",
		Glitch = "",
		Music = "",
	} :: { [string]: string },
}

return table.freeze(AssetConfig)
