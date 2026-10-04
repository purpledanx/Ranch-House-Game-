--[=[
Realistic Sound System — quick setup
- Place in StarterPlayerScripts; restart playtesting after worker changes.
- Doorways: name a frame Model DoorFrame/Doorway, or set SoundPortal = true
  on a Model, Part or Attachment centered in the opening.
- Exclude a Sound/AudioEmitter add a attribute: RealisticSoundEnabled = false.
- Walls only block when CanQuery AND CanCollide are true.
- Part attributes: SoundOcclusion = false ignores it; SoundOcclusionThickness
  (studs) and SoundOcclusionMaterial (e.g. "Wood") override its acoustic properties.
- SoundRoomBoundary = true on a wall/Model requires doorway routes; leave unset
  on open partitions.
- Script attributes: OcclusionDebug toggles logs; OcclusionDebugSound filters by name.
- Tune response, caching and budgets in SETTINGS below.
]=]

-- Configuration: time values are seconds, distances are studs, and EQ values are dB.
local SETTINGS = {
	Response = {
		VolumeSeconds = 0.025,
		MuffleSeconds = 0.012,
		GainSnapTolerance = 0.0001,
		EqualizerSnapToleranceDb = 0.001,
		MinimumDirectionStuds = 0.1,
	},
	Cache = {
		LifetimeSeconds = 0.25,
		DoorwayLifetimeSeconds = 0.1,
		MovementThresholdStuds = 0.2,
		MaintenanceIntervalSeconds = 1,
		UnusedLifetimeSeconds = 5,
		InitialAgeSeconds = 100,
		PriorityDistanceStuds = 20,
	},
	Budget = {
		RequestedWorkers = 256,
		DesktopJobs = 2,
		ReducedJobs = 1,
		DesktopProbes = 2,
		ReducedProbes = 1,
		MaximumInputGraphNodes = 32,
		MaximumResultWrappers = 3,
	},
	Performance = {
		DesktopIntervalSeconds = 0.033,
		MobileIntervalSeconds = 0.06,
		SlowIntervalSeconds = 0.09,
		InitialFramesPerSecond = 60,
		EnterSlowFramesPerSecond = 35,
		LeaveSlowFramesPerSecond = 50,
		FrameTimeSmoothingWeight = 0.05,
		MaximumFrameSampleSeconds = 0.25,
	},
	Debug = {
		EnabledByDefault = false,
		PrintIntervalSeconds = 1,
	},
}

-- Blocker snapshot layout shared with the occlusion worker's transport result.
local BLOCKER = {
	Object = 1,
	Transform = 2,
	Size = 3,
	Material = 4,
	CanCollide = 5,
	Transparency = 6,
	OcclusionOverride = 7,
	ThicknessOverride = 8,
	MaterialOverride = 9,
	Route = 10,
	CanQuery = 11,
}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

-- The scheduler parents its worker Actors to itself. Keep those client workers
-- beneath PlayerScripts by owning a clone here, rather than in ReplicatedStorage.
local schedulerClone = ReplicatedStorage.Modules.Util.ParallelScheduler:Clone()
schedulerClone.Name = "RealisticSoundScheduler"
schedulerClone.Parent = script

local ParallelScheduler = require(schedulerClone)
local OcclusionModule = ReplicatedStorage.Modules.Sounds:WaitForChild("RealisticSoundOcclusion")
local Paths = require(OcclusionModule.InstancePaths)

-- Runtime state.
local player = Players.LocalPlayer
local character = player.Character
local records = {}
local cache = {}
local pending = {}
local filter = {}
local filterVersion = 0
local now = 0
local scanElapsed = 0
local maintenanceElapsed = 0
local dispatchElapsed = 0
local frameTime = 1 / SETTINGS.Performance.InitialFramesPerSecond
local slow = false
local mobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
local connections = {}
local stopped = false

-- Enabled for the requested investigation; disable on this LocalScript to stop logs.
if script:GetAttribute("OcclusionDebug") == nil then
	script:SetAttribute("OcclusionDebug", SETTINGS.Debug.EnabledByDefault)
end

-- Diagnostics.
local function debugSound(object, record, result)
	if script:GetAttribute("OcclusionDebug") ~= true then
		return
	end
	local nameFilter = script:GetAttribute("OcclusionDebugSound")
	if type(nameFilter) == "string" and nameFilter ~= "" and not string.find(object.Name, nameFilter, 1, true) then
		return
	end
	if now < (record.nextDebug or 0) then
		return
	end
	record.nextDebug = now + SETTINGS.Debug.PrintIntervalSeconds
	local blockerLines = {}
	for _, snapshot in ipairs(result.blockers) do
		local part = snapshot[BLOCKER.Object]
		local path = part and part:GetFullName() or "<removed blocker>"
		local line = string.format(
			"  [%s] %s | material=%s | size=%s | CanQuery=%s",
			snapshot[BLOCKER.Route] or "path",
			path,
			snapshot[BLOCKER.Material],
			tostring(snapshot[BLOCKER.Size]),
			tostring(part and part.CanQuery)
		)
		table.insert(blockerLines, line)
	end

	local route = result.routeReason or (result.diffracted and "indirect" or "direct")
	local blockerSummary = #blockerLines > 0 and table.concat(blockerLines, "\n")
		or "  No blocking parts detected."
	local message = string.format(
		"[RealisticSound] %s | walls=%d gain=%.3f mid=%.1fdB high=%.1fdB | %s | portals=%d rays=%d\n%s",
		object:GetFullName(),
		result.walls,
		result.gain,
		result.mid,
		result.high,
		route,
		result.portalCount or 0,
		result.rays or 0,
		blockerSummary
	)
	print(message, object)
end

local function connect(signal, callback)
	local connection = signal:Connect(callback)
	table.insert(connections, connection)
	return connection
end

-- Source discovery and raycast exclusions.
local function rebuildFilter()
	local fresh = {}
	local house = workspace:FindFirstChild("House")
	local function exclude(object)
		if object then
			table.insert(fresh, object)
		end
	end

	exclude(house:FindFirstChild("RoomRegions"))
	exclude(house:FindFirstChild("Walk"))
	exclude(house:FindFirstChild("Hitbox"))
	exclude(workspace:FindFirstChild("InvWall"))
	exclude(workspace:FindFirstChild("SoundReverbV2DebugRays"))
	for _, other in ipairs(Players:GetPlayers()) do
		exclude(other.Character)
	end
	exclude(character)
	if #fresh ~= #filter then
		filterVersion = filterVersion + 1
	else
		for i, object in ipairs(fresh) do
			if filter[i] ~= object then
				filterVersion = filterVersion + 1
				break
			end
		end
	end
	filter = fresh
end

local function getSource(object, record)
	local source = record and record.spatialParent or object.Parent
	while source and source ~= workspace do
		if source:IsA("Attachment") then
			return source.WorldPosition, source.Parent, source
		elseif source:IsA("BasePart") then
			return source.Position, source, source
		elseif source:IsA("Model") then
			return source:GetPivot().Position, source.PrimaryPart, source
		end
		source = source.Parent
	end
	return nil
end

local function walkInputs(root, wanted)
	local stack, visited = {root}, {}
	local playing = false
	for _ = 1, SETTINGS.Budget.MaximumInputGraphNodes do
		local object = table.remove(stack)
		if not object then
			break
		end
		if object == wanted then
			return true
		end
		if not visited[object] then
			visited[object] = true
			if object:IsA("AudioPlayer") then
				playing = playing or object.IsPlaying
			else
				local pins = object:GetInputPins()
				if #pins == 0 then
					playing = true
				end -- Live inputs have no IsPlaying property.
				for _, pin in ipairs(pins) do
					for _, wire in ipairs(object:GetConnectedWires(pin)) do
						if wire.SourceInstance then
							table.insert(stack, wire.SourceInstance)
						end
					end
				end
			end
		end
	end
	if wanted then
		return #stack > 0
	end -- Keep unfamiliar/deep graphs intact rather than risk a loop.
	return playing
end

-- Owned audio effects and apparent source positioning.
local function ensureEffects(object, record)
	if object:IsA("Sound") then
		if not record.equalizer or not record.equalizer.Parent then
			local eq = Instance.new("EqualizerSoundEffect")
			eq.Name = "RealisticSoundMuffling"
			eq.LowGain, eq.MidGain, eq.HighGain = 0, 0, 0
			eq.Parent = object
			record.equalizer = eq
		end
		return
	end
	local incoming = object:GetConnectedWires("Input")
	if not record.fader or not record.fader.Parent then
		if #incoming == 0 then
			return
		end
		local eq = Instance.new("AudioEqualizer")
		eq.Name = "RealisticSoundMuffling"
		eq.LowGain, eq.MidGain, eq.HighGain = 0, 0, 0
		eq.Parent = object
		local fader = Instance.new("AudioFader")
		fader.Name = "RealisticSoundOcclusion"
		fader.Volume = record.gain
		fader.Parent = object
		for _, wire in ipairs(incoming) do
			wire.TargetInstance = eq
		end
		local bridge = Instance.new("Wire")
		bridge.SourceInstance, bridge.TargetInstance, bridge.Parent = eq, fader, eq
		local output = Instance.new("Wire")
		output.SourceInstance, output.TargetInstance, output.Parent = fader, object, fader
		record.equalizer, record.fader, record.output = eq, fader, output
	else
		for _, wire in ipairs(incoming) do
			if wire ~= record.output and not walkInputs(wire.SourceInstance, record.fader) then
				wire.TargetInstance = record.equalizer
			end
		end
	end
end

local function setAttribute(object, name, value)
	if object:GetAttribute(name) ~= value then
		object:SetAttribute(name, value)
	end
end

local function releasePosition(object, record)
	local anchor = record.anchor
	if not anchor then
		return
	end
	record.relocating = true
	if record.isSound then
		if object.Parent == anchor then
			object.Parent = record.spatialParent
		end
	end
	record.anchor, record.spatialParent = nil, nil
	anchor:Destroy()
	record.relocating = nil
end

local function updatePosition(object, record, listener, source, result)
	if not record.isSound then
		return
	end
	local doorway = result and result.doorwayPosition
	if not doorway or not listener or not source then
		releasePosition(object, record)
		return
	end
	local direction = doorway - listener
	if direction.Magnitude < SETTINGS.Response.MinimumDirectionStuds then
		releasePosition(object, record)
		return
	end
	if not record.anchor then
		record.spatialParent = object.Parent
		local anchor = Instance.new("Attachment")
		anchor.Name = "RealisticSoundDirection"
		anchor.Parent = object.Parent
		record.anchor = anchor
	end
	-- Preserve distance rolloff while steering the apparent direction through
	-- the opening. One reusable attachment per routed source, no helper Parts.
	local distance = math.max((source - listener).Magnitude, result.pathLength or 0)
	record.anchor.WorldPosition = listener + direction.Unit * distance
	record.relocating = true
	if record.isSound then
		object.Parent = record.anchor
	end
	record.relocating = nil
end

-- Sound registration and cleanup.
local function register(object)
	if records[object] or not (object:IsA("Sound") or object:IsA("AudioEmitter")) then
		return
	end
	local record = {
		gain = 1,
		mid = 0,
		high = 0,
		target = 1,
		targetMid = 0,
		targetHigh = 0,
		isSound = object:IsA("Sound")
	}
	if record.isSound then
		record.baseVolume, record.lastVolume = object.Volume, object.Volume
	end
	records[object] = record
end

-- Restore only effects and positioning owned by this system.
local function restoreSound(object, record)
	releasePosition(object, record)
	if record.isSound then
		if object.Volume == record.lastVolume then
			object.Volume = record.baseVolume
		end
	elseif record.fader and record.fader.Parent then
		local destination = record.output.TargetInstance or object
		for _, wire in ipairs(record.equalizer:GetConnectedWires("Input")) do
			wire.TargetInstance = destination
		end
		record.fader:Destroy()
	end
	if record.equalizer then
		record.equalizer:Destroy()
	end
	for _, name in ipairs({
		"OcclusionWallCount", "OcclusionTargetGain", "OcclusionHasPosition", "OcclusionDiffracted",
		"OcclusionTargetHighGain"
	}) do
		object:SetAttribute(name, nil)
	end
	record.equalizer, record.fader, record.output = nil, nil, nil
	record.entry, record.position = nil, nil
	record.active = false
	record.gain, record.target = 1, 1
	record.mid, record.high, record.targetMid, record.targetHigh = 0, 0, 0, 0
	if record.isSound then record.lastVolume = object.Volume end
end

local function unregister(object)
	local record = records[object]
	if not record or record.relocating then
		return
	end
	records[object] = nil
	restoreSound(object, record)
end

-- Cache validation and worker results.
local function barriersChanged(entry)
	for _, snapshot in ipairs(entry.result.blockers) do
		local part = snapshot[BLOCKER.Object]
		local partChanged = not part
			or not part.Parent
			or part.CFrame ~= snapshot[BLOCKER.Transform]
			or part.Size ~= snapshot[BLOCKER.Size]
			or part.Material.Name ~= snapshot[BLOCKER.Material]
			or part.CanCollide ~= snapshot[BLOCKER.CanCollide]
			or part.CanQuery ~= snapshot[BLOCKER.CanQuery]
			or part.Transparency ~= snapshot[BLOCKER.Transparency]
			or part:GetAttribute("SoundOcclusion") ~= snapshot[BLOCKER.OcclusionOverride]
			or part:GetAttribute("SoundOcclusionThickness") ~= snapshot[BLOCKER.ThicknessOverride]
			or part:GetAttribute("SoundOcclusionMaterial") ~= snapshot[BLOCKER.MaterialOverride]

		if partChanged then
			return true
		end
	end
	return false
end

-- Load one scheduler for every sound. Never queue a new batch while Work() is waiting.
-- Batches contain at most two jobs, so larger pools cannot improve latency.
local poolSize
if mobile then
	poolSize = SETTINGS.Budget.ReducedJobs
else
	poolSize = math.clamp(SETTINGS.Budget.RequestedWorkers, 1, SETTINGS.Budget.DesktopJobs)
end
local batchRunning = false
local schedulerFailed = false
local scheduler = ParallelScheduler:LoadModule(OcclusionModule)
scheduler:SetMaxWorkers(poolSize)
setAttribute(script, "OcclusionWorkerCount", poolSize)
local warned = false

local function unpackResult(value)
	-- Some worker templates forward the returned table; others pack return values.
	-- Accept either shape, but never silently discard a missing/invalid result.
	for _ = 1, SETTINGS.Budget.MaximumResultWrappers do
		if type(value) ~= "table" then
			break
		end
		if value.error then
			return value
		end
		local isResult = type(value.gain) == "number"
			and type(value.mid) == "number"
			and type(value.high) == "number"
			and type(value.blockers) == "table"
		if isResult then
			return value
		end
		value = value[1]
	end
	return {
		error = "ParallelScheduler returned no valid occlusion result",
	}
end

local function accept(request, result)
	local entry = request.entry
	entry.pending = nil
	if result and not result.error and cache[entry.key] == entry and request.version == filterVersion then
		-- Resolve blocker references once, after leaving SharedTable transport.
		for _, snapshot in ipairs(result.blockers) do
			snapshot[BLOCKER.Object] = Paths.Decode(snapshot[BLOCKER.Object])
		end
		-- Cache age starts when sampled, not when a delayed worker finishes.
		entry.result, entry.updated = result, request.started
		entry.listener, entry.source = request.listener, request.source
		entry.version = request.version
		if result.walls > 0 then
			setAttribute(script, "OcclusionPortalCount", result.portalCount or 0)
		end
		setAttribute(script, "OcclusionStatus", "Ready")
	elseif result and result.error and not warned then
		warned = true
		setAttribute(script, "OcclusionStatus", result.error)
		warn("Realistic sound calculation failed: " .. result.error)
	end
end

-- Bounded scheduler dispatch.
local function runBatch()
	if batchRunning or #pending == 0 or stopped then
		return
	end
	batchRunning = true
	setAttribute(script, "OcclusionStatus", "Calculating")
	local requests = pending
	pending = {}
	local filterJSON = Paths.EncodeList(filter)
	-- Work() yields, so run it away from Heartbeat. Audio writes remain on the main VM.
	task.spawn(function()
		local ok, results = pcall(function()
			for _, request in ipairs(requests) do
				scheduler:ScheduleWork(
					request.listener,
					request.source,
					request.sourcePath,
					filterJSON,
					request.probes
				)
			end
			return scheduler:Work()
		end)

		if not stopped then
			for index, request in ipairs(requests) do
				local value = ok and results and results[index]
				accept(request, ok and unpackResult(value) or {
					error = tostring(results),
				})
			end

			if not ok then
				-- Do not accumulate queued jobs after a scheduler setup failure.
				schedulerFailed = true
				if not warned then
					warned = true
					warn("Realistic sound scheduler failed: " .. tostring(results))
				end
			end
		end
		batchRunning = false
	end)
end

local function dispatch(entry, listener, probes)
	if batchRunning then
		return false
	end
	entry.pending = true
	table.insert(pending, {
		entry = entry,
		listener = listener,
		source = entry.position,
		sourcePath = Paths.Encode(entry.sourceObject),
		version = filterVersion,
		probes = probes,
		started = now,
	})
	return true
end

connect(player.CharacterAdded, function(newCharacter)
	character = newCharacter
	rebuildFilter()
end)
connect(player.CharacterRemoving, function(oldCharacter)
	if character == oldCharacter then
		character = nil
		rebuildFilter()
	end
end)
connect(workspace.DescendantAdded, register)
connect(workspace.DescendantRemoving, unregister)
for _, object in ipairs(workspace:GetDescendants()) do
	register(object)
end
rebuildFilter()

-- Active source scanning.
local function scan(listener)
	for _, entry in pairs(cache) do
		entry.active = false
	end
	for object, record in pairs(records) do
		if record.isSound and object.Volume ~= record.lastVolume then
			record.baseVolume = object.Volume
		end
		-- Set this Boolean attribute on a Sound or AudioEmitter to bypass occlusion.
		if object:GetAttribute("RealisticSoundEnabled") == false then
			if not record.excluded then
				restoreSound(object, record)
				record.excluded = true
			end
		else
			record.excluded = false
			-- Respect another script taking ownership of the source position.
			local soundWasMoved = record.isSound and object.Parent ~= record.anchor
			if record.anchor and soundWasMoved then
				releasePosition(object, record)
			end

			local position, sourceObject, key = getSource(object, record)
			local playing = record.isSound and object.IsPlaying or (not record.isSound and walkInputs(object))
			local active = listener and position and playing

			-- Native positional Sounds outside their rolloff are already inaudible.
			if active and record.isSound and object.Parent and not object.Parent:IsA("Model") then
				local hasSpatialParent = object.Parent:IsA("BasePart") or object.Parent:IsA("Attachment")
				local outsideRolloff = (position - listener).Magnitude > object.RollOffMaxDistance
				if hasSpatialParent and outsideRolloff then
					active = false
				end
			end

			record.active = active
			setAttribute(object, "OcclusionHasPosition", position ~= nil)

			if active then
				local entry = cache[key]
				if not entry then
					entry = {
						key = key,
						updated = -SETTINGS.Cache.InitialAgeSeconds,
						position = position,
						sourceObject = sourceObject,
					}
					cache[key] = entry
				end

				entry.active = true
				entry.lastUsed = now
				entry.position = position
				entry.sourceObject = sourceObject
				record.entry = entry
				record.position = position
				ensureEffects(object, record)

				local result = entry.result
				if result then
					record.target = result.gain
					record.targetMid = result.mid
					record.targetHigh = result.high
					setAttribute(object, "OcclusionWallCount", result.walls)
					setAttribute(object, "OcclusionTargetGain", result.gain)
					setAttribute(object, "OcclusionDiffracted", result.diffracted)
					setAttribute(object, "OcclusionTargetHighGain", result.high)
				end
			else
				record.entry = nil
				releasePosition(object, record)
				record.target = 1
				record.targetMid = 0
				record.targetHigh = 0
			end
		end
	end
end

-- Refresh priority and adaptive work budgets.
local function cacheEntryIsStale(entry, listener, lifetime)
	if not entry.result or entry.version ~= filterVersion then
		return true
	end
	if now - entry.updated >= lifetime then
		return true
	end
	if (entry.listener - listener).Magnitude >= SETTINGS.Cache.MovementThresholdStuds then
		return true
	end
	if (entry.source - entry.position).Magnitude >= SETTINGS.Cache.MovementThresholdStuds then
		return true
	end
	return barriersChanged(entry)
end

local function schedule(listener)
	if not listener or batchRunning or schedulerFailed then
		return
	end
	local jobCount = (slow or mobile) and SETTINGS.Budget.ReducedJobs or SETTINGS.Budget.DesktopJobs
	local probeCount = slow and SETTINGS.Budget.ReducedProbes or SETTINGS.Budget.DesktopProbes

	for _ = 1, jobCount do
		local best, bestPriority
		for _, entry in pairs(cache) do
			if entry.active and not entry.pending then
				-- A doorway can carry the audible high frequencies even when bass
				-- transmission through the wall dominates volume and direction.
				local hasPortal = entry.result and (entry.result.portalCount or 0) > 0
				local lifetime = hasPortal and SETTINGS.Cache.DoorwayLifetimeSeconds
					or SETTINGS.Cache.LifetimeSeconds

				if cacheEntryIsStale(entry, listener, lifetime) then
					-- Age prevents starvation; nearby/new sounds get quicker initial service.
					local distance = (entry.position - listener).Magnitude
					local distanceBonus = 1 / (1 + distance / SETTINGS.Cache.PriorityDistanceStuds)
					local priority = now - entry.updated + distanceBonus
					if not bestPriority or priority > bestPriority then
						best = entry
						bestPriority = priority
					end
				end
			end
		end
		if not best or not dispatch(best, listener, probeCount) then
			break
		end
	end
	runBatch()
end

local function getUpdateInterval()
	if slow then
		return SETTINGS.Performance.SlowIntervalSeconds
	end
	if mobile then
		return SETTINGS.Performance.MobileIntervalSeconds
	end
	return SETTINGS.Performance.DesktopIntervalSeconds
end

local function getListenerPosition()
	if not character then
		return nil
	end

	local head = character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart")
	return head and head.Position
end

local function recordNeedsUpdate(record)
	return record.active
		or record.gain ~= record.target
		or record.mid ~= record.targetMid
		or record.high ~= record.targetHigh
end

local function updateRecord(object, record, listener, volumeAlpha, muffleAlpha)
	-- Consume completed work immediately, without waiting for another scan.
	local result = record.active and record.entry and record.entry.result
	if result then
		record.target = result.gain
		record.targetMid = result.mid
		record.targetHigh = result.high
		debugSound(object, record, result)
	end

	updatePosition(object, record, listener, record.position, result)
	if not recordNeedsUpdate(record) then
		return
	end

	if record.isSound and object.Volume ~= record.lastVolume then
		record.baseVolume = object.Volume
	end

	record.gain = record.gain + (record.target - record.gain) * volumeAlpha
	record.mid = record.mid + (record.targetMid - record.mid) * muffleAlpha
	record.high = record.high + (record.targetHigh - record.high) * muffleAlpha

	if math.abs(record.gain - record.target) < SETTINGS.Response.GainSnapTolerance then
		record.gain = record.target
	end
	if math.abs(record.mid - record.targetMid) < SETTINGS.Response.EqualizerSnapToleranceDb then
		record.mid = record.targetMid
	end
	if math.abs(record.high - record.targetHigh) < SETTINGS.Response.EqualizerSnapToleranceDb then
		record.high = record.targetHigh
	end

	if record.isSound then
		local volume = record.baseVolume * record.gain
		if object.Volume ~= volume then
			object.Volume = volume
		end
		record.lastVolume = object.Volume
	elseif record.fader and record.fader.Parent then
		record.fader.Volume = record.gain
	end

	if record.equalizer and record.equalizer.Parent then
		record.equalizer.MidGain = record.mid
		record.equalizer.HighGain = record.high
	end
end

-- Frame updates.
connect(RunService.Heartbeat, function(dt)
	if stopped then
		return
	end
	now = now + dt
	local sampledFrameTime = math.min(dt, SETTINGS.Performance.MaximumFrameSampleSeconds)
	frameTime = frameTime + (sampledFrameTime - frameTime) * SETTINGS.Performance.FrameTimeSmoothingWeight

	if frameTime > 1 / SETTINGS.Performance.EnterSlowFramesPerSecond then
		slow = true
	elseif frameTime < 1 / SETTINGS.Performance.LeaveSlowFramesPerSecond then
		slow = false
	end
	maintenanceElapsed = maintenanceElapsed + dt
	if maintenanceElapsed >= SETTINGS.Cache.MaintenanceIntervalSeconds then
		maintenanceElapsed = 0
		rebuildFilter()
		for key, entry in pairs(cache) do
			if not entry.pending and now - (entry.lastUsed or 0) > SETTINGS.Cache.UnusedLifetimeSeconds then
				cache[key] = nil
			end
		end
	end

	scanElapsed = scanElapsed + dt
	local listener = getListenerPosition()
	local updateInterval = getUpdateInterval()
	if scanElapsed >= updateInterval then
		scanElapsed = 0
		scan(listener)
	end

	-- A completed batch need not wait for another full source scan. Keep a
	-- separate dispatch budget so movement responds promptly without a backlog.
	dispatchElapsed = dispatchElapsed + dt
	if not batchRunning and dispatchElapsed >= updateInterval then
		dispatchElapsed = 0
		schedule(listener)
	end

	local volumeAlpha = 1 - math.exp(-dt / SETTINGS.Response.VolumeSeconds)
	local muffleAlpha = 1 - math.exp(-dt / SETTINGS.Response.MuffleSeconds)
	for object, record in pairs(records) do
		updateRecord(object, record, listener, volumeAlpha, muffleAlpha)
	end
end)

-- Shutdown.
connect(script.Destroying, function()
	stopped = true
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
	for object in pairs(records) do
		unregister(object)
	end
	-- Wait for the scheduler's active batch before releasing its actors/shared tables.
	-- Preserve the workers during this script's destruction until Work() returns.
	if batchRunning and script.Parent then
		schedulerClone.Parent = script.Parent
	end
	task.spawn(function()
		while batchRunning do
			task.wait()
		end
		scheduler:Destroy()
		schedulerClone:Destroy()
	end)
	table.clear(pending)
	table.clear(cache)
end)
