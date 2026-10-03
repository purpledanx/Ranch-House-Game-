--[[
	-- Server API
	Network:FireClient(client, name, ...)
	Network:FireAllClients(name, ...)
	Network:FireOtherClients(client, name, ...)
	Network:FireOtherClientsWithinDistance(client, distance, name, ...)
	Network:FireAllClientsWithinDistance(position, distance, name, ...)
	
	Network:InvokeClientWithTimeout(timeout, client, name, ...) -> success, ...
	Network:InvokeClient(client, name, ...) -> success, ...
	
	Network:LogTraffic(duration)
	
	Network:GetPlayers() -> {client} [overrideable]
	Network:GetPlayerPosition(player) -> Vector3? [overrideable]
	
	-- Client API
	Network:FireServer(name, ...)
	
	Network:InvokeServerWithTimeout(timeout, name, ...) -> ...returnValues [unsafe]
	Network:InvokeServer(name, ...)  -> ...returnValues [unsafe]
	
	-- Shared API
	Network:BindFunctions(filters?, bindings)
	Network:BindEvents(filters?, bindings)
	Network:RegisterFilters(filters)
	
	-- Filters
	EventName = {
		MatchParams = { "string" },
		function(client: Player, value: string)
			-- this will not be called unless value is of type string
		end
	}
	
	-- Reference extension
	Network:AddReference(refString, refType, ...values)
	Network:AddReferenceAlias(refString, refType, ...values)
	Network:RemoveReference(refString, refType, ...values)
	
	Network:GetObject(refString, refType) -> ..values
	Network:GetReference(...values, refType) -> refString
	
	
	-- Examples
	
	Network:BindEvents({
		PrintString = {
			MatchParams = { "string" },
			function(client: Player, value: string)
				-- callback will never be called if value is not a string
				print(value)
			end
		}
	})
	
	Network:RegisterFilters({
		FilterName = {
			Priority = 0,
			function(handler, params)
				return function(...)
					if something then
						-- return false or nil to cancel event
						return false
					end
					
					-- return true, ...params to continue to next filter/callback
					return true, ...
				end
			end
		}
	})
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RunService = game:GetService("RunService")

--

local Network = {}
Network.Logging = nil

local IsServer = RunService:IsServer()
local IsStudio = RunService:IsStudio()

local Callback = require(script.Callback)

-- Invokes

function SafeInvokeBinding(binding, ...)
	local result = binding.Callback:ExecuteAsync(...)

	if result[1] == false or result[2] == false then
		return false
	end

	return true, unpack(result, 3)
end

function SafeInvokeWithTimeout(timeout: number?, handler, ...): {}
	local result = nil
	local waiting

	if timeout then
		task.delay(timeout, function()
			if not result then
				result = table.pack(false)

				if waiting then
					task.spawn(waiting)
				end
			end
		end)
	end

	task.spawn(function(...)
		local _result = table.pack(pcall(...))

		if not result then
			result = _result

			if waiting then
				task.spawn(waiting)
			end
		end
	end, ...)

	if not result then
		waiting = coroutine.running()
		coroutine.yield()
	end

	return result
end

-- Events

local PendingEvents = {}

function ExecutePendingEvents()
	local threadsToResume = {}
	local index = 1

	while index <= #PendingEvents do
		local handler, thread = PendingEvents[index], PendingEvents[index + 1]

		if handler.IsBound then
			table.insert(threadsToResume, thread)
			table.remove(PendingEvents, index + 1)
			table.remove(PendingEvents, index)
		else
			index += 2
		end
	end

	for _,thread in ipairs(threadsToResume) do
		task.spawn(thread)
	end
end

if IsServer then
	function OnServerEvent(handler, ...)
		--if not handler.IsBound and not handler.ReceivedUnboundEvent then
		--	handler.ReceivedUnboundEvent = true

		--	task.delay(10, function()
		--		if not handler.IsBound then
		--			error("Network: Received unbound FireServer '" .. handler.Name .. "'", -1)
		--		end
		--	end)
		--end

		if not handler.IsBound then
			table.insert(PendingEvents, handler)
			table.insert(PendingEvents, coroutine.running())
			coroutine.yield()
		end

		for _,binding in pairs(handler.Bindings) do
			binding.Callback:Execute(...)
		end
	end

	function OnServerInvoke(handler, ...)
		--if not handler.IsBound and not handler.ReceivedUnboundEvent then
		--	handler.ReceivedUnboundEvent = true

		--	task.delay(10, function()
		--		if not handler.IsBound then
		--			error("Network: Received unbound InvokeServer '" .. handler.Name .. "'", -1)
		--		end
		--	end)
		--end

		if not handler.IsBound then
			table.insert(PendingEvents, handler)
			table.insert(PendingEvents, coroutine.running())
			coroutine.yield()
		end

		return SafeInvokeBinding(handler.Binding, ...)
	end

else
	function OnClientEvent(handler, ...)
		--if not handler.IsBound and not handler.ReceivedUnboundEvent then
		--	handler.ReceivedUnboundEvent = true

		--	task.delay(10, function()
		--		if not handler.IsBound then
		--			error("Network: Received unbound FireClient '" .. handler.Name .. "'", -1)
		--		end
		--	end)
		--end

		if not handler.IsBound then
			table.insert(PendingEvents, handler)
			table.insert(PendingEvents, coroutine.running())
			coroutine.yield()
		end

		for _,binding in pairs(handler.Bindings) do
			binding.Callback:Execute(...)
		end
	end

	function OnClientInvoke(handler, ...)
		--if not handler.IsBound and not handler.ReceivedUnboundEvent then
		--	handler.ReceivedUnboundEvent = true

		--	task.delay(10, function()
		--		if not handler.IsBound then
		--			error("Network: Received unbound InvokeClient '" .. handler.Name .. "'", -1)
		--		end
		--	end)
		--end

		if not handler.IsBound then
			table.insert(PendingEvents, handler)
			table.insert(PendingEvents, coroutine.running())
			coroutine.yield()
		end

		return SafeInvokeBinding(handler.Binding, ...)
	end
end

-- Handlers

local Communication,FunctionsFolder,EventsFolder

if IsServer then
	Communication = Instance.new("Folder",ReplicatedStorage)
	Communication.Name = "Communication"
	FunctionsFolder = Instance.new("Folder",Communication)
	FunctionsFolder.Name = "Functions"
	EventsFolder = Instance.new("Folder",Communication)
	EventsFolder.Name = "Events"
else
	Communication = ReplicatedStorage:WaitForChild("Communication")
	FunctionsFolder = Communication:WaitForChild("Functions")
	EventsFolder = Communication:WaitForChild("Events")
end

local Handlers = {
	Event = {},
	Function = {}
}

function GetHandler(handlerType: string, handlerName: string)
	local handlers = Handlers[handlerType]
	if not handlers then
		error("Invalid handlerType '" .. tostring(handlerType).. "'")
	end

	local handler = handlers[handlerName]

	if not handler then
		handler = {
			Name = handlerName,
			Type = handlerType
		}
		handlers[handlerName] = handler

		if handlerType == "Event" then
			handler.Bindings = {}
		end

		task.spawn(function()
			if IsServer then
				if handlerType == "Event" then
					local remote = Instance.new("RemoteEvent")
					remote.Name = handlerName
					remote.Parent = EventsFolder
					handler.Remote = remote
					
					local unreliable = Instance.new("UnreliableRemoteEvent")
					unreliable.Name = "Unreliable"
					unreliable.Parent = remote
					handler.Unreliable = unreliable

					remote.OnServerEvent:Connect(function(...)
						OnServerEvent(handler, ...)
					end)
					
					unreliable.OnServerEvent:Connect(function(...)
						OnServerEvent(handler, ...)
					end)
				else
					local remote = Instance.new("RemoteFunction")
					remote.Name = handlerName
					remote.Parent = FunctionsFolder
					handler.Remote = remote

					remote.OnServerInvoke = function(...)
						return OnServerInvoke(handler, ...)
					end
				end
			else
				-- Custom WaitForChild, regular had issues with order of operation (events were going through before wfc resumed)
				local parent = handlerType == "Event" and EventsFolder or FunctionsFolder
				
				local function waitForChild(parent, name)
					-- don't really remember why this is necessary, but eh
					
					local result = parent:FindFirstChild(name)
					
					if not result then
						local waiting = coroutine.running()
						
						local con = parent.ChildAdded:Connect(function(child)
							if waiting and child.Name == name then
								result = child
								task.spawn(waiting)
							end
						end)

						coroutine.yield()
						waiting = nil
						con:Disconnect()
					end
					
					return result
				end
				
				waitForChild(parent, handlerName)
				
				--

				if handlerType == "Event" then
					local remote = waitForChild(EventsFolder, handlerName)
					local unreliable = waitForChild(remote, "Unreliable")
					
					handler.Remote = remote
					handler.Unreliable = unreliable

					if not IsServer then
						remote.Name = ""
					end

					remote.OnClientEvent:Connect(function(...)
						OnClientEvent(handler, ...)
					end)
					
					unreliable.OnClientEvent:Connect(function(...)
						OnClientEvent(handler, ...)
					end)
				else
					local remote = waitForChild(FunctionsFolder, handlerName)
					handler.Remote = remote

					if not IsServer then
						remote.Name = ""
					end

					remote.OnClientInvoke = function(...)
						return OnClientInvoke(handler, ...)
					end
				end
			end

			if handler.WaitingForRemote then
				local threads = handler.WaitingForRemote
				handler.WaitingForRemote = nil

				for _,thread in ipairs(threads) do
					task.spawn(thread)
				end
			end
		end)
	end

	return handler
end

-- Filters

local FilterMap = setmetatable({}, { __mode = "v" })
local FilterCounter = 0
local Filters = {}

function InitFilter(object)
	if FilterMap[object] then return FilterMap[object] end

	local filter

	if typeof(object) == "function" then
		filter = { object }
	elseif typeof(object) == "table" and typeof(object[1]) == "function" then
		filter = {}

		for key,value in pairs(object) do
			filter[key] = value
		end
	end

	if filter then
		filter.Priority = filter.Priority or 0
		filter.RegisterIndex = FilterCounter
		FilterCounter += 1

		FilterMap[object] = filter
	end

	return filter
end

function ApplyFilters(handler, binding)
	return function(...)
		local params = table.pack(true, ...)

		for index,filter in ipairs(binding.Filters) do
			params = table.pack(filter(unpack(params, 2, params.n)))

			if params[1] ~= true then
				if params[1] ~= nil and params[1] ~= false then
					task.spawn(function()
						error(string.format("Network: Filter #%d to '%s' returned invalid first value of type %s. False or nil expected to cancel event",
							index,
							handler.Name,
							typeof(params[1])
							), -1)
					end)
				end

				return false
			end
		end

		if IsServer and Network.Logging then
			Network.Logging[#Network.Logging + 1] = { true, handler.Remote, ... }
		end

		return true, binding[1](unpack(params, 2, params.n))
	end
end

-- Bindings

function InitBinding(handler, object, customFilters)
	local binding

	if typeof(object) == "function" then
		binding = { object }
	elseif typeof(object) == "table" and typeof(object[1]) == "function" then
		binding = {}

		for key,value in pairs(object) do
			binding[key] = value
		end
	end

	if not binding then
		return nil
	end

	local filters = {}

	for key,value in pairs(binding) do
		if key == 1 then continue end
		local filter = Filters[key]

		if not filter then
			error("Filter '" .. tostring(key) .. "' doesn't exist")
		end

		table.insert(filters, filter[1](handler, value, binding))
	end

	table.sort(filters, function(a, b)
		if a.Priority ~= b.Priority then
			return a.Priority < b.Priority
		end

		return a.RegisterIndex < b.RegisterIndex
	end)

	if customFilters then
		if typeof(customFilters) ~= "table" then
			customFilters = { customFilters }
		end

		for index,filter in ipairs(type(customFilters) == "table" and customFilters or { customFilters }) do
			if typeof(filter) ~= "function" then
				error("Invalid custom filter #" .. index .. " (function expected, got " .. typeof(filter) .. ")")
			end

			table.insert(filters, filter)
		end
	end

	binding.Filters = filters
	binding.Callback = Callback.new(ApplyFilters(handler, binding))

	return binding
end

function BindToHandler(handler, object, customFilters, executePendingEvents)
	local binding = InitBinding(handler, object, customFilters)

	if not binding then
		error("Invalid binding to '" .. handler.Name .. "'")
	end

	if handler.Type == "Event" then
		table.insert(handler.Bindings, binding)
	else
		if handler.Binding then
			error("Duplicate function handler to '" .. handler.Name .. "'")
		end

		handler.Binding = binding
	end

	if not handler.IsBound then
		handler.IsBound = true

		if executePendingEvents then
			ExecutePendingEvents()
		end
	end
end

-- Server API

if IsServer then
	function FireClient(handler, remote, client: Player, ...)
		if Network.Logging then
			Network.Logging[#Network.Logging + 1] = { false, remote, client, ... }
		end

		remote:FireClient(client, ...)
	end

	function InvokeClientWithTimeout(timeout: number?, handler, client: Player, ...)
		if Network.Logging then
			Network.Logging[#Network.Logging + 1] = { false, handler.Remote, client, ... }
		end

		local result = SafeInvokeWithTimeout(timeout, handler, handler.Remote.InvokeClient, handler.Remote, client, ...)

		if result[1] == false or result[2] == false then
			return false
		end

		return true, unpack(result, 3, result.n)
	end

	-- Events

	function Network:FireClient(client: Player, name: string, ...)
		local handler = GetHandler("Event", name)
		FireClient(handler, handler.Remote, client, ...)
	end

	function Network:FireAllClients(name: string, ...)
		local handler = GetHandler("Event", name)

		for _,client in self:GetPlayers() do
			FireClient(handler, handler.Remote, client, ...)
		end
	end

	function Network:FireOtherClients(exclude: Player?, name: string, ...)
		local handler = GetHandler("Event", name)

		for _,client in self:GetPlayers() do
			if client ~= exclude then
				FireClient(handler, handler.Remote, client, ...)
			end
		end
	end

	function Network:FireClientUnreliable(client: Player, name: string, ...)
		local handler = GetHandler("Event", name)
		FireClient(handler, handler.Unreliable, client, ...)
	end

	function Network:FireAllClientsUnreliable(name: string, ...)
		local handler = GetHandler("Event", name)

		for _,client in self:GetPlayers() do
			FireClient(handler, handler.Unreliable, client, ...)
		end
	end

	function Network:FireOtherClientsUnreliable(exclude: Player?, name: string, ...)
		local handler = GetHandler("Event", name)

		for _,client in self:GetPlayers() do
			if client ~= exclude then
				FireClient(handler, handler.Unreliable, client, ...)
			end
		end
	end
	
	function Network:FireOtherClientsWithinDistance(source: Player?, maxDistance: number, name: string, ...)
		local sourcePosition = self:GetPlayerPosition(source)
		if not sourcePosition then return end

		local handler = GetHandler("Event", name)

		for _,client in ipairs(self:GetPlayers()) do
			if client ~= source then
				local position = self:GetPlayerPosition(client)
				if not position then continue end

				local distance = (sourcePosition - position).Magnitude
				if distance <= maxDistance then
					FireClient(handler, handler.Remote, client, ...)
				end
			end
		end
	end

	function Network:FireAllClientsWithinDistance(sourcePosition: Vector3, maxDistance: number, name: string, ...)
		local handler = GetHandler("Event", name)

		for _,client in ipairs(self:GetPlayers()) do
			local position = self:GetPlayerPosition(client)
			if not position then continue end

			local distance = (sourcePosition - position).Magnitude
			if distance <= maxDistance then
				FireClient(handler, handler.Remote, client, ...)
			end
		end
	end

	-- Invokes

	function Network:InvokeClientWithTimeout(timeout: number, client: Player, name: string, ...)
		local handler = GetHandler("Function", name)
		return InvokeClientWithTimeout(timeout, handler, client, ...)

	end

	function Network:InvokeClient(client: Player, name: string, ...)
		local handler = GetHandler("Function", name)
		return InvokeClientWithTimeout(nil, handler, client, ...)
	end

	-- Overrides

	local Players = game:GetService("Players")

	function Network:GetPlayers(): { Player }
		return Players:GetPlayers()
	end

	function Network:GetPlayerPosition(player: Player): Vector3?
		local primary = player and player.Character and player.Character.PrimaryPart
		return primary and primary.Position or nil
	end
end


-- Client API

if not IsServer then
	function FireServer(handler, remote, ...)
		remote:FireServer(...)
	end

	function InvokeServerWithTimeout(timeout: number?, handler, ...)
		if not handler.Remote then
			if not handler.WaitingForRemote then handler.WaitingForRemote = {} end
			table.insert(handler.WaitingForRemote, coroutine.running())
			coroutine.yield()
		end

		local result = SafeInvokeWithTimeout(timeout, handler, handler.Remote.InvokeServer, handler.Remote, ...)

		if result[1] == false or result[2] == false then
			error("InvokeServer Error")
		end

		return unpack(result, 3, result.n)
	end

	-- Events

	function Network:FireServer(name, ...)
		local handler = GetHandler("Event", name)

		if handler.Remote then
			FireServer(handler, handler.Remote, ...)
		else
			task.spawn(function(...)
				if not handler.WaitingForRemote then handler.WaitingForRemote = {} end
				table.insert(handler.WaitingForRemote, coroutine.running())
				coroutine.yield()

				FireServer(handler, handler.Remote, ...)
			end, ...)
		end
	end
	
	function Network:FireServerUnreliable(name, ...)
		local handler = GetHandler("Event", name)

		if handler.Remote then
			FireServer(handler, handler.Unreliable, ...)
		else
			task.spawn(function(...)
				if not handler.WaitingForRemote then handler.WaitingForRemote = {} end
				table.insert(handler.WaitingForRemote, coroutine.running())
				coroutine.yield()

				FireServer(handler, handler.Unreliable, ...)
			end, ...)
		end
	end

	function Network:InvokeServerWithTimeout(timeout: number, name: string, ...)
		local handler = GetHandler("Function", name)
		return InvokeServerWithTimeout(timeout, handler, ...)
	end

	function Network:InvokeServer(name: string, ...)
		local handler = GetHandler("Function", name)
		return InvokeServerWithTimeout(nil, handler, ...)
	end

	-- Init

	EventsFolder.ChildAdded:Connect(function(child) GetHandler("Event", child.Name) end)
	for _,child in pairs(EventsFolder:GetChildren()) do task.spawn(GetHandler, "Event", child.Name) end

	FunctionsFolder.ChildAdded:Connect(function(child) GetHandler("Function", child.Name) end)
	for _,child in ipairs(FunctionsFolder:GetChildren()) do task.spawn(GetHandler, "Function", child.Name) end
end


-- Shared API

function Network:BindEvents(customFilters, bindings)
	if not bindings then
		customFilters, bindings = nil, customFilters
	end

	for key,binding in pairs(bindings) do
		BindToHandler(GetHandler("Event", key), binding, customFilters, false)
	end

	ExecutePendingEvents()
end

function Network:BindFunctions(customFilters, bindings)
	if not bindings then
		customFilters, bindings = nil, customFilters
	end

	for key,binding in pairs(bindings) do
		BindToHandler(GetHandler("Function", key), binding, customFilters, false)
	end

	ExecutePendingEvents()
end

function Network:RegisterFilters(filters)
	for key,filter in pairs(filters) do
		if Filters[key] then
			error("Duplicate filter '" .. key .. "'")
		end

		filter = InitFilter(filter)

		if not filter then
			error("Invalid filter '" .. key .. "'")
		end

		Filters[key] = filter
	end
end


-- Filters

Network:RegisterFilters({
	MatchParams = {
		--[[
			Errors if event parameter types do not match
			Example:
			
			EventName = {
				MatchParams = { "string", "number | string", "number?" },
				function(client: Player, arg1: string, arg2: number | string, arg3: number?)
					-- Is never called if argument types don't match
					-- Note that first param is ignored on server, as it will always be the player object
				end
			}
		--]]

		Priority = -100,
		function(handler, paramTypes)
			paramTypes = { unpack(paramTypes) }

			if IsServer then
				table.insert(paramTypes, 1, "Instance")
			end

			for i,v in pairs(paramTypes) do
				local list = type(v) == "string" and string.split(v:gsub("%?", "|nil"), "|") or v

				local dict = {}
				local typeListString = ""

				for _,v in pairs(list) do
					local typeString = v:gsub("^%s+", ""):gsub("%s+$", "")

					typeListString ..= (#typeListString > 0 and " or " or "") .. typeString
					dict[typeString:lower()] = true
				end

				dict._string = typeListString
				paramTypes[i] = dict
			end

			return function(...)
				local params = table.pack(...)

				for i,argExpected in ipairs(paramTypes) do
					local argType = typeof(params[i])
					local argExpected = paramTypes[i]

					if not argExpected[argType:lower()] and not argExpected.any then
						if IsStudio then
							warn(("[Network] Invalid argument #%d to %s (%s expected, got %s)"):format(i, handler.Name, argExpected._string, argType))
						end

						return false
					end
				end

				return true, ...
			end
		end
	}
})

-- Logging

if IsServer then
	function Network:LogTraffic(duration)
		if Network.Logging then return end
		warn("Logging Network Traffic...")

		Network.Logging = {}
		local start = tick()

		task.delay(duration, function()
			local effDur = tick() - start

			local log = Network.Logging
			Network.Logging = nil

			local clientTraffic = {}

			for i,v in pairs(log) do
				local remote = v[2]
				local player = v[3]

				local playerTraffic = clientTraffic[player]
				if not playerTraffic then
					playerTraffic = { total = 0 }
					clientTraffic[player] = playerTraffic
				end

				local remoteTraffic = playerTraffic[remote]
				if not remoteTraffic then
					remoteTraffic = { dataIn = {}, dataOut = {} }
					playerTraffic[remote] = remoteTraffic
				end

				local target = v[1] and remoteTraffic.dataIn or remoteTraffic.dataOut

				target[#target + 1] = v
				playerTraffic.total = playerTraffic.total + 1
			end

			for player,remotes in pairs(clientTraffic) do
				warn(string.format("Player '%s', total received: %d", player.Name, remotes.total))
				remotes.total = nil

				for remote,data in pairs(remotes) do
					-- Incoming

					local list = data.dataIn
					if #list > 0 then
						warn(string.format("   %s %s: %d (%.2f/s)", "FireServer", remote.Name, #list, #list / effDur))

						local count = math.min(#list, 3)
						for i = 1, count do
							local index = math.floor(1 + (i - 1) / math.max(1, count - 1) * (#list - 1) + 0.5)
							local params = list[1]
							local paramString = ""

							for i = 4, math.min(#params, 7) do
								local value = params[i]
								paramString ..= (#paramString > 0 and ", " or "") .. (typeof(value) == "string" and "string[" .. #value .. "]" or typeof(value))
							end

							warn(("      %d: %s"):format(index, paramString))
						end
					end

					-- Outgoing

					local list = data.dataOut
					if #list > 0 then
						warn(string.format("   %s %s: %d (%.2f/s)", "FireClient", remote.Name, #list, #list / effDur))

						local count = math.min(#list, 3)
						for i = 1, count do
							local index = math.floor(1 + (i - 1) / math.max(1, count - 1) * (#list - 1) + 0.5)
							local params = list[index]
							local paramString = ""

							for i = 4, math.min(#params, 7) do
								local value = params[i]
								paramString ..= (#paramString > 0 and ", " or "") .. (typeof(value) == "string" and "string[" .. #value .. "]" or typeof(value))
							end

							warn(string.format("      %d: %s", index, paramString))
						end
					end
				end
			end
		end)
	end
end



-- Reference extension

do
	local References = {} 
	local Objects = {}

	function Network:AddReference(key, refType, ...)
		local refData = {
			Type = refType,
			Reference = key,
			Objects = {...},
			Aliases = {}
		}

		if not References[refType] then
			References[refType] = {}
			Objects[refType] = {}
		end

		References[refType][refData.Reference] = refData

		local last = Objects[refType]
		for _,obj in ipairs(refData.Objects) do
			local list = last[obj] or {}
			last[obj] = list
			last = list
		end

		last.__Data = refData
	end

	function Network:AddReferenceAlias(key, refType, ...)
		local refData = References[refType] and References[refType][key]
		if not refData then
			warn("Tried to add an alias to a non-existing reference")
			return
		end

		local objects = {...}
		refData.Aliases[#refData.Aliases + 1] = objects

		local last = Objects[refType]
		for _,obj in ipairs(objects) do
			local list = last[obj] or {}
			last[obj] = list
			last = list
		end

		last.__Data = refData
	end

	function Network:RemoveReference(key, refType)
		local refData = References[refType] and References[refType][key]
		if not refData then
			warn("Tried to remove a non-existing reference")
			return
		end

		References[refType][refData.Reference] = nil

		local function rem(parent, objects, index)
			if index <= #objects then
				local key = objects[index]
				local child = parent[key]

				rem(child, objects, index + 1)

				if next(child) == nil then
					parent[key] = nil
				end
			elseif parent.__Data == refData then
				parent.__Data = nil
			end
		end

		local objects = Objects[refData.Type]
		rem(objects, refData.Objects, 1)

		for i,alias in ipairs(refData.Aliases) do
			rem(objects, alias, 1)
		end
	end

	function Network:GetObject(ref, refType)
		local refData = References[refType] and References[refType][ref]
		if not refData then
			return nil
		end

		return unpack(refData.Objects)
	end

	function Network:GetReference(...)
		local objects = {...}
		local refType = table.remove(objects)

		if not References[refType] then
			return nil
		end

		local last = Objects[refType]
		for i,v in ipairs(objects) do
			last = last[v]

			if not last then
				break
			end
		end

		local refData = last and last.__Data
		return refData and refData.Reference or nil
	end
end

return Network