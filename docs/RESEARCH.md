# What other RNG games do (and what we took)

Three research passes.
- **Pass 1:** the RNG genre in general (roll games, collect-and-hatch, farming).
- **Pass 2:** the closer subgenre, "roll characters that earn money". You roll or spin for units, place them on your base, and they make cash per second.
- **Pass 3:** why games in this style keep players: onboarding, the first minutes, session length and day-1/day-7 return. Sources are Roblox devforum postmortems and retention guides, not individual games.

## Scope and limits

I can't play Roblox games or watch gameplay, so these notes don't cover anything only visible in-game. They come from guides, wikis, store listings and articles. That covered about 20 games, not 50:

- **RNG roll games:** Sol's RNG, Anime Dice, Dungeon RNG, Character RNG, Spin a Kitty, Aura Craft, Slime RNG, Country RNG, Fish an Anime RNG, Car RNG, Weapon Fighting RNG, Tree RNG, Emote RNG, Build a Base RNG
- **Collect-and-hatch / farming games:** Pets Go, Pet Simulator 99, Grow a Garden, Fisch, Anime Vanguards, Steal a Brainrot

Prices and numbers below are snapshots from those sources and change often.

## Pass 3: what keeps players (onboarding and retention)

The devforum threads tell the same story: simulators lose about half of new players in the first 2 minutes when the first action isn't obvious, and lose the rest at the first slow wall. The fixes they report are all small.

| Finding | Source | What we did |
|---|---|---|
| **First reward within seconds.** No reading before the first roll | devforum day-1 retention threads, rolearn first-week guide | ROLL is a big button on screen from spawn (also R key). The first roll auto-places onto your base, so you earn cash before opening any menu. |
| **Point at the next goal, don't lock players in a tutorial** | devforum onboarding threads, Onboard framework release, 3D tutorial-arrow kits | **Guide:** a tip line plus a glowing beam to wherever the current quest happens. It disappears after the first rebirth. |
| **Remove busywork from the core loop** | Anime Dice and Pets Go "equip best" buttons; devforum simulator threads | **⭐ PLACE BEST** fills every slot with your top earners. **Auto-place** (on by default, toggle in Settings) puts each new roll into an empty slot. |
| **Reasons to stay longer this session** | devforum "playtime gift rewards" threads, Pet Simulator / Anime Dice gift timers | **Playtime gifts** at 2, 5, 10, 15, 20, 30, 45 and 60 minutes. A red **!** badge shows when one is ready. |
| **Reasons to return tomorrow** | rolearn 7-day-cliff, creation.dev retention glossary | Already had a daily streak and quests. Added red **!** badges on DAILY so it's noticed. |
| **Social pull** | creation.dev simulator guide, devforum session-time threads | Friend boost (pass 2), plus an **INVITE** button and an optional **group bonus** (+10% luck, needs `GROUP_ID`). |
| **Celebrate milestones loudly** | devforum engagement threads | **Confetti** on quest and milestone rewards; rare rolls already get the reveal cutscene and server announcements. |
| **Pacing: first rebirth fast, then real walls** | creation.dev rebirth glossary, Anime Dice rebirth-timing guides | **Pacing sim** (`tools/headless/pacing.luau`) plays a greedy free player through the real formulas. It found the first rebirth at under 4 minutes, chained rebirths, and floor 3 unreachable under the cash cap. After retuning: first rebirth at about **14 min**, floor 2 at about **2 h**, floor 3 at about **9 h**. |

### Not taken from pass 3

| Idea | Why not |
|---|---|
| **Forced step-by-step tutorial** | Several threads say forced tutorials lose more players than they help in simulators. The guide points but never blocks. |
| **Loading-screen ads / "like the game" prompts at join** | Friction before the first reward. |

## Pass 2: roll-and-earn games

**Games covered:**
- **Spin / roll:** Spin a Baddie, Spin a Soccer Card, Spin a Kitty, Spin a Brainrot, Anime Dice (deeper this time), Become a Billionaire, Tycoon RNG
- **Brainrot games:** Scroll a Brainrot, Steal a Brainrot (again), Plants vs Brainrots, Escape Tsunami for Brainrots, Steal a Baddie, Be a Lucky Block, Survive Lava for Brainrots
- **Card / RNG games:** Anime Card Farm, Anime Card Collection, Unknown RNG

That's about 35 games across both passes. Most guide sites blocked direct page fetches from this session, so details come from search summaries. They often disagreed on exact numbers.

### What they do well

| Idea | Seen in | Taken? |
|---|---|---|
| **Mutations multiply income**; the rarer the mutation, the bigger the multiplier, and weather/events cause special ones | Spin a Soccer Card (Venomous, Blessed, Rainbow, Divine…), Anime Card Farm (Golden 1.5x … Unknow 90x), Grow a Garden / Plants vs Brainrots (weather mutations), Steal a Brainrot (event traits + mutations stack) | **Yes.** <ul><li>Natural Golden 1.5x (1 in 50), Diamond 2x (1 in 250), Rainbow 4x (1 in 1,500)</li><li>8 biome mutations (Wet, Scorched, Shocked, Blooming, Sandy, Auroral, Bloodrot, Starfallen up to 5x) that only roll during their biome</li></ul> |
| **Rerollable traits / grades as the endgame income chase** | Anime Dice (grades D 1.1x → Z+ 25x for 1 Gem; traits Money I–III, Samurai 3x, Shogun 5x, Monarch 8x, Transcendent 15x) | **Yes:** **Traits** (spec's TraitIds) rerolled for **1 Gem**. Money I–III, Power I–III, Samurai 2x, Shogun 3x, Monarch 5x, Transcendent 10x (income and combat). Odds shown before rerolling. |
| **A second soft currency** for rerolls | Anime Dice gems, Spin a Baddie gems | **Yes:** **Gems** from daily rewards, quests, battle wins (+1), boss first clears (+10) and codes. Not sold for Robux (rerolls are random, so that would be another paid random item). |
| **Rebirth requires owning rare characters, not just cash** | Steal a Brainrot (2 Rares for rebirth 1, specific Brainrots later), Spin a Soccer Card (specific cards for Rebirth 4) | **Yes.** Rebirth also needs **2 monsters at a rarity bar** that climbs one tier every 2 rebirths. They are kept, not consumed. |
| **Rebirth unlocks better rolls / higher rarities** | Spin a Baddie (Secret at rebirth 14, Godly at 16…), Spin a Soccer Card packs gated by rebirth | **Yes:** Heaven Die needs Rebirth 2, Cosmic Rebirth 4, Glitch Rebirth 8. |
| **Fuse junk into rarer characters** | Be a Lucky Block fuse machine (4 → higher rarity), Survive Lava for Brainrots (duplicates → rarer variants) | **Yes:** **Fuse Machine**, 5 monsters of one rarity → 1 random monster of the next rarity (Backpack → Select → Fuse Machine). |
| **Friends in server boost income** | Steal a Brainrot (+10% playing with friends) | **Yes:** +10% live income per friend in the server, up to +50%, shown on the HUD. |
| **Scheduled event slot** | Steal a Brainrot "admin abuse" (Saturdays, Taco Tuesday) | **Yes:** **Lucky Hour**, 3x luck Saturdays 18:00–19:00 UTC, plus weekend double income. |
| **Money popping off your units** | Spin a Baddie (walk over the green pad), tycoons generally | **Partly:** floating **+$** popups over your placed monsters every 3 s, plus name/level/income tags. We kept automatic collection instead of walk-to-collect pads (see below). |
| **Offline income** | Spin a Kitty, Become a Billionaire, Scroll a Brainrot, Anime Dice | Already had it (8 h cap, extendable). |
| **Per-unit leveling** | Escape Tsunami for Brainrots (1.25x per level), Anime Dice pad upgrades | Already had it (monster upgrades). |
| **Spending order: fill pedestals → money upgrades → luck → better dice** | Anime Dice guides | Our quest chain already walks players through this order. |

### Not taken from pass 2

| Idea | Why not |
|---|---|
| **Walk-over collect pads + "Auto Collect" pass** (Spin a Baddie, tycoons) | It adds friction to the core loop and would change how income works everywhere. Easy to add later if you want that monetization hook. |
| **Stealing / base locks** (Steal a Brainrot) | The spec forbids other players touching your base. |
| **Conveyor of buyable characters** (Steal a Brainrot) | A whole second acquisition loop. Worth doing as its own feature. |
| **Bank to keep cards through rebirth** (Spin a Soccer Card) | Our rebirth already keeps every monster. |
| **Selling Gems for Robux** | Gems feed random rerolls, so selling them would be more paid random items. |

## Pass 1: general RNG patterns

### Patterns that keep showing up

| Pattern | Seen in | What it is | In Monster Roll |
|---|---|---|---|
| **Luck gamepasses** | Pet Sim 99 (Lucky 2x, Ultra Lucky 5x), Fish an Anime RNG (2x/4x), Country RNG, Car RNG, Weapon Fighting RNG | Permanent luck multiplier, usually 2x for 50–350 R$ and a bigger tier for 800–1,750 R$ | **Lucky 2x** (299), **Super Lucky 3x** (799), stacking to 6x |
| **VIP** | Sol's RNG (x1.2 luck, walk speed, tag; 249 R$), Country RNG, Emote RNG | Small luck + quality of life + a chat/overhead tag | **VIP** 1.2x luck, +4 walk speed, VIP title (249) |
| **Quick / Auto / Multi roll** | Sol's RNG Quick Roll (100), Country RNG Faster Roll, Anime Dice "roll +5 at once", Pet Sim +15 eggs, triple hatch passes | Faster cooldown, AFK rolling, several results per press | **Quick Roll**, **Auto Roll**, **Triple Roll** passes. Auto-roll is also earnable from the Evolution Tree (Auto Pickup) |
| **Potions / timed luck** | Sol's RNG (Fortune, Lucky Potion +100% 60 s), Pets Go (Lucky Potion I–V), Dungeon RNG | Temporary luck multiplier. Also handed out free via codes and dailies | **Luck Potion** product (2x, 15 min), daily day 4, codes |
| **Single-roll luck** | Sol's RNG Heavenly potion (one roll), Pets Go Instant Luck Potions | One very lucky roll | **Lucky Rolls**: banked 10x-luck rolls, sold in 10/100/1000 packs, also from codes. Toggle in Settings |
| **Server luck** | Slime RNG Server Luck x2 (99 R$), Dungeon RNG server boost meter | One purchase boosts everyone in the server, which is social and gets announced | **Server Luck** product (2x for everyone, 15 min, announced) |
| **Free periodic bonus rolls** | Pets Go Golden Die every 10 rolls (x1.5–2), Rainbow every 100 (x5–6.5) | A rhythm that keeps players rolling | **Golden** every 10th roll (2x), **Rainbow** every 100th (5x), shown on the HUD |
| **Biomes / weather** | Sol's RNG biomes (Rainy, Hell, Starfall change the aura table), Grow a Garden weather (server-wide, mutations), Fisch weather | Server-wide timed state that shifts odds; players time potions around it | **Biomes**: 8 weathers each boosting one element (3–5x), world tint, timer, announcement |
| **Rare-roll announcements and cutscenes** | Sol's RNG (global announcements past ~1 in 100M; unique cutscenes with music for the top tier; skip setting for low tiers) | Rarity-scaled spectacle | Server-wide announcement for Mythic+; **cross-server** for Secret+. RollFX spinner, flash and shake; Divine+ cutscene; skip-below setting |
| **Codes** | Anime Dice, Sol's RNG, Dungeon RNG and nearly every RNG game | Free potions, spins and rerolls; a marketing hook | **Codes** tab (`RELEASE`, `LUCKY`, `SPOOKY`), case-insensitive, once each, with expiry |
| **Premium bonus** | Some RNG games (+25% luck for Premium) | Extra luck for Roblox Premium | x1.1 luck (`MonetizationConfig.PREMIUM_LUCK`) |
| **Visible odds** | Sol's RNG ("1 in X" per aura), most RNG games | The odds table is part of the fun | Index shows live "1 in X" including luck, die and biome; the shop shows before/after odds |
| **Base with income pedestals + rebirth floors** | Steal a Brainrot (pedestals earn $/s, rebirth adds slots and a floor) | Very close to our base loop | Already ours. Added **floating name / level / $/s tags** over placed monsters |
| **Pity** | Anime Vanguards (pity counters per trait/unit) | Guaranteed rare after N attempts | Not added yet (see below) |
| **Mutations** | Grow a Garden, Fisch | Random modifiers multiplying value | Our Huge/Monstrous variants fill this role |

## Visuals that recur

- **Roll spinner:** names flick by and slow down. Sellable roll kits advertise a conveyor slow-down, camera shake, blur and a winner flash.
- **Rarity color identity** everywhere: text, outlines, flashes.
- **Escalating spectacle:** small rolls are a toast; rare ones get flash and shake; top tiers get a cutscene and a server-wide or global message. Low tiers can be skipped.
- **World mood changes** with weather or biomes.
- **Big, readable shop tiles:** a chunky icon, a short name and a one-line benefit. Luck items almost always use a **four-leaf clover**. The icons in `assets/shop-icons` follow that style.

## Not adopted, and why

| Idea | Why not |
|---|---|
| Stealing from other bases (Steal a Brainrot) | Our spec says other players must never be able to modify your base. |
| Pity counters | Worth adding later. Any pity rule has to be disclosed alongside the odds. |
| Paid currency packs / skip-rebirth products | Not requested. Easy to add as more `MonetizationConfig.Products` entries. |

## Roblox rules for paid luck

Luck boosts, luck passes and lucky rolls count as **paid random items** under Roblox's policy. What the code does:

- **Odds before purchase:** the actual odds (every rarity, as percentages summing to 100%) show before a purchase. The shop's odds panel shows "now → with this item".
- **Regional restrictions:** players whose `PolicyService:GetPolicyInfoForPlayerAsync(...).ArePaidRandomItemsRestricted` is true can't buy paid luck items, and paid luck effects aren't applied for them. Free luck still works for them: codes, daily, quests, Golden/Rainbow rolls, biomes.

This cloud session couldn't open Roblox's documentation site directly; the rules above come from search summaries of it. Have someone read the current [paid random items guidelines](https://create.roblox.com/docs/production/monetization/paid-random-items) before launch.

Spec §3.4 originally said the premium shop must never sell randomized paid rewards or let purchases affect competitive results. Selling luck is a deliberate change requested by the project owner. Leaderboards stay as they are: earnings, rebirths, unique monsters and battle progress.

## Sources

### Pass 3

- [Day-1 retention: losing half of players in under 2 minutes (devforum)](https://devforum.roblox.com/t/my-day-1-retention-is-awful-23-losing-half-my-players-in-under-2-minutes-what-am-i-doing-wrong-with-onboarding/4186434)
- [Improving new user engagement (devforum)](https://devforum.roblox.com/t/improving-new-user-engagement-on-my-game/2947546)
- [Increasing retention and engagement in a simulator (devforum)](https://devforum.roblox.com/t/how-to-increase-retention-engagement-etc-in-a-simulator/3292053)
- [Increasing session time and retention (devforum)](https://devforum.roblox.com/t/how-could-we-increase-session-time-and-retention-in-our-game/3562509)
- [Suggestions for session time and retention (devforum)](https://devforum.roblox.com/t/suggestions-for-increasing-session-time-and-retention/3842442)
- [Tips on retention and progression (devforum)](https://devforum.roblox.com/t/i-need-tips-on-making-my-game-retention-and-progression-better/3868947)
- [Low retention and session time (devforum)](https://devforum.roblox.com/t/game%E2%80%99s-retention-and-average-session-time-extremely-low/4269329)
- [Qualified play-through rate (devforum)](https://devforum.roblox.com/t/retention-qualified-playtroughrate-killing-my-game/4558372)
- [Playtime gift rewards (devforum)](https://devforum.roblox.com/t/help-with-playtime-gift-rewards/2644815)
- [Onboard tutorial framework (devforum)](https://devforum.roblox.com/t/release-onboard-%E2%80%94-modern-lightweight-onboarding-tutorial-framework/4751478)
- [Auto and triple hatch (devforum)](https://devforum.roblox.com/t/how-to-correctly-introduce-an-auto-hatch-and-triple-hatch-system-in-this-script/2059150)
- [First-week retention optimization (rolearn)](https://rolearn.dev/guidance/first-week-retention-optimization)
- [Player engagement and retention (rolearn)](https://rolearn.dev/guidance/player-engagement-retention)
- [The 7-day retention cliff (rolearn)](https://rolearn.dev/insights/player-retention-7day-cliff)
- [Roblox simulator game guide (creation.dev)](https://www.creation.dev/blog/roblox-simulator-game-guide)
- [Player retention (creation.dev)](https://www.creation.dev/glossary/player-retention)
- [Rebirth (creation.dev)](https://www.creation.dev/glossary/rebirth)

### Pass 2

- [Spin a Soccer Card beginner's guide (Deltia's)](https://deltiasgaming.com/spin-a-soccer-card-a-beginners-guide-roblox/)
- [Spin a Soccer Card wiki](https://spinasoccercard.wiki/)
- [Spin a Soccer Card (Rolimons)](https://www.rolimons.com/game/112490729816320)
- [Spin a Soccer Card April 2026 update (earnaldo)](https://earnaldo.com/blog/spin-a-soccer-card-update-april-2026)
- [Spin a Baddie wiki](https://spin-a-baddie.fandom.com/wiki/Spin_a_baddie_Wiki)
- [Spin a Baddie money guide (Deltia's)](https://deltiasgaming.com/roblox-spin-a-baddie-money-guide/)
- [Spin a Baddie rebirth (Pocket Tactics)](https://www.pockettactics.com/spin-a-baddie-rebirth)
- [Spin a Baddie pets (Pocket Tactics)](https://www.pockettactics.com/spin-a-baddie-pets)
- [Spin a Brainrot (Rolimons)](https://www.rolimons.com/game/112371649846345)
- [Spin a Kitty codes and overview (progameguides)](https://progameguides.com/roblox/spin-a-kitty-codes/)
- [Anime Dice income guide (allthings.how)](https://allthings.how/anime-dice-on-roblox-how-to-build-income-fast/)
- [Anime Dice traits tier list (allthings.how)](https://allthings.how/anime-dice-traits-tier-list/)
- [Anime Dice grades (bloxodes)](https://bloxodes.com/articles/anime-dice-grades-guide-boost-your-units-income)
- [Become a Billionaire codes (robloxden)](https://robloxden.com/game-codes/become-a-billionaire)
- [Tycoon RNG (earnaldo)](https://earnaldo.com/blog/tycoon-rng)
- [Scroll a Brainrot guide](https://ofzenandcomputing.com/how-to-play-scroll-a-brainrot/)
- [Plants vs Brainrots beginner's guide (Sportskeeda)](https://www.sportskeeda.com/roblox-news/plants-vs-brainrots-a-beginner-s-guide)
- [Plants vs Brainrots mutations (Deltia's)](https://deltiasgaming.com/?p=356749)
- [Escape Tsunami for Brainrots base upgrades (allthings.how)](https://allthings.how/escape-tsunami-for-brainrots-base-upgrades-how-slots-floors-and-rebirths-really-fit-together/)
- [Escape Tsunami for Brainrots rebirths (allthings.how)](https://allthings.how/how-rebirth-works-in-escape-tsunami-for-brainrots-all-20-levels/)
- [Anime Card Farm mutations (progameguides)](https://progameguides.com/roblox/anime-card-farm-mutations-guide/)
- [Anime Card Collection mutations (progameguides)](https://progameguides.com/roblox/anime-card-collection-mutations-guide/)
- [Steal a Brainrot traits (Deltia's)](https://deltiasgaming.com/?p=306346)
- [Steal a Brainrot admin abuse (Sportskeeda)](https://www.sportskeeda.com/roblox-news/when-admin-abuse-steal-brainrot-august-12-2025)
- [Be a Lucky Block fuse machine](https://findingdulcinea.com/be-a-lucky-block-fuse-machine-roblox-guide/)
- [Survive Lava for Brainrots fuse machine](https://www.rosenberryrooms.com/survive-lava-for-brainrots-fuse-machine-updater/)

### Pass 1

- [Sol's RNG luck guide (itemlevel)](https://itemlevel.net/sols-rng-how-to-get-more-luck-guide/)
- [Sol's RNG luck (progameguides)](https://progameguides.com/roblox/how-to-get-more-luck-in-roblox-sols-rng/)
- [Sol's RNG buffs and potions (Sportskeeda)](https://sportskeeda.com/roblox-news/sol-s-rng-all-buffs-crafting-items-potions)
- [Sol's RNG aura tiers and cutscenes (allthings.how)](https://allthings.how/sols-rng-aura-tier-list-every-rarity-and-drop-rate-ranked/)
- [Sol's RNG store listing (Rolimons)](https://www.rolimons.com/game/15532962292)
- [Anime Dice upgrade and dice guide (allthings.how)](https://allthings.how/anime-dice-best-dice-upgrade-priority-and-rebirth-tips/)
- [Anime Dice Update 8 (allthings.how)](https://allthings.how/anime-dice-update-8-genesis-trait-omega-grade-and-quirks-explained/)
- [Steal a Brainrot strategy and rebirth guide (playnews)](https://www.playnews.gg/en/guides/steal-a-brainrot-roblox-the-complete-strategy-rebirth-and-tier-list-guide-for-july-2026)
- [Steal a Brainrot rebirth 16 (Sportskeeda)](https://www.sportskeeda.com/roblox-news/steal-brainrot-rebirth-16-update-guide)
- [Pets Go rolling wiki](https://breezewiki.discard.no/pets-go/wiki/Rolling)
- [Pets Go rarer pets (progameguides)](https://progameguides.com/roblox/how-to-get-rarer-pets-in-pets-go/)
- [Pet Simulator 99 gamepasses (progameguides)](https://progameguides.com/roblox/all-pet-simulator-99-gamepasses-are-they-worth-it-roblox/)
- [Pet Simulator 99 gamepass tier list (Deltia's)](https://deltiasgaming.com/?p=397831)
- [Grow a Garden weather (rblxguide)](https://rblxguide.com/games/grow-a-garden/weather)
- [Grow a Garden weather events (fdaytalk)](https://www.fdaytalk.com/grow-a-garden-weather-events/)
- [Fisch mutations (allthings.how)](https://allthings.how/fisch-mutations-explained-every-multiplier-and-how-to-trigger-them/)
- [Fisch weather and admin events (Beebom)](https://beebom.com/fisch-weather-and-admin-events/amp/)
- [Anime Vanguards units and pity (allthings.how)](https://allthings.how/anime-vanguards-on-roblox-how-to-get-and-equip-units/)
- [Anime Vanguards traits (SeeMeta)](https://seemeta.com/en/anime-vanguards/traits)
- [Best Roblox RNG games 2026 (The Spike)](https://www.thespike.gg/roblox/best-roblox-games/best-rng-games)
- [Slime RNG luck (allthings.how)](https://allthings.how/how-to-increase-luck-in-slime-rng-on-roblox/)
- [Dungeon RNG on Roblox](https://www.roblox.com/games/17534163435/Dungeon-RNG)
- [Country RNG store (Rolimons)](https://www.rolimons.com/game/17153707455)
- [Fish an Anime RNG store (Rolimons)](https://www.rolimons.com/game/74729868188364)
- [2x Luck pass example (Rolimons)](https://www.rolimons.com/gamepass/1910704772)
- [Emote RNG store wiki](https://unofficial-emote-rng-rblx.fandom.com/wiki/Store)
- [RNG roll kit feature list (BuiltByBit)](https://builtbybit.com/resources/roblox-rng-roll-system.110610/)
- [Roblox paid random items guidelines](https://create.roblox.com/docs/production/monetization/paid-random-items)
- [PolicyService API reference](https://create.roblox.com/docs/en-us/reference/engine/classes/PolicyService.md)
- [DevForum: Policy info for player](https://devforum.roblox.com/t/policy-info-for-player/1926774)
