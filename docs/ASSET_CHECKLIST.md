# Asset import checklist

Generated from the config by `tests/tools/AssetChecklist.luau`. Regenerate after adding content:

```
lune run tests/run tests/tools/AssetChecklist.luau
```

Everything below already works with generated placeholders. Importing an asset is a
matter of naming it exactly as listed and dropping it in the listed folder; see
[ASSET_IMPORT.md](ASSET_IMPORT.md) for the step-by-step guide. Keys are case-sensitive.

Totals: 72 monsters, 36 enemies (9 bosses), 29 equipment icons, 10 NPCs, 41 sound keys.

## 1. Monster models

Folder: `ReplicatedStorage/Assets/MonsterModels` (Model named by **ModelKey**).
Icons go in `AssetConfig.Icons[IconKey]`; animations in `AssetConfig.Animations["<ModelKey>_Idle"]` etc.
The **MonsterId** is the permanent save-data id: never rename it.

| ✓ | MonsterId | Name | Rarity | Region | Element | ModelKey | IconKey | Notes |
|---|---|---|---|---|---|---|---|---|
| ☐ | `sprout_bunny` | Sprout Bunny | Common | Grassland | Nature | `SproutBunny` | `SproutBunny` | evolves → bloom_hare |
| ☐ | `pebble_pup` | Pebble Pup | Common | Grassland | Earth | `PebblePup` | `PebblePup` |  |
| ☐ | `puddle_slime` | Puddle Slime | Uncommon | Grassland | Water | `PuddleSlime` | `PuddleSlime` |  |
| ☐ | `breeze_finch` | Breeze Finch | Uncommon | Grassland | Wind | `BreezeFinch` | `BreezeFinch` |  |
| ☐ | `meadow_ram` | Meadow Ram | Rare | Grassland | Earth | `MeadowRam` | `MeadowRam` |  |
| ☐ | `sunpetal_fox` | Sunpetal Fox | Epic | Grassland | Light | `SunpetalFox` | `SunpetalFox` |  |
| ☐ | `clover_king` | Clover King | Legendary | Grassland | Nature | `CloverKing` | `CloverKing` |  |
| ☐ | `bloom_hare` | Bloom Hare | Uncommon | Grassland | Nature | `BloomHare` | `BloomHare` | evolution only |
| ☐ | `acorn_imp` | Acorn Imp | Common | Whispering Forest | Nature | `AcornImp` | `AcornImp` |  |
| ☐ | `glow_moth` | Glow Moth | Uncommon | Whispering Forest | Light | `GlowMoth` | `GlowMoth` |  |
| ☐ | `thornback_boar` | Thornback Boar | Uncommon | Whispering Forest | Earth | `ThornbackBoar` | `ThornbackBoar` |  |
| ☐ | `moss_golem` | Moss Golem | Rare | Whispering Forest | Nature | `MossGolem` | `MossGolem` | evolves → ancient_moss_colossus |
| ☐ | `spore_shaman` | Spore Shaman | Epic | Whispering Forest | Nature | `SporeShaman` | `SporeShaman` |  |
| ☐ | `elder_treant` | Elder Treant | Legendary | Whispering Forest | Nature | `ElderTreant` | `ElderTreant` |  |
| ☐ | `verdant_wyrm` | Verdant Wyrm | Mythic | Whispering Forest | Nature | `VerdantWyrm` | `VerdantWyrm` |  |
| ☐ | `ancient_moss_colossus` | Ancient Moss Colossus | Epic | Whispering Forest | Nature | `AncientMossColossus` | `AncientMossColossus` | evolution only |
| ☐ | `sand_skink` | Sand Skink | Common | Sunscorch Desert | Earth | `SandSkink` | `SandSkink` |  |
| ☐ | `dune_scorpion` | Dune Scorpion | Uncommon | Sunscorch Desert | Earth | `DuneScorpion` | `DuneScorpion` | evolves → emperor_scorpion |
| ☐ | `cactus_brute` | Cactus Brute | Rare | Sunscorch Desert | Nature | `CactusBrute` | `CactusBrute` |  |
| ☐ | `mirage_jackal` | Mirage Jackal | Epic | Sunscorch Desert | Wind | `MirageJackal` | `MirageJackal` |  |
| ☐ | `sunscale_basilisk` | Sunscale Basilisk | Legendary | Sunscorch Desert | Fire | `SunscaleBasilisk` | `SunscaleBasilisk` |  |
| ☐ | `pharaoh_sphinx` | Pharaoh Sphinx | Mythic | Sunscorch Desert | Light | `PharaohSphinx` | `PharaohSphinx` |  |
| ☐ | `emperor_scorpion` | Emperor Scorpion | Rare | Sunscorch Desert | Earth | `EmperorScorpion` | `EmperorScorpion` | evolution only |
| ☐ | `frost_marmot` | Frost Marmot | Uncommon | Frostpeak Mountains | Water | `FrostMarmot` | `FrostMarmot` |  |
| ☐ | `crag_goat` | Crag Goat | Uncommon | Frostpeak Mountains | Earth | `CragGoat` | `CragGoat` |  |
| ☐ | `yeti_cub` | Yeti Cub | Rare | Frostpeak Mountains | Water | `YetiCub` | `YetiCub` | evolves → yeti_monarch |
| ☐ | `storm_eagle` | Storm Eagle | Epic | Frostpeak Mountains | Wind | `StormEagle` | `StormEagle` |  |
| ☐ | `glacier_titan` | Glacier Titan | Legendary | Frostpeak Mountains | Water | `GlacierTitan` | `GlacierTitan` |  |
| ☐ | `thunder_roc` | Thunder Roc | Mythic | Frostpeak Mountains | Wind | `ThunderRoc` | `ThunderRoc` |  |
| ☐ | `avalanche_colossus` | Avalanche Colossus | Divine | Frostpeak Mountains | Earth | `AvalancheColossus` | `AvalancheColossus` |  |
| ☐ | `yeti_monarch` | Yeti Monarch | Epic | Frostpeak Mountains | Water | `YetiMonarch` | `YetiMonarch` | evolution only |
| ☐ | `magma_slug` | Magma Slug | Rare | Cinder Volcano | Fire | `MagmaSlug` | `MagmaSlug` | evolves → magma_leviathan |
| ☐ | `cinder_hound` | Cinder Hound | Rare | Cinder Volcano | Fire | `CinderHound` | `CinderHound` |  |
| ☐ | `obsidian_golem` | Obsidian Golem | Epic | Cinder Volcano | Earth | `ObsidianGolem` | `ObsidianGolem` |  |
| ☐ | `lava_drake` | Lava Drake | Legendary | Cinder Volcano | Fire | `LavaDrake` | `LavaDrake` |  |
| ☐ | `phoenix_hatchling` | Phoenix Hatchling | Mythic | Cinder Volcano | Fire | `PhoenixHatchling` | `PhoenixHatchling` | evolves → eternal_phoenix |
| ☐ | `inferno_behemoth` | Inferno Behemoth | Divine | Cinder Volcano | Fire | `InfernoBehemoth` | `InfernoBehemoth` |  |
| ☐ | `magma_leviathan` | Magma Leviathan | Epic | Cinder Volcano | Fire | `MagmaLeviathan` | `MagmaLeviathan` | evolution only |
| ☐ | `eternal_phoenix` | Eternal Phoenix | Divine | Cinder Volcano | Fire | `EternalPhoenix` | `EternalPhoenix` | evolution only |
| ☐ | `crystal_bat` | Crystal Bat | Rare | Crystal Caverns | Dark | `CrystalBat` | `CrystalBat` | evolves → crystal_vampire |
| ☐ | `geode_crab` | Geode Crab | Rare | Crystal Caverns | Earth | `GeodeCrab` | `GeodeCrab` |  |
| ☐ | `gloom_spider` | Gloom Spider | Epic | Crystal Caverns | Dark | `GloomSpider` | `GloomSpider` |  |
| ☐ | `amethyst_serpent` | Amethyst Serpent | Legendary | Crystal Caverns | Earth | `AmethystSerpent` | `AmethystSerpent` |  |
| ☐ | `shadow_lurker` | Shadow Lurker | Mythic | Crystal Caverns | Dark | `ShadowLurker` | `ShadowLurker` |  |
| ☐ | `prism_dragon` | Prism Dragon | Divine | Crystal Caverns | Light | `PrismDragon` | `PrismDragon` |  |
| ☐ | `void_crystal_wyrm` | Void Crystal Wyrm | Celestial | Crystal Caverns | Dark | `VoidCrystalWyrm` | `VoidCrystalWyrm` |  |
| ☐ | `crystal_vampire` | Crystal Vampire | Epic | Crystal Caverns | Dark | `CrystalVampire` | `CrystalVampire` | evolution only |
| ☐ | `cloud_lamb` | Cloud Lamb | Epic | Skyward Heaven | Light | `CloudLamb` | `CloudLamb` |  |
| ☐ | `halo_sprite` | Halo Sprite | Epic | Skyward Heaven | Light | `HaloSprite` | `HaloSprite` |  |
| ☐ | `seraph_lion` | Seraph Lion | Legendary | Skyward Heaven | Light | `SeraphLion` | `SeraphLion` |  |
| ☐ | `aurora_pegasus` | Aurora Pegasus | Mythic | Skyward Heaven | Wind | `AuroraPegasus` | `AuroraPegasus` |  |
| ☐ | `archangel_guardian` | Archangel Guardian | Divine | Skyward Heaven | Light | `ArchangelGuardian` | `ArchangelGuardian` |  |
| ☐ | `celestial_kirin` | Celestial Kirin | Celestial | Skyward Heaven | Light | `CelestialKirin` | `CelestialKirin` |  |
| ☐ | `comet_pup` | Comet Pup | Epic | Cosmic Rift | Cosmic | `CometPup` | `CometPup` | evolves → meteor_wolf |
| ☐ | `nebula_jelly` | Nebula Jelly | Legendary | Cosmic Rift | Cosmic | `NebulaJelly` | `NebulaJelly` |  |
| ☐ | `star_golem` | Star Golem | Mythic | Cosmic Rift | Cosmic | `StarGolem` | `StarGolem` |  |
| ☐ | `void_leviathan` | Void Leviathan | Divine | Cosmic Rift | Dark | `VoidLeviathan` | `VoidLeviathan` |  |
| ☐ | `galaxy_serpent` | Galaxy Serpent | Celestial | Cosmic Rift | Cosmic | `GalaxySerpent` | `GalaxySerpent` |  |
| ☐ | `supernova_titan` | Supernova Titan | Cosmic | Cosmic Rift | Cosmic | `SupernovaTitan` | `SupernovaTitan` |  |
| ☐ | `meteor_wolf` | Meteor Wolf | Legendary | Cosmic Rift | Cosmic | `MeteorWolf` | `MeteorWolf` | evolution only |
| ☐ | `pixel_slime` | Pixel Slime | Legendary | The Glitch | Glitch | `PixelSlime` | `PixelSlime` |  |
| ☐ | `error_hound` | Error Hound | Mythic | The Glitch | Glitch | `ErrorHound` | `ErrorHound` |  |
| ☐ | `null_knight` | Null Knight | Divine | The Glitch | Glitch | `NullKnight` | `NullKnight` |  |
| ☐ | `corrupted_seraph` | Corrupted Seraph | Celestial | The Glitch | Glitch | `CorruptedSeraph` | `CorruptedSeraph` |  |
| ☐ | `syntax_dragon` | Syntax Dragon | Cosmic | The Glitch | Glitch | `SyntaxDragon` | `SyntaxDragon` |  |
| ☐ | `overlord_404` | 404 Overlord | Glitched | The Glitch | Glitch | `Overlord404` | `Overlord404` |  |
| ☐ | `chimera_of_seasons` | Chimera of Seasons | Mythic | Whispering Forest | Nature | `ChimeraOfSeasons` | `ChimeraOfSeasons` | special fusion only |
| ☐ | `tempest_hydra` | Tempest Hydra | Divine | Frostpeak Mountains | Water | `TempestHydra` | `TempestHydra` | special fusion only |
| ☐ | `eclipse_dragon` | Eclipse Dragon | Celestial | Crystal Caverns | Dark | `EclipseDragon` | `EclipseDragon` | special fusion only |
| ☐ | `pumpkin_imp` | Pumpkin Imp | Rare | Whispering Forest | Fire | `PumpkinImp` | `PumpkinImp` | event: halloween_2026 |
| ☐ | `wraith_cat` | Wraith Cat | Legendary | Whispering Forest | Dark | `WraithCat` | `WraithCat` | event: halloween_2026 |
| ☐ | `lantern_king` | Hollow Lantern King | Mythic | Whispering Forest | Dark | `LanternKing` | `LanternKing` | event: halloween_2026 |

## 2. Enemy and boss models

Folder: `ReplicatedStorage/Assets/EnemyModels` (falls back to MonsterModels with the same key).

| ✓ | EnemyId | Name | Region | Element | Boss | ModelKey |
|---|---|---|---|---|---|---|
| ☐ | `mud_toad` | Mud Toad | Grassland | Water |  | `MudToad` |
| ☐ | `thistle_wasp` | Thistle Wasp | Grassland | Wind |  | `ThistleWasp` |
| ☐ | `wild_hopper` | Wild Hopper | Grassland | Nature |  | `WildHopper` |
| ☐ | `bramble_king_boar` | Bramble King Boar | Grassland | Earth | ★ | `BrambleKingBoar` |
| ☐ | `night_owl` | Night Owl | Whispering Forest | Dark |  | `NightOwl` |
| ☐ | `rotwood_stump` | Rotwood Stump | Whispering Forest | Nature |  | `RotwoodStump` |
| ☐ | `venom_shroom` | Venom Shroom | Whispering Forest | Nature |  | `VenomShroom` |
| ☐ | `hollow_treant` | Hollow Treant | Whispering Forest | Nature | ★ | `HollowTreant` |
| ☐ | `dust_devil` | Dust Devil | Sunscorch Desert | Wind |  | `DustDevil` |
| ☐ | `sand_raider` | Sand Raider | Sunscorch Desert | Earth |  | `SandRaider` |
| ☐ | `scarab_swarm` | Scarab Swarm | Sunscorch Desert | Earth |  | `ScarabSwarm` |
| ☐ | `sand_wyrm_queen` | Sand Wyrm Queen | Sunscorch Desert | Earth | ★ | `SandWyrmQueen` |
| ☐ | `harpy` | Harpy | Frostpeak Mountains | Wind |  | `Harpy` |
| ☐ | `ice_imp` | Ice Imp | Frostpeak Mountains | Water |  | `IceImp` |
| ☐ | `rock_troll` | Rock Troll | Frostpeak Mountains | Earth |  | `RockTroll` |
| ☐ | `frost_giant_jarl` | Frost Giant Jarl | Frostpeak Mountains | Water | ★ | `FrostGiantJarl` |
| ☐ | `ash_sprite` | Ash Sprite | Cinder Volcano | Fire |  | `AshSprite` |
| ☐ | `fire_salamander` | Fire Salamander | Cinder Volcano | Fire |  | `FireSalamander` |
| ☐ | `lava_golem` | Lava Golem | Cinder Volcano | Fire |  | `LavaGolem` |
| ☐ | `magma_tyrant` | Magma Tyrant | Cinder Volcano | Fire | ★ | `MagmaTyrant` |
| ☐ | `cave_ghoul` | Cave Ghoul | Crystal Caverns | Dark |  | `CaveGhoul` |
| ☐ | `crystal_mite` | Crystal Mite | Crystal Caverns | Earth |  | `CrystalMite` |
| ☐ | `echo_wraith` | Echo Wraith | Crystal Caverns | Dark |  | `EchoWraith` |
| ☐ | `gemheart_hydra` | Gemheart Hydra | Crystal Caverns | Dark | ★ | `GemheartHydra` |
| ☐ | `fallen_cherub` | Fallen Cherub | Skyward Heaven | Light |  | `FallenCherub` |
| ☐ | `halo_sentinel` | Halo Sentinel | Skyward Heaven | Light |  | `HaloSentinel` |
| ☐ | `storm_valkyrie` | Storm Valkyrie | Skyward Heaven | Wind |  | `StormValkyrie` |
| ☐ | `seraphim_judge` | Seraphim Judge | Skyward Heaven | Light | ★ | `SeraphimJudge` |
| ☐ | `meteor_brute` | Meteor Brute | Cosmic Rift | Cosmic |  | `MeteorBrute` |
| ☐ | `star_wisp` | Star Wisp | Cosmic Rift | Cosmic |  | `StarWisp` |
| ☐ | `void_drifter` | Void Drifter | Cosmic Rift | Dark |  | `VoidDrifter` |
| ☐ | `black_hole_devourer` | Black Hole Devourer | Cosmic Rift | Cosmic | ★ | `BlackHoleDevourer` |
| ☐ | `corrupted_sprite` | Corrupted Sprite | The Glitch | Glitch |  | `CorruptedSprite` |
| ☐ | `firewall_golem` | Firewall Golem | The Glitch | Glitch |  | `FirewallGolem` |
| ☐ | `lag_spike` | Lag Spike | The Glitch | Glitch |  | `LagSpike` |
| ☐ | `kernel_panic` | The Kernel Panic | The Glitch | Glitch | ★ | `KernelPanic` |

## 3. Equipment icons

`AssetConfig.Icons[IconKey] = "rbxassetid://..."`. Without one, the item's glyph is shown.

| ✓ | ItemId | Name | Category | Rarity | IconKey |
|---|---|---|---|---|---|
| ☐ | `swift_feather` | Swift Feather | Accessory | Uncommon | `SwiftFeather` |
| ☐ | `lucky_clover_pin` | Lucky Clover Pin | Accessory | Rare | `LuckyCloverPin` |
| ☐ | `crit_monocle` | Critical Monocle | Accessory | Epic | `CritMonocle` |
| ☐ | `healing_charm` | Healing Charm | Accessory | Epic | `HealingCharm` |
| ☐ | `ember_ring` | Ember Ring | Accessory | Legendary | `EmberRing` |
| ☐ | `elemental_amulet` | Elemental Amulet | Accessory | Legendary | `ElementalAmulet` |
| ☐ | `leaf_vest` | Leaf Vest | Armor | Common | `LeafVest` |
| ☐ | `bark_plate` | Bark Plate | Armor | Uncommon | `BarkPlate` |
| ☐ | `sandstone_mail` | Sandstone Mail | Armor | Rare | `SandstoneMail` |
| ☐ | `glacier_plate` | Glacier Plate | Armor | Epic | `GlacierPlate` |
| ☐ | `obsidian_aegis` | Obsidian Aegis | Armor | Legendary | `ObsidianAegis` |
| ☐ | `crystal_carapace` | Crystal Carapace | Armor | Mythic | `CrystalCarapace` |
| ☐ | `halo_armor` | Halo Armor | Armor | Divine | `HaloArmor` |
| ☐ | `nebula_shroud` | Nebula Shroud | Armor | Celestial | `NebulaShroud` |
| ☐ | `firewall_armor` | Firewall Armor | Armor | Cosmic | `FirewallArmor` |
| ☐ | `golden_idol` | Golden Idol | Relic | Rare | `GoldenIdol` |
| ☐ | `four_leaf_relic` | Four-Leaf Relic | Relic | Epic | `FourLeafRelic` |
| ☐ | `midas_crown` | Midas Crown | Relic | Legendary | `MidasCrown` |
| ☐ | `fortune_orb` | Fortune Orb | Relic | Mythic | `FortuneOrb` |
| ☐ | `cosmic_hourglass` | Cosmic Hourglass | Relic | Divine | `CosmicHourglass` |
| ☐ | `wooden_claws` | Wooden Claws | Weapon | Common | `WoodenClaws` |
| ☐ | `forest_fang` | Forest Fang | Weapon | Uncommon | `ForestFang` |
| ☐ | `sunsteel_blade` | Sunsteel Blade | Weapon | Rare | `SunsteelBlade` |
| ☐ | `frostbite_edge` | Frostbite Edge | Weapon | Epic | `FrostbiteEdge` |
| ☐ | `magma_maul` | Magma Maul | Weapon | Legendary | `MagmaMaul` |
| ☐ | `void_scythe` | Void Scythe | Weapon | Mythic | `VoidScythe` |
| ☐ | `seraph_lance` | Seraph Lance | Weapon | Divine | `SeraphLance` |
| ☐ | `starforged_glaive` | Starforged Glaive | Weapon | Celestial | `StarforgedGlaive` |
| ☐ | `null_pointer` | Null Pointer | Weapon | Cosmic | `NullPointer` |

## 4. NPC models

Folder: `ReplicatedStorage/Assets/NPCModels` (Model named by key). Fitted to ~6 studs tall at the shop counter.

| ✓ | Key | Where |
|---|---|---|
| ☐ | `DiceMerchant` | Dice Shop (hub) |
| ☐ | `FusionScientist` | Fusion Lab (hub) |
| ☐ | `Blacksmith` | Equipment Forge (hub) |
| ☐ | `Craftsman` | Crafting Workshop (hub) |
| ☐ | `VaultKeeper` | Chest Vault (hub) |
| ☐ | `StorageKeeper` | Monster Storage (hub) |
| ☐ | `Trader` | Trading Post (east avenue) |
| ☐ | `SkillSage` | Skill Shrine (west district) |
| ☐ | `RebirthPriest` | Rebirth Temple (west district) |
| ☐ | `AscensionOracle` | Ascension Altar (west district) |

## 5. Sounds

`AssetConfig.Sounds[SoundKey] = "rbxassetid://..."`. Empty keys are silent.

| ✓ | SoundKey |
|---|---|
| ☐ | `Achievement` |
| ☐ | `BossUltimate` |
| ☐ | `Buff` |
| ☐ | `ChestOpen` |
| ☐ | `Coins` |
| ☐ | `Cosmic` |
| ☐ | `Critical` |
| ☐ | `Dark` |
| ☐ | `Defeat` |
| ☐ | `Fire` |
| ☐ | `Fusion` |
| ☐ | `Glitch` |
| ☐ | `Heal` |
| ☐ | `HitBasic` |
| ☐ | `HitHeavy` |
| ☐ | `Ice` |
| ☐ | `Light` |
| ☐ | `Music` |
| ☐ | `Nature` |
| ☐ | `Place` |
| ☐ | `Purchase` |
| ☐ | `Rebirth` |
| ☐ | `RegionTravel` |
| ☐ | `RevealCommon` |
| ☐ | `RevealLegendary` |
| ☐ | `RevealMythic` |
| ☐ | `RevealRare` |
| ☐ | `Roar` |
| ☐ | `RollAdvanced` |
| ☐ | `RollBasic` |
| ☐ | `RollCosmic` |
| ☐ | `RollGlitch` |
| ☐ | `Shield` |
| ☐ | `UIClick` |
| ☐ | `UIError` |
| ☐ | `UIOpen` |
| ☐ | `Ultimate` |
| ☐ | `Upgrade` |
| ☐ | `Victory` |
| ☐ | `Water` |
| ☐ | `Wind` |
