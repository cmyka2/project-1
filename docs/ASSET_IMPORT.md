# Importing your assets

The game runs completely on generated placeholders: colored blob creatures for monsters and
enemies, block figures for NPCs, glyphs for icons, silence for sounds. Replacing any of them
needs **no code changes**. You name the asset by its key and put it in the right folder. Keys for
every asset are listed in [ASSET_CHECKLIST.md](ASSET_CHECKLIST.md), which is generated from the
config.

> **Never rename a `MonsterId`** (`moss_golem`, `sprout_bunny`, ...). It is the permanent id
> stored in player saves. The *ModelKey* and *DisplayName* can change freely.

## Where things go

| Asset | Location | Named by |
|---|---|---|
| Monster models | `ReplicatedStorage/Assets/MonsterModels` | `ModelKey` (e.g. `MossGolem`) |
| Enemy and boss models | `ReplicatedStorage/Assets/EnemyModels` (falls back to MonsterModels) | enemy `ModelKey` (e.g. `ThornBoar`) |
| NPC models (shopkeepers) | `ReplicatedStorage/Assets/NPCModels` | NPC key (e.g. `DiceMerchant`) |
| Icons | `AssetConfig.Icons[IconKey] = "rbxassetid://…"` | `IconKey` |
| Sounds | `AssetConfig.Sounds[SoundKey] = "rbxassetid://…"` | `SoundKey` |
| Animations | `AssetConfig.Animations["<ModelKey>_Idle"] = "rbxassetid://…"` | `<ModelKey>_Idle` |

`AssetConfig.MonsterModelFolders` / `EnemyModelFolders` list the folders searched, in order. A
model in `ServerStorage/MonsterModels` is found by the server only (base displays) and not by the
client (codex/inventory previews), so prefer `ReplicatedStorage/Assets`.

## Importing a monster model, step by step

1. **Import** the model into Studio (Avatar Importer, the 3D Importer, or a Toolbox package).
2. **Group** it into a single `Model`. Rename the Model to the monster's `ModelKey` exactly
   (case-sensitive), e.g. `MossGolem`. Look it up in [ASSET_CHECKLIST.md](ASSET_CHECKLIST.md).
3. **Pivot:** set `PrimaryPart` (or the pivot) to the model's root, ideally a `HumanoidRootPart`
   for rigs. The game stands the model's **bounding-box bottom** on the ground, so the pivot only
   matters for rotation.
4. **Facing:** the model should face **−Z** (Studio's front). If it doesn't, add a rotation
   override (below) instead of editing the model.
5. **Size doesn't matter.** Models are scaled automatically with `Model:ScaleTo` to a fixed
   height: `GameConfig.Plots.MonsterDisplayHeight` (7 studs) on bases, 6 studs in UI previews.
6. **Drop it** into `ReplicatedStorage/Assets/MonsterModels`. With Rojo you can simply add it in
   Studio. Every asset folder is marked `$ignoreUnknownInstances` in `default.project.json`, so a
   Rojo sync never deletes models you added by hand. To keep models in git, save them as `.rbxm`
   files and map them into the folder in `default.project.json`. **Save the place file either
   way**, because models added in Studio live only in the place.
7. **Play.** The base display, codex and inventory previews now use your model. If a key is still
   missing, the output shows one warning per key: `[Assets] Monster model 'X' not found … - using
   a placeholder`.

What the game does to a model it displays (`AssetRegistry.fitModel`):

- scales it to the target height, applies any override, and places it on the slot;
- turns off `CanCollide` on every part, so displays never block players;
- **static models** (no `Motor6D`) are fully anchored;
- **rigged models** (with `Motor6D` joints) only anchor the root (`PrimaryPart`, or
  `HumanoidRootPart`). Every part joined to the root through Motor6Ds or welds stays unanchored,
  because Roblox doesn't animate anchored limbs. Parts that aren't connected are anchored so they
  can't fall.

### Per-model tweaks (`src/shared/Config/AssetConfig.luau`)

```lua
ModelOverrides = {
    MossGolem = { Scale = 1.15, YOffset = -0.2, Rotation = 180 },
},
```

- `Scale`: extra multiplier on top of automatic height fitting (big bosses can be 1.3+).
- `YOffset`: studs to raise or lower after ground alignment (e.g. for floating creatures).
- `Rotation`: degrees around Y if the model doesn't face −Z.

## Animations

Each monster has `AnimationKeys` (`<ModelKey>_Idle`, `_Attack`, `_Cast`, `_Hit`, `_Ultimate`).
**Currently only `_Idle` is played**, looping on base displays, through the model's `Humanoid` or
`AnimationController` (an `Animator` is created if missing). The battle screen is 2D and uses card
effects, so the other keys are reserved for a future 3D battle view. A rig needs a `Humanoid` or
an `AnimationController`, plus Motor6D joints, for its animation to play.

```lua
Animations = {
    MossGolem_Idle = "rbxassetid://1234567890",
},
```

Animations must be owned by the experience's owner (user or group) or Roblox will refuse to load
them in the published game.

## Enemies and bosses

Same steps, using the enemy's `ModelKey` and `ReplicatedStorage/Assets/EnemyModels`. If an enemy
has no model of its own but a monster model with the same key exists, that one is used. Boss
models also appear as statues at the region gates (`WorldBuilder`).

## NPCs

Put a Model named after the NPC key (`DiceMerchant`, `FusionScientist`, `Blacksmith`, `Craftsman`,
`VaultKeeper`, `StorageKeeper`, `Trader`, `SkillSage`, `RebirthPriest`, `AscensionOracle`) into
`ReplicatedStorage/Assets/NPCModels`. It replaces the placeholder at that shop's counter and is
scaled to about 6 studs.

## Icons and sounds

Upload images and sounds on the Creator Dashboard and paste the ids into `AssetConfig`:

```lua
Icons = {
    MossGolem = "rbxassetid://111",       -- monster IconKey
    WoodenClaws = "rbxassetid://222",     -- equipment IconKey
},
Sounds = {
    RollBasic = "rbxassetid://333",
    RevealLegendary = "rbxassetid://444",
    -- every key already exists in the file with "" (silent)
},
```

Without an icon, monster cards show a rarity-colored portrait with the monster's initials and
element glyph, and equipment shows its glyph. Missing sounds are simply silent.

## Replacing world districts

`WorldBuilder` skips any district whose folder already exists in `Workspace.World`. To hand-build
a district, create `Workspace.World.<DistrictName>` with your build. Read the district names from
a running server's `Workspace.World`. Keep the ProximityPrompts' `Action` attributes if you want
the same interactions (see `InteractionController`).

## Asset checklist before launch

- [ ] Models for all monsters, enemies and bosses in [ASSET_CHECKLIST.md](ASSET_CHECKLIST.md)
- [ ] Idle animations for monster rigs (owned by the experience owner)
- [ ] Icons for monsters and equipment
- [ ] Every `SoundKey` filled in
- [ ] NPC models
- [ ] Run Play in Studio and confirm the output has **no** `[Assets] … using a placeholder`
      warnings (or only the ones you accept)
- [ ] Re-run `lune run tests/run tests/tools/AssetChecklist.luau` after adding monsters or items

## Placeholder-only assets

These are always procedural and need no import: dice visuals, roll reveal effects, plots, slot
pads, floors, the island, shops, region islands and battle UI.
