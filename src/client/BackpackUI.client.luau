-- Backpack: every monster instance you own, with search/sort/filter and a detail panel to
-- upgrade, lock, favorite, sell, fuse duplicates and pick your battle team. The server validates every action.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local Http = game:GetService("HttpService")
local Config = require(RS:WaitForChild("Monster"):WaitForChild("MonsterConfig"))
local Gear = require(RS.Monster:WaitForChild("GearConfig"))
local F = require(RS.Monster:WaitForChild("Formulas"))
local Traits = require(RS.Monster:WaitForChild("TraitConfig"))
local Inv = RS.Monster:WaitForChild("InventoryAction")
local BattleAction = RS.Monster:WaitForChild("BattleAction")
local player = Players.LocalPlayer
local state = player:WaitForChild("PlayerGui"):WaitForChild("State") -- private mirror of my save, written by the server

local function short(n)
	for _, u in { { 1e21, "sx" }, { 1e18, "qn" }, { 1e15, "qd" }, { 1e12, "t" }, { 1e9, "b" }, { 1e6, "m" }, { 1e3, "k" } } do
		if n >= u[1] then return (("%.1f"):format(n / u[1]):gsub("%.0$", "")) .. u[2] end
	end
	return n < 100 and (("%.1f"):format(n):gsub("%.0$", "")) or tostring(math.floor(n))
end
local function text(class, parent, str, size, pos, color)
	local l = Instance.new(class) l.Size = size l.Position = pos l.BackgroundTransparency = 1 l.Font = Enum.Font.FredokaOne l.TextScaled = true
	l.Text = str l.TextColor3 = color or Color3.new(1, 1, 1) l.TextStrokeTransparency = 0 l.Parent = parent
	return l
end
local function btn(parent, str, size, pos, color)
	local b = text("TextButton", parent, str, size, pos)
	b.BackgroundTransparency = 0 b.BackgroundColor3 = color
	Instance.new("UICorner", b)
	local st = Instance.new("UIStroke", b) st.Thickness = 3 st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	return b
end
local function decode(attr)
	local ok, v = pcall(Http.JSONDecode, Http, state:GetAttribute(attr) or "")
	return ok and v or {}
end
local function nameOf(m)
	local def = Config.ById[m.id]
	local mut = m.mu and Traits.MutationById[m.mu]
	return (mut and mut.name .. " " or "") .. (m.v ~= "Normal" and m.v:upper() .. " " or "") .. (def and def.name or m.id)
end

local gui = Instance.new("ScreenGui") gui.Name = "BackpackUI" gui.ResetOnSpawn = false gui.Parent = player:WaitForChild("PlayerGui")
local hud = btn(gui, "BAG", UDim2.fromOffset(120, 50), UDim2.new(0, 12, 0.5, -56), Color3.fromRGB(60, 140, 80))
hud.AnchorPoint = Vector2.new(0, 0.5)
local panel = Instance.new("Frame") panel.AnchorPoint = Vector2.new(0.5, 0.5) panel.Position = UDim2.fromScale(0.5, 0.5) panel.Size = UDim2.fromScale(0.94, 0.88)
panel.BackgroundColor3 = Color3.fromRGB(30, 36, 44) panel.Visible = false panel.Parent = gui
local lim = Instance.new("UISizeConstraint") lim.MaxSize = Vector2.new(1040, 720) lim.Parent = panel
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 18)
Instance.new("UIStroke", panel).Thickness = 4
local title = text("TextLabel", panel, "BACKPACK", UDim2.fromScale(0.2, 0.07), UDim2.fromScale(0.02, 0.015))
title.TextXAlignment = Enum.TextXAlignment.Left
local msg = text("TextLabel", panel, "", UDim2.fromScale(0.5, 0.05), UDim2.fromScale(0.44, 0.025), Color3.fromRGB(255, 220, 120))
local close = btn(panel, "X", UDim2.fromOffset(40, 40), UDim2.new(1, -48, 0, 8), Color3.fromRGB(220, 50, 50))
close.MouseButton1Click:Connect(function() panel.Visible = false end)

-- controls: search, sort, rarity filter
local search = Instance.new("TextBox") search.Size = UDim2.fromScale(0.26, 0.06) search.Position = UDim2.fromScale(0.02, 0.1)
search.PlaceholderText = "Search..." search.Text = "" search.ClearTextOnFocus = false search.Font = Enum.Font.FredokaOne search.TextScaled = true
search.BackgroundColor3 = Color3.fromRGB(50, 56, 70) search.TextColor3 = Color3.new(1, 1, 1) search.Parent = panel
Instance.new("UICorner", search)
local SORTS = {
	{ "Income", function(a, b) return a.m.inc > b.m.inc end },
	{ "Level", function(a, b) return a.m.lvl > b.m.lvl end },
	{ "Power", function(a, b) return (a.m.hp or 0) + (a.m.dmg or 0) * 5 > (b.m.hp or 0) + (b.m.dmg or 0) * 5 end },
	{ "Newest", function(a, b) return (a.m.t or 0) > (b.m.t or 0) end },
	{ "Rarity", function(a, b) return Config.Tier[Config.ById[a.m.id].rarity] > Config.Tier[Config.ById[b.m.id].rarity] end },
}
local sortI, filterI, elemI, roleI = 1, 0, 0, 0 -- 0 = all
local ELEMENTS = { "Nature", "Earth", "Fire", "Water", "Lightning", "Light", "Shadow", "Cosmic" }
local ROLES = { "Attacker", "Tank", "Healer", "Support", "Controller", "Specialist" }
local multi, picked = false, {} -- multi-select mode for selling several at once
local sortB = btn(panel, "", UDim2.fromScale(0.15, 0.06), UDim2.fromScale(0.3, 0.1), Color3.fromRGB(70, 90, 150))
local filterB = btn(panel, "", UDim2.fromScale(0.15, 0.06), UDim2.fromScale(0.465, 0.1), Color3.fromRGB(70, 90, 150))
local countL = text("TextLabel", panel, "", UDim2.fromScale(0.2, 0.04), UDim2.fromScale(0.22, 0.03), Color3.fromRGB(200, 200, 210))
local elemB = btn(panel, "", UDim2.fromScale(0.12, 0.06), UDim2.fromScale(0.63, 0.1), Color3.fromRGB(70, 90, 150))
local roleB = btn(panel, "", UDim2.fromScale(0.12, 0.06), UDim2.fromScale(0.755, 0.1), Color3.fromRGB(70, 90, 150))
local multiB = btn(panel, "Select", UDim2.fromScale(0.1, 0.06), UDim2.fromScale(0.88, 0.1), Color3.fromRGB(120, 90, 50))
-- Fuse Machine (shown in select mode): 5 monsters of one rarity -> 1 random monster of the next rarity
local fuseB = btn(panel, "", UDim2.fromScale(0.2, 0.05), UDim2.fromScale(0.78, 0.03), Color3.fromRGB(120, 70, 190))
fuseB.Visible = false
local grid = Instance.new("ScrollingFrame") grid.Position = UDim2.fromScale(0.02, 0.19) grid.Size = UDim2.fromScale(0.6, 0.79)
grid.BackgroundTransparency = 1 grid.BorderSizePixel = 0 grid.CanvasSize = UDim2.new() grid.AutomaticCanvasSize = Enum.AutomaticSize.Y grid.ScrollBarThickness = 8 grid.Parent = panel
local gl = Instance.new("UIGridLayout") gl.CellSize = UDim2.fromOffset(132, 92) gl.CellPadding = UDim2.fromOffset(8, 8)
gl.SortOrder = Enum.SortOrder.LayoutOrder gl.HorizontalAlignment = Enum.HorizontalAlignment.Center gl.Parent = grid
local detail = Instance.new("Frame") detail.Position = UDim2.fromScale(0.64, 0.19) detail.Size = UDim2.fromScale(0.34, 0.79)
detail.BackgroundColor3 = Color3.fromRGB(42, 48, 62) detail.Parent = panel
Instance.new("UICorner", detail)
local dl = Instance.new("UIListLayout") dl.Padding = UDim.new(0, 6) dl.SortOrder = Enum.SortOrder.LayoutOrder dl.HorizontalAlignment = Enum.HorizontalAlignment.Center dl.Parent = detail
local dp = Instance.new("UIPadding") dp.PaddingTop = UDim.new(0, 8) dp.Parent = detail

local selected, pendingSell
local refreshDetail

local function say(ok, err, okText)
	msg.TextColor3 = ok and Color3.fromRGB(140, 255, 140) or Color3.fromRGB(255, 140, 140)
	msg.Text = ok and (okText or "") or (err or "")
end

local function refreshGrid()
	for _, c in grid:GetChildren() do if c:IsA("GuiButton") then c:Destroy() end end
	local mons, placed, team = decode("Monsters"), decode("Placed"), decode("Team")
	local onBase = {}
	for sk, iid in placed do onBase[iid] = sk end
	local q, rar = search.Text:lower(), Config.Rarities[filterI]
	local items, total = {}, 0
	for iid, m in mons do
		total += 1
		local def = Config.ById[m.id]
		local el, ro = ELEMENTS[elemI], ROLES[roleI]
		if def and (q == "" or nameOf(m):lower():find(q, 1, true)) and (not rar or def.rarity == rar.id)
			and (not el or def.element == el) and (not ro or Config.RoleByElement[def.element] == ro) then
			table.insert(items, { iid = iid, m = m, def = def })
		end
	end
	local cmp = SORTS[sortI][2]
	table.sort(items, function(a, b)
		if (a.m.fav == true) ~= (b.m.fav == true) then return a.m.fav == true end -- favorites first
		return cmp(a, b)
	end)
	sortB.Text = "Sort: " .. SORTS[sortI][1]
	filterB.Text = rar and rar.id or "All rarities"
	countL.Text = total .. " / " .. (state:GetAttribute("Capacity") or 100) .. " monsters"
	elemB.Text = ELEMENTS[elemI] or "All elements"
	roleB.Text = ROLES[roleI] or "All roles"
	local n = 0 for iid in picked do if mons[iid] then n += 1 else picked[iid] = nil end end
	multiB.Text = multi and ("Sell " .. n) or "Select"
	fuseB.Visible = multi
	fuseB.Text = "⚗️ Fuse Machine " .. n .. "/5"
	for i, it in items do
		if i > 300 then break end -- keep the grid light; search narrows it
		local rc = Config.RarityById[it.def.rarity]
		local b = btn(grid, "", UDim2.new(), UDim2.new(), Color3.fromRGB(48, 54, 72))
		b.LayoutOrder = i
		local st = b:FindFirstChildOfClass("UIStroke")
		local hi = multi and picked[it.iid] or (not multi and it.iid == selected)
		st.Color = hi and Color3.new(1, 1, 1) or rc.color
		st.Thickness = hi and 5 or 3
		local mut = it.m.mu and Traits.MutationById[it.m.mu]
		text("TextLabel", b, nameOf(it.m), UDim2.new(1, -8, 0.32, 0), UDim2.fromOffset(4, 4), mut and mut.color or rc.color)
		text("TextLabel", b, "Lv " .. it.m.lvl .. (it.m.fr > 0 and ("  ★" .. it.m.fr) or ""), UDim2.new(1, -8, 0.22, 0), UDim2.new(0, 4, 0.36, 0))
		text("TextLabel", b, "$" .. short(it.m.inc) .. "/s", UDim2.new(1, -8, 0.2, 0), UDim2.new(0, 4, 0.58, 0), Color3.fromRGB(120, 255, 120))
		local tags = (it.m.lock and "🔒" or "") .. (it.m.fav and "⭐" or "") .. (onBase[it.iid] and "🏠" or "") .. (table.find(team, it.iid) and "⚔️" or "")
		text("TextLabel", b, tags, UDim2.new(1, -8, 0.18, 0), UDim2.new(0, 4, 0.8, 0))
		b.MouseButton1Click:Connect(function()
			if multi then
				picked[it.iid] = not picked[it.iid] or nil
				refreshGrid()
				return
			end
			selected, pendingSell = it.iid, nil
			msg.Text = ""
			refreshGrid()
			refreshDetail()
		end)
	end
end

refreshDetail = function()
	for _, c in detail:GetChildren() do if c:IsA("GuiObject") then c:Destroy() end end
	local mons = decode("Monsters")
	local m = selected and mons[selected]
	local order = 0
	local function line(str, color, h)
		order += 1
		local l = text("TextLabel", detail, str, UDim2.new(0.94, 0, 0, h or 24), UDim2.new(), color)
		l.LayoutOrder = order
		return l
	end
	local function action(str, color, fn)
		order += 1
		local b = btn(detail, str, UDim2.new(0.9, 0, 0, 40), UDim2.new(), color)
		b.LayoutOrder = order
		b.MouseButton1Click:Connect(fn)
		return b
	end
	if not m then line("Tap a monster to see its details", Color3.fromRGB(200, 200, 210)) return end
	local def = Config.ById[m.id]
	local rc = Config.RarityById[def.rarity]
	local placed, team, gear = decode("Placed"), decode("Team"), decode("Gear")
	local slot
	for sk, iid in placed do if iid == selected then slot = sk end end
	line(nameOf(m), rc.color, 32)
	line(def.rarity .. " • " .. def.element .. " • " .. (m.role or "") .. (slot and ("  •  on slot " .. slot) or ""), rc.color)
	line(Config.Lore[m.id] or "", Color3.fromRGB(190, 190, 210), 18)
	local mut, trait = m.mu and Traits.MutationById[m.mu], m.tr and Traits.TraitById[m.tr]
	if mut then line("Mutation: " .. mut.name .. " (x" .. mut.mult .. " income)", mut.color) end
	line(trait and ("Trait: " .. trait.name .. " (x" .. trait.income .. " income, x" .. trait.combat .. " combat)") or "Trait: none",
		trait and trait.color or Color3.fromRGB(170, 170, 180))
	line("Level " .. m.lvl .. " / " .. F.MAX_LEVEL .. "   Fusion ★" .. m.fr .. " / " .. F.MAX_FUSION)
	line("Income $" .. short(m.inc) .. "/s" .. (m.nxt and ("  →  $" .. short(m.nxt) .. "/s") or ""), Color3.fromRGB(120, 255, 120))
	line(("HP %s   DMG %s   SPD %s"):format(short(m.hp or 0), short(m.dmg or 0), tostring(m.spd or 0)), Color3.fromRGB(255, 200, 200))
	local worn = {}
	for _, g in gear do if g.m == selected then table.insert(worn, Gear.TypeById[g.t].icon .. " " .. Gear.name(g)) end end
	line(#worn > 0 and table.concat(worn, "  ") or "No gear (equip from the GEAR bag)", Color3.fromRGB(190, 200, 230), 20)

	if m.cost then
		action("Upgrade  $" .. short(m.cost), Color3.fromRGB(50, 170, 70), function()
			local ok, err = Inv:InvokeServer("upgrade", selected)
			say(ok, err, "Upgraded!")
		end)
	end
	action(m.lock and "🔓 Unlock" or "🔒 Lock", Color3.fromRGB(110, 110, 130), function()
		say(Inv:InvokeServer("lock", selected, not m.lock))
	end)
	action(m.fav and "Unfavorite" or "⭐ Favorite", Color3.fromRGB(150, 130, 50), function()
		say(Inv:InvokeServer("fav", selected, not m.fav))
	end)
	local inTeam = table.find(team, selected)
	action(inTeam and "Remove from team" or "⚔️ Add to battle team", Color3.fromRGB(170, 70, 60), function()
		local new = table.clone(team)
		if inTeam then table.remove(new, inTeam)
		elseif #new >= 3 then say(false, "Team is full (3). Remove one first.") return
		else table.insert(new, selected) end
		say(BattleAction:InvokeServer("team", #new > 0 and new or nil))
	end)
	-- fusion: this monster + 2 free copies (same monster and variant, not locked, not on the base)
	local copies = {}
	for iid, o in mons do
		local onBase = false
		for _, p in placed do if p == iid then onBase = true end end
		if iid ~= selected and o.id == m.id and o.v == m.v and not o.lock and not onBase then table.insert(copies, { iid = iid, lvl = o.lvl }) end
	end
	table.sort(copies, function(a, b) return a.lvl < b.lvl end)
	local need = (state:GetAttribute("FuseCopies") or F.FUSE_COPIES) - 1
	if m.fr < F.MAX_FUSION then
		action("Fuse ★" .. m.fr + 1 .. "  (" .. math.min(#copies, need) .. "/" .. need .. " copies, $" .. short(m.fuse) .. ")",
			Color3.fromRGB(120, 70, 190), function()
				if #copies < need then say(false, "Need " .. need .. " free unlocked copies") return end
				local mats = {}
				for k = 1, need do mats[k] = copies[k].iid end
				local ok, err = Inv:InvokeServer("fuse", selected, mats)
				say(ok, err, "Fused to ★" .. m.fr + 1 .. "!")
			end)
	end
	local function sell(ids, label)
		local ok, res, flag = Inv:InvokeServer("sell", ids, pendingSell == label)
		if not ok and flag == "confirm" then pendingSell = label say(false, res .. " Tap again to confirm.") return end
		pendingSell = nil
		if ok and table.find(ids, selected) then selected = nil end
		say(ok, res, ok and ("Sold for $" .. short(res)) or nil)
	end
	action("🎲 Reroll Trait (" .. Traits.TRAIT_COST .. " 💎, you have " .. (state:GetAttribute("Gems") or 0) .. ")", Color3.fromRGB(70, 120, 200), function()
		local ok, res = Inv:InvokeServer("trait", selected)
		say(ok, res, ok and ("New trait: " .. Traits.TraitById[res].name) or nil)
	end)
	-- trait odds, shown before spending Gems
	local odds, parts = Traits.traitOdds(), {}
	for _, t in Traits.Traits do table.insert(parts, t.name .. " " .. ("%.2f"):format(odds[t.id] * 100) .. "%") end
	line(table.concat(parts, " • "), Color3.fromRGB(170, 170, 190), 30).TextWrapped = true
	action("Sell  $" .. short(m.sell), Color3.fromRGB(200, 120, 40), function() sell({ selected }, "one") end)
	local dupes = {}
	for _, c in copies do if not mons[c.iid].fav and #dupes < 100 then table.insert(dupes, c.iid) end end
	if #dupes > 0 then
		action("Sell " .. #dupes .. " duplicate(s), keep this one", Color3.fromRGB(170, 90, 30), function() sell(dupes, "dupes") end)
	end
end

sortB.MouseButton1Click:Connect(function() sortI = sortI % #SORTS + 1 refreshGrid() end)
filterB.MouseButton1Click:Connect(function() filterI = (filterI + 1) % (#Config.Rarities + 1) refreshGrid() end)
elemB.MouseButton1Click:Connect(function() elemI = (elemI + 1) % (#ELEMENTS + 1) refreshGrid() end)
roleB.MouseButton1Click:Connect(function() roleI = (roleI + 1) % (#ROLES + 1) refreshGrid() end)
-- first tap enters select mode; with picks, tap sells them (locked/placed ones are refused by the server)
local confirmMulti = false
multiB.MouseButton1Click:Connect(function()
	local ids = {}
	for iid in picked do table.insert(ids, iid) end
	if not multi or #ids == 0 then
		multi = not multi
		table.clear(picked)
		msg.Text = multi and "Tap monsters to pick them, then Sell them or put 5 of one rarity in the Fuse Machine" or ""
		refreshGrid()
		return
	end
	local ok, res, flag = Inv:InvokeServer("sell", ids, confirmMulti)
	if not ok and flag == "confirm" then confirmMulti = true say(false, res .. " Tap Sell again to confirm.") return end
	confirmMulti = false
	if ok then multi = false table.clear(picked) end
	say(ok, res, ok and ("Sold " .. #ids .. " for $" .. short(res)) or nil)
	refreshGrid()
end)
fuseB.MouseButton1Click:Connect(function()
	local ids = {}
	for iid in picked do table.insert(ids, iid) end
	local ok, res = Inv:InvokeServer("upfuse", ids)
	if ok then multi = false table.clear(picked) end
	say(ok, res, ok and ("Fused into " .. (Config.ById[res.id] and Config.ById[res.id].name or res.id) .. "!") or nil)
	refreshGrid()
end)
search:GetPropertyChangedSignal("Text"):Connect(function() if panel.Visible then refreshGrid() end end)
for _, a in { "Monsters", "Placed", "Team", "Gear", "Gems" } do
	state:GetAttributeChangedSignal(a):Connect(function()
		if not panel.Visible then return end
		refreshGrid()
		refreshDetail()
	end)
end
hud.MouseButton1Click:Connect(function()
	panel.Visible = not panel.Visible
	if panel.Visible then msg.Text = "" refreshGrid() refreshDetail() end
end)
