-- Mock Roblox runtime: just enough of the engine (instances, attributes, signals, task scheduler with virtual
-- time, JSON-round-tripping DataStore with failure injection) to run the real server scripts headless.
-- It is a stand-in, not Roblox: physics, replication, rendering and real DataStore limits are not modeled.
local R = {}
local ROOT = "src/"

-- SCHEDULER (virtual time)
local now, queue, seq = 0, {}, 0
local function schedule(t, co, ...)
	seq += 1
	table.insert(queue, { t = t, s = seq, co = co, args = table.pack(...) })
end
local function resume(co, ...)
	local ok, err = coroutine.resume(co, ...)
	if not ok then
		R.errors = R.errors or {}
		table.insert(R.errors, tostring(err) .. "\n" .. debug.traceback(co))
		print("SCRIPT ERROR: " .. tostring(err))
	end
end
local task = {}
function task.spawn(f, ...)
	local co = type(f) == "thread" and f or coroutine.create(f)
	resume(co, ...)
	return co
end
function task.defer(f, ...)
	local co = type(f) == "thread" and f or coroutine.create(f)
	schedule(now, co, ...)
	return co
end
function task.delay(d, f, ...)
	local co = coroutine.create(f)
	schedule(now + (d or 0), co, ...)
	return co
end
function task.wait(d)
	local co = coroutine.running()
	schedule(now + math.max(d or 0, 1 / 60), co)
	coroutine.yield()
	return d
end
function R.run(dt)
	local stop = now + dt
	while true do
		table.sort(queue, function(a, b) if a.t ~= b.t then return a.t < b.t end return a.s < b.s end)
		local e = queue[1]
		if not e or e.t > stop then break end
		table.remove(queue, 1)
		now = math.max(now, e.t)
		if coroutine.status(e.co) == "suspended" then resume(e.co, table.unpack(e.args, 1, e.args.n)) end
	end
	now = stop
end
R.timeOffset = 1700000000
local fakeOs = setmetatable({ clock = function() return now end, time = function() return math.floor(R.timeOffset + now) end }, { __index = os })

-- SIGNALS
local Signal = {}
Signal.__index = Signal
local function newSignal() return setmetatable({ handlers = {} }, Signal) end
function Signal:Connect(fn)
	local h = { fn = fn, on = true }
	table.insert(self.handlers, h)
	return { Disconnect = function() h.on = false end, Connected = true }
end
function Signal:Fire(...)
	for _, h in table.clone(self.handlers) do if h.on then task.spawn(h.fn, ...) end end
end
function Signal:Wait()
	local co = coroutine.running()
	local c
	c = self:Connect(function(...) c.Disconnect() task.spawn(co, ...) end)
	return coroutine.yield()
end

-- MATH TYPES
local V3 = {}
V3.__index = function(v, k)
	if k == "Magnitude" then return math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z) end
	if k == "Unit" then local m = math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z) return Vector3new(v.X / m, v.Y / m, v.Z / m) end
	return nil
end
function Vector3new(x, y, z) return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, V3) end
V3.__add = function(a, b) return Vector3new(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
V3.__sub = function(a, b) return Vector3new(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
V3.__mul = function(a, b)
	if type(a) == "number" then a, b = b, a end
	if type(b) == "number" then return Vector3new(a.X * b, a.Y * b, a.Z * b) end
	return Vector3new(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
V3.__div = function(a, b) return Vector3new(a.X / b, a.Y / b, a.Z / b) end
V3.__unm = function(a) return Vector3new(-a.X, -a.Y, -a.Z) end
local Vector3 = { new = Vector3new, zAxis = Vector3new(0, 0, 1), xAxis = Vector3new(1, 0, 0), yAxis = Vector3new(0, 1, 0) }
local CF = {}
CF.__index = function(c, k)
	if k == "Position" or k == "p" then return c.pos end
	if k == "LookVector" then return Vector3new(0, 0, -1) end
	if k == "X" then return c.pos.X elseif k == "Y" then return c.pos.Y elseif k == "Z" then return c.pos.Z end
	return nil
end
local function cfnew(x, y, z)
	if type(x) == "table" then return setmetatable({ pos = x }, CF) end
	return setmetatable({ pos = Vector3new(x, y, z) }, CF)
end
CF.__mul = function(a, b)
	if getmetatable(b) == CF then return cfnew(a.pos + b.pos) end
	return a.pos + b
end
CF.__add = function(a, v) return cfnew(a.pos + v) end
CF.__sub = function(a, v) return cfnew(a.pos - v) end
local CFrame = { new = cfnew, lookAt = function(a) return cfnew(a) end, Angles = function() return cfnew(0, 0, 0) end, identity = cfnew(0, 0, 0) }
local C3 = {}
C3.__index = { Lerp = function(c, o, t) return setmetatable({ R = c.R + (o.R - c.R) * t, G = c.G + (o.G - c.G) * t, B = c.B + (o.B - c.B) * t }, C3) end }
local Color3 = {
	new = function(r, g, b) return setmetatable({ R = r or 0, G = g or 0, B = b or 0 }, C3) end,
	fromRGB = function(r, g, b) return setmetatable({ R = r / 255, G = g / 255, B = b / 255 }, C3) end,
	fromHSV = function() return setmetatable({ R = 0.5, G = 0.5, B = 0.5 }, C3) end,
}
local function proxy(path)
	return setmetatable({}, { __index = function(_, k) return proxy(path .. "." .. k) end, __tostring = function() return path end })
end
local Enum = proxy("Enum")
local UDim2 = { new = function(...) return { ... } end, fromScale = function(...) return { ... } end, fromOffset = function(...) return { ... } end }
local UDim = { new = function(...) return { ... } end }
local Vector2 = { new = function(x, y) return { X = x, Y = y } end }

-- INSTANCES
local Inst = {}
local IsA = {
	Part = { BasePart = true, PVInstance = true }, SpawnLocation = { BasePart = true, Part = true }, Model = { PVInstance = true },
	ScreenGui = { LayerCollector = true }, BillboardGui = { LayerCollector = true }, SurfaceGui = { LayerCollector = true },
	TextLabel = { GuiObject = true }, TextButton = { GuiObject = true, GuiButton = true }, Frame = { GuiObject = true },
	NumberValue = { ValueBase = true }, IntValue = { ValueBase = true },
}
local EVENTS = { PromptGamePassPurchaseFinished = true, OnClientEvent = true, Triggered = true, CharacterAdded = true, Event = true, Destroying = true, DescendantAdded = true, PlayerAdded = true, PlayerRemoving = true }
local Methods = {}
local function newInst(class, name)
	local o = { ClassName = class, Name = name or class, _kids = {}, _attrs = {}, _asig = {}, _ev = {} }
	return setmetatable(o, Inst)
end
Inst.__index = function(t, k)
	if Methods[k] then return Methods[k] end
	if k == "Parent" then return rawget(t, "_parent") end
	if EVENTS[k] then
		local ev = rawget(t, "_ev")
		ev[k] = ev[k] or newSignal()
		return ev[k]
	end
	if k == "Position" and rawget(t, "CFrame") then return rawget(t, "CFrame").pos end
	for _, c in rawget(t, "_kids") do if c.Name == k then return c end end
	return nil
end
local function fireDescAdded(p, c)
	local a = p
	while a do
		local ev = rawget(a, "_ev")
		if ev.DescendantAdded then ev.DescendantAdded:Fire(c) end
		a = rawget(a, "_parent")
	end
end
Inst.__newindex = function(t, k, v)
	if k == "Parent" then
		local old = rawget(t, "_parent")
		if old then
			local kids = rawget(old, "_kids")
			local i = table.find(kids, t)
			if i then table.remove(kids, i) end
		end
		rawset(t, "_parent", v)
		if v then table.insert(rawget(v, "_kids"), t) fireDescAdded(v, t) end
		return
	end
	rawset(t, k, v)
end
Inst.__tostring = function(t) return t.Name end
function Methods:GetChildren() return table.clone(rawget(self, "_kids")) end
function Methods:GetDescendants()
	local out = {}
	local function walk(i) for _, c in rawget(i, "_kids") do table.insert(out, c) walk(c) end end
	walk(self)
	return out
end
function Methods:FindFirstChild(name, rec)
	for _, c in rawget(self, "_kids") do if c.Name == name then return c end end
	if rec then for _, c in rawget(self, "_kids") do local f = c:FindFirstChild(name, true) if f then return f end end end
	return nil
end
function Methods:IsA(c) return self.ClassName == c or c == "Instance" or (IsA[self.ClassName] and IsA[self.ClassName][c]) or false end
function Methods:FindFirstChildOfClass(c) for _, k in rawget(self, "_kids") do if k.ClassName == c then return k end end return nil end
function Methods:FindFirstChildWhichIsA(c, rec)
	for _, k in rawget(self, "_kids") do if k:IsA(c) then return k end end
	if rec then for _, k in rawget(self, "_kids") do local f = k:FindFirstChildWhichIsA(c, true) if f then return f end end end
	return nil
end
function Methods:FindFirstAncestor(name)
	local a = self.Parent
	while a do if a.Name == name then return a end a = a.Parent end
	return nil
end
function Methods:WaitForChild(name, timeout)
	local start = now
	while true do
		local c = self:FindFirstChild(name)
		if c then return c end
		if timeout and now - start >= timeout then return nil end
		task.wait(0.1)
	end
end
function Methods:Destroy()
	for _, c in self:GetChildren() do c:Destroy() end
	local ev = rawget(self, "_ev")
	if ev.Destroying then ev.Destroying:Fire() end
	self.Parent = nil
	rawset(self, "_destroyed", true)
end
function Methods:ClearAllChildren() for _, c in self:GetChildren() do c:Destroy() end end
function Methods:SetAttribute(k, v)
	local a = rawget(self, "_attrs")
	if a[k] == v then return end
	a[k] = v
	local s = rawget(self, "_asig")[k]
	if s then s:Fire() end
end
function Methods:GetAttribute(k) return rawget(self, "_attrs")[k] end
function Methods:GetAttributeChangedSignal(k)
	local s = rawget(self, "_asig")
	s[k] = s[k] or newSignal()
	return s[k]
end
function Methods:PivotTo(cf) rawset(self, "_pivot", cf) end
function Methods:GetPivot() return rawget(self, "_pivot") or cfnew(0, 0, 0) end
function Methods:GetBoundingBox() return self:GetPivot(), Vector3new(4, 4, 4) end
function Methods:ScaleTo() end
function Methods:GetScale() return 1 end
function Methods:Fire(...) self.Event:Fire(...) end
function Methods:Kick(msg) rawset(self, "kicked", msg or true) R.leave(self) end
function Methods:Clone() local c = newInst(self.ClassName, self.Name) return c end
function Methods:Invoke(...) return self.OnInvoke(...) end
local Instance = { new = function(class, parent)
	local o = newInst(class)
	if class == "Part" or class == "SpawnLocation" then
		rawset(o, "Size", Vector3new(4, 1, 2))
		rawset(o, "CFrame", cfnew(0, 0, 0))
	end
	if parent then o.Parent = parent end
	return o
end }

-- JSON (shapes like Roblox HttpService: array if keys are 1..n, else object with string keys)
local function encode(v)
	local t = type(v)
	if t == "nil" then return "null" end
	if t == "boolean" then return tostring(v) end
	if t == "number" then
		if v ~= v or v == math.huge or v == -math.huge then error("JSON can't encode " .. tostring(v)) end
		if v == math.floor(v) and math.abs(v) < 1e15 then return string.format("%d", v) end
		return string.format("%.17g", v)
	end
	if t == "string" then return '"' .. v:gsub('[%c"\\]', function(c) return string.format("\\u%04x", c:byte()) end) .. '"' end
	if t == "table" then
		local n, count = #v, 0
		for _ in v do count += 1 end
		local out = {}
		if count == n and n > 0 then
			for i = 1, n do out[i] = encode(v[i]) end
			return "[" .. table.concat(out, ",") .. "]"
		end
		for k, x in v do
			if type(k) ~= "string" and type(k) ~= "number" then error("bad JSON key " .. type(k)) end
			table.insert(out, encode(tostring(k)) .. ":" .. encode(x))
		end
		return "{" .. table.concat(out, ",") .. "}"
	end
	error("JSON can't encode " .. t)
end
local function decode(s)
	local i = 1
	local function ws() i = s:find("[^%s]", i) or #s + 1 end
	local val
	local function str()
		local out, j = {}, i + 1
		while true do
			local c = s:sub(j, j)
			if c == '"' then i = j + 1 return table.concat(out) end
			if c == "\\" then
				local n = s:sub(j + 1, j + 1)
				if n == "u" then table.insert(out, string.char(tonumber(s:sub(j + 2, j + 5), 16) % 256)) j += 6
				else table.insert(out, ({ n = "\n", t = "\t", r = "\r", b = "\b", f = "\f" })[n] or n) j += 2 end
			else table.insert(out, c) j += 1 end
		end
	end
	function val()
		ws()
		local c = s:sub(i, i)
		if c == "{" then
			local o = {}
			i += 1 ws()
			if s:sub(i, i) == "}" then i += 1 return o end
			while true do
				ws() local k = str() ws() i += 1 -- :
				o[k] = val() ws()
				local d = s:sub(i, i) i += 1
				if d == "}" then return o end
			end
		elseif c == "[" then
			local a = {}
			i += 1 ws()
			if s:sub(i, i) == "]" then i += 1 return a end
			while true do
				table.insert(a, val()) ws()
				local d = s:sub(i, i) i += 1
				if d == "]" then return a end
			end
		elseif c == '"' then return str()
		elseif s:sub(i, i + 3) == "true" then i += 4 return true
		elseif s:sub(i, i + 4) == "false" then i += 5 return false
		elseif s:sub(i, i + 3) == "null" then i += 4 return nil
		else
			local num = s:match("^-?[%d%.eE+-]+", i)
			i += #num
			return tonumber(num)
		end
	end
	return val()
end
R.encode, R.decode = encode, decode

-- SERVICES
local game = newInst("DataModel", "game")
local services = {}
local function svc(name, class)
	local s = newInst(class or name, name)
	s.Parent = game
	services[name] = s
	return s
end
local workspace = svc("Workspace")
local Players = svc("Players")
local RS = svc("ReplicatedStorage")
local SS = svc("ServerStorage")
local SSS = svc("ServerScriptService")
svc("RunService").IsStudio = function() return R.studio == true end
svc("Debris").AddItem = function(_, inst, t) task.delay(t, function() inst:Destroy() end) end
svc("CollectionService").AddTag = function() end
local guid = 0
svc("HttpService").JSONEncode = function(_, v) return encode(v) end
services.HttpService.JSONDecode = function(_, s) return decode(s) end
services.HttpService.GenerateGUID = function() guid += 1 return "guid-" .. guid end
-- DataStore: values are JSON round-tripped like the real service; failNext injects errors
R.store = {}
R.failNext = 0
R.dsCalls = 0
local Store = {}
function Store:UpdateAsync(key, fn)
	R.dsCalls += 1
	task.wait(0.05)
	if R.failNext > 0 then R.failNext -= 1 error("502: simulated DataStore outage") end
	local raw = R.store[key]
	local new = fn(raw and decode(raw) or nil)
	if new ~= nil then R.store[key] = encode(new) end
	return new
end
function Store:GetAsync(key) local raw = R.store[key] return raw and decode(raw) or nil end
svc("DataStoreService").GetDataStore = function() return Store end
game.JobId = "server-A"
function game:GetService(n) return services[n] end
function game:BindToClose(fn) R.closers = R.closers or {} table.insert(R.closers, fn) end
local mps = svc("MarketplaceService")
mps.UserOwnsGamePassAsync = function() return false end
mps.PromptGamePassPurchase = function() end
mps.PromptProductPurchase = function() end
rawget(mps, "_ev").PromptGamePassPurchaseFinished = newSignal()
local playerList = {}
function Players:GetPlayerByUserId(id) for _, p in playerList do if p.UserId == id and p.Parent then return p end end return nil end
function Players:GetPlayers() local o = {} for _, p in playerList do if p.Parent then table.insert(o, p) end end return o end

local Random = {}
Random.__index = Random
function Random.new(seed) return setmetatable({ s = math.floor((seed or 12345) % 2147483646) + 1 }, Random) end
function Random:NextNumber(a, b)
	self.s = (self.s * 48271) % 2147483647
	local x = self.s / 2147483647
	if a then return a + (b - a) * x end
	return x
end
function Random:NextInteger(a, b) return a + math.floor(self:NextNumber() * (b - a + 1)) end

-- MODULE LOADING
local env
local cache = {}
local function load(path, scriptInst)
	local src = readfile(path)
	local f = compile("local script = ...\n" .. src, path:match("[^/]+$"))
	setfenv(f, env)
	return f(scriptInst)
end
local function req(inst)
	if R.stubs and R.stubs[inst.Name] then return R.stubs[inst.Name] end
	if cache[inst] then return cache[inst] end
	assert(inst and rawget(inst, "_path"), "require of unknown module " .. tostring(inst))
	cache[inst] = load(rawget(inst, "_path"), inst)
	return cache[inst]
end
local function module(parent, name, path)
	local m = newInst("ModuleScript", name)
	rawset(m, "_path", path)
	m.Parent = parent
	return m
end
local mon = newInst("Folder", "Monster")
mon.Parent = RS
for _, n in { "MonsterConfig", "Weighted", "LuckConfig", "Formulas", "RebirthConfig", "GearConfig", "BattleConfig", "DiceConfig", "SkillTree", "AssetRegistry", "MonsterModel", "ProgressConfig" } do
	module(mon, n, ROOT .. "shared/Monster/" .. n .. ".luau")
end
for _, n in { "PlaceMonster", "BuySkill", "Rebirth", "DiceAction", "ChestAction", "BattleAction", "InventoryAction", "RollAction", "ProgressAction", "ShopAction" } do
	local rf = newInst("RemoteFunction", n)
	rf.Parent = mon
end
local ann = newInst("RemoteEvent", "Announce")
ann.Parent = mon
R.announced = {}
function Methods:FireAllClients(...) table.insert(R.announced, { ... }) end
function Methods:FireClient(...) end
for _, n in { "DataService", "DataSchema", "Game", "Guard", "BattleEngine" } do module(SSS, n, ROOT .. "server/" .. n .. ".luau") end
local tests = newInst("Folder", "Tests")
tests.Parent = SS
for _, n in { "RollSpec", "BattleSpec", "ProgressionSpec", "RunAll" } do module(tests, n, ROOT .. "serverstorage/Tests/" .. n .. ".luau") end

env = setmetatable({
	game = game, workspace = workspace, Instance = Instance, Vector3 = Vector3, Vector2 = Vector2, CFrame = CFrame, Color3 = Color3,
	Enum = Enum, UDim2 = UDim2, UDim = UDim, task = task, os = fakeOs, require = req, typeof = function(v)
		local mt = getmetatable(v)
		if mt == Inst then return "Instance" elseif mt == V3 then return "Vector3" elseif mt == CF then return "CFrame" end
		return type(v)
	end,
	Random = Random, warn = function(...) R.warnings = R.warnings or {} table.insert(R.warnings, table.concat(table.pack(...), " ")) end,
}, { __index = _G })
R.env, R.game, R.services, R.Instance, R.newInst, R.task = env, game, services, Instance, newInst, task
R.Vector3, R.CFrame, R.Color3 = Vector3, CFrame, Color3
R.req, R.SSS, R.RS, R.SS = req, SSS, RS, SS
function R.runScript(path, name)
	local s = newInst("Script", name)
	s.Parent = SSS
	task.spawn(function() load(path, s) end)
end

-- players
function R.join(userId, name)
	local p = newInst("Player", name)
	rawset(p, "UserId", userId)
	rawset(p, "DisplayName", name)
	local pg = newInst("PlayerGui", "PlayerGui")
	pg.Parent = p
	p.Parent = Players
	table.insert(playerList, p)
	Players.PlayerAdded:Fire(p)
	return p
end
function R.leave(p)
	if not p.Parent then return end
	Players.PlayerRemoving:Fire(p)
	task.defer(function() p.Parent = nil end)
end
function R.state(p) return p.PlayerGui:FindFirstChild("State") end
function R.attr(p, k)
	local s = R.state(p)
	local v = s and s:GetAttribute(k)
	if type(v) == "string" and (v:sub(1, 1) == "{" or v:sub(1, 1) == "[") then return decode(v) end
	return v
end
function R.invoke(name, p, ...)
	local rf = mon:FindFirstChild(name)
	local res
	local args = table.pack(...)
	task.spawn(function() res = table.pack(rf.OnServerInvoke(p, table.unpack(args, 1, args.n))) end)
	R.run(0.3)
	assert(res, name .. " never returned")
	return table.unpack(res, 1, res.n)
end
function R.now() return now end
return R
