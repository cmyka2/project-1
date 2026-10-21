# Formulas

Every gameplay formula, with the module that implements it. Names in `Code` refer to config
fields. The same shared modules run on the server (authoritative) and on the client (display
only), so what the UI shows is exactly what the server computes.

## Rolling

### Luck (`Util/Modifiers.luckFor`, `Util/RollMath.effectiveLuck`)

```
additive = Luck (skills, ascension, rebirths, passes) + EquipmentLuck (items worn by the battle team)
           + HighTierLuck (only for dice with Order >= Luck.HighTierFromOrder, i.e. Volcano and above)
raw      = Dice.BaseLuck * (1 + additive) * BoostLuckMult (strongest active potion) * EventLuckMult
```

Soft cap (`DiceConfig.Luck`):

```
effective = raw                                           if raw <= SoftCapStart (4)
          = SoftCapStart + (raw - SoftCapStart) ^ 0.6     otherwise
effective = clamp(effective, 1, HardCap (20))             (NaN, 0 or negative -> 1)
```

Modifier caps (`Util/Modifiers` `CAPS`): `EquipmentLuck` ≤ `EquipmentConfig.LuckCap`, rebirth luck ≤
`RebirthConfig.LuckBonusCap`, `RollCostReduction` ≤ 0.3, `UpgradeCostReduction` and
`ServiceCostReduction` ≤ 0.5, `RebirthKeepCoins` ≤ 0.25, `CritChance` ≤ 0.5 (from bonuses),
`DamageReduction` ≤ 0.5, `StatusResist` ≤ 0.6.

### Odds (`RollMath.rarityOdds`, `RollMath.roll`)

Two stages, both on the server:

1. **Rarity.** For each rarity on the dice that has at least one monster in the dice's pool:
   ```
   w'(r) = Dice.RarityWeights[r] * effective ^ Rarity.LuckExponent
   P(r)  = w'(r) / Σ w'
   ```
   `LuckExponent` is 0 for Common (luck never makes Common more likely), rising to 1 for Legendary
   and above. Higher luck therefore shifts weight towards rarer tiers, but because every weight
   stays finite, nothing is ever guaranteed. Invalid weights (0, negative, NaN, inf) are ignored.
2. **Monster.** Within the chosen rarity, pick a monster by `MonsterDef.RollWeight`.

The dice panel shows exactly `P(r)` at the player's current effective luck (`1 in N` = `1/P`).

Roll cost: `max(1, round(Dice.Cost * (1 - RollCostReduction)))`.

## Base and income

### Slots and floors (`Util/BaseLayout`)

```
totalSlots(rebirths) = 5 + rebirths
floorCount(rebirths) = min(3, 1 + floor(rebirths / 6))      -> floor 2 at rebirth 6, floor 3 at rebirth 12
slots per floor      = 1 floor : all slots
                       2 floors: 5 / rest
                       3 floors: 5 / 6 / rest
```

Slot ids `1..totalSlots` never change. When a floor unlocks, slots after the fifth (then after the
eleventh) move to the new floor together with their monsters.

### Monster income (`Util/StatMath.monsterIncome`)

```
income = BaseIncomePerSecond * Rarity.IncomeMultiplier
       * (1 + (Level - 1) * LevelIncomeBonusPerLevel)
       * (1 + Upgrade * UpgradeIncomeBonusPerLevel * (1 + UpgradeEffectiveness))
       * (1 + Stars * StarIncomeBonus)
       * (1 + equipment IncomePct)
```

### Total income (`StatMath.totalIncome`, `Modifiers.incomeMultiplier`)

```
rate = Σ income(placed monster, each counted once) * (1 + Income) * BoostIncomeMult * EventIncomeMult
```

The global multiplier is applied **once** to the sum, never per monster. The server's income tick
(`TycoonService`, every `IncomeTickSeconds`) is the only place coins are earned passively.

### Offline income (`Server/Modules/OfflineIncome`)

```
away      = now - LastSeen                  (0 if under OfflineMinSeconds or negative)
counted   = min(away, cap)    cap        = min(OfflineMaxCapHours,  OfflineBaseCapHours  + OfflineCapHours) h
coins     = floor(permanentRate * counted * efficiency)
                              efficiency = min(OfflineMaxEfficiency, OfflineBaseEfficiency + OfflineEfficiency)
permanentRate = rate without BoostIncomeMult and EventIncomeMult
```

This is paid inside the same atomic DataStore write that claims the session lock and moves
`LastSeen`, so it can't be paid twice.

## Costs and values

| What | Formula |
|---|---|
| Monster upgrade | `BaseIncome * Rarity.IncomeMultiplier * UpgradeCostSeconds * UpgradeCostGrowth ^ Upgrade * (1 - UpgradeCostReduction)` (reduction ≤ 0.5) |
| Max upgrade rank | `Rarity.MaxUpgradeLevel` |
| Sell value | `SellDice.Cost * SellBaseFraction * Rarity.SellMultiplier / FloorSellMultiplier * (1 + Stars * SellPerStar) * (1 + SellValue) + UpgradeRefund` |
| Upgrade refund on sale | `SellUpgradeRefund * Σ upgrade costs at the maximum reduction`, which is never more than what was paid |
| Region unlock | `Region.UnlockCost` coins, plus previous boss defeated and `RequiredRebirths` |
| Rebirth n → n+1 | `RebirthConfig.BaseCost * Growth ^ n`, requires `RequiredRegionByRebirth[n+1]` unlocked |
| Skill node level L → L+1 | `round(BaseCost * CostGrowth ^ L)` gems |
| Ascension node level L → L+1 | `BaseCost + CostPerLevel * L` ascension points |
| Equipment upgrade | `UpgradeBaseCoins[rarity] * UpgradeCoinGrowth ^ Level` coins (service discount applies) + `(Level + 1) * UpgradeMaterialPerLevel` region material |
| Star fusion to star s | `DuplicatesPerStar[s]` copies + `target sell value * CoinsPerStarMultiplier * s` coins |
| Rarity fusion | `InputCount` same-rarity monsters from one region + `regionDice.Cost * CoinsDiceCostMultiplier * tier` coins + `tier * MaterialPerTier` region material, giving one random monster of the next rarity from that region's pool |
| Service discount | `round(base * (1 - ServiceCostReduction))` (≤ 0.5): coin costs of crafting, fusion, evolution and equipment upgrades |

`SellDice` is the monster's region dice, or its event dice for event monsters.
`FloorSellMultiplier` is the `SellMultiplier` of the most common rarity on that dice, so the
commonest result of any dice sells for `SellBaseFraction` (12%) of its cost.

**Economy invariants**, asserted in `tests/unit/Economy.spec.luau`:
- The expected sell value of a roll is below 90% of the discounted roll cost, for every dice, at
  luck 1 and at the hard cap, with every sell bonus maxed. Rolling then selling never makes money.
- Upgrading then selling never returns more than the upgrade cost.
- Rarity fusion never produces more sell value than its inputs plus coins.

## Movement (`Util/Modifiers.walkSpeed`, `sprintSpeed`, `jumpPower`)

```
walk speed   = Movement.BaseWalkSpeed (32) * (1 + WalkSpeed)       (Mobility skills)
sprint speed = walk speed * Movement.SprintMultiplier (1.5)         (48 with no bonuses)
jump power   = Movement.BaseJumpPower (50) * (1 + JumpPower)
```

The server sets walk speed and jump power on the character; the client switches to sprint speed
while sprinting. `Config.spec` checks that the fastest possible sprint (every walk-speed bonus
maxed) stays well under `AntiExploit.MaxSpeedStudsPerSecond`.

## Rebirth

On rebirth, what `RebirthConfig.Reset` lists is reset (by default: coins, keeping
`RebirthKeepCoins` ≤ 25%, and monster upgrade ranks). The player gains:

```
Income  += IncomeBonusPerRebirth (0.35) per rebirth
Luck    += LuckBonusPerRebirth (0.02) per rebirth, up to LuckBonusCap (0.4)
AscensionPoints += AscensionPointsPerRebirth (+ AscensionMilestoneBonus every 5th)
Gems    += GemsPerRebirth * newCount
slots   += 1 (floors per BaseLayout)
```

## Combat (`Server/Modules/BattleEngine`, `Util/StatMath`)

### Stats

```
monster stat = Base * Rarity.StatMultiplier * (1 + 0.06 * (Level - 1)) * (1 + UpgradeStatBonusPerLevel * Upgrade)
             * (1 + StarStatBonus * Stars) * (1 + equipment %) * (1 + skill/ascension %)
enemy stat   = Archetype base * Region.StatScale * Enemy.PowerFactor * (1 + 0.06 * (Level - 1))   (health also * HealthFactor)
power        = (0.2 * MaxHealth + 2.2 * Attack + 1.6 * Defense + 0.8 * Speed) * (1 + CritChance * (CritDamage - 1))
```

`Region.RecommendedPower` is kept within ±35% of that region's boss encounter power
(`tests/balance/Balance.spec.luau`).

### Turn order

Each round, living units act in order of effective Speed (`Speed * (1 + speed modifiers)`). Ties
go to the player side first, then the lower slot. A battle longer than `MaxRounds` (40) is a
defeat.

### Hit chance

```
hit = clamp(Ability.Accuracy * Accuracy * (1 + accuracy mods) - Evasion * (1 + evasion mods), 0.05, 1)
```

### Damage

```
atk     = Attack * (1 + attack mods)            def = Defense * (1 + defense mods) * (1 - DefensePierce)
damage  = Ability.Power * atk * atk / (atk + def * DefenseWeight)
        * ElementEffectiveness        (1.5 super effective, 0.67 resisted, 1 neutral)
        * (1 + ElementDamage)         if the ability's element is the attacker's own
        * CritDamage                  on a crit (chance = CritChance + Ability.CritBonus, ≤ 0.75)
        * (1 + UltimateDamage)        for ultimates
        * max(0.25, 1 + DamageTaken modifiers)
        * (1 - DamageReduction (≤ 0.75)) * (1 - ElementResist (≤ 0.5))
        * uniform(VarianceMin 0.92, VarianceMax 1.08)
damage  = clamp(floor(damage), 1, 1e15)        (0 only for configured immunities)
```

Shields absorb damage before health. Status application chance is
`Ability chance * (1 - StatusResist (≤ 0.8))`. Bosses get +0.25 status resist.

### Energy and ultimates

Energy (max 100) is gained from basic attacks (+30), specials (+15), defending (+20) and taking
damage (+8). An ultimate needs its `EnergyCost` and resets energy to 0. Abilities have per-unit
cooldowns.

### Experience

```
XP to go from level L to L+1 = floor(40 * L ^ 1.6)          max level 60
battle XP per team member = Encounter.RewardXp * (1 + XpGain)    (20% of RewardXp on defeat)
```

### Arena (Elo)

```
expected = 1 / (1 + 10 ^ ((opponent - rating) / 400))
rating  += round(32 * (result - expected)),  result = 1 win / 0 loss,  rating ≥ 0
```

Win reward: `max(regionScale * 200, income/s * ArenaRewardCoinsSeconds)` coins times battle-coin
multipliers, plus `ArenaRewardGems`.

## Chests

Rewards are drawn on the server from the chest's weighted pool. `P(entry) = Weight / Σ Weight` is
the chance shown in the chest UI before buying. Entries marked `Scaled` multiply their coin range
by the player's region scale.
