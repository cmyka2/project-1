-- Deterministic virtual-time scheduler that stands in for Roblox's `task`
-- library during headless tests. Nothing sleeps for real: tests advance the
-- clock explicitly and every due thread is resumed in order.

local Scheduler = {}

local now = 0
local queue = {} -- { { thread, wake, args, seq } }
local seq = 0
local errors = {}

local function push(thread, wake, args)
	seq += 1
	table.insert(queue, { thread = thread, wake = wake, args = args, seq = seq })
end

local function resume(thread, ...)
	local ok, err = coroutine.resume(thread, ...)
	if not ok then
		local trace = debug.traceback(thread, tostring(err))
		table.insert(errors, trace)
		print("[Scheduler] thread error: " .. trace)
	end
end

function Scheduler.now()
	return now
end

function Scheduler.errors()
	return errors
end

function Scheduler.clearErrors()
	table.clear(errors)
end

local function toThread(fnOrThread)
	if type(fnOrThread) == "thread" then
		return fnOrThread
	end
	return coroutine.create(fnOrThread)
end

Scheduler.task = {}

function Scheduler.task.spawn(fnOrThread, ...)
	local thread = toThread(fnOrThread)
	resume(thread, ...)
	return thread
end

function Scheduler.task.defer(fnOrThread, ...)
	local thread = toThread(fnOrThread)
	push(thread, now, table.pack(...))
	return thread
end

function Scheduler.task.delay(seconds, fnOrThread, ...)
	local thread = toThread(fnOrThread)
	push(thread, now + math.max(0, seconds or 0), table.pack(...))
	return thread
end

function Scheduler.task.wait(seconds)
	local thread = coroutine.running()
	local start = now
	push(thread, now + math.max(0, seconds or 0), nil)
	coroutine.yield()
	return now - start
end

function Scheduler.task.cancel(thread)
	for i = #queue, 1, -1 do
		if queue[i].thread == thread then
			table.remove(queue, i)
		end
	end
	pcall(coroutine.close, thread)
end

function Scheduler.task.synchronize() end
function Scheduler.task.desynchronize() end

-- Runs every thread due at or before the current time (including threads
-- scheduled for "now" by the threads it runs).
function Scheduler.flush()
	local guard = 0
	while true do
		guard += 1
		if guard > 100000 then
			error("Scheduler.flush: runaway loop")
		end
		local bestIndex = nil
		for i, item in queue do
			if item.wake <= now then
				if
					bestIndex == nil
					or item.wake < queue[bestIndex].wake
					or (item.wake == queue[bestIndex].wake and item.seq < queue[bestIndex].seq)
				then
					bestIndex = i
				end
			end
		end
		if not bestIndex then
			return
		end
		local item = table.remove(queue, bestIndex)
		if coroutine.status(item.thread) == "suspended" then
			if item.args then
				resume(item.thread, table.unpack(item.args, 1, item.args.n))
			else
				resume(item.thread)
			end
		end
	end
end

-- Advances virtual time, waking threads in timestamp order. `step` controls
-- the granularity used for Heartbeat callbacks (see MockRoblox).
function Scheduler.advance(seconds, onStep, step)
	local target = now + seconds
	step = step or 1 / 4
	Scheduler.flush()
	while now < target do
		local nextWake = target
		for _, item in queue do
			if item.wake < nextWake then
				nextWake = item.wake
			end
		end
		local stepEnd = math.min(target, now + step, math.max(nextWake, now))
		if stepEnd <= now then
			stepEnd = math.min(target, now + step)
		end
		local dt = stepEnd - now
		now = stepEnd
		if onStep and dt > 0 then
			onStep(dt)
		end
		Scheduler.flush()
	end
end

function Scheduler.reset()
	now = 0
	table.clear(queue)
	table.clear(errors)
end

return Scheduler
