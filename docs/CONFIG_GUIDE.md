# Configuration guide

Every tunable value and every piece of content is in `src/shared/Config/`. Gameplay code reads
these modules and never hard-codes numbers. After any change:

```sh
LUNE_BIN=lune lune run tests/run                                     # validates every config cross-reference
BALANCE_WRITE=1 lune run tests/run tests/balance/Balance.spec.luau    # re-simulates pacing -> docs/BALANCE.md
lune run tests/run tests/tools/AssetChecklist.luau                   # refreshes docs/ASSET_CHECKLIST.md
```

`tests/unit/Config.spec.luau` fails loudly on unknown ids, dice pools missing a weighted rarity,
regions without a dice, material or boss, broken recipes or chests, cyclic skill prerequisites and
malformed quests. `Economy.spec` and `Balance.spec` fail if a change creates a money loop, a
progression wall or a region whose recommended power no longer matches its boss.

## Rules that protect player saves

- **Ids are permanent:** `MonsterId`, `ItemId`, skill and ascension node ids, quest and
  achievement ids, region ids, material and consumable ids. Saves store these strings. Renaming
  one deletes it from every profile; sanitize drops unknown ids on load. Change `DisplayName`
  instead.
- **Removing content:** monsters or items whose id disappears are dropped from inventories on
  load (and logged). To retire content safely, keep the definition and remove it from dice pools,
  drops and recipes.
- **Changing the profile shape** (`server/Modules/DataSchema.luau`): add a migration step, bump
  `CURRENT_VERSION` (and `GameConfig.Data.SchemaVersion`), and add a fixture test to
  `tests/unit/DataSchema.spec.luau`. A server refuses data from a newer version rather than
  corrupting it.
- **Never change `GameConfig.Data.StoreName`** after launch unless you mean to wipe all progress.

## Config files

| File | Controls |
|---|---|
| `GameConfig` | Data store name/locks/retries/autosave, world size, plots (count, size, floor height), travel, movement (base walk speed, jump power, sprint multiplier and keys), social (trading, visits, announcements), leaderboards, anti-exploit rates, QA allow-list, tutorial steps |
| `RarityConfig` | The 10 rarities: tier, color, income/stat/sell multipliers, luck exponent, max upgrade rank, announcement level, reveal effects |
| `MonsterConfig` | All 72 monsters (`M(id, name, rarity, region, element, archetype, abilities, opts)`): income and stats are derived from region scale × archetype unless overridden; evolution, fusion-only and event flags |
| `DiceConfig` | Each dice: cost, currency, base luck, rarity weights, pool, region/rebirth requirement; multi-roll unlocks, auto-roll pacing, free roll, luck soft/hard cap |
| `RegionConfig` | The 9 regions: order, unlock cost/boss/rebirth requirement, recommended power, income/stat scale, dice, material, theme colors |
| `EconomyConfig` | Starting money, currency cap, sell and upgrade formulas, stars, level income, offline earnings, inventory capacity, base cosmetics |
| `RebirthConfig` | Max rebirths, cost curve, required region per rebirth, permanent bonuses, what resets, ascension tree |
| `SkillTreeConfig` | Skill nodes (6 branches + cross-branch), costs, prerequisites, effects, respec fee/cooldown |
| `CombatConfig` | Elements and the effectiveness chart, status effects, archetype base stats, damage/hit/crit constants, energy, turn timeout, XP curve, arena rating |
| `AbilityConfig` | Every ability: power, target, element, cooldown, energy, statuses, heals, shields |
| `EnemyConfig` | Region rosters (regulars and bosses with phases), encounter lists, rewards, drops, AI tuning |
| `EquipmentConfig` | Items: category, rarity, region, stats, set bonuses, compatibility; upgrade costs, luck cap |
| `CraftingConfig` | Materials, consumables (potions, battle items), recipes, special fusions, star/rarity fusion rules, queue size |
| `ChestConfig` | Chests: price, currency, weighted reward pools (shown as odds in-game), open limits |
| `QuestConfig` | Main chain, daily/weekly pools, region and event quests, achievements, daily login calendar, codex milestones |
| `EventConfig` | Live events: schedule (weekly days or fixed UTC window), luck/income/battle multipliers, event dice/chest/quests |
| `MonetizationConfig` | Developer products and game passes (ids from the Creator Dashboard; `0` = disabled) |
| `AssetConfig` | Model folders, model overrides, icon/sound/animation ids (see [ASSET_IMPORT.md](ASSET_IMPORT.md)) |

Global modifier caps (`RollCostReduction` ≤ 0.3, `UpgradeCostReduction` ≤ 0.5, ...) are in
`src/shared/Util/Modifiers.luau` (`CAPS`). Raise them only after re-running `Economy.spec`.

## Common tasks

### Add a monster

```lua
-- MonsterConfig.luau, in the region's section
M("ember_fox", "Ember Fox", "Epic", "Volcano", "Fire", "Speedster", { "quick_jab", "ember_bite", "inferno" }, {
    Description = "Its tail is a little too warm to pet.",
    -- optional: IncomeFactor = 1.1, StatFactor = 0.95, RollWeight = 2, ModelKey = "EmberFox"
})
```

- Region dice pools are built automatically from every rollable monster of that region, so the
  new monster can be rolled immediately if the region's dice weights its rarity.
- Abilities: `[1]` is the basic attack, then specials, and the last one is the ultimate. All
  must exist in `AbilityConfig`.
- Then import the model under its `ModelKey` (default: PascalCase of the id → `EmberFox`).

### Change odds

Edit `DiceConfig` → the dice's `RarityWeights`. Weights are relative. Odds update everywhere,
including the in-game odds table. To change how strongly luck affects a rarity, edit
`RarityConfig.<Rarity>.LuckExponent`. Re-run `RollMath.spec` and `Balance.spec`.

### Retune pacing

The pacing levers, from strongest to weakest:

1. `RegionConfig.<Region>.UnlockCost` and `RebirthConfig.BaseCost` / `Growth`: the coin gates.
2. `DiceConfig.<dice>.Cost`: how fast rolling compounds income (payback time is in BALANCE.md).
3. `EconomyConfig.UpgradeCostSeconds` / `UpgradeCostGrowth`.
4. `RebirthConfig.IncomeBonusPerRebirth`.

Run `BALANCE_WRITE=1 lune run tests/run tests/balance/Balance.spec.luau` and compare the pacing
table. The current tuning gives about 55 min to the first rebirth, about 88 h to Glitch, and
about 142 h to rebirth 12 for an always-online player (about 79 days at 1 h/day).

### Add a region

Add the region to `RegionConfig` (with `Index`, `DiceId`, `MaterialId`, `BossEncounterId =
"<region>_boss"`), a dice in `DiceConfig`, a material in `CraftingConfig.Materials`, a roster in the
`Rosters` table of `EnemyConfig`, and monsters in `MonsterConfig`. WorldBuilder creates the gate and floating
island automatically. `Config.spec` checks all the links.

### Add a live event

```lua
-- EventConfig.luau
winter_2026 = {
    Id = "winter_2026", DisplayName = "Frostfall", Description = "...",
    Schedule = { Kind = "Fixed", StartUtc = 1797638400, EndUtc = 1798848000 },
    LuckMultiplier = 1, IncomeMultiplier = 1.25, BattleCoinMultiplier = 1,
    DiceId = "frost_dice", ChestId = "event_chest", QuestIds = { ... },
    Color = Color3.fromRGB(150, 220, 255), Glyph = "❄",
},
```

Add it to `EventConfig.Order`, add the event dice (with `EventId`) to `DiceConfig`, add event
monsters with `EventId = "winter_2026"`, and add quests to `QuestConfig`. Events turn on and off
from server time. The current Halloween event ends on 2026-11-03 00:00 UTC.

### Set up purchases

Create the products and passes on the Creator Dashboard, then fill in `ProductId` / `GamePassId`
in `MonetizationConfig`. Grants are defined there too. Products are granted only through
`ProcessReceipt`, once per receipt. Pass ownership is checked with MarketplaceService on join and
after a purchase.

### Give QA accounts cheats in live servers

`GameConfig.Cheats.AllowedUserIds = { 12345678 }`. In Studio, cheats are always on. The server
checks every command.
