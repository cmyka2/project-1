# Monster Roll: Rise of the Mythics

A multiplayer Roblox monster-collecting RNG tycoon. Roll dice to discover 72 monsters across 10
rarities, place them in your base to earn coins, upgrade and fuse them, battle through nine
regions in turn-based combat, and rebirth for more base slots and floors.

Everything is server-authoritative and driven from config modules. All art is generated as
placeholders until you import your own models, which takes no code changes (see
[docs/ASSET_IMPORT.md](docs/ASSET_IMPORT.md)).

> **Status:** the codebase passes 164 automated tests in a Roblox mock engine (Lune), strict
> type-checking and lint. It has **not** been run in Roblox Studio or a live server yet. Read
> [docs/TEST_REPORT.md](docs/TEST_REPORT.md) before publishing; the first Studio session should
> follow the checklist there.

## The map

One rectangular island. Four player bases line the north edge and four line the south edge.
The middle is a plaza (spawn, daily rewards, quests, leaderboards), with shop districts on the
east and west sides and nine region gates that teleport to floating region islands.

```
        north  [Base 1] [Base 2] [Base 3] [Base 4]
               ============ promenade ============
   Skill Shrine     |                    |  Dice Shop
   Rebirth Temple   |   CENTRAL PLAZA    |  Fusion Lab · Forge
   Ascension Altar  |                    |  Workshop · Chest Vault
   Battle Arena ====|====================|== Trading Post
   Region Gates x9  |                    |  Monster Storage
               ============ promenade ============
        south  [Base 5] [Base 6] [Base 7] [Base 8]
```

## Features

| Area | What's in it |
|---|---|
| Rolling | 9 region dice + 1 event dice, luck with soft/hard cap, odds shown for every dice, multi-roll (1/3/5/10), server-paced auto-roll, free roll, auto-sell by rarity, announcements |
| Collection | 72 monsters (incl. evolution, fusion-only and event monsters), codex with milestones, lock/favorite, filters, bulk sell |
| Tycoon | Per-monster income, upgrades, offline earnings, base cosmetics, 5 + rebirths slots across up to 3 floors (floor 2 at rebirth 6, floor 3 at rebirth 12) |
| Progression | 6-branch skill tree with cross-branch nodes and respec, rebirth (30), ascension tree, 9 regions with unlock requirements |
| Items | 29 equipment pieces in 4 categories, upgrades, salvage, crafting queue, potions, chests with published odds |
| Fusion | Star fusion, rarity fusion, special recipes, evolution |
| Combat | Turn-based 3v3, 9 elements, 14 status effects, abilities with cooldowns/energy/ultimates, enemy AI profiles, multi-phase bosses, async arena with Elo |
| Meta | Main/daily/weekly/region/event quests, achievements, 7-day daily rewards, tutorial, leaderboards, trading, events (weekend luck, Halloween) |
| Movement | Walk speed 32 (2× Roblox default), sprint 1.5× (Shift held on PC, Sprint button on touch, L3 on gamepad), Mobility skills add % on top |
| Platform | Responsive UI for phone/tablet/PC, settings (audio, reduced effects, skip animations), QA cheat panel (Studio/allow-listed only) |
| Safety | Session-locked saves with retries and migrations, rate-limited validated remotes, idempotent purchases, exploit telemetry |

## Quick start

### Option A: open the built place

1. Open `build/MonsterRoll.rbxl` in Roblox Studio (rebuild it with `rojo build default.project.json -o build/MonsterRoll.rbxl`).
2. **Game Settings → Security**: turn on *Enable Studio Access to API Services* if you want real
   DataStore saves in Studio. If it's off, the game uses an in-memory store and warns about it
   in the output. Your progress then resets when you stop.
3. Press **Play**. The world, plots and placeholder monsters are built at runtime.
4. To test multiplayer: **Test → Clients and Servers → 2+ players → Start**.

### Option B: live-sync with Rojo (recommended for development)

```sh
rokit install                 # installs rojo, selene, stylua (see rokit.toml)
rojo serve default.project.json
```

Then, in Studio, open an empty Baseplate, install the Rojo plugin, and click **Connect**. Delete
the default `Baseplate` part, because the game builds its own island.

### Before publishing

- **Game Settings → Places → Max Players = 8**. There are 8 base plots. A 9th player can still
  play and gets the next plot that frees up, but they have no base until then.
- **Monetization:** create the developer products and game passes on the Creator Dashboard and put
  their ids into `src/shared/Config/MonetizationConfig.luau`. While an id is `0`, that item is
  disabled.
- **Assets:** import models, icons, sounds and animations (see
  [docs/ASSET_CHECKLIST.md](docs/ASSET_CHECKLIST.md)).
- **QA access:** add QA UserIds to `GameConfig.Cheats.AllowedUserIds` if they need cheats on live
  servers. In Studio, cheats are always available.
- Run the Studio test checklist in [docs/TEST_REPORT.md](docs/TEST_REPORT.md#what-still-needs-testing-in-roblox).

## Project layout

```
src/
  shared/            -> ReplicatedStorage.Shared   (config, types, pure math, net API)
    Config/          all tunables: monsters, dice, regions, economy, combat, ...
    Util/            pure, unit-tested modules (RollMath, StatMath, BaseLayout, Modifiers, ...)
    AssetRegistry    model/icon/sound lookup with generated placeholders
    Net              list of every remote
  server/            -> ServerScriptService.Server
    Bootstrap.server.luau   the only server Script: init/start every service in order
    Modules/         DataSchema, BattleEngine, NetServer, RateLimiter, WorldBuilder, ...
    Services/        31 services (data, roll, tycoon, combat, quests, trading, ...)
  client/            -> StarterPlayerScripts.Client
    ClientBootstrap.client.luau   the only LocalScript
    Controllers/     17 controllers (UI, state, roll, inventory, combat, movement, ...)
    UI/              Theme, Kit (components), Cards, Icons
tests/               Lune test harness, unit, integration and balance specs
docs/                architecture, formulas, config, assets, balance, test report
```

## Development commands

| Task | Command |
|---|---|
| All tests | `LUNE_BIN=lune lune run tests/run` |
| One spec | `lune run tests/run tests/unit/RollMath.spec.luau` |
| Regenerate balance report | `BALANCE_WRITE=1 lune run tests/run tests/balance/Balance.spec.luau` |
| Regenerate asset checklist | `lune run tests/run tests/tools/AssetChecklist.luau` |
| Strict type-check | `./scripts/analyze.sh` (needs `rojo` and `luau-lsp`; see the script) |
| Lint | `selene src` |
| Format | `stylua src tests` |
| Build place | `rojo build default.project.json -o build/MonsterRoll.rbxl` |

CI (`.github/workflows/ci.yml`) runs the format check, lint, strict type-check, the full test suite and the place build on every push and pull request.

## Documentation

| Doc | For |
|---|---|
| [ARCHITECTURE.md](docs/ARCHITECTURE.md) | How the systems fit together: services, networking, data, security |
| [FORMULAS.md](docs/FORMULAS.md) | Every gameplay formula (odds, luck, income, costs, damage, ...) |
| [CONFIG_GUIDE.md](docs/CONFIG_GUIDE.md) | What each config file controls and how to add content safely |
| [ASSET_IMPORT.md](docs/ASSET_IMPORT.md) | Importing your monster/enemy/NPC models, icons, sounds, animations |
| [ASSET_CHECKLIST.md](docs/ASSET_CHECKLIST.md) | Generated list of every asset key the game looks for |
| [BALANCE.md](docs/BALANCE.md) | Generated pacing simulation and economy tables |
| [TEST_REPORT.md](docs/TEST_REPORT.md) | What was tested, results, bugs fixed, known limitations |
