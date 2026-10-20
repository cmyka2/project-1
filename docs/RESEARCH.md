# What other RNG games do (and what we took)

## Scope and limits

I can't play Roblox games or watch gameplay, so these notes don't cover anything only visible in-game. They come from guides, wikis, store listings and articles. That covered about 20 games, not 50:

- **RNG roll games:** Sol's RNG, Anime Dice, Dungeon RNG, Character RNG, Spin a Kitty, Aura Craft, Slime RNG, Country RNG, Fish an Anime RNG, Car RNG, Weapon Fighting RNG, Tree RNG, Emote RNG, Build a Base RNG
- **Collect-and-hatch / farming games:** Pets Go, Pet Simulator 99, Grow a Garden, Fisch, Anime Vanguards, Steal a Brainrot

Prices and numbers below are snapshots from those sources and change often.

## Patterns that keep showing up

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
