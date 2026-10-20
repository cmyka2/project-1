# MASTER DEVELOPMENT PROMPT — MONSTER ROLL: RISE OF THE MYTHICS
## Complete Roblox Studio Game Implementation

You are a senior Roblox game developer, Luau programmer, gameplay systems engineer, UI designer, and technical architect.

Your task is to build a complete, playable, multiplayer Roblox game called **Monster Roll: Rise of the Mythics** inside the existing Roblox Studio project.

This is a real implementation task, not a brainstorming exercise. Create the scripts, modules, UI, world interactions, data systems, gameplay logic, and connections required for the game to function.

We already have the 3D models and other assets for the game, but they have not all been imported into Roblox Studio yet. Do not assume that every model is already available. Build the complete underlying systems first, create temporary placeholder assets when necessary, and make it easy to connect our actual models later.

Do not stop after generating a plan or a few example scripts. Work through implementation in manageable stages until the core game is playable and all major systems are connected.

---

# 1. NON-NEGOTIABLE DEVELOPMENT RULES

## 1.1 Inspect the existing project first

Before making changes:

1. Inspect the current Roblox Studio project structure.
2. Identify existing scripts, ModuleScripts, RemoteEvents, RemoteFunctions, models, folders, UI, and workspace objects.
3. Identify any existing systems that can be reused.
4. Do not delete or overwrite existing assets or working systems without understanding their purpose.
5. Create an implementation plan based on the actual project structure.
6. Build an asset registry for the models that have already been imported.
7. Record missing assets and provide a clean way to connect them later.

If a model is missing, the corresponding gameplay system must still function using a temporary placeholder.

Never invent an asset path and assume it exists. Validate asset references at runtime.

## 1.2 Use modular Luau architecture

Do not place the entire game in one giant script.

Separate the game into logical services, modules, and controllers. Each system should have a clear responsibility and a defined interface.

Use:

- ServerScriptService for authoritative server logic.
- ReplicatedStorage for shared modules, configurations, and remote definitions.
- StarterPlayerScripts for client controllers.
- StarterGui for UI templates when appropriate.
- ServerStorage for server-only templates and sensitive data.
- Workspace for the island, interactable world objects, bases, battle arenas, and active world models.
- DataStoreService for persistent player data.
- CollectionService tags or an equivalent registry for identifying interactable objects.
- Attributes for simple replicated object metadata when useful.

Do not put server-only secrets, authoritative currency calculations, or trusted roll results in client-controlled code.

Use typed Luau where practical. Give modules clear names, validate arguments, handle errors, and avoid circular dependencies.

## 1.3 Build in stages

Implement in this order:

1. Project structure and configuration.
2. Island generation and asset registry.
3. Player data, saving, and loading.
4. Monster definitions, inventory, and RNG.
5. Base slots and income.
6. Dice shop and progression.
7. Upgrade tree.
8. Rebirth and multiple floors.
9. Chests, equipment, fusion, and crafting.
10. Turn-based battle system.
11. UI and world interactions.
12. Multiplayer synchronization, security, and performance.
13. Testing, debugging, and final integration.

At the end of each stage, verify that it works before moving on.

Do not claim that a system is complete unless it has actually been implemented and tested or its remaining limitations are explicitly documented.

---

# 2. CORE GAME CONCEPT

The game is a monster-collecting RNG simulator combined with a tycoon, incremental progression game, and turn-based tactical RPG.

The player starts with a small base on a square island.

They roll dice to obtain monster characters. Every monster has a rarity, model, income value, health, damage, abilities, and optional traits.

Players store their monsters in a backpack, place selected monsters on their base to earn money per second, upgrade their economy, purchase better dice, collect gear from chests, and battle enemies in themed regions.

Eventually, players rebirth, gain permanent progression benefits, expand their base, unlock additional floors, and pursue the rarest monsters.

All major systems must connect to one another.

For example:

- Rolling adds a monster to inventory.
- Inventory allows the player to place that monster at their base.
- Placing it increases income.
- Income purchases dice and monster upgrades.
- Better dice unlock stronger monster pools.
- Combat rewards provide gear and crafting materials.
- Gear improves combat stats and may also improve income.
- Skill-tree upgrades affect rolling, income, movement, and combat.
- Rebirth resets specified progression while preserving permanent rewards.
- Additional base slots let players earn income from more monsters.

Do not implement systems as isolated demonstrations. Connect them through shared data, configurations, and services.

---

# 3. WORLD DESIGN: SQUARE STUD ISLAND

Build a large square island in the ocean, using the classic Roblox stud-built aesthetic.

The island should have a flat, readable central plaza, raised edges, grass terrain, studded construction blocks, paths, lamps, fences, decorative trees, and water surrounding the island.

The island is divided into five major zones:

1. Central plaza.
2. Left player-base district.
3. Right player-base district.
4. Top-edge shop district.
5. Bottom-edge shop and feature district.

The two side edges are reserved for player bases. The top and bottom edges contain shops, services, and progression features.

## 3.1 Central plaza

Place a large, visually impressive monster statue in the center of the island.

The statue should sit on a circular pedestal with surrounding lamps, landscaping, and a broad stone plaza.

The center should contain:

- Main statue.
- Central fountain or energy ring.
- Main spawn location.
- Main navigation signs.
- Decorative benches and planters.
- Clear paths leading toward all four edges.
- A central information board.
- An optional tutorial guide NPC.

The statue should be a configurable asset so our actual statue model can replace the placeholder later.

Do not block paths with decoration. Players must be able to navigate around the plaza easily.

## 3.2 Left and right base districts

Create two visually distinct base districts on opposite sides of the island.

Use a blue theme for the left district and a red theme for the right district, but allow the color scheme to be changed through configuration.

Each district contains individual player plots.

Each plot needs:

- A unique plot identifier.
- An owner UserId.
- A floor system.
- Monster display slots.
- A plot entrance.
- A base upgrade interaction.
- A clearly visible owner sign.
- A monster placement interface.
- A money-per-second display.
- A rebirth and floor information display.

A player must only be able to modify their own base.

Do not assign a player a plot already owned by another player.

If a district is full, allocate another valid plot if available or inform the player that no plot is currently available.

Never let a client select another player's base as their own.

## 3.3 Base floors

Players begin with five total monster slots.

Each rebirth grants one additional slot.

At rebirth 6, unlock the second floor.

At rebirth 12, unlock the third floor.

The maximum number of floors is three.

The floor count is:

Floors = min(3, 1 + floor(RebirthCount / 6))

Total slots = 5 + RebirthCount

At rebirth 0, the player has five slots on floor 1.

At rebirth 6, the player has eleven total slots across two floors.

At rebirth 12, the player has seventeen total slots across three floors.

Distribute slots across the unlocked floors as evenly as practical, with the first floor retaining its original five slots. For example, floors 2 and 3 each receive the six slots unlocked by their respective milestones, with later rebirth slots assigned to the current highest floor.

Create a floor selector or elevator interface so the player can move between floors.

Floor unlocking must be handled by the server.

If actual multi-story models are not available, generate temporary platforms, stairs, and slot markers.

## 3.4 Top-edge shop district

Build clearly separated shop buildings for:

- Dice Shop.
- Chest Shop.
- Upgrade Tree.
- Rebirth Altar.
- Premium and Cosmetics Shop.

Each shop must have a recognizable building silhouette, sign, entrance, interaction prompt, and corresponding UI panel.

The Premium and Cosmetics Shop must never sell randomized paid rewards or allow paid purchases to manipulate competitive results unfairly.

## 3.5 Bottom-edge feature district

Build:

- Summoning and rolling station.
- Monster Codex and collection index.
- Leaderboard station.
- Daily Rewards building.
- Event Portal.
- Battle Portal.
- Equipment Forge.
- Crafting and Fusion Station.

Some services may share a building if space is limited, but their UI and interactions must remain distinct.

## 3.6 Procedural layout and asset placeholders

Create a configurable world layout module with coordinates, sizes, colors, and asset references.

Do not scatter hardcoded positions across many scripts.

Provide an editor-friendly way to configure:

- Island dimensions.
- District boundaries.
- Shop positions.
- Base plot positions.
- Statue position.
- Spawn locations.
- Portal locations.
- Decoration density.
- Path widths.

Use anchored static geometry and avoid unnecessary physics calculations.

If our models are not imported yet, generate simple temporary buildings and signs with Parts or Models. Keep placeholders clearly labeled so they can be replaced later.

---

# 4. ASSET REGISTRY AND MODEL INTEGRATION

Create an AssetRegistry module.

It should provide a single source of truth for all model references.

Organize asset categories for:

- Monsters.
- Dice.
- Shops.
- Bases.
- Statues.
- Chests.
- Weapons.
- Armor.
- Accessories.
- Relics.
- Battle arenas.
- Enemies.
- Bosses.
- UI icons.
- Sounds.
- Particles.
- Animations.
- Portals.

Each registry entry should contain a stable identifier and, when available, the model reference.

Example conceptual structure:

MonsterModels:
- moss_goblin
- meadow_slime
- frostfang
- solarius
- null_0

DiceModels:
- grassland_die
- forest_die
- desert_die
- mountain_die
- volcano_die
- cave_die
- heaven_die
- cosmic_die
- glitch_die

Do not rely on display names as unique identifiers.

Create functions such as:

- GetAsset(category, assetId)
- HasAsset(category, assetId)
- CreateAsset(category, assetId, parent)
- RegisterAsset(category, assetId, instance)
- ValidateRegistry()

When an asset is missing, return a safe placeholder or a clear error message. Do not crash the entire game because one model has not been imported.

Allow models to be registered through a configuration table or a dedicated folder structure.

For monster models, validate that the model has a usable PrimaryPart or another valid pivot setup. Handle models without Humanoids if they are intended to be decorative or non-character entities.

Do not assume that every monster needs a Humanoid. Use a consistent model wrapper that supports both rigged characters and static display models.

For each imported monster, allow configuration of:

- Display name.
- Rarity.
- Base income.
- Base HP.
- Base damage.
- Speed.
- Element.
- Combat role.
- Animation references.
- Ability identifiers.
- Icon or viewport preview.

---

# 5. PLAYER DATA AND PERSISTENCE

Create a DataService that owns the player's persistent data.

Use DataStoreService with safe retry handling, schema versions, and server-side validation.

Do not let clients directly write saved data.

## 5.1 Player data schema

Use a versioned schema with fields similar to:

- SchemaVersion.
- Cash.
- LifetimeEarnings.
- RebirthCount.
- AscensionPoints.
- PurchasedDice.
- SelectedDie.
- MonsterInventory.
- EquippedGear.
- PlacedMonsters.
- UnlockedFloors.
- SkillTreeNodes.
- CollectionDiscoveries.
- BattleTeams.
- BattleProgress.
- CraftingMaterials.
- CompletedQuests.
- DailyRewardState.
- UnlockedRegions.
- CosmeticUnlocks.
- Settings.

Monster instances need unique instance IDs.

A monster definition ID identifies the monster type. An instance ID identifies the specific copy owned by a player.

Store monster instance data such as:

- InstanceId.
- MonsterId.
- Level.
- FusionRank.
- TraitIds.
- EquippedGearIds.
- CurrentExperience.
- Favorite status.
- Creation timestamp if useful.

Avoid saving Roblox Instance objects, Models, functions, or other unserializable data.

## 5.2 Saving requirements

Implement:

- Player data loading when the player joins.
- Safe defaults for new players.
- Migration for older schema versions.
- Periodic autosaving.
- Saving when the player leaves.
- Best-effort saving during server shutdown.
- Retry logic for transient DataStore failures.
- Protection against concurrent save conflicts.
- Data loss prevention and useful server logs.

Use UpdateAsync or another appropriate safe write pattern.

Do not overwrite valid saved data with a default profile if loading fails.

If the player's data fails to load, do not let them play a normal save session that might overwrite their existing profile. Show a loading or retry state and handle the failure safely.

Use session locking or an equivalent mechanism to reduce the chance of two servers modifying the same player profile simultaneously.

Use a tested, well-defined approach for handling temporary DataStore outages.

## 5.3 Economy precision

Choose one currency representation and use it consistently.

If ordinary numbers are used for the initial game, impose reasonable upper bounds and validate all calculations.

If the economy eventually exceeds safe numeric precision, implement a structured large-number representation or a carefully designed currency scaling system.

Do not use client-displayed abbreviated values such as "$5B" as the actual saved currency value.

All authoritative currency changes must go through EconomyService.

## 5.4 Persistence rules

The following should normally persist through rebirth:

- Monster collection.
- Protected monster copies.
- Gear inventory.
- Collection discoveries.
- Permanent skill nodes if designated permanent.
- Ascension Points.
- Cosmetic unlocks.
- Rebirth count.

Regular cash, purchased dice, temporary progression, and other resettable fields should follow a clearly defined rebirth policy.

Make the reset policy explicit in a RebirthConfig module.

---

# 6. MONSTER DEFINITIONS AND RARITY SYSTEM

Create a central MonsterConfig module.

Each monster definition should include:

- Unique ID.
- Display name.
- Rarity.
- Base roll weight.
- Base income per second.
- Base health.
- Base damage.
- Speed.
- Element.
- Role.
- Passive ability.
- Active abilities.
- Model asset ID.
- Icon asset ID.
- Lore description.
- Fusion rules.
- Optional special traits.

Initial example monsters:

Moss Goblin:
- Common.
- Base income: $1/s.
- Basic melee attacker.
- Nature element.

Meadow Slime:
- Common.
- Base income: $2/s.
- Balanced starter monster.
- Nature element.

Rockling:
- Common.
- Base income: $3/s.
- Defensive monster.
- Earth element.

Frostfang:
- Epic.
- Base income: $30/s.
- Fast attacker with a freezing skill.
- Water or Ice element.

Solarius:
- Mythic.
- Base income: $1,000/s.
- Powerful fire or light attacker.

NULL-0:
- Glitched.
- Base income: a configurable high-end value.
- Unique reality-distortion abilities.

These are example definitions, not the complete monster roster.

Create data-driven definitions so new monsters can be added without rewriting the RNG or inventory systems.

## 6.1 Rarity tiers

Support:

- Common.
- Uncommon.
- Rare.
- Epic.
- Legendary.
- Mythic.
- Divine.
- Celestial.
- Transcendent.
- Eternal.
- Secret.
- Glitched.

Every rarity should have configurable:

- Color.
- Display label.
- Visual effect.
- Announcement rules.
- Default income scaling.
- Collection UI style.

Use the actual rarity distribution calculated by the server when displaying odds.

## 6.2 Monster RNG

Create an RNGService that runs on the server.

The client sends a roll request. The server verifies that the player can roll, determines the selected die, checks eligibility, calculates the probability distribution, and chooses the result.

The client must never choose or submit the monster result.

Validate:

- The selected die is owned.
- The selected die is available.
- The player has enough money if the roll costs money.
- The player has not exceeded the roll rate limit.
- The player has inventory capacity if the game enforces a capacity.
- The player is eligible for event-exclusive monsters.
- The requested roll mode is permitted.

Use a proper weighted random selection algorithm.

Do not simply multiply all rare monster probabilities by the luck multiplier. That can cause the total probability to exceed 100% or distort the intended odds.

Instead, define base weights and apply a controlled rarity adjustment. Normalize the final weights before selecting a result.

Make the probability algorithm deterministic under test conditions by allowing an injectable random-number source in development tests, but never allow the live client to control the random seed.

Every eligible monster must have a valid, nonnegative weight.

If a monster is not eligible for the selected die or world, it must not enter that roll pool.

The resulting distribution must sum to 100%.

Add automated tests for:

- Probability normalization.
- Zero and invalid weights.
- Empty pools.
- Luck modifiers.
- World-specific eligibility.
- Extreme luck values.
- Expected approximate distributions over many simulated rolls.

## 6.3 Roll animation and rare discoveries

After the server chooses a monster, send the result to the owning client.

The client can play:

- Dice tumbling animation.
- Monster silhouette reveals.
- Rarity-colored screen effects.
- Sound effects.
- Monster reveal animation.
- New-discovery banner.
- Optional server-wide rare discovery announcement.

The animation must not determine the actual result.

If the client disconnects during the animation, the awarded monster must still be saved correctly.

Do not let a visual animation failure cause a duplicate reward.

## 6.4 Luck system

Support luck from:

- Base die.
- Skill tree.
- Rebirth bonuses.
- Temporary boosts.
- Events.
- Equipment effects, if allowed.

Define the combination rules in LuckConfig.

Use diminishing returns or a controlled rarity adjustment at high values.

Show actual effective odds for the current die and active modifiers.

Do not display misleading odds.

---

# 7. DICE SHOP AND WORLD PROGRESSION

Create DiceConfig and DiceService modules.

The initial progression order is:

1. Grassland Die.
2. Forest Die.
3. Desert Die.
4. Mountain Die.
5. Volcano Die.
6. Cave Die.
7. Heaven Die.
8. Cosmic Die.
9. Glitch Die.

Each die needs:

- Unique ID.
- Display name.
- Purchase cost.
- Luck parameter.
- Eligible monster pool.
- Required region or rebirth.
- Visual model.
- Unlock requirements.
- Optional special roll mechanics.

Example initial costs:

- Grassland: Free.
- Forest: $5,000.
- Desert: $75,000.
- Mountain: $1,000,000.
- Volcano: $25,000,000.
- Cave: $750,000,000.
- Heaven: $20,000,000,000.
- Cosmic: $2 trillion.
- Glitch: $500 trillion.

All costs must be configurable.

These values are balancing placeholders. Do not assume they are final.

The shop must display the purchase price, effective luck, eligible rarity tiers, and unlock requirements.

Buying a die must:

1. Validate ownership and cost on the server.
2. Deduct the currency through EconomyService.
3. Save the purchase.
4. Unlock the die.
5. Update the UI.
6. Allow the player to equip the die.

Prevent duplicate purchases from charging twice.

Provide a way to equip previously purchased dice without buying them again.

A higher-tier die should not necessarily eliminate the usefulness of every earlier die. Support region-specific pools and collection objectives.

---

# 8. BACKPACK, INVENTORY, AND COLLECTION CODEX

Create InventoryService and CollectionService.

The backpack stores monster instances, not just monster definitions.

The inventory interface must support:

- Grid view.
- Monster icons or viewport previews.
- Search.
- Sorting.
- Filtering by rarity.
- Filtering by element.
- Filtering by combat role.
- Sorting by income.
- Sorting by combat power.
- Sorting by level.
- Sorting by newest.
- Favorites.
- Locking valuable monsters.
- Multi-selection.
- Selling duplicates.
- Fusion.
- Equipping gear.
- Viewing monster details.
- Placing a monster at the base.
- Removing a monster from a base slot.

The inventory UI must update when monsters are awarded, fused, sold, placed, unplaced, or equipped.

## 8.1 Duplicate handling

Duplicates may be:

- Kept.
- Sold.
- Fused.
- Converted into research materials.

A locked monster must not be sold or fused without a deliberate unlock action.

Prevent accidental destruction of the last copy of a rare monster by adding a confirmation step or a protection rule.

The collection book should track discovery independently from current inventory ownership.

Selling a monster must not erase a legitimate discovery from the Codex.

## 8.2 Collection rewards

Create configurable rewards for unique monster milestones, such as:

- 10 unique monsters: coins.
- 25 unique monsters: inventory expansion.
- 50 unique monsters: a small permanent luck bonus.
- 100 unique monsters: title.
- 250 unique monsters: base decoration.
- Complete a regional collection: themed aura.

Only award each milestone once unless a specific repeatable reward is intended.

---

# 9. BASE SLOT AND MONSTER PLACEMENT SYSTEM

Create BaseService and PlacementService.

Every player has a plot assigned by the server.

Every base slot has a unique ID and a maximum one-monster occupancy.

A monster can only occupy one base slot at a time.

Placing a monster must verify:

- The plot belongs to the player.
- The slot exists and is unlocked.
- The slot is empty.
- The player owns the monster instance.
- The monster is not already placed elsewhere.
- The monster is not in a conflicting state.

When a monster is placed:

1. Record its instance ID in the slot.
2. Mark the monster as placed.
3. Spawn or display the correct model.
4. Attach its income information.
5. Recalculate total income.
6. Update the player's base UI.
7. Save the placement.

When removed, reverse the placement state without deleting the monster.

Use stable slot IDs rather than relying on the order of children inside a Model.

For floors, store the floor number as slot metadata.

Do not let players exceed their unlocked slot capacity.

If a placed model is missing, retain the placement record and show a placeholder instead of losing the monster.

---

# 10. IDLE INCOME AND ECONOMY SERVICE

Create EconomyService and IncomeService.

Every placed monster generates money per second.

Use a configurable formula such as:

MonsterIncome =
BaseIncome
× MonsterUpgradeMultiplier
× ApplicableSkillMultiplier
× ApplicableGearMultiplier
× ApplicableRebirthMultiplier
× OtherAllowedBonuses

Define stacking rules carefully.

Do not apply a bonus twice because both the server and a client controller calculate it.

The server must be the only authority for awarding currency.

## 10.1 Income processing

Use a centralized income-processing service instead of creating one infinite loop per monster.

Calculate total income for each player and award currency using a controlled update interval.

Support:

- Live income display.
- Income per second.
- Individual monster income.
- Total base income.
- Upgrade previews.
- Offline earnings.
- Income boosts.
- Server-side income validation.

Avoid excessive per-frame updates.

## 10.2 Offline earnings

When the player leaves, save the appropriate timestamp and relevant income state.

When the player rejoins:

1. Calculate the eligible elapsed time.
2. Apply the offline earnings cap.
3. Calculate earnings from the saved, eligible placed monsters.
4. Apply only bonuses that are allowed to persist offline.
5. Award currency through EconomyService.
6. Display an offline earnings summary.

For example, use a configurable maximum of eight hours.

Do not calculate offline earnings from untrusted client values.

Do not let a player change their system clock or submit a fake elapsed time to increase rewards.

---

# 11. INDIVIDUAL MONSTER UPGRADES

Create MonsterUpgradeService.

Players can upgrade an individual monster to increase its income, level, and potentially its combat stats.

Each upgrade should display:

- Current level.
- Current income.
- Next income.
- Upgrade cost.
- Current combat stats.
- Next combat stats.
- Maximum level if applicable.

Use a configurable cost curve, for example:

UpgradeCost =
BaseUpgradeCost × GrowthRate ^ CurrentLevel

Use appropriate numeric safeguards.

Upgrading must validate the monster instance, ownership, cost, and maximum level on the server.

Do not accept the client's claimed current level or income.

Apply upgrades to the monster instance data and recalculate relevant derived values.

Support separate income upgrades and combat training if needed.

---

# 12. BRANCHING EVOLUTION SKILL TREE

Create SkillTreeConfig and SkillTreeService.

The tree has six primary branches:

1. Luck.
2. Economy.
3. Damage.
4. Health and Defense.
5. Mobility.
6. Utility.

Each node contains:

- Unique node ID.
- Display name.
- Branch.
- Description.
- Cost.
- Prerequisite nodes.
- Maximum rank.
- Effect type.
- Effect value.
- Optional rebirth or region requirement.

## 12.1 Luck branch

Include:

- Lucky Charm.
- Rare Hunter.
- Legendary Focus.
- Mythic Resonance.
- Double Fortune.
- Discovery Streak.
- Cosmic Fortune.

These nodes improve rolling, discovery bonuses, or special roll mechanics.

## 12.2 Economy branch

Include:

- Coin Collector.
- Efficient Training.
- Golden Pedestals.
- Idle Earnings.
- Fusion Efficiency.
- Treasure Research.
- Empire Builder.

## 12.3 Damage branch

Include:

- Sharpened Claws.
- Critical Strike.
- Elemental Mastery.
- Combo Master.
- Boss Hunter.
- Skill Amplification.
- Ultimate Awakening.

## 12.4 Health and Defense branch

Include:

- Thick Hide.
- Iron Guard.
- Regeneration.
- Last Stand.
- Team Protection.
- Elemental Resistance.
- Guardian's Resolve.

## 12.5 Mobility branch

Include:

- Quick Feet.
- Longer Dash.
- Reduced Cooldown.
- Jump Boost.
- Auto Pickup.
- Portal Mastery.
- Phantom Sprint.

Player movement speed must not automatically become battle turn speed unless a specific node explicitly grants that effect.

## 12.6 Utility branch

Include:

- Bigger Backpack.
- Faster Rolling.
- Quick Fusion.
- Extra Team Preset.
- Better Chest Finder.
- Equipment Slots.
- Research Lab.

## 12.7 Cross-branch nodes

Add advanced nodes that require combinations of branches.

Examples:

- Fortune Engine: Luck + Economy.
- War Beast: Damage + Defense.
- Explorer's Instinct: Luck + Mobility.
- Master Collector: Utility + Economy.
- Divine Ascension: requirements across all six branches.

## 12.8 Skill-tree UI

Create a responsive UI with:

- Six visually distinct branches.
- Nodes connected by lines.
- Locked, available, and purchased states.
- Current rank.
- Cost.
- Requirements.
- Effect preview.
- Purchase confirmation.
- Search or filtering for large trees.
- Reset or respec option.

Use client-side animation for visuals, but perform all purchases and prerequisite validation on the server.

Never trust the client to submit a valid node rank or effect.

Use a centralized modifier system so a skill bonus is not accidentally applied more than once.

---

# 13. REBIRTH AND ASCENSION SYSTEM

Create RebirthConfig and RebirthService.

Rebirth resets specified regular progression and awards permanent benefits.

The player must meet configured requirements such as:

- Required lifetime earnings.
- Required progression milestone.
- Required regional boss defeat.
- Required rebirth cost.

The actual requirements should be data-driven.

## 13.1 Rebirth slot rules

Total slots:

5 + RebirthCount

Floors:

min(3, 1 + floor(RebirthCount / 6))

Floor 1 is available from the beginning.

Floor 2 unlocks at rebirth 6.

Floor 3 unlocks at rebirth 12.

No additional floors unlock beyond floor 3.

Every rebirth increases total slots by one.

At rebirth 6, the player has 11 total slots.

At rebirth 12, the player has 17 total slots.

Additional rebirths continue increasing slots while keeping the maximum at three floors.

## 13.2 Rebirth reset policy

Before rebirth, show a confirmation UI listing:

- What will reset.
- What will remain.
- New slot count.
- New floor count.
- Permanent bonuses.
- Ascension Points awarded.
- Requirements that were met.

Perform the entire reset on the server.

Use a transactional approach to prevent partial rebirth states.

The reset must not accidentally duplicate money, monsters, gear, or rewards.

Protect the monster collection, discoveries, equipment, and permanent unlocks according to the configured rules.

## 13.3 Permanent rewards

Support:

- Permanent income bonuses.
- Controlled permanent luck bonuses.
- Additional slots.
- Ascension Points.
- Milestone titles.
- Base decorations.
- Special auras.
- Milestone chest rewards.

Create a separate Ascension Tree for permanent upgrades purchased with Ascension Points.

Make sure permanent modifiers stack consistently with normal skill-tree modifiers.

---

# 14. CHESTS, EQUIPMENT, FUSION, AND CRAFTING

Create ChestService, EquipmentService, FusionService, and CraftingService.

## 14.1 Chest tiers

Support:

- Wooden Chest.
- Forest Chest.
- Desert Chest.
- Mountain Chest.
- Volcano Chest.
- Crystal Chest.
- Divine Chest.
- Cosmic Chest.

Each chest configuration contains:

- Purchase cost.
- Required region.
- Allowed gear pool.
- Drop weights.
- Guaranteed reward rules if applicable.
- Visual model ID.
- Animation ID.
- Optional key requirements.

Example initial prices:

- Wooden: $2,500.
- Forest: $40,000.
- Desert: $600,000.
- Mountain: $12,000,000.
- Volcano: $300,000,000.
- Crystal: $8 billion.
- Divine: $250 billion.
- Cosmic: endgame currency requirement.

These are configurable placeholders.

## 14.2 Chest opening

The server must determine the reward.

The client may request a chest opening and play an animation, but cannot choose the reward.

Validate ownership, cost, eligibility, and rate limits.

The chest reward must be granted exactly once, even if the client disconnects or the animation fails.

Support batch openings only through server-validated requests.

Display accurate odds and reward categories.

## 14.3 Gear categories

Weapons:
- Damage.
- Critical chance.
- Elemental power.

Armor:
- Maximum health.
- Defense.
- Damage reduction.

Accessories:
- Speed.
- Healing.
- Critical effects.
- Utility.

Relics:
- Special passive effects.
- Unique ability modifications.
- Team synergies.

Start each monster with three equipment slots:

- Weapon.
- Armor.
- Accessory.

Add relics as an advanced or endgame feature.

## 14.4 Equipment data

Each equipment instance should have:

- Instance ID.
- Definition ID.
- Rarity.
- Level.
- Randomized secondary stats if applicable.
- Upgrade rank.
- Binding or ownership state.
- Equipped monster instance ID.

Do not store equipment solely by its display name.

The same gear definition can have many independently owned instances.

## 14.5 Fusion

Allow compatible duplicate monsters to fuse into a higher fusion rank.

Use a configurable recipe and cost.

Validate all selected instance IDs on the server.

Do not fuse locked monsters.

Prevent the same instance from being used twice in one fusion request.

Ensure that the player cannot lose unrelated inventory items due to malformed requests.

Apply fusion changes atomically.

Fusion may increase:

- Income.
- Health.
- Damage.
- Skill strength.
- Visual effects.

## 14.6 Crafting

Introduce regional materials:

- Forest Essence.
- Desert Relics.
- Mountain Shards.
- Ember Shards.
- Crystal Fragments.
- Divine Dust.
- Cosmic Cores.

Crafting recipes should be data-driven.

The server must verify the recipe, inventory, material quantities, and costs before completing a craft.

---

# 15. TURN-BASED MONSTER BATTLE SYSTEM

Create a separate battle subsystem.

Suggested modules:

- BattleService.
- BattleState.
- BattleRules.
- BattleTurnService.
- BattleAbilityService.
- BattleRewardService.
- BattleAIService.
- BattleArenaService.
- BattleUIController.
- BattleConfig.
- EnemyConfig.
- AbilityConfig.

Combat must be server-authoritative.

The client submits an action request, and the server checks whether that action is legal.

## 15.1 Team construction

Start with three active monsters per battle team.

Allow additional saved team presets through progression.

A team may contain monsters with different roles:

- Attacker.
- Tank.
- Support.
- Healer.
- Controller.
- Specialist.

Prevent the same monster instance from being assigned to conflicting teams if the game rules prohibit it.

The player must own every monster included in a team.

## 15.2 Battle stats

Each monster needs:

- Current HP.
- Maximum HP.
- Damage.
- Defense.
- Speed.
- Critical chance.
- Element.
- Role.
- Abilities.
- Status effects.
- Ultimate energy.
- Gear modifiers.
- Skill-tree modifiers.

Keep base stats separate from derived stats.

Derived stats should be recalculated through a single consistent modifier pipeline.

Avoid applying equipment or skill-tree modifiers twice.

## 15.3 Turn order

At the beginning of a round, calculate action order from speed and any applicable effects.

Use a stable tie-breaking rule.

Track:

- Current round.
- Active combatants.
- Action order.
- Whose turn it is.
- Available actions.
- Cooldowns.
- Status effects.
- Battle outcome.

Only the currently authorized player should be able to submit an action for their active turn.

The server should reject out-of-turn actions, duplicate actions, invalid targets, and invalid ability IDs.

## 15.4 Available actions

Basic Attack:
- Deals standard damage.
- Builds ultimate energy.

Skill:
- Uses a configured ability.
- May deal damage, heal, shield, or apply a status effect.
- May require energy or have a cooldown.

Defend:
- Reduces incoming damage.
- May generate energy.

Ultimate:
- Consumes required energy.
- Executes a powerful ability.

Support switching between active and reserve monsters once reserves are introduced.

## 15.5 Damage formula

Use a documented damage calculation.

For example:

RawDamage = AttackerDamage × AbilityMultiplier

Then apply defense, elemental advantage, critical effects, shields, damage modifiers, and caps according to a consistent order.

Use a formula that avoids defense reducing all damage to zero.

Do not trust a client-submitted damage amount.

All damage and healing must be calculated on the server.

## 15.6 Elements

Support:

- Nature.
- Earth.
- Fire.
- Water.
- Lightning.
- Light.
- Shadow.
- Cosmic.

Initial elemental relationships:

- Nature is strong against Earth and weak against Fire.
- Earth is strong against Lightning and weak against Nature.
- Fire is strong against Nature and weak against Water.
- Water is strong against Fire and weak against Lightning.
- Lightning is strong against Water and weak against Earth.
- Light and Shadow counter one another.
- Cosmic has no automatic advantage or weakness.

A strong matchup can apply a configurable 1.25× multiplier.

A weak matchup can apply a configurable 0.8× multiplier.

These values must be centralized in BattleConfig.

## 15.7 Status effects

Implement:

- Burn.
- Poison.
- Freeze.
- Stun.
- Shield.
- Regeneration.
- Weaken.
- Mark.
- Expose.
- Cleanse.

Every status effect must define:

- Duration.
- Application rules.
- Stacking behavior.
- Turn timing.
- Removal conditions.
- Immunity or resistance rules.
- Visual presentation.

Bosses should have resistance rules for repeated control effects.

Avoid allowing infinite stun or freeze loops.

## 15.8 Enemy AI

Create a simple but extensible enemy AI.

The AI should consider:

- Current HP.
- Available abilities.
- Ability cooldowns.
- Player monster HP.
- Threat level.
- Elemental matchups.
- Healing opportunities.
- Defensive opportunities.

Start with a basic legal-action selection algorithm and expand it to boss-specific behavior.

Enemy AI must run on the server.

## 15.9 Battle modes

Implement the battle system so it can support:

- Story battles.
- Regional bosses.
- Endless Tower.
- Daily Challenges.
- Element Trials.
- Survival Mode.
- Cooperative Boss Raids.
- Optional PvP Arena.

Prioritize Story Battles and regional bosses first.

Do not attempt to implement every mode before the core battle engine works.

## 15.10 Battle rewards

Award rewards through BattleRewardService.

Possible rewards:

- Cash.
- Experience.
- Equipment.
- Chest keys.
- Crafting materials.
- Boss tokens.
- Region progression.
- Collection discoveries.

Use server-defined reward tables.

Ensure each completed battle can only grant its rewards once.

Boss milestones should provide reliable guaranteed rewards in addition to random drops.

## 15.11 Battle arenas

Build separate arenas for:

1. Grassland.
2. Forest.
3. Desert.
4. Mountain.
5. Volcano.
6. Cave.
7. Heaven.
8. Cosmic.
9. Glitch.

Each arena should have:

- Environment model.
- Spawn positions.
- Enemy spawn definitions.
- Boss definitions.
- Difficulty settings.
- Music configuration.
- Reward configuration.
- Unlock requirements.

Use placeholder arenas until the actual models are imported.

Do not require every player to fight in the same shared battle instance.

Use isolated battle sessions or a suitable arena allocation system so players cannot interfere with one another's combat.

---

# 16. REGIONS, BOSSES, AND WORLD PROGRESSION

Create RegionConfig and RegionService.

Each region has:

- Display name.
- Required die or progression milestone.
- Required battle completion.
- Eligible monster pool.
- Enemy roster.
- Boss.
- Equipment pool.
- Materials.
- Chest unlock.
- Rewards.

Progression order:

1. Grassland.
2. Forest.
3. Desert.
4. Mountain.
5. Volcano.
6. Cave.
7. Heaven.
8. Cosmic.
9. Glitch.

Example bosses:

- Grassland: Overgrown Brute.
- Forest: Elder Root.
- Desert: Pharaoh of Dust.
- Mountain: Frost King.
- Volcano: Infernos, the World Eater.
- Cave: The Buried Ancient.
- Heaven: The Fallen Luminary.
- Cosmic: The Star Devourer.
- Glitch: The Null Sovereign.

Every boss should have a unique identity, attack pattern, and reward table.

Unlocking a new region should require a defined progression condition rather than only an arbitrary money amount.

---

# 17. USER INTERFACE

Create a consistent UI system that matches the stud-built, thick-outlined, colorful fantasy art direction.

The UI must be readable at desktop, mobile, and tablet resolutions.

Use scalable layouts, UIListLayout, UIGridLayout, constraints, and responsive sizing.

Avoid fixed pixel layouts that break on mobile.

## 17.1 Main HUD

Display:

- Current cash.
- Cash per second.
- Current die.
- Luck indicator.
- Roll button.
- Backpack button.
- Upgrade button.
- Shop button.
- Battle button.
- Rebirth button.
- Current region.
- Quest or objective indicator.

Use consistent iconography and color coding.

## 17.2 Rolling interface

Display:

- Selected die.
- Current odds.
- Luck modifiers.
- Roll button.
- Auto-roll toggle if unlocked.
- Quick-roll option if unlocked.
- Roll animation.
- Result reveal.
- New discovery status.

Auto-roll must obey the same server validation and rate limits as manual rolling.

Do not allow the client to run unlimited roll requests.

## 17.3 Backpack interface

Display:

- Inventory grid.
- Search field.
- Sort and filter controls.
- Selected monster detail panel.
- Income.
- Health.
- Damage.
- Level.
- Fusion rank.
- Traits.
- Equipment.
- Place, equip, fuse, or sell actions.

## 17.4 Shops

Each shop needs a dedicated UI with:

- Item list.
- Prices.
- Requirements.
- Locked states.
- Purchase buttons.
- Owned indicators.
- Confirmation where necessary.

## 17.5 Skill tree

Show the six main branches, connected nodes, costs, prerequisites, rank, and effect previews.

## 17.6 Rebirth interface

Show:

- Requirements.
- Current rebirth count.
- Next slot count.
- Current and next floor count.
- Permanent rewards.
- Reset consequences.
- Confirmation button.

## 17.7 Battle interface

Show:

- Player team.
- Enemy team.
- Health bars.
- Turn order.
- Current turn.
- Ability buttons.
- Cooldowns.
- Ultimate energy.
- Status effects.
- Combat log.
- Victory or defeat screen.
- Rewards.

The interface must communicate whose turn it is and why an action is unavailable.

---

# 18. REMOTE EVENTS AND SECURITY

Create a centralized remote definition module.

Do not scatter arbitrary remote names and unchecked calls throughout the codebase.

Use RemoteEvents and RemoteFunctions only where appropriate.

Possible remote categories:

- RequestRoll.
- RollResult.
- RequestPurchase.
- PurchaseResult.
- RequestPlaceMonster.
- RequestRemoveMonster.
- RequestMonsterUpgrade.
- RequestSkillPurchase.
- RequestRebirth.
- RequestChestOpen.
- RequestEquipmentChange.
- RequestFusion.
- RequestCraft.
- RequestBattleStart.
- RequestBattleAction.
- BattleStateUpdate.
- InventoryUpdate.
- EconomyUpdate.
- Notification.
- DataLoadStatus.

These are conceptual names; adapt them to the existing project architecture.

For every client-to-server request:

1. Validate the player.
2. Validate argument types.
3. Validate identifiers against server-side registries.
4. Validate ownership.
5. Validate state and prerequisites.
6. Validate affordability.
7. Apply rate limits.
8. Perform the authoritative action.
9. Update server state.
10. Replicate the result.

Never accept a client-supplied currency balance, monster stat, damage amount, roll result, rarity, item reward, or ownership claim.

Use per-player rate limits for expensive operations.

Protect against:

- Remote spam.
- Duplicate purchases.
- Duplicate rewards.
- Invalid item IDs.
- Forged monster instance IDs.
- Negative currency requests.
- Invalid skill ranks.
- Invalid battle actions.
- Unauthorized plot changes.
- Repeated fusion requests.
- Replayed chest openings.

Server-side checks are mandatory even if the UI prevents invalid actions.

---

# 19. MULTIPLAYER AND LEADERBOARDS

Support multiple players on the same island.

Each player must have independent:

- Inventory.
- Currency.
- Dice.
- Skill tree.
- Base slots.
- Battle state.
- Rebirth progress.
- Equipment.
- Collection discoveries.

Players can view each other's bases, but cannot modify them.

Add optional social features:

- Visit another player's base.
- Inspect public monster displays.
- View public collection milestones.
- Compare income and rebirth counts.
- Send nonintrusive emotes.
- View leaderboards.

Leaderboards can include:

- Highest lifetime earnings.
- Highest rebirth count.
- Most unique monsters.
- Rarest discoveries.
- Highest battle progression.
- Highest Endless Tower floor.

Use OrderedDataStore for appropriate persistent global rankings.

Do not expose private inventory data unnecessarily.

Do not use leaderboards as the only source of truth for a player's actual progression.

---

# 20. DAILY REWARDS, QUESTS, AND EVENTS

Create DailyRewardService, QuestService, and EventService.

## 20.1 Daily rewards

Create a seven-day reward cycle.

Possible rewards:

- Day 1: Cash.
- Day 2: Chest.
- Day 3: Crafting materials.
- Day 4: Temporary luck boost.
- Day 5: Gear.
- Day 6: Rare chest.
- Day 7: Special cosmetic or guaranteed progression reward.

Daily reward timestamps must be validated on the server.

Prevent duplicate claims.

Handle date changes and offline players correctly.

## 20.2 Quests

Create quests such as:

- Roll ten times.
- Discover a new monster.
- Place three monsters.
- Earn a target amount of money.
- Upgrade a monster.
- Open a chest.
- Win a battle.
- Defeat a boss.
- Fuse a duplicate.
- Perform a rebirth.

Quest progress must be tracked through authoritative game events rather than client-submitted progress values.

## 20.3 Events

Support configurable events:

- Double income.
- Increased regional monster discoveries.
- Limited-time bosses.
- Seasonal cosmetics.
- Community collection challenges.
- Special crafting recipes.

Events must have defined start and end times and must not overwrite normal progression data.

---

# 21. PERFORMANCE AND CODE QUALITY

The game must run smoothly on typical Roblox devices.

Requirements:

- Avoid one infinite loop per monster.
- Avoid excessive RemoteEvent traffic.
- Avoid rebuilding entire UIs for minor changes.
- Cache configuration lookups where appropriate.
- Reuse models and UI templates.
- Use controlled update intervals.
- Disconnect unused event connections.
- Clean up battle instances and temporary effects.
- Avoid unnecessary physics simulation.
- Use streaming-friendly world design where appropriate.
- Avoid excessive unanchored decorative Parts.
- Pool repeated visual effects if necessary.
- Avoid keeping references to departed players.
- Use reliable cleanup when a player leaves during a battle or animation.

Keep the code understandable and maintainable.

Prefer small, focused modules over one large service containing unrelated systems.

Add useful logs for errors and development diagnostics, but do not flood production output with per-frame messages.

---

# 22. TESTING REQUIREMENTS

Create a testing plan and implement automated tests for the most important gameplay rules.

Use unit tests for pure logic and integration tests for connected systems.

Test the following.

## Economy

- Income calculations.
- Purchase affordability.
- Upgrade cost calculations.
- Currency bounds.
- Offline earnings.
- Rebirth income reset.

## RNG

- Probability normalization.
- Rarity distribution.
- Luck adjustments.
- Invalid pools.
- World eligibility.
- Roll rate limiting.

## Inventory

- Monster award.
- Duplicate handling.
- Placement.
- Unplacement.
- Selling.
- Fusion.
- Locking.
- Ownership checks.

## Base

- Plot allocation.
- Slot limits.
- Floor unlocking.
- Rebirth slot count.
- Unauthorized placement rejection.

## Skill tree

- Prerequisite checks.
- Currency deductions.
- Maximum ranks.
- Modifier application.
- Respec behavior.

## Equipment

- Chest affordability.
- Drop table validity.
- Gear ownership.
- Equipment slots.
- Stat recalculation.
- Crafting costs.

## Combat

- Turn order.
- Valid targets.
- Damage calculation.
- Status effect timing.
- Healing.
- Defeat and victory conditions.
- Reward deduplication.
- Battle cleanup.

## Persistence

- New player initialization.
- Successful loading.
- Failed loading.
- Schema migration.
- Saving after important changes.
- Rejoining after progression.
- DataStore failure handling.

## Multiplayer

- Two players receiving separate plots.
- Unauthorized base modification.
- Cross-player inventory access attempts.
- Remote spam.
- Disconnects during battles.
- Simultaneous purchase requests.

Use Roblox Studio's server and client test modes with multiple simulated players whenever possible.

Do not mark the game fully tested just because the scripts were created.

---

# 23. DEVELOPMENT DELIVERABLES

Produce the following inside the actual Roblox Studio project:

1. A clear folder and script structure.
2. A configurable world layout.
3. An asset registry.
4. A player data schema.
5. A persistent DataService.
6. A server-authoritative economy.
7. Monster definitions and RNG.
8. Inventory and collection systems.
9. Base plots and monster placement.
10. Dice shop and world progression.
11. Individual monster upgrades.
12. Branching skill tree.
13. Rebirth and floor unlocking.
14. Chest and equipment systems.
15. Fusion and crafting.
16. Turn-based battle engine.
17. Enemy AI and boss definitions.
18. Responsive UI.
19. Multiplayer plot protection.
20. Daily rewards and quest infrastructure.
21. Logging and test utilities.
22. A setup and asset-import guide.
23. A list of systems that are complete, incomplete, or blocked.
24. A list of required assets that have not yet been imported.

Use placeholder models only where needed. Do not let missing artwork prevent the underlying game systems from functioning.

---

# 24. FINAL ACCEPTANCE CRITERIA

The game is not ready merely because the island looks good.

The following end-to-end workflow must work:

1. A new player joins and receives a valid saved profile.
2. The player is assigned an available base plot.
3. The player starts with the Grassland Die.
4. The player rolls and receives a server-generated monster.
5. The monster appears in the backpack and collection system.
6. The player places the monster in an available base slot.
7. The monster begins generating money.
8. The player upgrades the monster.
9. The income increases correctly.
10. The player buys a new die.
11. The player equips the new die and rolls again.
12. The player purchases an Evolution Tree node.
13. The corresponding bonus affects gameplay exactly once.
14. The player buys a chest and receives server-generated gear.
15. The player equips the gear and sees the correct stat changes.
16. The player creates a legal battle team.
17. The player enters a battle and selects valid turn-based actions.
18. The player wins a battle and receives the correct rewards.
19. The player meets rebirth requirements.
20. The player confirms rebirth and receives permanent rewards.
21. The player gains one extra slot and unlocks the appropriate floor milestone.
22. The player leaves and rejoins.
23. Their inventory, currency, progression, gear, and base placement load correctly.
24. Another player cannot access or modify the first player's private data or base.

If a feature is not fully implemented, identify exactly what is missing and what is needed to complete it.

Do not silently substitute a nonfunctional UI button for a working system.

Do not leave placeholder functions that pretend to grant rewards without implementing the actual logic.

Do not hardcode fake success messages.

---

# 25. HOW TO EXECUTE THIS PROMPT

Begin by inspecting the current Roblox Studio project and reporting the existing structure, reusable systems, imported assets, and missing assets.

Then implement the game in stages, starting with the project architecture, world layout, data persistence, and core RNG loop.

After each stage:

- Explain which scripts and modules were created or modified.
- Explain how the modules connect.
- Run the tests that are available.
- Report errors and limitations honestly.
- Fix identified issues before continuing.

Keep a checklist of the acceptance criteria and update it as features become functional.

If you have access to tools that can directly edit the Roblox Studio project, use them to implement the code and world objects. If you only have access to a code editor or text output, provide complete, correctly named Luau scripts and precise installation instructions rather than claiming that the project has already been modified.

Do not stop at planning. Start implementing the first working version, then continue expanding it.

The priority is a stable, playable core game with real server-side logic, persistent data, working monster collection, income generation, base placement, upgrades, and rebirth. Build the more advanced combat, gear, and endgame systems on top of that foundation.

**Final goal:** A complete and extensible Roblox monster RNG simulator with a square stud-built island hub, two-sided player base districts, themed shops, collectible monster characters, a functioning idle economy, a branching skill tree, multiple base floors, rebirth progression, equipment chests, and a tactical turn-based combat system. All gameplay must be connected, secure, save correctly, and be ready for our existing 3D models to be imported and assigned through the asset registry.
