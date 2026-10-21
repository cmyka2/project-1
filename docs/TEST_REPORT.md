# Test report

**Date:** 2026-10-21. **Scope:** the full codebase in this repository.

## Read this first

- **Everything here was run outside Roblox.** The tests run the real game code in a Roblox mock
  engine on [Lune](https://lune-org.github.io/docs) 0.8.9 (`tests/harness`). The game has **not**
  been opened in Roblox Studio, played on a live server, or played by a person. No screenshots or
  visual checks of the UI or world exist.
- The mock imitates Roblox's Instance tree, signals, services, DataStores (with JSON round-trips
  and failure injection), remotes, scheduling and time. It does **not** simulate rendering,
  physics, real networking, replication timing, DataStore throttling, MarketplaceService,
  PolicyService, TextService, animation playback or device input.
- A passing test means the logic behaves as specified under the mock. The section
  [What still needs testing in Roblox](#what-still-needs-testing-in-roblox) lists what only Studio
  or a live server can confirm.

## Results

| Check | Tool | Result |
|---|---|---|
| Automated tests | Lune harness, `lune run tests/run` | **164 passed, 0 failed** (13 specs) |
| Strict type-check | luau-lsp 1.38.0, `--!strict`, Roblox type definitions | **0 errors** |
| Lint | selene 0.27.1 (Roblox std) | **0 errors, 0 warnings** |
| Formatting | StyLua 0.20.0 `--check src tests` | **clean** |
| Place build | Rojo 7.4.4 | `build/MonsterRoll.rbxl` built. Loaded back with Lune's Roblox library: 1 Script, 1 LocalScript, 93 ModuleScripts, all expected services and asset folders present, `StarterPlayer.EnableMouseLockOption` off |

### Specs

| Spec | Tests | What it covers |
|---|---|---|
| `unit/Config` | 10 | Every config loads. Monsters, dice pools, regions, encounters, drops, recipes, chests, fusions, skill/ascension prerequisites (acyclic), quests and achievements reference valid ids. The spec's `moss_golem` example is matched. Walk speed is 32 and sprint 48; sprinting with every walk-speed bonus maxed stays well under the speed-telemetry limit |
| `unit/RollMath` | 13 | Odds sum to 1 for every dice and luck; tier ordering; exact weights at luck 1; monotonic luck effect; no guaranteed results at max luck; invalid weights ignored; soft/hard cap; edge RNG values; **chi-square over 200k samples**; **100k-roll two-stage distribution check** against the published odds |
| `unit/BaseLayout` | 7 | Every slot/floor example from the design spec (5/6/10/11/17/18 slots, 5/6, 5/6/6, 5/6/7), floor unlocks at 6 and 12, one slot per rebirth on the top floor, stable dense ids, invalid input |
| `unit/BattleEngine` | 17 | Turn order and ties; damage formula (base, minimum/never NaN, element matrix, crits, defense pierce); burn ticks and expiry, poison stacking, stun, defending, shields; cooldowns and ultimate energy; invalid targets, foreign units and out-of-turn actions; boss phases (buffs, summons, once only); victory/defeat and the round limit; **enemy AI fuzz** (only available abilities and valid targets) |
| `unit/DataSchema` | 10 | Defaults and JSON round-trip; **v1 → v3 migration fixture**; refusing newer versions; repairing currencies, unknown monsters, duplicate placements, bad slots, illegal levels/upgrades, double-equipped slots, missing wearers, future timestamps, garbage and wrong-typed sections; idempotence |
| `unit/Economy` | 15 | Income formula; global multiplier applied once; no double counting; upgrade cost curve; **no roll-then-sell, upgrade-then-sell or rarity-fusion money loops at maxed luck and bonuses**; modifier aggregation and caps; potions/events online-only; luck composition; offline income cap, efficiency and edge cases |
| `unit/AssetRegistry` | 5 | Placeholder for missing models (and recorded as missing); imported model used by key with no code change; static models anchored; **rigged models keep limbs unanchored** so animations can play; unset ids return nil |
| `integration/CoreLoop` | 7 | Boot without warnings → join → defaults and plot (5 slots) → server roll → place → income → upgrade → remove → leave/rejoin persistence |
| `integration/ClientSmoke` | 6 | All 17 client controllers boot and receive state; all 20 panels build; **walking at 32 and sprinting at 48**: Shift is held, the touch button toggles, a server speed re-apply doesn't cancel a sprint, respawning ends it; roll through the UI with the reveal; placement and income; **a full battle through the battle screen to Victory** and its result panel |
| `integration/Persistence` | 16 | Save and lock release on leave; retries with backoff; total save failure keeps the session and reports it; **failed loads kick and never overwrite**; transient load failures recover; lock held by another server (wait, then refuse); load right after the other server releases; **stale-lock takeover**; newer-version data refused untouched; stored v1 profile migrated and written back; tampered stored profile repaired; **offline income paid once, atomically with the lock**, not again on rejoin, not twice after a crash; session takeover stops saving and kicks; **BindToClose saves everyone** |
| `integration/Security` | 28 | Every request has one handler; **fuzzing all 56 requests with 26 malformed values in 6 argument shapes, plus no arguments (about 8,800 calls), without a handler error or a profile needing repair**; rate limits (burst, refill, per player); acting on another player's monsters; locked/unaffordable dice and bad counts; unaffordable rolls charge nothing; free-roll cooldown; locked monsters can't be sold; duplicate id lists; double daily/achievement/quest claims; trading (stolen ids, duplicate ids, self-trade, offered monsters locked, offer changes reset confirmations, fair swap without duplication, vanished monster cancels the swap, leaving cancels); **cheats refused outside Studio** unless allow-listed; **purchases granted once per receipt**, acknowledged only after saving; replication reaches only the owner; leaderboards expose only public fields |
| `integration/Progression` | 25 | Battles pay rewards once; Forest locked until the Grassland boss; boss drop and cooldown; region unlock and travel; locked-region encounters refused; forfeits pay nothing; skill prerequisites, max level, costs, respec and cooldown; equipment (one per category, upgrade, salvage); crafting (ingredients, timer, single claim, queue size, locked recipes); star fusion, rarity fusion, evolution, locked fodder refused; chests opened only as many times as owned; achievements; daily quests; **13 consecutive rebirths with every slot filled: pads per floor match the layout, floors unlock at 6 and 12, placements survive**; tutorial flow; QA offline cheat; **9th player with no plot gets the next freed plot** |
| `balance/Balance` | 5 | Pacing simulation guardrails: every region reachable; Forest < 15 min and Desert < 1 h; first rebirth 30 min – 4 h; no milestone is a wall; recommended power within ±35% of each boss |

## Bugs found and fixed during verification

Found by the tests above and fixed in code. Each fix has a test that would catch it again.

| # | Severity | Bug | Fix |
|---|---|---|---|
| 1 | **Critical (economy)** | Rolling then selling was profitable on Mountain dice and above (expected sale 0.8×–6.5× the roll cost), an infinite-money loop | Sell value is now relative to the monster's own dice and its most common rarity; `SellBaseFraction` 0.25 → 0.12; dice-discount cap 0.5 → 0.3. Expected sale is now about 20% of cost (≤ 44% at the luck hard cap) |
| 2 | **Critical (economy)** | Upgrade-then-sell returned more than the upgrade cost for top-tier monsters | Upgrades now add a bounded refund (50% of their cost at the maximum discount) instead of a percentage of base sell value |
| 3 | High (economy) | Event monsters' sell value used their nominal region's dice, re-opening loop #1 on the event dice once Forest dice got more expensive | Event monsters are priced against their event dice |
| 4 | **High (data)** | A stored profile with a wrong-typed section (e.g. `Currencies = "x"`) crashed sanitize. The player could never load and was kicked on every join | Wrong-typed sections are reset to defaults and logged |
| 5 | **High (exploit)** | "Locked" monsters could be sold or used as fusion fodder by passing the confirm flag | Lock is now a hard lock; only Favorites can be overridden with confirmation. Client sell dialog updated |
| 6 | High (data) | When another server took over a session, the player kept playing on a session that could no longer save, silently losing progress | The player is kicked with a clear message |
| 7 | High (balance) | The whole game (9 regions, 12 rebirths) took about 3 hours of active play and 2 days for a casual player | Retuned dice costs, region unlock costs, the rebirth curve and upgrade costs from the pacing simulation. Now about 55 min to the first rebirth, about 88 h to Glitch, about 142 h to rebirth 12 (79 days at 1 h/day). See [BALANCE.md](BALANCE.md) |
| 8 | Medium | `RecommendedPower` values were 2–6× below the real boss power and were never shown | Recalibrated to about 95% of each boss's power, shown on region cards, and guarded by a test |
| 9 | Medium | Imported rigged models would never animate: every part was anchored, and Roblox doesn't animate anchored limbs | Only the root is anchored; parts joined to it stay unanchored |
| 10 | Medium | A player who joined a full server never got a plot, even after one freed up | A freed plot is handed to the waiting player |
| 11 | Low (QA tool) | The `SimulateOffline` cheat had no effect, because the next save reset `LastSeen` | The session keeps the simulated time for later saves |
| 12 | Low (tooling) | The full-suite runner crashed (`io.write` doesn't exist in Lune) | Uses `@lune/stdio` |
| 13 | Low (tooling) | Rojo sync could, in principle, remove models added in Studio to the asset folders | Asset folders are explicitly `$ignoreUnknownInstances` |

Earlier in development, the tooling also caught and fixed: about 46 strict type errors; Selene
findings (shadowed builtins, arity issues, unused imports); a performance problem where the
inventory and skill tree rebuilt on every currency tick; and test-construction mistakes in the
battle engine spec.

## Known limitations and things not implemented

- **Not tested in Roblox Studio or live servers**, as above.
- **Trading persistence is two writes.** The two players' profiles are separate DataStore keys. The
  swap is atomic in server memory and both profiles are saved immediately, but a server crash
  between the two saves could duplicate or lose the traded monsters. A cross-key transaction log
  (e.g. MemoryStore-backed escrow) is not implemented.
- **No co-op battles.** Battles are single-player PvE. The arena is asynchronous PvP against an
  AI-controlled copy of another player's team, or a bot.
- **Battles are 2D.** The battle screen uses cards with animated hits and effects. 3D battle
  models and the `Attack/Cast/Hit/Ultimate` animation keys are not used yet. Only `Idle` plays,
  on base displays.
- **All art is placeholder.** No monster, enemy or NPC models, icons, sounds or animations are
  included (`AssetConfig` ids are empty). See [ASSET_CHECKLIST.md](ASSET_CHECKLIST.md): 72 monster
  models, 36 enemy models (9 bosses), 29 equipment icons, 10 NPCs, 41 sounds.
- **Monetization is off.** All product and game-pass ids are `0` until created on the Creator
  Dashboard. Real purchase prompts, receipts and pass ownership have never been exercised against
  Roblox (only `ProcessReceipt` logic in the mock).
- **Balance is simulated, not playtested.** The pacing model ignores skills, ascension, equipment,
  potions, events, stars, levels and battle income, so real players should progress somewhat
  faster. Combat difficulty is checked against `StatMath.power`, not against played battles.
- **English only.** No localization tables.
- **Gamepad/console:** panels can be closed with B and Roblox's default UI selection applies, but
  controller navigation was not designed or tested. Touch layouts were designed for phones and
  tablets but never seen on a device.
- **StreamingEnabled is off.** The generated world is about 2,400 instances (1,593 parts), so this
  should be fine, but memory on low-end phones is unmeasured.
- **Leaderboards** use OrderedDataStores on slow timers. Behavior under real request budgets with
  many servers is unverified.
- **Events are date-based.** Halloween 2026 ends on 2026-11-03 00:00 UTC. Future events must be
  added to `EventConfig`.
- **Studio fallback store.** With API access off in Studio, data lives in memory and resets when
  the session stops (a warning says so).

## What still needs testing in Roblox

Do these in Studio, then on a private live server, before launch:

1. **Boot:** Play solo. The output should have no errors. Expect only `[Assets] … placeholder`
   warnings until assets are imported. Walk the island and check the plots (4 north, 4 south),
   plaza, both shop districts, arena and region gates.
2. **UI on devices:** use the Device Emulator for a small phone, a large phone, a tablet and
   1080p/1440p desktop. Check the HUD, every panel, scrolling lists, the battle screen, popups,
   toasts and notches/safe areas.
3. **Core loop by hand:** roll (single, multi, auto), the reveal animation, place on a pad,
   income ticking, upgrade, sell with confirmation, lock/favorite.
4. **Multiplayer:** Test → *Clients and Servers* with 2–3 players. Check plot assignment,
   announcements, trading end to end, visiting plots and leaderboards.
5. **Persistence for real:** enable API services, play, leave, rejoin; check offline earnings;
   join the same account in two Studio servers to see the session lock message; force-stop the
   server and rejoin.
6. **Battles:** play every region's encounters and bosses with level-appropriate teams. Check the
   turn timer, statuses, boss phases and the arena.
7. **Movement:** walk around at the base speed of 32 and hold Shift to sprint at 48. Check that
   the Sprint button appears on a phone (Device Emulator) and doesn't overlap the HUD, that L3
   toggles sprint on a gamepad, and that the world (jumps, elevator pads, gates) still feels
   right at 2× speed.
8. **Rebirth 6 and 12** with the QA panel (`SetRebirths`, `AddCoins`): check that floors 2 and 3
   appear, monsters move up, the elevator pads carry players between floors, and every pad is reachable.
9. **Performance:** MicroProfiler and the Developer Console with 8 players and full bases. Watch
   server heartbeat, client frame time, memory and network receive.
10. **Purchases:** after setting real ids, test products and passes on a live private server
   (Studio purchases are simulated).
11. **Imported assets:** after importing models, check scale, facing, idle animation and that
    nothing collides on bases or in previews.
