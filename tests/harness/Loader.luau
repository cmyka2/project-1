-- Builds a mock DataModel from default.project.json using Rojo's file
-- conventions and provides an instance-based `require`, so game code runs
-- unmodified under Lune.

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local serde = require("@lune/serde")
local Mock = require("./MockRoblox")
local Scheduler = require("./Scheduler")

local Loader = {}

local sourcePaths = setmetatable({}, { __mode = "k" }) -- instance -> file path
local sources = {} -- file path -> source text (read up front: Lune file IO yields)
local moduleCache = {}
local loading = {}

local function stripExt(name)
	for _, ext in { ".server.luau", ".client.luau", ".luau", ".server.lua", ".client.lua", ".lua" } do
		if string.sub(name, -#ext) == ext then
			return string.sub(name, 1, -#ext - 1), ext
		end
	end
	return nil, nil
end

local function classForExt(ext)
	if string.find(ext, "server") then
		return "Script"
	elseif string.find(ext, "client") then
		return "LocalScript"
	end
	return "ModuleScript"
end

local function buildDir(dirPath, inst)
	local entries = fs.readDir(dirPath)
	table.sort(entries)
	for _, entry in entries do
		local full = dirPath .. "/" .. entry
		if fs.isDir(full) then
			local initFile, initClass = nil, nil
			for _, candidate in { "init.server.luau", "init.client.luau", "init.luau" } do
				if fs.isFile(full .. "/" .. candidate) then
					initFile = full .. "/" .. candidate
					local _, ext = stripExt(candidate)
					initClass = classForExt(ext)
					break
				end
			end
			local child = Mock.newInstance(initClass or "Folder")
			rawset(child, "Name", entry)
			if initFile then
				sourcePaths[child] = initFile
			end
			child.Parent = inst
			buildDir(full, child)
		else
			local base, ext = stripExt(entry)
			if base and not string.match(base, "^init$") and not string.find(entry, "%.spec%.") then
				local child = Mock.newInstance(classForExt(ext))
				rawset(child, "Name", base)
				sourcePaths[child] = full
				child.Parent = inst
			end
		end
	end
end

local function buildNode(node, inst, root)
	if node["$path"] then
		local path = root .. "/" .. node["$path"]
		if fs.isDir(path) then
			buildDir(path, inst)
		else
			sourcePaths[inst] = path
		end
	end
	for key, child in node do
		if string.sub(key, 1, 1) ~= "$" then
			local existing = inst:FindFirstChild(key)
			local childInst = existing
			if not childInst then
				local className = child["$className"] or "Folder"
				if child["$path"] and not child["$className"] then
					local p = root .. "/" .. child["$path"]
					if fs.isFile(p) then
						local _, ext = stripExt(p)
						className = classForExt(ext or ".luau")
					end
				end
				childInst = Mock.newInstance(className)
				rawset(childInst, "Name", key)
				childInst.Parent = inst
			end
			buildNode(child, childInst, root)
		end
	end
end

function Loader.build(root)
	local project = serde.decode("json", fs.readFile(root .. "/default.project.json"))
	local tree = project.tree
	for serviceName, node in tree do
		if string.sub(serviceName, 1, 1) ~= "$" then
			local svc = Mock.game:GetService(serviceName)
			buildNode(node, svc, root)
		end
	end
	for _, path in sourcePaths do
		if not sources[path] then
			sources[path] = fs.readFile(path)
		end
	end
	return Mock.game
end

local function makeEnv(scriptInst)
	local env = Mock.globals()
	env.script = scriptInst
	env.require = function(target)
		return Loader.require(target)
	end
	env.shared = {}
	return setmetatable(env, { __index = _G })
end

function Loader.require(target)
	if not Mock.isInstance(target) then
		error("require expects a ModuleScript instance, got " .. tostring(target))
	end
	if not target:IsA("ModuleScript") then
		error("require target is not a ModuleScript: " .. target:GetFullName())
	end
	local cached = moduleCache[target]
	if cached ~= nil then
		return cached.value
	end
	local holder = loading[target]
	if holder then
		local holderInfo = if type(holder) == "thread"
			then coroutine.status(holder) .. "\n" .. debug.traceback(holder)
			else ""
		error("cyclic require detected: " .. target:GetFullName() .. "\nholder: " .. holderInfo)
	end
	local path = sourcePaths[target]
	if not path then
		error("no source for module " .. target:GetFullName())
	end
	loading[target] = coroutine.running()
	local source = sources[path] or error("source not preloaded: " .. path)
	local okLoad, chunk = pcall(luau.load, source, { debugName = path, environment = makeEnv(target) })
	if not okLoad then
		loading[target] = nil
		error("failed to compile " .. path .. ": " .. tostring(chunk), 2)
	end
	local results = table.pack(pcall(chunk))
	loading[target] = nil
	if not results[1] then
		error("error while loading " .. path .. ": " .. tostring(results[2]), 2)
	end
	table.remove(results, 1)
	results.n -= 1
	if results.n ~= 1 then
		error("module " .. path .. " must return exactly one value")
	end
	moduleCache[target] = { value = results[1] }
	return results[1]
end

-- Runs a Script/LocalScript instance in its own thread.
function Loader.runScript(scriptInst)
	local path = sourcePaths[scriptInst]
	assert(path, "no source for script " .. scriptInst:GetFullName())
	local chunk = luau.load(sources[path], { debugName = path, environment = makeEnv(scriptInst) })
	return Scheduler.task.spawn(chunk)
end

function Loader.find(pathString)
	local node = Mock.game
	for part in string.gmatch(pathString, "[^%.]+") do
		local nextNode = node:FindFirstChild(part)
		if not nextNode then
			if node == Mock.game then
				nextNode = Mock.game:GetService(part)
			else
				error("Loader.find: missing " .. part .. " in " .. pathString)
			end
		end
		node = nextNode
	end
	return node
end

function Loader.requirePath(pathString)
	return Loader.require(Loader.find(pathString))
end

return Loader
