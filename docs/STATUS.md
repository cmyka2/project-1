# Monster Roll: implementation status

Branch `studio-export`. Spec: [`docs/SPEC.md`](SPEC.md).

## How this was verified, and what wasn't

**Nothing in this branch has been run in Roblox Studio yet.** The cloud session that wrote it can't reach Studio.

What *has* been run, on a Luau host outside Roblox (`tools/headless`):

| Check | What it covers |
|---|---|
| `check.luau` | Every `.luau` file under `src/` compiles (syntax only, no type check). |
| `specs.luau` | The Studio specs in `ServerStorage/Tests` all pass: **RollSpec**, **BattleSpec** and **ProgressionSpec**. |
| `sim.luau` | The **real** server scripts run on a mock engine (150/150 checks pass): DataService, Game, Guard, MonsterService, ChestService, BattleService, ProgressService, LeaderboardService, MonetizationService, PlotAssigner. |
| `fallback.luau` | With an empty workspace, HubFallback builds every hub piece and a roll works. |

The specs cover:
- **RollSpec:** RNG normalization, die eligibility, extreme luck, invalid weights, exact luck multipliers, biome boosts, chest luck, gear power.
- **BattleSpec:** the damage formula, statuses, Last Stand, Mark, the healer role, boss resistance.
- **ProgressionSpec:**
  - slot/floor formula and rebirth reset
  - v1→v3 migration and old-tree refund
  - session-lock rules
  - Evolution Tree ranks, prerequisites, rebirth gates
  - Ascension costs
  - the daily cycle and event windows

The sim walks the §24 flow plus:
- ranked skill nodes, Ascension, respec
- quests, milestones, daily streak, events and boosts
- gear upgrades, relics, batch chests
- team presets and arena build/cleanup
- cosmetics and leaderboards
- Robux shop: pass ownership, receipt dedupe, server luck, region restriction, lucky/golden/triple rolls, codes, settings
- session lock, DataStore outage, migration, newer-schema refusal, stolen lock, shutdown

The mock (`tools/headless/mockrbx.luau`) is a stand-in for the engine, not the engine itself. It does **not** model replication, real DataStore/OrderedDataStore limits or throttling, MarketplaceService, physics, rendering, ProximityPrompt range, or anything on the client. **No client UI has been executed anywhere**, mock included.

### Run it

Studio (after Rojo sync), in the server command bar:

```lua
print(require(game.ServerStorage.Tests.RunAll)())
-- Studio-only QA hooks:
game.ServerStorage.DevGiveCash:Invoke(game.Players.<you>, 1e9)
game.ServerStorage.DevGiveMonster:Invoke(game.Players.<you>, "frostfang|Normal", 3)
game.ServerStorage.DevSetRebirths:Invoke(game.Players.<you>, 12)
game.ServerStorage.DevStartEvent:Invoke("weekend_income", 600)
game.ServerStorage.DevStartBiome:Invoke("starfall", 120)
game.ServerStorage.DevGrantPass:Invoke(game.Players.<you>, "lucky")       -- test passes without Roblox ids
game.ServerStorage.DevGrantProduct:Invoke(game.Players.<you>, "lucky_100") -- test products without Roblox ids
```

Saving in Studio needs a published place with *Enable Studio Access to API Services*. Without it the HUD shows "progress is NOT saved" and the leaderboards rank only that server.

Headless (Rust toolchain plus a C++ compiler, run from the repo root):

```sh
cargo build --release --manifest-path tools/headless/Cargo.toml
B=tools/headless/target/release/headless
$B tools/headless/check.luau $(find src -name '*.luau')
$B tools/headless/specs.luau
$B tools/headless/sim.luau
$B tools/headless/fallback.luau
```

## Acceptance criteria (spec §24)

Status values:
- **Implemented**: the server path passes in the mock sim.
- **Pending playtest**: needs a Studio run before it can be called tested.

Every row is pending a Studio playtest.

| # | Criterion | Status | Server evidence (mock sim) | Pending playtest |
|---|---|---|---|---|
| 1 | New player gets a valid saved profile | Implemented | Profile written with session lock; `DataStatus` goes `loading` → `ready` | Published-place DataStore |
| 2 | Assigned an available plot | Implemented | Separate plots; third player gets `PlotStatus = "full"`, then the next plot that frees up | Real `Workspace.Hub.Plots` |
| 3 | Starts with the Grassland Die | Implemented | New profile | DiceUI |
| 4 | Rolls a server-generated monster | Implemented | Prompt roll, cooldown; ROLL button only near the station | Prompt, toast, ROLL button |
| 5 | In backpack + collection | Implemented | Instance + discovery + `LastRoll` | BackpackUI, IndexUI |
| 6 | Places it in a slot | Implemented | Placement by instance id, all rejections | BaseUI on the real plot |
| 7 | Generates money | Implemented | 10 s of income matches the rate | Pad labels, HUD |
| 8–9 | Upgrades it, income rises correctly | Implemented | × `levelMult(2)` exactly | Backpack upgrade |
| 10–11 | Buys a die, equips it, rolls again | Implemented | Charges once; tiers can't be skipped | DiceUI |
| 12–13 | Buys an Evolution Tree node (cash); the bonus applies exactly once | Implemented | Coin Collector rank 1 → ×1.1, rank 2 → ×1.2 (server value and published value) | SkillTreeUI |
| 14–15 | Buys a chest, equips the gear, stats change | Implemented | Income × (1 + power); stat raised | ChestUI |
| 16 | Legal battle team | Implemented | Owned, distinct, ≤ 3; presets | Backpack / BattleUI |
| 17–18 | Turn-based battle, correct rewards once | Implemented | Win → cash + materials + progress, single payout; arena built and removed | BattleUI over the 3D arena |
| 19–21 | Rebirth requirements, permanent rewards, slot + floor | Implemented | Cash reset, everything else kept, AP, 11 slots and Floor2 at rebirth 6 | RebirthUI, floor geometry, elevator |
| 22–23 | Leave/rejoin restores everything | Implemented | Lock released; offline earnings (8 h + skill/ascension cap); all data restored after a JSON round-trip | Real join timing |
| 24 | Others can't touch your data or base | Implemented | Cross-player place/equip/sell rejected; State is per player | State replicates only to its owner |

## System map

| System (spec §) | Status | Where |
|---|---|---|
| **Persistence §5** | **Done.** <ul><li>UpdateAsync only, session lock (heartbeat, 5 min expiry), retries</li><li>Schema v3, migrations v1→v2→v3 (the old tree is refunded in cash)</li><li>Autosave, debounced saves after purchases, release on leave, BindToClose</li><li>Kick instead of defaults when loading fails</li></ul> | `server/DataService`, `server/DataSchema` |
| **Economy §5.3 / §10** | **Done.** <ul><li>`Game.addCash` / `Game.spend` are the only cash writers</li><li>One income loop</li><li>Offline earnings from server timestamps, 8 h cap, extended by Idle Earnings and Timeless Rest</li><li>Event and boost multipliers never apply offline</li></ul> | `server/Game`, `MonsterService` |
| **RNG + luck §6** | **Done.** <ul><li>Normalized weighted pool with per-die eligibility</li><li>Luck = die × boosts × (1 + skill + ascension + milestone + 2% per rebirth), diminishing past 25</li><li>Double Fortune bonus rolls; Discovery Streak cash</li><li>Server-wide announcements for Mythic+ or Monstrous rolls</li><li>Auto-roll (Auto Pickup node) and the ROLL button both go through the same server roll</li></ul> | `Weighted`, `LuckConfig`, `MonsterConfig`, `MonsterService` |
| **Monsters §6** | **Done.** <ul><li>36 monsters with role (by element), lore and element</li><li>Glitched monsters only from the Glitch die</li></ul> | `MonsterConfig` |
| **Inventory / Codex §8** | **Done.** <ul><li>Instances with ids</li><li>Search; sort by income, level, power, newest, rarity; filters by rarity, element, role; favorites first</li><li>Lock, multi-select sell, sell duplicates, last-copy confirmation</li><li>Fusion (3 copies; 2 with Quick Fusion)</li><li>The Codex keeps sold monsters; lore and role on hover</li><li>Collection milestones: 10/25/50/100 unique, plus full rarity sets with auras</li></ul> | `BackpackUI`, `IndexUI`, `ProgressService` |
| **Base, floors §9 / §3.3** | **Done.** Slots = 5 + r, floors = min(3, 1 + r // 6). Generated placeholder Floor2/Floor3 with elevators unless Studio provides them | `Formulas`, `MonsterService`, `BaseUI` |
| **Upgrades §11** | **Done.** Cost curve, discounted by Efficient Training; server-computed previews | `Formulas`, `Game` |
| **Dice §7** | **Done.** <ul><li>Buy once, equip</li><li>The shop shows each die's effective luck with your bonuses, its rarity cap and its unlock requirement</li></ul> | `DiceUI` |
| **Evolution Tree §12 (cash)** | **Done.** <ul><li>The spec's six branches, 7 nodes each, all names as listed</li><li>5 cross-branch nodes: Fortune Engine, War Beast, Explorer's Instinct, Master Collector, Divine Ascension (needs all six branches)</li><li>Multiple ranks with rising **cash** costs; multi-prerequisites; rebirth gates</li><li>Every effect is live through `Game.stat`</li><li>UI: hex branches joined by lines, locked/available/owned/maxed states, rank and price, tap to inspect then tap to buy, search, respec (75% refund, confirmed)</li></ul> | `SkillTree`, `SkillTreeUI`, `MonsterService` BuySkill |
| **Rebirth / Ascension §13** | **Done.** <ul><li>Requirement table (cost, plus boss gate from rebirth 3)</li><li>Explicit reset policy</li><li>Permanent +10% income and +2% luck per rebirth</li><li>AP (1 per rebirth, 6 on floor milestones)</li><li>**Ascension Tree:** 6 permanent nodes bought with AP; respec doesn't touch them</li></ul> | `RebirthConfig`, `SkillTreeUI` Ascension panel |
| **Chests / gear §14** | **Done.** <ul><li>Batch opens (1 or 10); chest discount and chest luck from the tree</li><li>Gear levels 1–10 (+10% power each), random secondary stat (income, crit or energy)</li><li>Relics: 4th slot, unlocked by Equipment Slots; from Divine/Cosmic chests or crafting</li></ul> | `GearConfig`, `ChestService`, `ChestUI` |
| **Crafting §14.6** | **Done.** 6 recipes, including an event-only one; materials from every region | `GearConfig.Recipes` |
| **Battle §15** | **Done.** <ul><li>Roles (stat profiles + Healer/Support/Controller/Specialist traits)</li><li>All 10 spec statuses: burn, poison, freeze, stun, weaken, expose, shield, regen + cleanse, mark</li><li>Control immunity, longer for bosses</li><li>Skill-tree combat mods: crit, elemental, energy, boss, skill/ult amp, regen, Last Stand, protect, resist, guard</li><li>Team presets; all 9 regions (27 stages) with the spec's bosses</li><li>Per-battle isolated placeholder 3D arena</li></ul> | `BattleEngine`, `BattleConfig`, `BattleService`, `BattleUI` |
| **Regions §16** | **Done.** 9 regions, unlocked by previous boss + owning that region's die; materials per region | `BattleConfig` |
| **HUD / UI §17** | **Done.** <ul><li>Cash, cash/s, region, quest tracker, events, notices, announcements</li><li>BAG, INDEX, GEAR, BATTLE and TREE buttons; DAILY, RANKS and STYLE buttons; ROLL, AUTO, DASH and TRAVEL buttons</li></ul> | client scripts |
| **Mobility nodes** | **Done.** <ul><li>Walk speed and jump power set on the server</li><li>Dash (Q or button) runs on the client; distance and cooldown come from the tree</li><li>Portal Mastery fast travel is validated on the server</li></ul> | `ActionUI`, `ProgressService` |
| **Security §18** | **Done.** Every remote goes through `Guard`: per-action cooldowns, token bucket, arg validation, ownership checks | `server/Guard` |
| **Leaderboards §19** | **Done.** OrderedDataStore top 10 for earnings, rebirths, unique monsters and battle progress; falls back to this server where unavailable | `LeaderboardService`, `ExtrasUI` |
| **Daily / quests / events §20** | **Done.** <ul><li>7-day UTC cycle (streak resets after a missed day); day 4 is a 2× luck boost</li><li>15-quest chain, 3 active, auto-completed from server counters</li><li>Events: weekend double income; Halloween 1.5× luck (2026-10-24 → 11-02) with an event recipe</li></ul> | `ProgressConfig`, `ProgressService`, `ExtrasUI` |
| **Cosmetics §3.4** | **Done.** <ul><li>Titles over the head and aura particles</li><li>Bought with cash, earned from milestones/daily/VIP, or a fixed Robux supporter aura</li></ul> | `ProgressService` |
| **Robux shop (added on request)** | **Done (needs Roblox ids).** <ul><li>Gamepasses: Lucky 2x, Super Lucky 3x, VIP, Quick Roll, Auto Roll, Triple Roll, Huge Backpack</li><li>Products: 10/100/1000 Lucky Rolls (10x luck each), Luck Potion, Server Luck</li><li>One ProcessReceipt; the receipt is saved before PurchaseGranted, so a purchase is never granted twice</li><li>Odds shown before purchase; paid luck blocked where Roblox restricts paid random items</li><li>Clover icons ready to upload</li></ul> This deliberately changes spec §3.4 ("never randomized paid rewards"); see `docs/RESEARCH.md`. | `MonetizationConfig`, `MonetizationService`, `ShopUI`, `assets/shop-icons` |
| **Genre mechanics (from research)** | **Done.** <ul><li>Golden roll every 10th, Rainbow every 100th</li><li>8 biomes boosting one element's odds, with world tint and timers</li><li>Codes</li><li>Cross-server Secret+ announcements</li><li>Premium x1.1 luck</li><li>Roll FX: spinner, flash, shake, cutscene, skip setting</li><li>Floating tags over placed monsters</li></ul> See `docs/RESEARCH.md` for what was taken from which games. | `MonsterService`, `ProgressService`, `RollFX`, `HudUI` |
| **Asset registry §4** | **Done.** Used for monsters, shops, statue, arenas, enemies, bosses and aura particles | `AssetRegistry` |
| **World §3** | **Kept.** The Studio hub is found at runtime; HubFallback adds labeled placeholders for anything missing, including DailyRewards, Leaderboard and CosmeticShop | `HubFallback` |

### Still not done (deliberately left for later)

- **Battle modes beyond story + regional bosses:** Endless Tower, Daily Challenges, Element Trials, Survival, co-op raids, PvP. The spec says to prioritize story and bosses; the engine takes any enemy list, so these are content plus a mode selector.
- **Reserve monsters / switching in battle.** The spec only asks for this "once reserves are introduced".
- **Converting duplicates into research materials.** Listed as optional ("may").
- **Robux ids.** Every `gamepass` / `product` in `MonetizationConfig`, plus `aura_supporter.product` in `ProgressConfig`, is `nil` until you create it on the Creator Dashboard. Until then the UI shows "Coming soon". Steps:
  1. Upload `assets/shop-icons/<id>.png` as each item's image.
  2. Paste the ids into the config, and paste each image id into `image` for in-game icons.
- **Pity counters.** Not added (see `docs/RESEARCH.md`).
- **Battle visuals.** Arenas and units are static placeholders; turns don't play attack animations yet.
- **Balance.** Every number is a placeholder: costs, curves, regions 3–9 stats (×2.5 per region), rewards.

## Studio playtest checklist (highest risk first)

1. **Hub names match.** Code expects:
   - `Workspace.Hub.Plots.Plot<N>`: attributes `PlotId`, `Owner = ""`, `Color`; children `Base`, `OwnerSign`, `SpawnPoint`, `Slot1..10` (attribute `SlotIndex`), `Collect1..10`.
   - `Workspace.Hub.Shops.SummonArea.SummonCore`, which has a ProximityPrompt.
   - Prompts under models named `DiceShop`, `ChestShop`, `UpgradeTree`, `RebirthAltar`, `Index`, `DailyRewards`, `Leaderboard` and `CosmeticShop`. The Robux shop opens from the 🍀 SHOP button, not a building.
   
   Missing pieces become magenta "PLACEHOLDER" stand-ins, and Output says so.
2. **Private State replication.** The server creates `PlayerGui.State` (ScreenGui, `ResetOnSpawn = false`) and every client UI waits for it. Check that it:
   - appears for its owner,
   - survives a respawn,
   - is not visible to other players.
3. **Saves in a published place.**
   - Join, roll, place, buy tree ranks, leave, rejoin.
   - Second-server lock: expect a ~30 s wait, then a kick.
   - An existing v1/v2 save migrates. Old tree nodes come back as cash, so tell testers.
4. **Evolution Tree UI.**
   - 48 hexes with lines, on a phone and on desktop.
   - Tap-tap purchase, search jump, respec confirmation, Ascension panel.
5. **Floors and elevators** at `DevSetRebirths` 6 and 12.
6. **Battle arena.**
   - You're teleported to a far-off platform; KO'd units disappear.
   - Leaving returns you to where you were.
   - The see-through battle screen is still readable.
7. **ActionUI dash** (LinearVelocity) feels right and can't push you through walls more than normal movement can.
8. **Leaderboards** populate after about 2 min in a live server.
9. **Cosmetics**: a title shows over the head; an aura emits.
10. **Robux shop.**
    - With real ids: test purchases in Studio; the receipt is granted once, and a rejoin still has the Lucky Rolls.
    - Odds panel numbers match the Index.
    - `PolicyService` restriction behaves as expected on a test account.
11. **RollFX.** Spinner, flash, shake and the Divine+ cutscene (`DevGiveMonster` won't trigger it; roll with `DevGrantProduct lucky_1000`). The skip setting works.
12. **Biomes.** `DevStartBiome`: tint, timer, announcement, Index odds change.
13. **Attribute sizes** with a full backpack (≈30 KB `Monsters` JSON). **HUD overlap** on small screens: the left button stack (BAG to TREE), the top-left row and the right action column.

## Model assets the code asks for (registry ids)

Drop a `Model` named with the id into `ReplicatedStorage.Assets.<Category>`, or call `AssetRegistry.RegisterAsset`. Models need a PrimaryPart (or any BasePart). A Humanoid is not required.

**Monsters** (36), `Assets.Monsters.<id>`, used on pedestals, roll reveals, Index viewports and battle arenas:

| Rarity | Ids |
|---|---|
| Common | `moss_goblin`, `meadow_slime`, `rockling` |
| Uncommon | `puddle_pup`, `ember_imp`, `spark_bug` |
| Rare | `thornback`, `dune_crawler`, `gloom_bat` |
| Epic | `frostfang`, `magma_brute`, `storm_drake` |
| Legendary | `elder_treant`, `sandstorm_sphinx`, `tidal_serpent` |
| Mythic | `solarius`, `void_stalker`, `inferno_titan` |
| Divine | `seraph_guardian`, `aurora_whale`, `thunder_god` |
| Celestial | `star_weaver`, `moon_howler`, `comet_rider` |
| Transcendent | `astral_hydra`, `prism_phoenix`, `eclipse_lord` |
| Eternal | `time_keeper`, `world_turtle`, `first_flame` |
| Secret | `the_watcher`, `mimic_king`, `hollow_echo` |
| Glitched (Glitch die only) | `null_0`, `err0r_beast`, `missing_texture` |

**Battle** (`Assets.Arenas`, `Assets.Enemies`, `Assets.Bosses`). Enemy ids are the enemy name in snake_case.

| Category | Ids |
|---|---|
| Arenas | `grassland_arena`, `forest_arena`, `desert_arena`, `mountain_arena`, `volcano_arena`, `cave_arena`, `heaven_arena`, `cosmic_arena`, `glitch_arena` |
| Enemies | `wild_slime`, `moss_goblin`, `thorn_sprite`, `bark_hound`, `ember_wisp`, `grove_warden`, `spore_witch`, `dust_scarab`, `sand_djinn`, `ice_ram`, `crag_golem`, `lava_hound`, `ash_wyrm`, `crystal_bat`, `deep_lurker`, `cloud_sprite`, `halo_knight`, `star_mote`, `nebula_eater`, `corrupt_byte`, `stack_overflow` |
| Bosses | `overgrown_brute`, `elder_root`, `pharaoh_of_dust`, `frost_king`, `infernos_the_world_eater`, `the_buried_ancient`, `the_fallen_luminary`, `the_star_devourer`, `the_null_sovereign` |

**Cosmetics** (`Assets.Particles`): ParticleEmitters named `aura_ember`, `aura_meadow`, `aura_solar`, `aura_glitch` and `aura_supporter`. Missing ones fall back to a colored default emitter.

**Used only when the Studio hub lacks that piece** (HubFallback):

| Category | Ids |
|---|---|
| Shops (`Assets.Shops`) | `summon_station`, `dice_shop`, `chest_shop`, `upgrade_tree`, `rebirth_altar`, `index_codex`, `daily_rewards`, `leaderboard_board`, `cosmetic_shop` |
| Statues (`Assets.Statues`) | `main_statue` |

**Optional:** `Plot<N>.Floor2` / `Floor3` models with `Slot<i>` parts (attribute `SlotIndex`):

| Floor | Slots |
|---|---|
| Floor2 | 11–16 |
| Floor3 | 17–40 |

They replace the generated placeholder decks.

**Sounds** (`Assets.Sounds`): `roll_tick`, `roll_reveal`, `roll_rare` (Sound instances). Until imported, a built-in ping plays.

**Shop icons:** 12 generated PNGs in `assets/shop-icons`, regenerated by `tools/icons/make_shop_icons.py`. Upload them as gamepass/product images, then put the image ids in `MonetizationConfig.image`.

**Not referenced by code yet:** the Dice, Bases, Chests, Weapons, Armor, Accessories, Relics, Icons, Animations and Portals categories. Those items are drawn as UI swatches or emoji today.
