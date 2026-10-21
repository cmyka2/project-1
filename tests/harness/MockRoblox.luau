-- A small, permissive Roblox engine mock for headless tests under Lune.
-- Datatypes (Vector3, CFrame, Color3, UDim2, Enum...) come from @lune/roblox;
-- Instances, signals, services and DataStores are implemented here in plain
-- Luau. Unknown properties read as nil; unknown methods error loudly so tests
-- reveal engine APIs the mock does not cover yet.

local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local Scheduler = require("./Scheduler")

local Mock = {}

local rawTypeof = typeof

---------------------------------------------------------------------------
-- Signals
---------------------------------------------------------------------------
local SignalMeta = {}
SignalMeta.__index = SignalMeta
local ConnectionMeta = {}
ConnectionMeta.__index = ConnectionMeta

local function newSignal(name)
	return setmetatable({ _name = name or "Signal", _handlers = {}, _waiting = {} }, SignalMeta)
end
Mock.newSignal = newSignal

function SignalMeta:Connect(fn)
	assert(type(fn) == "function", "Connect expects a function")
	local conn = setmetatable({ Connected = true, _signal = self, _fn = fn }, ConnectionMeta)
	table.insert(self._handlers, conn)
	return conn
end

function SignalMeta:Once(fn)
	local conn
	conn = self:Connect(function(...)
		conn:Disconnect()
		fn(...)
	end)
	return conn
end

function SignalMeta:Fire(...)
	local snapshot = table.clone(self._handlers)
	for _, conn in snapshot do
		if conn.Connected then
			Scheduler.task.spawn(conn._fn, ...)
		end
	end
	local waiting = self._waiting
	self._waiting = {}
	for _, thread in waiting do
		Scheduler.task.spawn(thread, ...)
	end
end

function SignalMeta:Wait()
	table.insert(self._waiting, coroutine.running())
	return coroutine.yield()
end

function SignalMeta:DisconnectAll()
	for _, conn in self._handlers do
		conn.Connected = false
	end
	table.clear(self._handlers)
end

function ConnectionMeta:Disconnect()
	if not self.Connected then
		return
	end
	self.Connected = false
	local list = self._signal._handlers
	local index = table.find(list, self)
	if index then
		table.remove(list, index)
	end
end

---------------------------------------------------------------------------
-- Instances
---------------------------------------------------------------------------
local INHERITANCE = {
	Part = { "BasePart", "PVInstance" },
	MeshPart = { "BasePart", "PVInstance" },
	WedgePart = { "BasePart", "PVInstance" },
	CornerWedgePart = { "BasePart", "PVInstance" },
	TrussPart = { "BasePart", "PVInstance" },
	SpawnLocation = { "Part", "BasePart", "PVInstance" },
	Seat = { "Part", "BasePart", "PVInstance" },
	UnionOperation = { "BasePart", "PVInstance" },
	Terrain = { "BasePart", "PVInstance" },
	Model = { "PVInstance" },
	Workspace = { "Model", "PVInstance" },
	Frame = { "GuiObject", "GuiBase2d" },
	ScrollingFrame = { "GuiObject", "GuiBase2d" },
	TextLabel = { "GuiObject", "GuiBase2d" },
	TextButton = { "GuiButton", "GuiObject", "GuiBase2d" },
	ImageLabel = { "GuiObject", "GuiBase2d" },
	ImageButton = { "GuiButton", "GuiObject", "GuiBase2d" },
	TextBox = { "GuiObject", "GuiBase2d" },
	ViewportFrame = { "GuiObject", "GuiBase2d" },
	CanvasGroup = { "GuiObject", "GuiBase2d" },
	ScreenGui = { "LayerCollector", "GuiBase2d" },
	BillboardGui = { "LayerCollector", "GuiBase2d" },
	SurfaceGui = { "LayerCollector", "GuiBase2d" },
	PointLight = { "Light" },
	SpotLight = { "Light" },
	SurfaceLight = { "Light" },
	Script = { "BaseScript", "LuaSourceContainer" },
	LocalScript = { "Script", "BaseScript", "LuaSourceContainer" },
	ModuleScript = { "LuaSourceContainer" },
	Player = {},
	Humanoid = {},
	Motor6D = { "JointInstance" },
	Weld = { "JointInstance" },
	Snap = { "JointInstance" },
}

local SIGNAL_NAMES = {
	Changed = true,
	ChildAdded = true,
	ChildRemoved = true,
	DescendantAdded = true,
	DescendantRemoving = true,
	Destroying = true,
	AncestryChanged = true,
	Touched = true,
	TouchEnded = true,
	Triggered = true,
	TriggerEnded = true,
	PromptShown = true,
	PromptHidden = true,
	OnServerEvent = true,
	OnClientEvent = true,
	Event = true,
	Died = true,
	Running = true,
	HealthChanged = true,
	CharacterAdded = true,
	CharacterRemoving = true,
	CharacterAppearanceLoaded = true,
	PlayerAdded = true,
	PlayerRemoving = true,
	Heartbeat = true,
	Stepped = true,
	RenderStepped = true,
	PreSimulation = true,
	PostSimulation = true,
	MouseButton1Click = true,
	Activated = true,
	Completed = true,
	Chatted = true,
	Idled = true,
	PromptGamePassPurchaseFinished = true,
	PromptProductPurchaseFinished = true,
	MouseButton1Down = true,
	MouseButton1Up = true,
	MouseEnter = true,
	MouseLeave = true,
	FocusLost = true,
	InputBegan = true,
	InputEnded = true,
	InputChanged = true,
	MenuOpened = true,
	WindowFocusReleased = true,
	PromptTriggered = true,
}

local DEFAULTS = {
	BasePart = function()
		return {
			Size = roblox.Vector3.new(4, 1, 2),
			CFrame = roblox.CFrame.new(),
			Anchored = false,
			CanCollide = true,
			CanTouch = true,
			CanQuery = true,
			Transparency = 0,
			Color = roblox.Color3.fromRGB(163, 162, 165),
			Material = roblox.Enum.Material.Plastic,
			CastShadow = true,
		}
	end,
	Humanoid = function()
		return {
			Health = 100,
			MaxHealth = 100,
			WalkSpeed = 16,
			JumpPower = 50,
			UseJumpPower = true,
			DisplayName = "",
		}
	end,
	ProximityPrompt = function()
		return {
			Enabled = true,
			MaxActivationDistance = 10,
			HoldDuration = 0,
			ActionText = "",
			ObjectText = "",
		}
	end,
	GuiObject = function()
		return {
			Visible = true,
			BackgroundTransparency = 0,
			BackgroundColor3 = roblox.Color3.fromRGB(255, 255, 255),
			Size = roblox.UDim2.new(0, 100, 0, 100),
			Position = roblox.UDim2.new(0, 0, 0, 0),
			AnchorPoint = roblox.Vector2.new(0, 0),
			Rotation = 0,
			ZIndex = 1,
			LayoutOrder = 0,
			Text = "",
			TextTransparency = 0,
			TextColor3 = roblox.Color3.fromRGB(0, 0, 0),
			AutoButtonColor = true,
		}
	end,
	UIScale = function()
		return { Scale = 1 }
	end,
	UIStroke = function()
		return { Thickness = 1, Color = roblox.Color3.fromRGB(0, 0, 0), Transparency = 0 }
	end,
	Camera = function()
		return { FieldOfView = 70, CFrame = roblox.CFrame.new() }
	end,
	LayerCollector = function()
		return { Enabled = true }
	end,
}

local instanceMeta = {}
local liveInstances = setmetatable({}, { __mode = "k" })
local InstanceAPI = {}

local function isInstance(v)
	return type(v) == "table" and liveInstances[v] == true
end
Mock.isInstance = isInstance

local function classIsA(className, query)
	if className == query or query == "Instance" then
		return true
	end
	local parents = INHERITANCE[className]
	if parents then
		for _, p in parents do
			if p == query then
				return true
			end
		end
	end
	return false
end

local function newInstance(className, parent)
	local data = {
		ClassName = className,
		Name = className,
		_children = {},
		_attributes = {},
		_tags = {},
		_signals = {},
		_attrSignals = {},
		_propSignals = {},
		_destroyed = false,
		_props = {},
		_parent = nil,
	}
	for base, factory in DEFAULTS do
		if classIsA(className, base) then
			for k, v in factory() do
				data._props[k] = v
			end
		end
	end
	local inst = setmetatable(data, instanceMeta)
	liveInstances[inst] = true
	if parent then
		inst.Parent = parent
	end
	return inst
end
Mock.newInstance = newInstance

local function getSignal(inst, name)
	local s = rawget(inst, "_signals")[name]
	if not s then
		s = newSignal(name)
		rawget(inst, "_signals")[name] = s
	end
	return s
end
Mock.getSignal = getSignal

local function setParent(inst, parent)
	local old = rawget(inst, "_parent")
	if old == parent then
		return
	end
	if parent ~= nil and not isInstance(parent) then
		error("Parent must be an Instance or nil")
	end
	if old then
		local list = rawget(old, "_children")
		local i = table.find(list, inst)
		if i then
			table.remove(list, i)
		end
		getSignal(old, "ChildRemoved"):Fire(inst)
	end
	rawset(inst, "_parent", parent)
	if parent then
		table.insert(rawget(parent, "_children"), inst)
		getSignal(parent, "ChildAdded"):Fire(inst)
		local ancestor = parent
		while ancestor do
			getSignal(ancestor, "DescendantAdded"):Fire(inst)
			ancestor = rawget(ancestor, "_parent")
		end
	end
	getSignal(inst, "AncestryChanged"):Fire(inst, parent)
end

instanceMeta.__index = function(inst, key)
	if key == "Parent" then
		return rawget(inst, "_parent")
	end
	local method = InstanceAPI[key]
	if method then
		return method
	end
	if SIGNAL_NAMES[key] then
		return getSignal(inst, key)
	end
	local props = rawget(inst, "_props")
	local v = props[key]
	if v ~= nil then
		return v
	end
	if key == "Position" and props.CFrame then
		return props.CFrame.Position
	end
	if key == "PrimaryPart" or key == "Character" then
		return nil
	end
	-- Child lookup by name (Roblox allows inst.ChildName)
	for _, child in rawget(inst, "_children") do
		if rawget(child, "Name") == key then
			return child
		end
	end
	return nil
end

instanceMeta.__newindex = function(inst, key, value)
	if key == "Parent" then
		if rawget(inst, "_destroyed") then
			error("The Parent property of " .. tostring(rawget(inst, "Name")) .. " is locked")
		end
		setParent(inst, value)
		return
	end
	if key == "Name" or key == "ClassName" then
		rawset(inst, key, tostring(value))
		getSignal(inst, "Changed"):Fire(key)
		return
	end
	local props = rawget(inst, "_props")
	if key == "Position" and rawTypeof(value) == "Vector3" then
		local cf = props.CFrame or roblox.CFrame.new()
		props.CFrame = cf - cf.Position + value
	else
		props[key] = value
	end
	local ps = rawget(inst, "_propSignals")[key]
	if ps then
		ps:Fire()
	end
	getSignal(inst, "Changed"):Fire(key)
end

instanceMeta.__tostring = function(inst)
	return rawget(inst, "Name")
end

function InstanceAPI.IsA(inst, className)
	return classIsA(rawget(inst, "ClassName"), className)
end

function InstanceAPI.GetChildren(inst)
	return table.clone(rawget(inst, "_children"))
end

function InstanceAPI.GetDescendants(inst)
	local out = {}
	local function walk(node)
		for _, child in rawget(node, "_children") do
			table.insert(out, child)
			walk(child)
		end
	end
	walk(inst)
	return out
end

function InstanceAPI.FindFirstChild(inst, name, recursive)
	for _, child in rawget(inst, "_children") do
		if rawget(child, "Name") == name then
			return child
		end
	end
	if recursive then
		for _, child in rawget(inst, "_children") do
			local found = InstanceAPI.FindFirstChild(child, name, true)
			if found then
				return found
			end
		end
	end
	return nil
end

function InstanceAPI.FindFirstChildOfClass(inst, className)
	for _, child in rawget(inst, "_children") do
		if rawget(child, "ClassName") == className then
			return child
		end
	end
	return nil
end

function InstanceAPI.FindFirstChildWhichIsA(inst, className, recursive)
	for _, child in rawget(inst, "_children") do
		if classIsA(rawget(child, "ClassName"), className) then
			return child
		end
	end
	if recursive then
		for _, child in rawget(inst, "_children") do
			local found = InstanceAPI.FindFirstChildWhichIsA(child, className, true)
			if found then
				return found
			end
		end
	end
	return nil
end

function InstanceAPI.FindFirstAncestorWhichIsA(inst, className)
	local p = rawget(inst, "_parent")
	while p do
		if classIsA(rawget(p, "ClassName"), className) then
			return p
		end
		p = rawget(p, "_parent")
	end
	return nil
end

function InstanceAPI.FindFirstAncestor(inst, name)
	local p = rawget(inst, "_parent")
	while p do
		if rawget(p, "Name") == name then
			return p
		end
		p = rawget(p, "_parent")
	end
	return nil
end

function InstanceAPI.WaitForChild(inst, name, timeout)
	local found = InstanceAPI.FindFirstChild(inst, name)
	if found then
		return found
	end
	local deadline = Scheduler.now() + (timeout or 5)
	while Scheduler.now() < deadline do
		Scheduler.task.wait(0.1)
		found = InstanceAPI.FindFirstChild(inst, name)
		if found then
			return found
		end
	end
	if timeout == nil then
		print("[Mock] Infinite yield possible on WaitForChild(" .. tostring(name) .. ")")
	end
	return nil
end

function InstanceAPI.IsDescendantOf(inst, ancestor)
	local p = rawget(inst, "_parent")
	while p do
		if p == ancestor then
			return true
		end
		p = rawget(p, "_parent")
	end
	return false
end

function InstanceAPI.IsAncestorOf(inst, descendant)
	return InstanceAPI.IsDescendantOf(descendant, inst)
end

function InstanceAPI.GetFullName(inst)
	local parts = {}
	local node = inst
	while node and rawget(node, "ClassName") ~= "DataModel" do
		table.insert(parts, 1, rawget(node, "Name"))
		node = rawget(node, "_parent")
	end
	return table.concat(parts, ".")
end

function InstanceAPI.Destroy(inst)
	if rawget(inst, "_destroyed") then
		return
	end
	getSignal(inst, "Destroying"):Fire()
	for _, child in table.clone(rawget(inst, "_children")) do
		InstanceAPI.Destroy(child)
	end
	setParent(inst, nil)
	rawset(inst, "_destroyed", true)
	for _, s in rawget(inst, "_signals") do
		s:DisconnectAll()
	end
end

function InstanceAPI.ClearAllChildren(inst)
	for _, child in table.clone(rawget(inst, "_children")) do
		InstanceAPI.Destroy(child)
	end
end

function InstanceAPI.Clone(inst)
	local copy = newInstance(rawget(inst, "ClassName"))
	rawset(copy, "Name", rawget(inst, "Name"))
	for k, v in rawget(inst, "_props") do
		rawget(copy, "_props")[k] = v
	end
	for k, v in rawget(inst, "_attributes") do
		rawget(copy, "_attributes")[k] = v
	end
	for k, v in rawget(inst, "_tags") do
		rawget(copy, "_tags")[k] = v
	end
	for _, child in rawget(inst, "_children") do
		InstanceAPI.Clone(child).Parent = copy
	end
	return copy
end

function InstanceAPI.SetAttribute(inst, name, value)
	rawget(inst, "_attributes")[name] = value
	local s = rawget(inst, "_attrSignals")[name]
	if s then
		s:Fire()
	end
end

function InstanceAPI.GetAttribute(inst, name)
	return rawget(inst, "_attributes")[name]
end

function InstanceAPI.GetAttributes(inst)
	return table.clone(rawget(inst, "_attributes"))
end

function InstanceAPI.GetAttributeChangedSignal(inst, name)
	local signals = rawget(inst, "_attrSignals")
	if not signals[name] then
		signals[name] = newSignal("AttributeChanged")
	end
	return signals[name]
end

function InstanceAPI.GetPropertyChangedSignal(inst, name)
	local signals = rawget(inst, "_propSignals")
	if not signals[name] then
		signals[name] = newSignal("PropertyChanged")
	end
	return signals[name]
end

function InstanceAPI.AddTag(inst, tag)
	rawget(inst, "_tags")[tag] = true
	Mock.CollectionTagAdded(inst, tag)
end

function InstanceAPI.RemoveTag(inst, tag)
	rawget(inst, "_tags")[tag] = nil
end

function InstanceAPI.HasTag(inst, tag)
	return rawget(inst, "_tags")[tag] == true
end

function InstanceAPI.GetTags(inst)
	local out = {}
	for tag in rawget(inst, "_tags") do
		table.insert(out, tag)
	end
	return out
end

function InstanceAPI.GetPivot(inst)
	local props = rawget(inst, "_props")
	if props.CFrame then
		return props.CFrame
	end
	if props.WorldPivot then
		return props.WorldPivot
	end
	return roblox.CFrame.new()
end

function InstanceAPI.PivotTo(inst, cf)
	assert(rawTypeof(cf) == "CFrame", "PivotTo expects a CFrame")
	local props = rawget(inst, "_props")
	if classIsA(rawget(inst, "ClassName"), "BasePart") then
		props.CFrame = cf
	else
		props.WorldPivot = cf
		-- move direct BasePart children along (good enough for tests)
		for _, child in rawget(inst, "_children") do
			if classIsA(rawget(child, "ClassName"), "BasePart") then
				rawget(child, "_props").CFrame = cf
			end
		end
	end
end

function InstanceAPI.GetBoundingBox(inst)
	local size = roblox.Vector3.new(4, 4, 4)
	for _, d in InstanceAPI.GetDescendants(inst) do
		local s = rawget(d, "_props").Size
		if s and rawTypeof(s) == "Vector3" then
			size = roblox.Vector3.new(math.max(size.X, s.X), math.max(size.Y, s.Y), math.max(size.Z, s.Z))
		end
	end
	return InstanceAPI.GetPivot(inst), size
end

function InstanceAPI.GetExtentsSize(inst)
	local _, size = InstanceAPI.GetBoundingBox(inst)
	return size
end

function InstanceAPI.ScaleTo(inst, scale)
	rawget(inst, "_props")._Scale = scale
end

function InstanceAPI.GetScale(inst)
	return rawget(inst, "_props")._Scale or 1
end

function InstanceAPI.SetPrimaryPartCFrame(inst, cf)
	InstanceAPI.PivotTo(inst, cf)
end

function InstanceAPI.BreakJoints() end
function InstanceAPI.SetNetworkOwner() end
function InstanceAPI.SetNetworkOwnershipAuto() end

function InstanceAPI.GetDebugId(inst)
	return tostring(inst)
end

-- RemoteEvent / BindableEvent / RemoteFunction ---------------------------------
-- Values crossing the network are deep-copied (no shared references), like Roblox does.
local function netCopy(value, seen)
	if type(value) ~= "table" or isInstance(value) then
		return value
	end
	if getmetatable(value) ~= nil then
		return value
	end
	seen = seen or {}
	if seen[value] then
		return seen[value]
	end
	local out = {}
	seen[value] = out
	for k, v in value do
		out[netCopy(k, seen)] = netCopy(v, seen)
	end
	return out
end
Mock.netCopy = netCopy

local function deliverToClient(inst, player, args)
	if Mock.localPlayer and player == Mock.localPlayer then
		local copied = {}
		for i = 1, args.n do
			copied[i] = netCopy(args[i])
		end
		getSignal(inst, "OnClientEvent"):Fire(table.unpack(copied, 1, args.n))
	end
end

function InstanceAPI.FireClient(inst, player, ...)
	local args = table.pack(...)
	Mock.recordClientEvent(rawget(inst, "Name"), player, args)
	deliverToClient(inst, player, args)
end

function InstanceAPI.FireAllClients(inst, ...)
	local args = table.pack(...)
	for _, player in Mock.players do
		Mock.recordClientEvent(rawget(inst, "Name"), player, args)
		deliverToClient(inst, player, args)
	end
end

-- Client -> server invoke as the local player.
function InstanceAPI.InvokeServer(inst, ...)
	local handler = rawget(inst, "_props").OnServerInvoke
	assert(handler, "no OnServerInvoke for " .. rawget(inst, "Name"))
	local args = table.pack(...)
	for i = 1, args.n do
		args[i] = netCopy(args[i])
	end
	return netCopy(handler(Mock.localPlayer, table.unpack(args, 1, args.n)))
end

function InstanceAPI.FireServer(inst, ...)
	getSignal(inst, "OnServerEvent"):Fire(Mock.localPlayer, ...)
end

function InstanceAPI.CaptureFocus() end
function InstanceAPI.ReleaseFocus() end
function InstanceAPI.GetMouseLocation()
	return roblox.Vector2.new(0, 0)
end

function InstanceAPI.Fire(inst, ...)
	getSignal(inst, "Event"):Fire(...)
end

function InstanceAPI.InvokeClient()
	error("InvokeClient must never be used by the server")
end

-- Humanoid / Player / Animation -------------------------------------------------
function InstanceAPI.Kick(inst, message)
	rawset(inst, "_kicked", message or "")
	Mock.removePlayer(inst)
end

function InstanceAPI.LoadCharacter(inst)
	Mock.spawnCharacter(inst)
end

function InstanceAPI.GetRankInGroup()
	return 0
end

function InstanceAPI.IsInGroup()
	return false
end

function InstanceAPI.RequestStreamAroundAsync() end

function InstanceAPI.LoadAnimation(inst, animation)
	local track = newInstance("AnimationTrack")
	rawget(track, "_props").Animation = animation
	return track
end

function InstanceAPI.Play(inst)
	local onPlay = rawget(inst, "_props")._onPlay
	if onPlay then
		onPlay()
	end
end
function InstanceAPI.Stop() end
function InstanceAPI.AdjustSpeed() end
function InstanceAPI.Emit() end
function InstanceAPI.MoveTo() end
function InstanceAPI.ChangeState() end

function InstanceAPI.GetPlayingAnimationTracks()
	return {}
end

-- Terrain -----------------------------------------------------------------------
function InstanceAPI.FillBlock(inst, cf, size, material)
	Mock.terrainFills += 1
end
function InstanceAPI.FillBall()
	Mock.terrainFills += 1
end
function InstanceAPI.FillRegion()
	Mock.terrainFills += 1
end
function InstanceAPI.FillCylinder()
	Mock.terrainFills += 1
end
function InstanceAPI.FillWedge()
	Mock.terrainFills += 1
end
function InstanceAPI.Clear() end

-- Workspace ---------------------------------------------------------------------
function InstanceAPI.Raycast()
	return nil
end

function InstanceAPI.GetPartBoundsInBox()
	return {}
end

function InstanceAPI.GetServerTimeNow()
	return Mock.unixTime()
end

---------------------------------------------------------------------------
-- Instance library + extra datatypes
---------------------------------------------------------------------------
Mock.Instance = {
	new = function(className, parent)
		return newInstance(className, parent)
	end,
}

Mock.terrainFills = 0

local function makeRandom(seed)
	-- xorshift-ish PRNG, deterministic per seed
	local state = math.floor((seed or os.clock() * 1e6) % 2147483647)
	if state <= 0 then
		state = 1234567
	end
	local r = {}
	local function nextFloat()
		state = (state * 48271) % 2147483647
		return state / 2147483647
	end
	function r:NextNumber(min, max)
		local f = nextFloat()
		if min == nil then
			return f
		end
		return min + (max - min) * f
	end
	function r:NextInteger(min, max)
		return min + math.floor(nextFloat() * (max - min + 1))
	end
	function r:Clone()
		return makeRandom(state)
	end
	return r
end
Mock.Random = { new = makeRandom }

Mock.TweenInfo = {
	new = function(time, style, direction, repeatCount, reverses, delay)
		return {
			Time = time or 1,
			EasingStyle = style,
			EasingDirection = direction,
			RepeatCount = repeatCount or 0,
			Reverses = reverses or false,
			DelayTime = delay or 0,
		}
	end,
}

Mock.RaycastParams = {
	new = function()
		return { FilterDescendantsInstances = {}, FilterType = nil }
	end,
}

Mock.OverlapParams = {
	new = function()
		return { FilterDescendantsInstances = {}, FilterType = nil }
	end,
}

Mock.Font = {
	new = function(family, weight, style)
		return { Family = family, Weight = weight, Style = style }
	end,
	fromEnum = function(e)
		return { Family = tostring(e) }
	end,
	fromName = function(name)
		return { Family = name }
	end,
}

Mock.DateTime = {
	now = function()
		local t = Mock.unixTime()
		return { UnixTimestamp = math.floor(t), UnixTimestampMillis = math.floor(t * 1000) }
	end,
}

---------------------------------------------------------------------------
-- Virtual wall clock (unix) driven by the scheduler
---------------------------------------------------------------------------
Mock.unixBase = 1792549555 -- 2026-10-21 (the halloween demo event is active)
function Mock.unixTime()
	return Mock.unixBase + Scheduler.now()
end

---------------------------------------------------------------------------
-- DataStores
---------------------------------------------------------------------------
Mock.dataStores = {}
Mock.dataStoreFailures = 0 -- number of upcoming calls that should error
Mock.dataStoreCalls = 0

-- Failures can be injected globally (Mock.dataStoreFailures) or for one store
-- (store._failures), so tests can break player data without breaking leaderboards.
local function maybeFail(op, store)
	Mock.dataStoreCalls += 1
	if store and (store._failures or 0) > 0 then
		store._failures -= 1
		error("502: API Services rejected request (" .. op .. ", injected failure)")
	end
	if Mock.dataStoreFailures > 0 then
		Mock.dataStoreFailures -= 1
		error("502: API Services rejected request (" .. op .. ", injected failure)")
	end
end

local function roundTrip(value)
	if value == nil then
		return nil
	end
	-- simulate JSON serialization: drops functions, metatables, non-string keys in dicts
	return serde.decode("json", serde.encode("json", value))
end

Mock.roundTrip = roundTrip
Mock.serde = serde

local function newDataStore(name)
	local store = { _name = name, _data = {}, _versions = {}, _failures = 0 }
	function store:GetAsync(key)
		maybeFail("GetAsync", self)
		return roundTrip(self._data[key])
	end
	function store:SetAsync(key, value)
		maybeFail("SetAsync", self)
		self._data[key] = roundTrip(value)
	end
	function store:UpdateAsync(key, transform)
		maybeFail("UpdateAsync", self)
		local old = roundTrip(self._data[key])
		local new = transform(old, nil)
		if new ~= nil then
			self._data[key] = roundTrip(new)
			self._versions[key] = (self._versions[key] or 0) + 1
		end
		return roundTrip(self._data[key])
	end
	function store:RemoveAsync(key)
		maybeFail("RemoveAsync", self)
		local old = self._data[key]
		self._data[key] = nil
		return old
	end
	function store:IncrementAsync(key, delta)
		maybeFail("IncrementAsync", self)
		self._data[key] = (self._data[key] or 0) + (delta or 1)
		return self._data[key]
	end
	-- Ordered store API
	function store:GetSortedAsync(ascending, pageSize)
		maybeFail("GetSortedAsync", self)
		local rows = {}
		for k, v in self._data do
			table.insert(rows, { key = k, value = v })
		end
		table.sort(rows, function(a, b)
			if ascending then
				return a.value < b.value
			end
			return a.value > b.value
		end)
		local page = {}
		for i = 1, math.min(pageSize or 10, #rows) do
			page[i] = rows[i]
		end
		return {
			GetCurrentPage = function()
				return page
			end,
			IsFinished = true,
		}
	end
	return store
end

---------------------------------------------------------------------------
-- Services and the DataModel
---------------------------------------------------------------------------
local game = newInstance("DataModel")
rawset(game, "Name", "Game")
rawget(game, "_props").JobId = "test-job-1"
rawget(game, "_props").PlaceId = 1
rawget(game, "_props").GameId = 1
rawget(game, "_props").PlaceVersion = 1
Mock.game = game
Mock.bindToClose = {}
Mock.isStudio = true

local services = {}

local function service(name, className)
	local s = services[name]
	if not s then
		s = newInstance(className or name)
		rawset(s, "Name", name)
		rawset(s, "_parent", game)
		table.insert(rawget(game, "_children"), s)
		services[name] = s
	end
	return s
end

function InstanceAPI.GetService(inst, name)
	assert(inst == game, "GetService must be called on game")
	return service(name)
end

function InstanceAPI.FindService(inst, name)
	return services[name]
end

function InstanceAPI.BindToClose(_, fn)
	table.insert(Mock.bindToClose, fn)
end

-- Workspace & Terrain
local workspace = service("Workspace")
local terrain = newInstance("Terrain")
rawset(terrain, "Name", "Terrain")
terrain.Parent = workspace
rawget(workspace, "_props").Gravity = 196.2
local camera = newInstance("Camera")
rawset(camera, "Name", "Camera")
camera.Parent = workspace
rawget(workspace, "_props").CurrentCamera = camera
rawget(camera, "_props").ViewportSize = roblox.Vector2.new(1280, 720)
rawget(camera, "_props").CFrame = roblox.CFrame.new()
Mock.workspace = workspace

-- RunService
local runService = service("RunService")
function InstanceAPI.IsStudio()
	return Mock.isStudio
end
function InstanceAPI.IsServer()
	return true
end
Mock.isClient = false
function InstanceAPI.IsClient()
	return Mock.isClient
end
function InstanceAPI.IsRunning()
	return true
end

-- HttpService
local http = service("HttpService")
local guidCounter = 0
function InstanceAPI.GenerateGUID(_, wrap)
	guidCounter += 1
	local hex = string.format("%08x-0000-4000-8000-%012x", guidCounter, guidCounter)
	return if wrap == false then hex else "{" .. hex .. "}"
end
function InstanceAPI.JSONEncode(_, value)
	return serde.encode("json", value)
end
function InstanceAPI.JSONDecode(_, text)
	return serde.decode("json", text)
end

-- DataStoreService
service("DataStoreService")
function InstanceAPI.GetDataStore(_, name, scope)
	local key = name .. "/" .. tostring(scope or "global")
	if not Mock.dataStores[key] then
		Mock.dataStores[key] = newDataStore(key)
	end
	return Mock.dataStores[key]
end
function InstanceAPI.GetOrderedDataStore(_, name, scope)
	local key = "ordered:" .. name .. "/" .. tostring(scope or "global")
	if not Mock.dataStores[key] then
		Mock.dataStores[key] = newDataStore(key)
	end
	return Mock.dataStores[key]
end
function InstanceAPI.GetRequestBudgetForRequestType()
	return 100
end

-- CollectionService
service("CollectionService")
local tagged = {}
local tagAddedSignals = {}
function Mock.CollectionTagAdded(inst, tag)
	tagged[tag] = tagged[tag] or setmetatable({}, { __mode = "k" })
	tagged[tag][inst] = true
	if tagAddedSignals[tag] then
		tagAddedSignals[tag]:Fire(inst)
	end
end
function InstanceAPI.GetTagged(inst, tag)
	if inst ~= services.CollectionService then
		error("GetTagged is a CollectionService method")
	end
	local out = {}
	for i in tagged[tag] or {} do
		if not rawget(i, "_destroyed") and i:HasTag(tag) then
			table.insert(out, i)
		end
	end
	return out
end
function InstanceAPI.GetInstanceAddedSignal(_, tag)
	tagAddedSignals[tag] = tagAddedSignals[tag] or newSignal("TagAdded")
	return tagAddedSignals[tag]
end
function InstanceAPI.GetInstanceRemovedSignal(_, tag)
	return newSignal("TagRemoved")
end

-- MarketplaceService / PolicyService / misc
service("MarketplaceService")
Mock.ownedPasses = {}
function InstanceAPI.UserOwnsGamePassAsync(_, userId, passId)
	return Mock.ownedPasses[tostring(userId) .. ":" .. tostring(passId)] == true
end
function InstanceAPI.PromptProductPurchase() end
function InstanceAPI.PromptGamePassPurchase() end
function InstanceAPI.GetProductInfo()
	return { Name = "Product", PriceInRobux = 0 }
end

service("PolicyService")
Mock.paidRandomRestricted = {}
function InstanceAPI.GetPolicyInfoForPlayerAsync(_, player)
	return {
		ArePaidRandomItemsRestricted = Mock.paidRandomRestricted[player] == true,
		AllowedExternalLinkReferences = {},
	}
end

service("AnalyticsService")
Mock.analytics = {}
function InstanceAPI.LogEconomyEvent(_, ...)
	table.insert(Mock.analytics, { "Economy", ... })
end
function InstanceAPI.LogCustomEvent(_, ...)
	table.insert(Mock.analytics, { "Custom", ... })
end
function InstanceAPI.LogOnboardingFunnelStepEvent(_, ...)
	table.insert(Mock.analytics, { "Funnel", ... })
end
function InstanceAPI.LogProgressionEvent(_, ...)
	table.insert(Mock.analytics, { "Progression", ... })
end

service("MessagingService")
function InstanceAPI.PublishAsync() end
function InstanceAPI.SubscribeAsync()
	return { Disconnect = function() end }
end

service("TweenService")
function InstanceAPI.Create(_, target, info, goals)
	local tween = newInstance("Tween")
	rawget(tween, "_props")._onPlay = function()
		for k, v in goals do
			target[k] = v
		end
		getSignal(tween, "Completed"):Fire(roblox.Enum.PlaybackState.Completed)
	end
	return tween
end
function InstanceAPI.Cancel() end
function InstanceAPI.Pause() end

service("Debris")
function InstanceAPI.AddItem(_, inst, lifetime)
	Scheduler.task.delay(lifetime or 10, function()
		if isInstance(inst) then
			inst:Destroy()
		end
	end)
end

service("PhysicsService")
function InstanceAPI.RegisterCollisionGroup() end
function InstanceAPI.CollisionGroupSetCollidable() end
function InstanceAPI.IsCollisionGroupRegistered()
	return false
end

service("Lighting")
service("ReplicatedStorage")
service("ServerStorage")
service("ServerScriptService")
service("StarterGui")
service("StarterPack")
local starterPlayer = service("StarterPlayer")
local sps = newInstance("StarterPlayerScripts")
rawset(sps, "Name", "StarterPlayerScripts")
sps.Parent = starterPlayer
service("SoundService")
service("Teams")
service("TextChatService")
service("BadgeService")
function InstanceAPI.AwardBadge() end
service("TeleportService")
service("GroupService")
local uis = service("UserInputService")
rawget(uis, "_props").TouchEnabled = false
rawget(uis, "_props").KeyboardEnabled = true
service("GuiService")
service("ProximityPromptService")
service("ContextActionService")
-- ContextActionService: bindings are recorded so tests can drive them with Mock.fireAction.
Mock.boundActions = {}
function InstanceAPI.BindAction(_, name, fn, _createTouchButton, ...)
	Mock.boundActions[name] = { fn = fn, keys = { ... } }
end
function InstanceAPI.BindActionAtPriority(_, name, fn, _createTouchButton, _priority, ...)
	Mock.boundActions[name] = { fn = fn, keys = { ... } }
end
function InstanceAPI.UnbindAction(_, name)
	Mock.boundActions[name] = nil
end
function InstanceAPI.SetTitle() end
function InstanceAPI.SetPosition() end
function InstanceAPI.GetButton()
	return nil
end
function Mock.fireAction(name, state, keyCode, inputType)
	local binding = Mock.boundActions[name]
	assert(binding, "no action bound: " .. tostring(name))
	return binding.fn(name, state, { KeyCode = keyCode, UserInputType = inputType })
end

-- Players
local players = service("Players")
rawget(players, "_props").MaxPlayers = 12
Mock.players = {}
Mock.clientEvents = {} -- name -> list of { player, args }

function Mock.recordClientEvent(name, player, args)
	Mock.clientEvents[name] = Mock.clientEvents[name] or {}
	table.insert(Mock.clientEvents[name], { player = player, args = args })
end

function Mock.clearClientEvents()
	table.clear(Mock.clientEvents)
end

function InstanceAPI.GetPlayers(inst)
	return table.clone(Mock.players)
end

function InstanceAPI.GetPlayerByUserId(_, userId)
	for _, p in Mock.players do
		if rawget(p, "_props").UserId == userId then
			return p
		end
	end
	return nil
end

function InstanceAPI.GetUserIdFromNameAsync()
	return 1
end

function InstanceAPI.GetNameFromUserIdAsync(_, userId)
	return "User" .. tostring(userId)
end

function Mock.spawnCharacter(player)
	local props = rawget(player, "_props")
	local old = props.Character
	if old then
		getSignal(player, "CharacterRemoving"):Fire(old)
		old:Destroy()
	end
	local character = newInstance("Model")
	rawset(character, "Name", rawget(player, "Name"))
	local root = newInstance("Part")
	rawset(root, "Name", "HumanoidRootPart")
	root.Parent = character
	local humanoid = newInstance("Humanoid")
	rawset(humanoid, "Name", "Humanoid")
	humanoid.Parent = character
	rawget(character, "_props").PrimaryPart = root
	character.Parent = workspace
	props.Character = character
	getSignal(player, "CharacterAdded"):Fire(character)
	return character
end

-- Makes `player` the LocalPlayer for client code running in this process.
function Mock.setLocalPlayer(player)
	Mock.localPlayer = player
	rawget(players, "_props").LocalPlayer = player
	Mock.isClient = true
end

function Mock.addPlayer(userId, name)
	local player = newInstance("Player")
	rawset(player, "Name", name or ("Player" .. userId))
	local props = rawget(player, "_props")
	props.UserId = userId
	props.DisplayName = name or ("Player" .. userId)
	props.AccountAge = 365
	props.MembershipType = roblox.Enum.MembershipType.None
	local gui = newInstance("PlayerGui")
	rawset(gui, "Name", "PlayerGui")
	gui.Parent = player
	player.Parent = players
	table.insert(Mock.players, player)
	getSignal(players, "PlayerAdded"):Fire(player)
	return player
end

function Mock.removePlayer(player)
	local i = table.find(Mock.players, player)
	if not i then
		return
	end
	getSignal(players, "PlayerRemoving"):Fire(player)
	table.remove(Mock.players, i)
	local character = rawget(player, "_props").Character
	if character then
		character:Destroy()
	end
	player.Parent = nil
end

-- Heartbeat driver: fires RunService.Heartbeat for each virtual step
function Mock.advance(seconds, step)
	Scheduler.advance(seconds, function(dt)
		getSignal(runService, "Heartbeat"):Fire(dt)
		getSignal(runService, "Stepped"):Fire(Scheduler.now(), dt)
	end, step or 0.25)
end

-- Runs BindToClose callbacks (simulated server shutdown)
function Mock.shutdown()
	for _, fn in Mock.bindToClose do
		Scheduler.task.spawn(fn)
	end
	Mock.advance(30, 0.5)
end

---------------------------------------------------------------------------
-- Globals for loaded chunks
---------------------------------------------------------------------------
function Mock.typeof(v)
	if isInstance(v) then
		return "Instance"
	end
	if type(v) == "table" then
		local mt = getmetatable(v)
		if mt == SignalMeta then
			return "RBXScriptSignal"
		elseif mt == ConnectionMeta then
			return "RBXScriptConnection"
		end
	end
	return rawTypeof(v)
end

Mock.logs = { warn = {}, print = {} }
Mock.echo = false

function Mock.globals()
	return {
		game = game,
		workspace = workspace,
		Workspace = workspace,
		Instance = Mock.Instance,
		Enum = roblox.Enum,
		Vector3 = roblox.Vector3,
		Vector2 = roblox.Vector2,
		CFrame = roblox.CFrame,
		Color3 = roblox.Color3,
		BrickColor = roblox.BrickColor,
		UDim = roblox.UDim,
		UDim2 = roblox.UDim2,
		NumberSequence = roblox.NumberSequence,
		NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
		ColorSequence = roblox.ColorSequence,
		ColorSequenceKeypoint = roblox.ColorSequenceKeypoint,
		NumberRange = roblox.NumberRange,
		Rect = roblox.Rect,
		PhysicalProperties = roblox.PhysicalProperties,
		Ray = roblox.Ray,
		Region3 = roblox.Region3,
		Font = Mock.Font,
		TweenInfo = Mock.TweenInfo,
		RaycastParams = Mock.RaycastParams,
		OverlapParams = Mock.OverlapParams,
		Random = Mock.Random,
		DateTime = Mock.DateTime,
		task = Scheduler.task,
		typeof = Mock.typeof,
		tick = function()
			return Mock.unixTime()
		end,
		time = function()
			return Scheduler.now()
		end,
		wait = Scheduler.task.wait,
		os = setmetatable({
			time = function(t)
				if t then
					return os.time(t)
				end
				return math.floor(Mock.unixTime())
			end,
			clock = function()
				return Scheduler.now()
			end,
		}, { __index = os }),
		warn = function(...)
			local parts = {}
			for i = 1, select("#", ...) do
				parts[i] = tostring((select(i, ...)))
			end
			local line = table.concat(parts, " ")
			table.insert(Mock.logs.warn, line)
			if Mock.echo then
				print("[warn] " .. line)
			end
		end,
		print = function(...)
			local parts = {}
			for i = 1, select("#", ...) do
				parts[i] = tostring((select(i, ...)))
			end
			local line = table.concat(parts, " ")
			table.insert(Mock.logs.print, line)
			if Mock.echo then
				print(line)
			end
		end,
		debug = setmetatable({
			profilebegin = function() end,
			profileend = function() end,
		}, { __index = debug }),
	}
end

return Mock
