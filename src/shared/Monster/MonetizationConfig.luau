-- Robux shop: gamepasses (permanent) and developer products (consumable), modeled on the top RNG games
-- (2x/3x luck passes, VIP, quick/auto/multi roll, lucky-roll packs, luck potions, server luck).
-- gamepass / product = the Roblox ids from the Creator Dashboard (nil = shown as "coming soon" until filled in).
-- robux = the price shown before the real price loads (set the real price on the dashboard).
-- image = rbxassetid of the uploaded icon (PNG sources in assets/shop-icons); emoji is the fallback.
--
-- Luck passes, potions, server luck and lucky rolls change roll odds, so Roblox treats them as paid random items:
-- the shop shows the resulting odds (percent, summing to 100%) before purchase, and players whose
-- PolicyService.ArePaidRandomItemsRestricted is true can't buy them and don't get paid luck effects.
local Mon = {}

-- effects: luckMult (multiplies effective luck, stacks multiplicatively), multiRoll (rolls per roll), cosmetic
-- (granted when owned); rollspeed / autoroll / storage / walkspeed add into Game.stat like skill-tree effects
Mon.Passes = {
	{ id = "lucky", name = "Lucky", icon = "🍀", color = Color3.fromRGB(80, 210, 90), robux = 299, gamepass = nil,
		effects = { luckMult = 2 }, desc = "Permanent 2x luck on every roll", luck = true },
	{ id = "super_lucky", name = "Super Lucky", icon = "🍀🍀", color = Color3.fromRGB(40, 230, 140), robux = 799, gamepass = nil,
		effects = { luckMult = 3 }, desc = "Permanent 3x luck (stacks with Lucky: 6x)", luck = true },
	{ id = "vip", name = "VIP", icon = "👑", color = Color3.fromRGB(255, 210, 60), robux = 249, gamepass = nil,
		effects = { luckMult = 1.2, walkspeed = 4, cosmetic = "title_vip" }, desc = "1.2x luck, +4 walk speed, VIP title", luck = true },
	{ id = "quick_roll", name = "Quick Roll", icon = "⚡", color = Color3.fromRGB(255, 230, 90), robux = 149, gamepass = nil,
		effects = { rollspeed = 0.4 }, desc = "Roll 40% faster" },
	{ id = "auto_roll", name = "Auto Roll", icon = "🔁", color = Color3.fromRGB(90, 180, 255), robux = 199, gamepass = nil,
		effects = { autoroll = 1 }, desc = "Auto-roll at the Summon station" },
	{ id = "triple_roll", name = "Triple Roll", icon = "🎲", color = Color3.fromRGB(200, 120, 255), robux = 399, gamepass = nil,
		effects = { multiRoll = 3 }, desc = "Roll 3 monsters at once" },
	{ id = "big_backpack", name = "Huge Backpack", icon = "🎒", color = Color3.fromRGB(230, 140, 70), robux = 149, gamepass = nil,
		effects = { storage = 200 }, desc = "+200 backpack space" },
}
-- grant: luckyRolls (each is one roll at LUCKY_ROLL_MULT luck), potion { mult, secs }, serverLuck { mult, secs }
Mon.LUCKY_ROLL_MULT = 10
Mon.Products = {
	{ id = "lucky_10", name = "10 Lucky Rolls", icon = "🍀", color = Color3.fromRGB(80, 210, 90), robux = 49, product = nil,
		grant = { luckyRolls = 10 }, desc = "10 rolls at 10x luck", luck = true },
	{ id = "lucky_100", name = "100 Lucky Rolls", icon = "🍀", color = Color3.fromRGB(60, 220, 120), robux = 399, product = nil,
		grant = { luckyRolls = 100 }, desc = "100 rolls at 10x luck", luck = true },
	{ id = "lucky_1000", name = "1000 Lucky Rolls", icon = "🍀", color = Color3.fromRGB(40, 255, 160), robux = 2999, product = nil,
		grant = { luckyRolls = 1000 }, desc = "1000 rolls at 10x luck", luck = true },
	{ id = "luck_potion", name = "Luck Potion", icon = "🧪", color = Color3.fromRGB(120, 230, 120), robux = 79, product = nil,
		grant = { potion = { mult = 2, secs = 900 } }, desc = "2x luck for 15 minutes", luck = true },
	{ id = "server_luck", name = "Server Luck", icon = "🌍", color = Color3.fromRGB(80, 255, 200), robux = 199, product = nil,
		grant = { serverLuck = { mult = 2, secs = 900 } }, desc = "2x luck for EVERYONE in the server, 15 minutes", luck = true },
}
Mon.PassById, Mon.ProductById = {}, {}
for _, p in Mon.Passes do Mon.PassById[p.id] = p end
for _, p in Mon.Products do Mon.ProductById[p.id] = p end

-- Roblox Premium members get a small luck bonus (common in the genre; set to 1 to turn it off)
Mon.PREMIUM_LUCK = 1.1
-- members of the game's Roblox group get a luck bonus (fill in GROUP_ID; nil = off)
Mon.GROUP_ID, Mon.GROUP_LUCK = nil, 1.1
-- every 10th roll is Golden (2x luck), every 100th is Rainbow (5x); free for everyone
Mon.GOLDEN_EVERY, Mon.GOLDEN_MULT, Mon.RAINBOW_EVERY, Mon.RAINBOW_MULT = 10, 2, 100, 5

-- product of an effect over owned passes (multiplicative for luckMult, additive for the rest)
function Mon.passStat(owned, effect: string): number
	local mult = effect == "luckMult"
	local v = mult and 1 or 0
	for id in owned do
		local pass = Mon.PassById[id]
		local e = pass and pass.effects[effect]
		if e then v = mult and v * e or v + e end
	end
	return v
end
return Mon
