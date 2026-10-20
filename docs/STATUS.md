# Monster Roll: implementation status

Branch `studio-export`. Spec: [`docs/SPEC.md`](SPEC.md).

## How this was verified, and what wasn't

**Nothing in this branch has been run in Roblox Studio yet.** The cloud session that wrote it can't reach Studio.

What *has* been run, on a Luau host outside Roblox (`tools/headless`):

| Check | What it covers |
|---|---|
| `check.luau` | Every `.luau` file under `src/` compiles (syntax only, no type check). |
| `specs.luau` | The Studio specs in `ServerStorage/Tests` (RollSpec, BattleSpec, ProgressionSpec), all passing. |
| `sim.luau` | The **real** server scripts (DataService, Game, Guard, MonsterService, ChestService, BattleService, PlotAssigner) running on a mock engine, walking the §24 flow plus lock, outage, migration and shutdown cases. 96/96 checks pass. |
| `fallback.luau` | An empty workspace: HubFallback builds the island, 8 plots, the shops and the summon station, and a roll works. |

The mock (`tools/headless/mockrbx.luau`) is a stand-in for the engine, not the engine itself. It does **not** model replication, real DataStore limits or throttling, physics, rendering, ProximityPrompt range, or anything on the client. **No client UI has been executed anywhere**, mock included. "Mock-verified" below means server logic only.

### Run it

Studio (after Rojo sync), in the server command bar:

```lua
print(require(game.ServerStorage.Tests.RunAll)())
-- Studio-only QA hooks:
game.ServerStorage.DevGiveCash:Invoke(game.Players.<you>, 1e6)
game.ServerStorage.DevGiveMonster:Invoke(game.Players.<you>, "frostfang|Normal", 3)
game.ServerStorage.DevSetRebirths:Invoke(game.Players.<you>, 12)
```

Saving in Studio needs a published place with *Enable Studio Access to API Services*. Without it the HUD shows "progress is NOT saved", which is expected.

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
- **Implemented**: code is complete and the server path passes in the mock sim.
- **Pending playtest**: needs a Studio run before it can be called tested.

Every row is pending a Studio playtest.

| # | Criterion | Status | Server evidence (mock sim) | Pending playtest / gaps |
|---|---|---|---|---|
| 1 | New player gets a valid saved profile | Implemented | Profile written with session lock; `DataStatus` goes `loading` → `ready` | Real DataStore in a published place |
| 2 | Assigned an available plot | Implemented | Separate plots for two players; third player gets `PlotStatus = "full"`, then the next plot that frees up | Real `Workspace.Hub.Plots`, teleport to `SpawnPoint` |
| 3 | Starts with the Grassland Die | Implemented | `Dice.grassland` and `SelectedDie` on a new profile | DiceUI shows "Equipped" |
| 4 | Rolls a server-generated monster | Implemented | Summon prompt → weighted roll on the server; roll cooldown enforced | Prompt at the real SummonCore, roll toast |
| 5 | Monster in backpack + collection | Implemented | Instance created, `Index.D` updated, `LastRoll` published | BackpackUI and IndexUI render it |
| 6 | Places it in a base slot | Implemented | Placement by instance id; double placement and locked slot rejected; model on pedestal | BaseUI prompt + picker on the real plot |
| 7 | Monster generates money | Implemented | 10 s of income matches the per-second rate | Pad `$x/s` labels, HUD cash/s |
| 8 | Upgrades the monster | Implemented | `InventoryAction upgrade`: level 2, cost charged; forged id rejected | BackpackUI upgrade button |
| 9 | Income increases correctly | Implemented | Income × `levelMult(2)` exactly | — |
| 10 | Buys a new die | Implemented | Buy charges once; can't skip a tier; can't equip unowned | DiceUI |
| 11 | Equips it and rolls again | Implemented | Forest die selected, second roll uses its pool | — |
| 12 | Buys an Evolution Tree node | Implemented | `money1` bought; prerequisites enforced; no re-buy | SkillTreeUI (the existing hex tree) |
| 13 | Bonus applies exactly once | Implemented | Income × 1.25 exactly, server value and published value | — |
| 14 | Buys a chest, gets server gear | Implemented | Wooden chest → gear; bad batch size and missing die rejected | ChestUI result text |
| 15 | Equips gear, stats change | Implemented | Income × (1 + bonus); weapon/armor/accessory stat goes up | ChestUI GEAR bag, Backpack detail |
| 16 | Builds a legal battle team | Implemented | Owned, distinct, ≤ 3; duplicates and unowned rejected | Backpack "Add to battle team" |
| 17 | Enters a battle, picks turn-based actions | Implemented | Battle start, attack loop, server-side turn checks | BattleUI cards, status icons, buttons |
| 18 | Wins and gets the right rewards | Implemented | Cash + materials + progress paid once; acting after the end pays nothing | Victory panel text |
| 19 | Meets rebirth requirements | Implemented | Cost, plus a boss gate (`grass3`) from rebirth 3 | RebirthUI requirement lines |
| 20 | Confirms rebirth, gets permanent rewards | Implemented | Cash reset; monsters, gear and placement kept; AP awarded | RebirthUI confirm |
| 21 | +1 slot and floor milestones | Implemented | Rebirth 6 → 11 slots, `Floor2` generated with slot 11, placing there works | Placeholder floor geometry, elevator prompts and teleport |
| 22 | Leaves and rejoins | Implemented | Lock released on leave, `LastOnline` stamped; offline earnings for 2 h, capped at 8 h | Real join/leave timing |
| 23 | Everything loads correctly | Implemented | Monsters, placements, gear (on its monster), rebirths and cash restored after a JSON round-trip | — |
| 24 | Others can't touch your data/base | Implemented | Other player can't place, equip or sell your things; State is per player in their own PlayerGui | Confirm the State ScreenGui replicates only to its owner |

Also mock-verified:
- Lock held by another live server → join kicked, save untouched.
- Expired lock is taken over.
- DataStore outage on load → kick, never overwrite with defaults.
- v1 save migrated on load.
- Newer schema refused.
- Lock stolen mid-session → this server stops writing and removes the player.
- BindToClose saves and releases.
- Remote spam rate-limited.
- NaN, fractional and table arguments rejected.
- Fusion validation: same copy twice, target as material, locked copy.
- Last-copy sell confirmation.
- Codex keeps a sold monster.

## System map (what existed → what it is now)

| System (spec §) | Before | Now | Where |
|---|---|---|---|
| Persistence §5 | GetAsync + blind UpdateAsync, no lock, v1 | **Done.** UpdateAsync only, session lock (job id + heartbeat, 5 min expiry), retries with backoff, schema v2 + v1 migration, autosave 60 s, debounced save after purchases, release on leave, BindToClose, kick instead of defaults on failure | `server/DataService`, `server/DataSchema` |
| Economy §5.3 / §10 | Inline in MonsterService | **Done.** `Game.addCash` / `Game.spend` are the only cash writers. Plain numbers capped at 1e15 (ponytail note to switch before costs pass that). One income loop (1 s). Offline earnings from server timestamps, 8 h cap. All current bonuses are permanent, so all of them apply offline | `server/Game`, `MonsterService` |
| RNG §6.2 / §6.4 | Weights × luck on Rare+, normalized | **Done.** Shared weighted picker (invalid weights → 0, empty pool → nothing). Per-monster eligible pool (tier cap, die-exclusive Glitched). Luck = die × (1 + skill + 2%/rebirth), diminishing past 25, hard cap 500, tier-graded boost, renormalized. Index shows the server's effective odds | `Weighted`, `LuckConfig`, `MonsterConfig.pool` |
| Inventory §8 | Stack counts per `id\|variant` | **Done.** Instances `{id, v, lvl, fr, lock, fav, t}` with ids `m<n>`; capacity 100 + storage nodes; lock, favorite, sell (last-copy confirm for Rare+), fusion (3 copies, atomic). **Partial:** no multi-select grid (there's a "sell duplicates" button), no research-material conversion, no collection milestone rewards (§8.2) | `MonsterService` InventoryAction, `client/BackpackUI` |
| Base / placement §9, floors §3.3 / §13.1 | 10 pedestals, slots capped at 10, one floor | **Done.** Slots = 5 + r (cap 40), floors = min(3, 1 + r // 6). Slot→floor mapping: 1–10 on floor 1, 11–16 on floor 2, 17+ on floor 3. Upper floors use `Plot.Floor2/Floor3` from Studio if present, else generated placeholder decks with pedestals and elevator pads. A placement whose model is missing shows a placeholder | `Formulas`, `MonsterService` base section, `client/BaseUI` |
| Monster upgrades §11 | — | **Done.** Cost = base × 25 × 1.2^(lvl−1), max level 50, income × (1 + 0.25(lvl−1)); combat × (1 + 0.05(lvl−1)). Preview values (`inc`, `nxt`, `cost`) are computed on the server and published | `Formulas`, `Game.publish` |
| Dice §7 | Buy / equip | **Done.** Kept as it was, plus ownership check at roll time and the die's own pool. **Partial:** the shop shows die luck and rarity cap, but effective luck only for the equipped die | `MonsterService`, `client/DiceUI` |
| Skill tree §12 | Hex tree, 4 effects live | **Partial.** Same tree. `income`, `luck`, `rollspeed`, `walkspeed`, `damage`, `health`, `storage` and `sell` are all live through `Tree.stat` (one place). **Missing:** the spec's six named branches and nodes, ranks, cross-branch multi-prerequisites, respec | `SkillTree`, `client/SkillTreeUI` |
| Rebirth §13 | Cost → cash reset, +1 slot | **Done.** Requirement table (cost, plus boss gate from rebirth 3). Reset policy explicit in `RebirthConfig.Resets/Keeps` and pure `apply()`. Permanent +10% income and +2% luck per rebirth; AP 1 per rebirth, 6 on floor milestones. **Missing:** the Ascension Tree to spend AP | `RebirthConfig`, `MonsterService` |
| Chests / gear §14 | Gear on a base slot | **Done.** Gear sits on a monster instance (one per type) and boosts income + weapon damage / armor HP / accessory speed. Batch open 1–10, paid and granted in one step. **Partial:** no gear levels, secondary stats or relics | `ChestService`, `GearConfig`, `client/ChestUI` |
| Crafting §14.6 | — | **Done (small).** Materials from battles, two recipes (Rare and Epic gear), server-checked | `GearConfig.Recipes`, `ChestService` |
| Battle §15 | Engine + one region | **Done (core).** Statuses burn, poison, freeze, stun, weaken, expose, shield, regen (+cleanse), with control immunity (bosses longer). AI weighs element and HP and self-buffs when hurt. Saved team of 3. Grassland + Forest regions with die gating, materials, guaranteed first-clear boss gear, single payout. **Missing:** Mark, team presets beyond 1, reserves/switching, 3D arenas (battles are a 2D UI), regions 3–9, other battle modes | `BattleEngine`, `BattleConfig`, `BattleService`, `client/BattleUI` |
| Security §18 | Shared 0.2 s cooldown | **Done.** `Guard`: per-action cooldowns + token bucket (12 burst, 8/s); string/int/id-list validation; ownership checked against server data on every remote. Remote layout kept: 7 RemoteFunctions in `ReplicatedStorage.Monster`, `InventoryAction` added | `server/Guard` |
| Private state §19 | All Player attributes (visible to everyone) | **Done.** `PlayerGui.State` ScreenGui, only replicated to its owner. Public: `PlotId`, `DataStatus`, `PlotStatus`, leaderstats Cash/Rebirths | `Game.state` |
| Asset registry §4 | `MonsterModel` looked in a folder | **Done.** `AssetRegistry` Get/Has/Create/Register/ValidateRegistry. Labeled magenta placeholders. One summary line per category at server start | `shared/Monster/AssetRegistry`, `HubFallback` |
| World §3 | Built in Studio (~3,200 instances) | **Kept.** Code finds it at runtime. `HubFallback` adds labeled placeholders only for missing pieces. **Not in repo:** the Studio world itself; layout config covers placeholders only | `HubFallback`, `serverstorage/HubBuildKit` |
| HUD §17.1 | Leaderstats only | **Partial.** HudUI shows cash, cash/s, save status, plot-full notice, offline summary and server notices. **Missing:** current region, quest indicator, roll button (rolling stays at the summon prompt) | `client/HudUI` |
| Leaderboards §19, daily rewards / quests / events §20, premium shop §3.4, collection milestones §8.2, auto-roll §17.2, rare-roll announcements §6.3 | — | **Missing** | — |

## Studio playtest checklist (highest risk first)

1. **Hub names match.** Code expects:
   - `Workspace.Hub.Plots.Plot<N>`: attributes `PlotId`, `Owner = ""`, `Color`; children `Base`, `OwnerSign` (SurfaceGuis with `Label`), `SpawnPoint`, `Slot1..10` (attribute `SlotIndex`), `Collect1..10` (with `Label`).
   - `Workspace.Hub.Shops.SummonArea.SummonCore`, which has a ProximityPrompt.
   - Prompts under models named `DiceShop`, `ChestShop`, `UpgradeTree`, `RebirthAltar` and `Index`.
   
   Anything missing gets a magenta "PLACEHOLDER" stand-in, and Output says so.
2. **Private State replication.** The server creates `PlayerGui.State` (ScreenGui, `ResetOnSpawn = false`). Every client UI waits for it. Check:
   - It appears for its owner.
   - It survives a respawn.
   - It does not appear for other players.
3. **Saves in a published place.**
   - Join, roll, place, leave, rejoin.
   - Two servers: join the second while the first is still open. The second should wait about 30 s and then kick with "still open on another server".
   - An existing v1 save migrates (stacks become instances, placements and gear follow).
4. **Floors.**
   - `DevSetRebirths` 6, then 12: Floor2 and Floor3 decks appear and the elevator prompts teleport you.
   - BaseUI prompts appear on the new pedestals.
   - Placing on slot 11 and on slot 17 works.
5. **Attribute sizes** with a full backpack (100–200 monsters): the `Monsters` JSON is about 30 KB.
6. **UI layouts on a phone-sized viewport.**
   - BackpackUI is new and dense.
   - The BattleUI stage list now scrolls.
7. **Balance.** Every number is a placeholder: upgrade curve, fuse/sell values, rebirth cost 25k × 3^r, offline cap, luck caps, Forest region stats.

## Model assets the code asks for (registry ids)

Drop a `Model` named with the id into `ReplicatedStorage.Assets.<Category>`, or call `AssetRegistry.RegisterAsset`. Models need a PrimaryPart (or any BasePart). A Humanoid is not required.

**Monsters** (36), `ReplicatedStorage.Assets.Monsters.<id>`, used by base pedestals, roll reveals and Index viewports:

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

**Used only when the Studio hub lacks that piece** (HubFallback):

| Category | Ids |
|---|---|
| Shops (`Assets.Shops`) | `summon_station`, `dice_shop`, `chest_shop`, `upgrade_tree`, `rebirth_altar`, `index_codex` |
| Statues (`Assets.Statues`) | `main_statue` |

**Optional:** `Plot<N>.Floor2` / `Floor3` models built in Studio. Put pedestal parts named `Slot<i>` with attribute `SlotIndex` in them:

| Floor | Slots |
|---|---|
| Floor2 | 11–16 |
| Floor3 | 17–40 |

They replace the generated placeholder decks.

**Not referenced by code yet:** the spec categories Dice, Bases, Chests, Weapons, Armor, Accessories, Relics, Arenas, Enemies, Bosses, Icons, Sounds, Particles, Animations and Portals. Dice, chests and gear are drawn as UI swatches or emoji, and battles are 2D. They have registry categories ready, but no code asks for them.
