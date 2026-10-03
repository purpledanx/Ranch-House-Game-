local Callback = {}
Callback.__index = {}

--

local ActiveThreads = {}

local function SignalCallback(thread, fn)
	while true do
		fn(coroutine.yield())
		ActiveThreads[thread] = nil
	end
end

--

local WaitingThreads = {}

local function AsyncCallback(thread, fn)
	local result = table.pack(true, fn(coroutine.yield()))
	
	local state = WaitingThreads[thread]
	if state and not state.result then
		state.result = result
		
		if state.waiting then
			task.spawn(state.waiting)
		end
	end
end

task.spawn(function()
	while true do
		task.wait()
		
		for thread,state in pairs(WaitingThreads) do
			if not state.result and coroutine.status(thread) == "dead" then
				state.result = { false } 
				
				if state.waiting then
					task.defer(state.waiting)
				end
			end
		end
	end
end)

--

local function SignalCreator(fn)
	local callback = coroutine.yield()
	
	while true do
		local thread = coroutine.create(callback)
		coroutine.resume(thread, thread, fn)
		callback = coroutine.yield(thread)
	end
end

--

function Callback.__index:Execute(...)
	local thread = self.thread
	
	if thread then
		self.thread = nil
	else
		local success
		success, thread = coroutine.resume(self.creator, SignalCallback)
	end
	
	ActiveThreads[thread] = true
	task.spawn(thread, ...)
	
	if ActiveThreads[thread] then
		ActiveThreads[thread] = nil
	else
		self.thread = thread
	end
end

function Callback.__index:ExecuteAsync(...)
	local success, thread = coroutine.resume(self.creator, AsyncCallback)
	local state = {
		result = nil,
		waiting = nil
	}
	
	WaitingThreads[thread] = state
	task.spawn(thread, ...)
	
	if not state.result then
		state.waiting = coroutine.running()
		coroutine.yield()
	end
	
	WaitingThreads[thread] = nil
	
	return state.result
end

function Callback.new(fn)
	local threadCreator = coroutine.create(SignalCreator)
	coroutine.resume(threadCreator, fn)
	
	return setmetatable({ fn = fn, creator = threadCreator, thread = nil }, Callback)
end

return Callback