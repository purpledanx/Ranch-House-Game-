-- Pure spatial reads and acoustic math; ParallelScheduler owns worker execution.
local Paths = require(script.InstancePaths)
local MAX_RAYS = 24
local MAX_HITS = 8

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
-- Reduce wall transmission's influence when a verified indirect route exists.
local DIRECT_WEIGHT_WITH_INDIRECT_ROUTE = 0

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
	local function trace(origin, destination, stopAtWall)
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
		local first
		for _ = 1, MAX_HITS do
			if remaining == 0 then return {low = 0, mid = 0, high = 0, walls = walls, first = first} end
			remaining = remaining - 1
			params.FilterDescendantsInstances = excluded
			local hit = workspace:Raycast(origin, delta, params)
			if not hit then
				-- A ray starting inside a wall can miss its containing surface.
				-- Confirm apparent openings from the other endpoint as well.
				if remaining == 0 then
					return {low = 0, mid = 0, high = 0, walls = walls, first = first}
				end
				remaining = remaining - 1
				hit = workspace:Raycast(destination, delta * -1, params)
			end
			if not hit then
				return {low = amplitude(low), mid = amplitude(mid), high = amplitude(high), walls = walls, first = first}
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
				low = math.min(18, low + (profile[1] + profile[2] * thickness) * TRANSMISSION_SCALE)
				mid = math.min(30, mid + (profile[3] + profile[4] * thickness) * TRANSMISSION_SCALE)
				high = math.min(42, high + (profile[5] + profile[6] * thickness) * TRANSMISSION_SCALE)
			end
			table.insert(excluded, part)
		end
		-- An incomplete visibility test cannot establish an opening. Keep a
		-- quiet transmission path instead of abruptly muting dense geometry.
		return {low = stopAtWall and 0 or amplitude(18), mid = stopAtWall and 0 or amplitude(30),
			high = stopAtWall and 0 or amplitude(42), walls = walls, first = first}
	end

	local direct = trace(job.listener, job.source, false)
	local allowEdges, routeReason = false, "clear direct path"
	if direct.first then allowEdges, routeReason = canBendAround(direct.first.Instance) end
	if direct.walls > 0 then
		-- Grazing a thin wall must not restore intelligible high frequencies.
		-- Keep bass transmission gentle, but reserve clear mids/highs for an
		-- actual opening. This also separates open- and closed-door timbres.
		direct.mid = math.min(direct.mid, direct.low * amplitude(12))
		direct.high = math.min(direct.high, direct.low * amplitude(28))
	end
	local bestLow, bestMid, bestHigh = 0, 0, 0
	local doorwayPosition, pathLength
	local portalCount = 0
	if direct.first and remaining >= 6 and job.probes > 0 then
		local portals = getPortals()
		portalCount = #portals
		-- Evaluate only the cheapest candidate routes; the overall ray cap still
		-- applies. Door leaves and adjacent walls remain in all visibility tests.
		for _, portal in ipairs(portals) do
			portal.cost = (portal.center - job.listener).Magnitude + (job.source - portal.center).Magnitude
		end
		table.sort(portals, function(a, b) return a.cost < b.cost end)
		local distance = math.max((job.source - job.listener).Magnitude, 0.1)
		local tested = 0
		for _, portal in ipairs(portals) do
			if remaining < 6 or tested >= math.min(job.probes, 2) then break end
			local listenerSide = (job.listener - portal.center):Dot(portal.normal)
			local sourceSide = (job.source - portal.center):Dot(portal.normal)
			if listenerSide * sourceSide < 0 then
				tested = tested + 1
				local side = listenerSide >= 0 and 1 or -1
				local entry = portal.center + portal.normal * portal.depth * side
				local exit = portal.center - portal.normal * portal.depth * side
				routeLabel = "doorway"
				local a = trace(job.listener, entry, true)
				local clear = false
				if a.walls == 0 and a.low > 0 then
					local b = trace(entry, exit, true)
					if b.walls == 0 and b.low > 0 then
						local c = trace(exit, job.source, true)
						clear = c.walls == 0 and c.low > 0
					end
				end
				if clear then
					local detour = (entry - job.listener).Magnitude + (exit - entry).Magnitude + (job.source - exit).Magnitude
					local incoming = (entry - job.listener).Unit
					local outgoing = (job.source - exit).Unit
					local through = (exit - entry).Unit
					local bend = (1 - math.clamp(incoming:Dot(through), -1, 1))
						+ (1 - math.clamp(through:Dot(outgoing), -1, 1))
					local spread = math.sqrt(distance / math.max(detour, distance)) * math.exp(-math.max(0, detour - distance) / 60)
					local candidate = spread * amplitude(3 + 3 * bend)
					if candidate > bestLow then
						routeReason = "verified doorway route"
						doorwayPosition, pathLength = entry, detour
						bestLow = candidate
						bestMid = spread * amplitude(6 + 5 * bend)
						bestHigh = spread * amplitude(11 + 8 * bend)
					end
				end
			end
		end
	end
	-- Test continuous paths around exposed edges. Room names alone cannot
	-- reject an open-plan partition; adjoining geometry must block the route.
	if direct.first and remaining >= 6 and job.probes > 0 and allowEdges then
		local part = direct.first.Instance
		local cf, half = part.CFrame, part.Size * 0.5
		local normal = half.X < half.Z and cf.RightVector or cf.LookVector
		local tangent = half.X < half.Z and cf.LookVector or cf.RightVector
		local depth = math.min(half.X, half.Z) + 0.25
		local width = math.max(half.X, half.Z) + 0.35
		local hitHeight = cf:PointToObjectSpace(direct.first.Position).Y
		local center = cf:PointToWorldSpace(Vector3.new(0, hitHeight, 0))
		local listenerSide = (job.listener - center):Dot(normal)
		local sourceSide = (job.source - center):Dot(normal)
		local distance = (job.source - job.listener).Magnitude
		-- A large open-plan partition can still have a nearby exposed edge.
		if distance > 0.1 then
			local side = listenerSide > 0 and 1 or -1
			local sourceSign = sourceSide > 0 and 1 or -1
			local candidates = {}
			local function addCandidate(edge)
				local entry, exit = edge + normal * depth * side, edge + normal * depth * sourceSign
				table.insert(candidates, {entry = entry, exit = exit,
					length = (entry - job.listener).Magnitude + (exit - entry).Magnitude + (job.source - exit).Magnitude})
			end
			addCandidate(center + tangent * width)
			addCandidate(center - tangent * width)
			addCandidate(cf:PointToWorldSpace(Vector3.new(0, half.Y + 0.35, 0)))
			table.sort(candidates, function(a, b) return a.length < b.length end)
			for probe = 1, math.min(job.probes + 1, #candidates) do
				if remaining < 6 then break end
				local entry, exit = candidates[probe].entry, candidates[probe].exit
				routeLabel = "obstacle bypass"
				local a = trace(job.listener, entry, true)
				if a.walls == 0 and a.low > 0 then
					local b = trace(entry, exit, true)
					if b.walls == 0 and b.low > 0 then
						local c = trace(exit, job.source, true)
						if c.walls == 0 and c.low > 0 then
							local detour = (entry - job.listener).Magnitude + (exit - entry).Magnitude + (job.source - exit).Magnitude
							local excess = math.max(0, detour - distance)
							-- Excess path length, not the mere presence of a center-ray hit,
							-- controls this approximation. Higher frequencies lose more energy.
							local spread = distance / math.max(detour, distance)
							local candidate = spread * amplitude(1.5 + 1.5 * excess)
							if candidate > bestLow then
								routeReason = "verified obstacle diffraction"
								doorwayPosition, pathLength = entry, detour
								bestLow = candidate
								bestMid = spread * amplitude(2 + 3 * excess)
								bestHigh = spread * amplitude(3 + 6 * excess)
							end
						end
					end
				end
			end
		end
	end
	-- One bounded serial query phase per job; avoid yielding between route legs.
	task.desynchronize()
	-- These approximate routes share source energy; summing them can make a
	-- blocked source as loud as an unobstructed one. Use the strongest route.
	local directWeight = direct.walls > 0 and bestLow > 0 and DIRECT_WEIGHT_WITH_INDIRECT_ROUTE or 1
	local weightedDirectLow = direct.low * directWeight
	local low = math.clamp(math.max(weightedDirectLow, bestLow), 0.001, 1)
	local mid = math.clamp(math.max(direct.mid * directWeight, bestMid), 0.001, low)
	local high = math.clamp(math.max(direct.high * directWeight, bestHigh), 0.001, mid)
	return {gain = low, mid = math.clamp(20 * math.log10(mid / low), -60, 0),
		high = math.clamp(20 * math.log10(high / low), -60, 0), walls = direct.walls,
		diffracted = bestLow > 0,
		doorwayPosition = bestLow > weightedDirectLow and doorwayPosition or nil,
		pathLength = pathLength, portalCount = portalCount, routeReason = routeReason,
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
