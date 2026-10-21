# Architecture

## Principles

1. **The server decides everything that matters.** Rolls, damage, rewards, prices, unlocks and
   trades are computed on the server. The client sends *intents* ("roll this dice 5 times") and
   renders what the server replies or replicates. It can never send a result.
2. **Config, not code.** Every tunable number and every piece of content lives in
   `src/shared/Config/*`. See [CONFIG_GUIDE.md](CONFIG_GUIDE.md).
3. **Pure math is separate and tested.** Odds, luck, income, costs, slot layout, modifiers, profile
   migration and the battle engine are pure modules with injected randomness, covered by unit tests.
4. **Assets are optional.** Gameplay refers to keys (`ModelKey`, `IconKey`, `SoundKey`). Missing
   assets fall back to generated placeholders. See [ASSET_IMPORT.md](ASSET_IMPORT.md).
5. **One entry point per side.** `Server/Bootstrap.server.luau` and
   `Client/ClientBootstrap.client.luau` are the only scripts. Everything else is a ModuleScript.

## Runtime layout

| Rojo source | Roblox location | Contents |
|---|---|---|
| `src/shared` | `ReplicatedStorage.Shared` | Config, Types, Net, AssetRegistry, Util (pure modules) |
| (folders) | `ReplicatedStorage.Assets` | `MonsterModels`, `EnemyModels`, `NPCModels`, `Effects`, `Animations`: drop imported assets here |
| `src/server` | `ServerScriptService.Server` | Bootstrap, Modules, Services |
| (folders) | `ServerStorage` | optional server-only model folders |
| `src/client` | `StarterPlayer.StarterPlayerScripts.Client` | ClientBootstrap, Controllers, UI |

## Server

### Lifecycle

`Bootstrap` requires the services in a fixed `ORDER` and runs them in two phases:

1. `init()` on every service, in order: create remote handlers and signals. Nothing yields here.
2. `start()` on every service, each in its own thread: connections and loops.

Player lifecycle is driven by `PlayerDataService`. Once a profile has loaded, `onPlayerReady(player,
profile, loadInfo)` runs on every service **in order**. On leave, `onPlayerRemoving(player,
profile)` runs **in reverse order** before the final save, so later services clean up before the
services they depend on.

### Services (in boot order)

| Service | Responsibility |
|---|---|
| AnalyticsService | Failure-proof wrapper over Roblox analytics, plus counters for the QA panel |
| PlayerDataService | Profile load/save, session locks, autosave, BindToClose, migrations ([Persistence](#persistence)) |
| ReplicationService | Sends each player their own profile and server-derived values, batched |
| AntiExploitService | Telemetry for rejected requests and implausible movement (logs, never auto-punishes) |
| WorldService | Builds the world once (WorldBuilder), key locations, out-of-bounds recovery, teleports |
| EconomyService | The only place currencies/materials change: finite, non-negative, capped, tracked |
| MonsterService | Creates monster instances, codex discovery, battle XP |
| InventoryService | Monster/equipment/consumable/chest inventories; lock, favorite and "busy" protections |
| EventService | Live events from server time (weekend luck, Halloween) |
| PlotService | 8 plots, ownership, slot pads per floor, plot handoff when one frees up |
| TycoonService | Placement, the central income tick, monster displays on the base |
| UpgradeService | Monster upgrades, base cosmetics |
| RollService | Dice validation, server RNG, multi-roll, auto-roll, auto-sell, announcements |
| RegionService | Region unlocks, travel, daily exploration caches |
| SkillTreeService | Skill purchases and respec |
| AscensionService | Ascension tree |
| RebirthService | Rebirth requirements, resets and rewards; rebuilds the slot layout |
| EquipmentService | Equip (one per category per monster), upgrade, salvage |
| CraftingService | Timed crafting queue; ingredients consumed atomically, claims granted once |
| FusionService | Star/rarity/special fusion and evolution |
| ChestService | Chest purchases and drops; paid-random restrictions via PolicyService |
| CombatService | Battle sessions over `BattleEngine`: teams, PvE, arena, action validation, timeouts, rewards |
| QuestService | Main, daily, weekly, region and event quests from server-side GameEvents |
| AchievementService | Achievements and codex milestones |
| DailyRewardService | 7-day login calendar (UTC days) |
| TutorialService | Step progression from GameEvents |
| LeaderboardService | OrderedDataStore boards on slow timers |
| TradingService | Two-player trades with locks, confirmations, countdown and revalidation |
| MonetizationService | Idempotent `ProcessReceipt`, game-pass checks via MarketplaceService |
| SettingsService | Validated player settings, movement modifiers |
| CheatService | QA commands, gated server-side (Studio or allow-listed UserIds) |

Shared server modules (`Server/Modules`) are `NetServer`, `RateLimiter`, `GameEvents` (the
server-only event bus that feeds quests, achievements and the tutorial), `DataSchema`,
`OfflineIncome`, `BattleEngine`, `WorldBuilder` and `BuildKit`.

## Networking

All remotes are listed in `Shared/Net.luau` and created by the server at startup.
`NetServer.init()` destroys any pre-existing `Remotes` folder first, so a client can never supply
its own.

- **Requests** are RemoteFunctions, client → server. Every handler goes through `NetServer.handle`,
  which wraps it with:
  1. a per-player, per-request **token bucket** (`Rate`/`Burst`; failures return `"Slow down!"`);
  2. a **profile-ready** check;
  3. an **exclusive in-flight lock**, so a player can't overlap two calls to the same request;
  4. **pcall isolation**: an error returns a generic failure and is logged with context;
  5. a uniform result: `{ ok: boolean, err: string?, data: any? }`.

  Handlers receive raw `unknown` arguments and validate them with `Shared/Util/Guard`, which checks
  types, ranges, integers, NaN/inf, string length and array shape, and rejects duplicate ids.
  Malformed requests return `NetServer.invalid(...)`, which also feeds the anti-exploit telemetry.
- **Events** are RemoteEvents, server → client only: `StateSync`, `Notify`, `AutoRollResult`,
  `BattleUpdate`, `TradeUpdate`, `Announce`, `Popup`, `CheatAccess`.
- The server never calls `InvokeClient`.

### Replication

`ReplicationService` keeps a client replica of *only that player's* profile:

- `Full` on join and on `RequestState` (a late client listener can resync);
- `Key` deltas for changed top-level sections, and `Monsters`/`Equipment` deltas per instance;
- `Derived` values computed on the server through registered providers: income rate, modifiers,
  capacities, plot index, auto-roll state, and so on. The client never recomputes authoritative
  numbers.

Pushes are batched at most ~10 per second per player. Other players' data is never sent, except
the public fields of trade offers, leaderboards and plot owners.

## Persistence

`PlayerDataService` stores one record per player, `{ Profile, Lock }`, under
`Player_<UserId>` in `GameConfig.Data.StoreName`.

- **Session lock.** Loading is a single `UpdateAsync` that claims `Lock = { SessionId, Time }`.
  If another server holds a lock newer than `LockStaleSeconds` (30 min), the load aborts and
  retries every `LockWaitSeconds`; if the lock is still held afterwards, the player is kicked with
  a "still being saved" message. A stale lock (crashed server) is taken over.
- **Migration and repair** run inside the same transform: `DataSchema.migrate` (versioned steps
  v1→v2→v3; data from a newer version is refused, untouched) then `DataSchema.sanitize`. Sanitize
  repairs invalid numbers, unknown ids, bad placements, double-equipped slots, future timestamps
  and wrong-typed sections, and drops unknown keys. Every repair is logged.
- **Offline income** is computed and added in that same atomic write, which also moves `LastSeen`,
  so an absence can never be paid twice, even if the server crashes right after loading.
- **Failed loads never overwrite.** After `LoadAttempts` failures with backoff, the player is
  kicked with "Nothing was lost". The game never falls back to a default profile that could later
  be saved over real data.
- **Saves** use `UpdateAsync` with retries and backoff. They refuse to write if the lock now belongs
  to another server; the player is then kicked, rather than playing on without saving. Saves
  happen on a staggered autosave (every 90 s), after trades and purchases, on leave and on
  `BindToClose`, which saves every player in parallel within the shutdown budget. Finalization runs
  once per session.
- **Studio without API access** uses an in-memory store and says so in the output. This is never
  used on live servers.

## World

`WorldBuilder` builds everything procedurally, with anchored parts and about 2,400 instances in
total: the island (640 × 820 studs), 8 plots on the north and south edges, the central plaza, the
east shop district, the west progression district with the battle arena and nine region gates,
and nine floating region islands. Any district whose folder already exists in `Workspace.World` is
skipped, so hand-built replacements are preserved. Interactions use ProximityPrompts carrying an
`Action` attribute, which `InteractionController` turns into UI or requests. The server
re-validates every request (ownership, requirements, costs, cooldowns). Physical distance is only
checked where location is the point, such as exploration caches. Shops and panels are also
reachable from the HUD by design, so standing next to a shop is never required.

Plots: each owned plot shows exactly `BaseLayout.totalSlots(rebirths)` pads, laid out on
`BaseLayout.floorCount(rebirths)` floors. Slot ids are stable. When floor 2 unlocks (rebirth 6),
the slots beyond the first five move up, keeping their monsters. Locked floors show their unlock
rebirth.

## Client

`ClientBootstrap` loads 17 controllers in order (`init`, then `start`).

- `StateController` holds the replica and exposes change signals. UI reads from it and never writes.
- `UIController` owns the HUD (currencies, navigation, quick roll, quest tracker), one-at-a-time
  panel windows, toasts, confirmations and popups. It scales for phone, tablet and desktop.
- Feature controllers build their panels from `UI/Kit` components: Roll, Inventory/Codex,
  Tycoon/Base, Combat, Progression (skills/ascension/rebirth/regions), Shop
  (fusion/crafting/chests), Quest (quests/achievements/daily/events), Social (trade/leaderboards),
  Settings, Tutorial, Cheat (QA, only when the server authorizes it).
- `MovementController` handles sprinting. The server sets the character's walk speed
  (`Derived.WalkSpeed`) and publishes `Derived.SprintSpeed`; the client only switches between the two.
  Shift is hold-to-sprint; gamepad L3 and the touch button toggle. Shift Lock is disabled
  (`StarterPlayer.EnableMouseLockOption = false`) so Shift is free for sprinting.
- `AudioController` and `EffectsController` play keyed sounds and client-only VFX. `ReducedEffects`
  turns off shakes and flashes.
- Requests go through `UIController.call(name, ...)`, which shows server errors as toasts. Panels
  re-render from state changes, not from request replies, so the UI can't drift from the server.

## Security model (summary)

| Threat | Defense |
|---|---|
| Forged results (rolls, damage, rewards) | Never accepted: the server computes everything |
| Malformed or hostile arguments | Guard validation in every handler; fuzz-tested over every request |
| Request spam | Token buckets per player per request, plus in-flight locks |
| Acting on others' items | Every id is looked up in the caller's own profile |
| Double claims (daily, quests, achievements, crafts, chests, receipts) | Claimed state checked and set in the same synchronous step; receipts are idempotent |
| Duplication through trades | Duplicate ids rejected, offered monsters locked, any change clears confirmations, full revalidation before an atomic in-memory swap, immediate saves |
| Money loops | Sell value capped well below expected roll cost at max luck and bonuses; upgrade and fusion refunds bounded (tests in `Economy.spec`) |
| Cheat remotes | Server-side check on every call; never trusted from the client |
| Data loss and corruption | Session locks, atomic load transform, sanitize, retries, no default-profile overwrite |
| Teleport/speed exploits | Server-side out-of-bounds recovery; speed telemetry |

## Testing

`tests/harness` contains a Roblox mock engine for Lune: Instances, signals, services,
DataStores with failure injection and JSON round-trips, a virtual-time scheduler, remotes with
client delivery, and a Rojo-style module loader. It boots the **real** server and client code.
See [TEST_REPORT.md](TEST_REPORT.md) for what is and isn't covered.
