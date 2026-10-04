-- Pure spatial reads and acoustic math; ParallelScheduler owns worker execution.
local Paths = require(script.InstancePaths)
local MAX_RAYS = 24
local MAX_HITS = 8
local MAX_DIRECT_RAYS = 6 -- Leave at least 18 rays for routes around obstructions.
local BLOCKED_DIRECT_MID_LOSS_DB = 8
local BLOCKED_DIRECT_HIGH_LOSS_DB = 20
-- Gentle game-scale air absorption relative to bass. Distance loudness rolloff
-- remains engine-owned; these values only change the frequency balance.
local DISTANCE_FILTER = {
	MidLossDbPerStud = 0.008,
	HighLossDbPerStud = 0.035,
	MaxMidLossDb = 4,
	MaxHighLossDb = 12,
}
local ROUTE = {
	SurfaceClearanceStuds = 0.15,
	EdgeClearanceStuds = 0.35,
	LocalProbeOffsetStuds = 0.75,
	LowBaseLossDb = 0.5,
	MidBaseLossDb = 1,
	HighBaseLossDb = 2,
	LowLossPerExtraStud = 0.75,
	MidLossPerExtraStud = 1.5,
	HighLossPerExtraStud = 3,
}

local SEARCH = {
	MaxNodes = 40,
	MaxIterations = 24,
	MaxPortals = 4,
	MaxCandidates = 64,
	MaxDetours = 3,
	MaxOpeningHops = 3,
	NodeMergeStuds = 0.1,
	MaxHints = 32,
	HintLifetimeSeconds = 1,
	VerifiedSegmentPreference = 0.15,
	MaxPreferenceStuds = 1,
	WideProbeStuds = 3,
}
local routeHints, routeHintCount = {}, 0

-- Tuned game approximations in dB, not measured laboratory transmission coefficients.
-- Each band has a surface loss plus an additional loss per stud of wall thickness.
local MATERIALS = {
	Wood = {2, 1, 5, 2, 9, 3.5},
	WoodPlanks = {2, 1, 5, 2, 9, 3.5},
	Concrete = {6, 3, 13, 5, 22, 8},
	Brick = {5, 2.5, 11, 4, 19, 7},
	Metal = {5, 2, 12, 4, 20, 7},
	DiamondPlate = {5, 2, 12, 4, 20, 7},
	Glass = {2, 1, 6, 2, 12, 4},
	Plastic = {2, 0.8, 4, 1.5, 7, 2.5},
	SmoothPlastic = {2, 0.8, 4, 1.5, 7, 2.5},
	Fabric = {1, 0.5, 3, 1, 8, 3},
	Rock = {6, 3, 13, 5, 22, 8},
	Slate = {6, 3, 13, 5, 22, 8},
}
local DEFAULT_MATERIAL = MATERIALS.Concrete
local TRANSMISSION_SCALE = 0.45
-- Keep transmission as a baseline when a diffraction route appears/disappears.
local DIRECT_WEIGHT_WITH_INDIRECT_ROUTE = 1
-- Unclassified parts may be furniture panels rather than separate room walls.
-- Keep the strongest loss plus a small contribution from the rest. Explicit
-- SoundRoomBoundary geometry remains additive. This is a bounded approximation.
local SECONDARY_BLOCKER_WEIGHT = 0.15

local function amplitude(db)
	return 10 ^ (-db / 20)
end

local function wallThickness(part, origin, direction, length)
	local override = part:GetAttribute("SoundOcclusionThickness")
	if typeof(override) == "number" and override == override then
		return math.clamp(override, 0.05, 12)
	end
	-- Ray/OBB intersection, including rotated walls. Meshes use their bounding box.
	local p = part.CFrame:PointToObjectSpace(origin)
	local d = part.CFrame:VectorToObjectSpace(direction)
	local half = part.Size * 0.5
	local enter, leave = 0, length
	local function slab(position, delta, extent)
		if math.abs(delta) < 0.00001 then return math.abs(position) <= extent end
		local a, b = (-extent - position) / delta, (extent - position) / delta
		enter = math.max(enter, math.min(a, b))
		leave = math.min(leave, math.max(a, b))
		return enter <= leave
	end
	if not slab(p.X, d.X, half.X)
		or not slab(p.Y, d.Y, half.Y)
		or not slab(p.Z, d.Z, half.Z)
	then
		return 0.25
	end
	return math.clamp(leave - enter, 0.05, 12)
end

-- Discover actual openings, never infer one from the end of a wall part.
-- Models named DoorFrame/Doorway are supported automatically. Other layouts
-- can mark a Model, Part or Attachment at the opening with SoundPortal=true.
local portalObjects, nextPortalRefresh = {}, 0
local function getPortals()
	if os.clock() >= nextPortalRefresh then
		nextPortalRefresh = os.clock() + 5
		table.clear(portalObjects)
		local root = workspace:FindFirstChild("House") or workspace
		for _, object in ipairs(root:GetDescendants()) do
			local marked = object:GetAttribute("SoundPortal")
			local name = string.lower(object.Name):gsub("[%s_%-]", "")
			if marked ~= false and (marked == true or (object:IsA("Model")
				and (name:match("^doorframe%d*$") or name:match("^doorway%d*$")))) then
				if object:IsA("Model") or object:IsA("BasePart") or object:IsA("Attachment") then
					table.insert(portalObjects, object)
				end
			end
		end
	end
	local portals = {}
	for _, object in ipairs(portalObjects) do
		if object.Parent and object:GetAttribute("SoundPortal") ~= false then
			local cf, size
			if object:IsA("Model") then
				cf, size = object:GetBoundingBox()
			elseif object:IsA("BasePart") then
				cf, size = object.CFrame, object.Size
			else
				cf, size = object.WorldCFrame, Vector3.new(0, 0, 0)
			end
			local normal = size.X < size.Z and cf.RightVector or cf.LookVector
			table.insert(portals, {
				center = cf.Position,
				normal = normal,
				depth = math.min(size.X, size.Z) * 0.5 + 0.2})
		end
	end
	return portals
end

-- Room labels and House ancestry cannot distinguish an open partition from a
-- sealed wall. Only explicit author intent disables edges; otherwise validate
-- a continuous route against ALL surrounding geometry, including closed doors.
local function canBendAround(part)
	local ancestor = part
	while ancestor and ancestor ~= workspace do
		if ancestor:GetAttribute("SoundRoomBoundary") == true then
			return false, "SoundRoomBoundary; doorway required"
		end
		ancestor = ancestor.Parent
	end
	return true, "testing exposed edges against surrounding geometry"
end
local function solve(job)
	-- Roblox requires raycast-parameter writes in the serial phase, even when
	-- each worker owns its own parameters. Query batches run serially; path
	-- acoustic mixing resumes in parallel after all bounded queries finish.
	task.synchronize()
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.IgnoreWater = true
	-- Let the engine skip non-collidable decorations without spending hit budget.
	-- CanQuery is also checked below because RespectCanCollide prioritizes collision.
	params.RespectCanCollide = true
	local remaining = MAX_RAYS
	local blockers, seen = {}, {}
	local routeLabel = "direct"
	local function trace(origin, destination, stopAtWall, rayLimit)
		local remainingFloor = math.max(0, remaining - (rayLimit or MAX_RAYS))
		local delta = destination - origin
		local length = delta.Magnitude
		if length < 0.001 then
			return {low = 1, mid = 1, high = 1, walls = 0}
		end
		local unit = delta / length
		local excluded = table.clone(job.filter)
		-- A sound may be parented to a room/house Model. Excluding that Model
		-- would also remove its walls and doors from every visibility test.
		if job.sourceObject and job.sourceObject:IsA("BasePart") then
			table.insert(excluded, job.sourceObject)
		end
		local low, mid, high, walls = 0, 0, 0, 0
		local strongest = {0, 0, 0}
		local totals = {0, 0, 0}
		local boundaries = {0, 0, 0}
		local dominant, dominantLoss
		local first
		local function cappedResult()
			-- Exhausting the probe budget is not another physical wall. Retain
			-- observed transmission; unfinished visibility never proves a route.
			return {low = stopAtWall and 0 or amplitude(walls > 0 and low or 18),
				mid = stopAtWall and 0 or amplitude(walls > 0 and mid or 30),
				high = stopAtWall and 0 or amplitude(walls > 0 and high or 42), walls = walls, first = first, dominant = dominant}
		end
		for _ = 1, MAX_HITS do
			if remaining <= remainingFloor then return cappedResult() end
			remaining = remaining - 1
			params.FilterDescendantsInstances = excluded
			local hit = workspace:Raycast(origin, delta, params)
			if not hit then
				-- A ray starting inside a wall can miss its containing surface.
				-- Confirm apparent openings from the other endpoint as well.
				if remaining <= remainingFloor then return cappedResult() end
				remaining = remaining - 1
				hit = workspace:Raycast(destination, delta * -1, params)
			end
			if not hit then
				return {low = amplitude(low), mid = amplitude(mid), high = amplitude(high), walls = walls, first = first, dominant = dominant}
			end
			local part = hit.Instance
			if not part:IsA("BasePart") then
				return {low = 0.03, mid = 0.008, high = 0.001, walls = walls + 1}
			end
			local override = part:GetAttribute("SoundOcclusion")
			local blocks = part.CanQuery and part.CanCollide and override ~= false
			if blocks then
				walls = walls + 1
				first = first or hit
				if not seen[part] then
					seen[part] = true
					table.insert(blockers, {Paths.Encode(part), part.CFrame, part.Size, part.Material.Name, part.CanCollide, part.Transparency,
						override, part:GetAttribute("SoundOcclusionThickness"), part:GetAttribute("SoundOcclusionMaterial"), routeLabel, part.CanQuery})
				end
				if stopAtWall then return {low = 0, mid = 0, high = 0, walls = walls, first = first} end
				local material = part:GetAttribute("SoundOcclusionMaterial") or part.Material.Name
				local profile = MATERIALS[material] or DEFAULT_MATERIAL
				local thickness = wallThickness(part, origin, unit, length)
				local bendable = canBendAround(part)
				for band = 1, 3 do
					local loss = (profile[band * 2 - 1] + profile[band * 2] * thickness) * TRANSMISSION_SCALE
					if bendable then
						totals[band] = totals[band] + loss
						strongest[band] = math.max(strongest[band], loss)
					else
						boundaries[band] = boundaries[band] + loss
					end
					if band == 1 and (not dominantLoss or loss > dominantLoss) then
						dominant, dominantLoss = hit, loss
					end
				end
				local function bandLoss(band, cap)
					local primary = math.max(boundaries[band], strongest[band])
					return math.min(cap, primary + SECONDARY_BLOCKER_WEIGHT * (totals[band] + boundaries[band] - primary))
				end
				low, mid, high = bandLoss(1, 18), bandLoss(2, 30), bandLoss(3, 42)
			end
			table.insert(excluded, part)
		end
		-- An incomplete visibility test cannot establish an opening. Keep a
		-- quiet transmission path instead of abruptly muting dense geometry.
		return cappedResult()
	end

	local direct = trace(job.listener, job.source, false, MAX_DIRECT_RAYS)
	local bestLow, bestMid, bestHigh = 0, 0, 0
	local doorwayPosition, pathLength
	local directRays = MAX_RAYS - remaining
	local directDistance = (job.source - job.listener).Magnitude
	local bestExcess, routeTests, portalCount = 0, 0, 0
	local routeReason = "clear direct path"
	if direct.walls > 0 then
		direct.mid = math.min(direct.mid, direct.low * amplitude(BLOCKED_DIRECT_MID_LOSS_DB))
		direct.high = math.min(direct.high, direct.low * amplitude(BLOCKED_DIRECT_HIGH_LOSS_DB))
		routeReason = "transmission; no verified connected route"
	end
	if direct.first and job.probes > 0 and directDistance > 0.001 then
		local nodes, edges, candidates = {}, {}, {}
		local function addNode(position)
			for index, node in ipairs(nodes) do
				if (node - position).Magnitude < SEARCH.NodeMergeStuds then return index end
			end
			if #nodes >= SEARCH.MaxNodes then return nil end
			table.insert(nodes, position); edges[#nodes] = {}
			return #nodes
		end
		addNode(job.listener); addNode(job.source)
		local function enqueue(path, depth, priority, bypassed)
			if #candidates >= SEARCH.MaxCandidates then return end
			local length = 0
			for index = 2, #path do length = length + (nodes[path[index]] - nodes[path[index - 1]]).Magnitude end
			table.insert(candidates, {path = path, depth = depth, length = length, priority = priority or 0,
				bypassed = bypassed or {}})
		end
		local function expandSegment(candidate, index, hit)
			if not hit or candidate.depth >= SEARCH.MaxDetours or not canBendAround(hit.Instance) then return end
			local part, path = hit.Instance, candidate.path
			-- An unsuccessful detour around the same surface is rejected, rather
			-- than repeatedly inserting tiny steps that consume the search budget.
			if candidate.bypassed[part] then return end
			local origin, destination = nodes[path[index - 1]], nodes[path[index]]
			local cf, half = part.CFrame, part.Size * 0.5
			local normal = half.X < half.Z and cf.RightVector or cf.LookVector
			local tangent = half.X < half.Z and cf.LookVector or cf.RightVector
			local center = cf:PointToWorldSpace(Vector3.new(0, cf:PointToObjectSpace(hit.Position).Y, 0))
			local originSide = (origin - center):Dot(normal) >= 0 and 1 or -1
			local destinationSide = (destination - center):Dot(normal) >= 0 and 1 or -1
			local surfaceNormal = hit.Normal or normal * originSide
			local lateral = surfaceNormal:Cross(Vector3.yAxis)
			if lateral.Magnitude < 0.001 then lateral = tangent end
			local surface = hit.Position + surfaceNormal * ROUTE.SurfaceClearanceStuds
			local function insertWaypoints(points)
				local added = {}
				for _, point in ipairs(points) do
					local node = addNode(point)
					if not node then return end
					for _, existing in ipairs(path) do if existing == node then return end end
					table.insert(added, node)
				end
				local newPath = {}
				for offset, node in ipairs(path) do
					if offset == index then for _, extra in ipairs(added) do table.insert(newPath, extra) end end
					table.insert(newPath, node)
				end
				local bypassed = table.clone(candidate.bypassed)
				bypassed[part] = true
				enqueue(newPath, candidate.depth + 1, candidate.priority, bypassed)
			end
			for _, radius in ipairs({ROUTE.LocalProbeOffsetStuds, SEARCH.WideProbeStuds}) do
				for _, axis in ipairs({lateral.Unit, Vector3.yAxis}) do
					insertWaypoints({surface + axis * radius})
					insertWaypoints({surface - axis * radius})
				end
			end
			local depth = math.min(half.X, half.Z) + ROUTE.SurfaceClearanceStuds
			local width = math.max(half.X, half.Z) + ROUTE.EdgeClearanceStuds
			for _, edge in ipairs({center + tangent * width, center - tangent * width,
				cf:PointToWorldSpace(Vector3.new(0, half.Y + ROUTE.EdgeClearanceStuds, 0)),
				cf:PointToWorldSpace(Vector3.new(0, -half.Y - ROUTE.EdgeClearanceStuds, 0))}) do
				insertWaypoints({edge + normal * depth * originSide, edge + normal * depth * destinationSide})
			end
		end
		-- Cache waypoint hints, never stale visibility. Moving doors are tested anew.
		local cacheKey = job.sourceObject or job.source
		local hint = routeHints[cacheKey]
		if hint and os.clock() - hint.time <= SEARCH.HintLifetimeSeconds then
			local path = {1}
			for _, point in ipairs(hint.points) do
				local node = addNode(point)
				if node then table.insert(path, node) end
			end
			table.insert(path, 2); enqueue(path, 0)
		end
		local portals = getPortals()
		portalCount = #portals
		table.sort(portals, function(a, b)
			return (a.center - job.listener).Magnitude + (a.center - job.source).Magnitude
				< (b.center - job.listener).Magnitude + (b.center - job.source).Magnitude
		end)
		local openings = {}
		for index = 1, math.min(#portals, SEARCH.MaxPortals) do
			local portal = portals[index]
			local a = addNode(portal.center + portal.normal * portal.depth)
			local b = addNode(portal.center - portal.normal * portal.depth)
			if a and b then table.insert(openings, {a, b}) end
		end
		-- Both directions of each opening are graph edges. Chains can join rooms
		-- even when listener and source lie on the same side of one door's plane.
		local function connectOpenings(path, used, count)
			if count > 0 then
				local complete = table.clone(path); table.insert(complete, 2); enqueue(complete, 0)
			end
			if count >= SEARCH.MaxOpeningHops then return end
			for index, opening in ipairs(openings) do
				if not used[index] then
					used[index] = true
					local previous = nodes[path[#path]]
					local a, b = opening[1], opening[2]
					if (nodes[b] - previous).Magnitude < (nodes[a] - previous).Magnitude then a, b = b, a end
					local nextPath = table.clone(path)
					table.insert(nextPath, a); table.insert(nextPath, b)
					connectOpenings(nextPath, used, count + 1)
					used[index] = nil
				end
			end
		end
		connectOpenings({1}, {}, 0)
		edges[1][2], edges[2][1] = {clear = false, hit = direct.first}, {clear = false, hit = direct.first}
		enqueue({1, 2}, 0, 1)
		-- Bounded best-first refinement of complete paths. Only a failed segment
		-- branches; verified segments are reused across candidates within this job.
		local function candidateScore(candidate)
			local verified = 0
			for index = 2, #candidate.path do
				local a, b = candidate.path[index - 1], candidate.path[index]
				if edges[a][b] and edges[a][b].clear then
					verified = verified + (nodes[a] - nodes[b]).Magnitude
				end
			end
			-- Finish promising routes before exploring equivalent alternatives;
			-- cap the preference so a much longer cached route cannot dominate.
			return candidate.length - math.min(verified * SEARCH.VerifiedSegmentPreference, SEARCH.MaxPreferenceStuds)
		end
		for _ = 1, SEARCH.MaxIterations do
			if #candidates == 0 then break end
			local best = 1
			for index = 2, #candidates do
				local a, b = candidates[index], candidates[best]
				if a.priority < b.priority or (a.priority == b.priority and candidateScore(a) < candidateScore(b)) then best = index end
			end
			local candidate = table.remove(candidates, best)
			local path, clear = candidate.path, true
			routeTests = routeTests + 1
			for index = 2, #path do
				local a, b = path[index - 1], path[index]
				local edge = edges[a][b]
				if not edge then
					if remaining < 2 then clear = false; break end
					routeLabel = "connected route"
					local leg = trace(nodes[a], nodes[b], true)
					edge = {clear = leg.walls == 0 and leg.low > 0, hit = leg.first}
					edges[a][b] = edge
					-- Only clear checks are symmetric; a blocker hit is direction-specific.
					if edge.clear then edges[b][a] = edge end
				end
				if not edge.clear then expandSegment(candidate, index, edge.hit); clear = false; break end
			end
			if clear then
				local length = candidate.length
				local excess = math.max(0, length - directDistance)
				local spread = directDistance / math.max(length, directDistance)
				bestLow = spread * amplitude(ROUTE.LowBaseLossDb + ROUTE.LowLossPerExtraStud * excess)
				bestMid = spread * amplitude(ROUTE.MidBaseLossDb + ROUTE.MidLossPerExtraStud * excess)
				bestHigh = spread * amplitude(ROUTE.HighBaseLossDb + ROUTE.HighLossPerExtraStud * excess)
				doorwayPosition, pathLength, bestExcess = nodes[path[2]], length, excess
				routeReason = "verified connected route"
				local points = {}
				for index = 2, #path - 1 do table.insert(points, nodes[path[index]]) end
				if not routeHints[cacheKey] and routeHintCount >= SEARCH.MaxHints then
					table.clear(routeHints); routeHintCount = 0
				end
				if not routeHints[cacheKey] then routeHintCount = routeHintCount + 1 end
				routeHints[cacheKey] = {time = os.clock(), points = points}
				break
			end
			if remaining < 2 then break end
		end
	end
	-- One bounded serial query phase per job; avoid yielding between route legs.
	task.desynchronize()
	-- These approximate routes share source energy; summing them can make a
	-- blocked source as loud as an unobstructed one. Use the strongest route.
	local directWeight = direct.walls > 0 and bestLow > 0 and DIRECT_WEIGHT_WITH_INDIRECT_ROUTE or 1
	local weightedDirectLow = direct.low * directWeight
	local function distanceBands(mid, high, distance)
		return mid * amplitude(math.min(distance * DISTANCE_FILTER.MidLossDbPerStud, DISTANCE_FILTER.MaxMidLossDb)),
			high * amplitude(math.min(distance * DISTANCE_FILTER.HighLossDbPerStud, DISTANCE_FILTER.MaxHighLossDb))
	end
	-- Filter each path over its own travel distance before choosing band energy.
	local directMid, directHigh = distanceBands(direct.mid, direct.high, directDistance)
	bestMid, bestHigh = distanceBands(bestMid, bestHigh, pathLength or directDistance)
	local low = math.clamp(math.max(weightedDirectLow, bestLow), 0.001, 1)
	local mid = math.clamp(math.max(directMid * directWeight, bestMid), 0.001, low)
	local high = math.clamp(math.max(directHigh * directWeight, bestHigh), 0.001, mid)
	return {gain = low, mid = math.clamp(20 * math.log10(mid / low), -60, 0),
		high = math.clamp(20 * math.log10(high / low), -60, 0), walls = direct.walls,
		diffracted = bestLow > 0,
		doorwayPosition = bestLow > weightedDirectLow and doorwayPosition or nil,
		pathLength = pathLength, portalCount = portalCount, routeReason = routeReason,
		directRays = directRays, routeTests = routeTests, pathExcess = bestExcess,
		rays = MAX_RAYS - remaining, blockers = blockers}
end

-- ParallelScheduler appends TaskIndex after these transport-safe arguments.
local previousFilterJSON, previousFilter
return function(listener, source, sourcePath, filterJSON, probes)
	local refresh = filterJSON ~= previousFilterJSON or not previousFilter
	if not refresh then
		for _, object in ipairs(previousFilter) do if not object.Parent then refresh = true; break end end
	end
	if refresh then
		previousFilterJSON, previousFilter = filterJSON, Paths.DecodeList(filterJSON)
	end
	local ok, result = pcall(solve, {
		listener = listener, source = source, sourceObject = Paths.Decode(sourcePath),
		filter = previousFilter, probes = probes,
	})
	-- Match the scheduler worker contract used by Calculate Raycast Bounce:
	-- each task returns an array containing its result.
	if not ok then return {{error = tostring(result)}} end
	return {result}
end
