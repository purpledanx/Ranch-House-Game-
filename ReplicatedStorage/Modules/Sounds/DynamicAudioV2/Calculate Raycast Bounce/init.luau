local CastVisuals = require(script:WaitForChild("CastVisuals"))
local HttpService = game:GetService("HttpService")
local player = game.Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local constants
local lastConstantsStr

local Filter = {}
for i,v in ipairs(game.Workspace.House.Hitbox:GetChildren()) do
	if v:IsA("BasePart") then
		table.insert(Filter,v)
	end
end

for i,v in ipairs(game.Workspace.House.RoomRegions:GetChildren()) do
	if v:IsA("BasePart") then
		table.insert(Filter,v)
	end
end

for i,v in ipairs(game.Workspace:GetChildren()) do
	if v.Name == "PathThrough" then
		table.insert(Filter,v)
	end
end

if character then
	table.insert(Filter, character)
end

local RaycastParam = RaycastParams.new()
RaycastParam.FilterType = Enum.RaycastFilterType.Exclude
RaycastParam:AddToFilter(Filter)
RaycastParam.RespectCanCollide = false
RaycastParam.BruteForceAllSlow = false

local function computeUniqueIdentifier(object)
	local fullPath = object.Name
	local current = object.Parent
	while current and current ~= game do
		fullPath = current.Name .. "`" .. fullPath
		current = current.Parent
	end
	-- Create a hash based on the full path
	return HttpService:GenerateGUID(false) .. "-" .. tostring(#fullPath)
end

local function getFullName(object)
	local result = object.Name .. "#" .. computeUniqueIdentifier(object)
	object = object.Parent
	while object and object ~= game do
		result = object.Name .. "#" .. computeUniqueIdentifier(object) .. "`" .. result
		object = object.Parent
	end
	return result
end

local function StringToInstance(Table: {string}): {Instance}
	local newTable = setmetatable({}, {__mode = "vk"})
	for i, v in pairs(Table) do
		local segments = v:split("`")
		local current = game.Workspace

		for _, segment in ipairs(segments) do
			local name, id = segment:match("^(.*)#(.*)$")
			if current then
				local found = nil
				for _, child in ipairs(current:GetChildren()) do
					-- Match name and regenerate the unique identifier
					if child.Name == name and computeUniqueIdentifier(child) == id then
						found = child
						break
					end
				end
				current = found
			end
		end

		newTable[i] = current
	end
	return newTable
end

local function InstanceToString(Table: {Instance}): {string}
	local newTable = table.clone(Table)
	for i, v in ipairs(newTable) do
		newTable[i] = getFullName(v)
	end
	return newTable
end

local function RandomDirection(_RandomSeed:Random)
	-- Generate two random numbers for spherical coordinates
	local u = _RandomSeed:NextNumber() -- Random number in [0, 1]
	local v = _RandomSeed:NextNumber() -- Random number in [0, 1]

	-- Convert to spherical coordinates
	local theta = 2 * math.pi * u -- Angle around the Z-axis
	local phi = math.acos(2 * v - 1) -- Angle from the Z-axis

	-- Convert spherical coordinates to Cartesian coordinates
	local x = math.sin(phi) * math.cos(theta)
	local y = math.sin(phi) * math.sin(theta)
	local z = math.cos(phi)
	local Vector = Vector3.new(x, y, z)
	-- Return the random unit vector
	u = nil
	v = nil
	theta = nil
	phi = nil
	x = nil
	y = nil
	z = nil
	return Vector
end

local function Reflect(Direction: Vector3, RayNormal: Vector3)
	return Direction - 2 * Direction:Dot(RayNormal) * RayNormal
end

local Raycast
local function ShootRay(Origin: Vector3, Direction: Vector3, MaxDistance)
	--debug.profilebegin("Raycast Bounce")
	Raycast =  workspace:Raycast(Origin, Direction * MaxDistance, RaycastParam)
	if Raycast then
		--print(Raycast.Distance)
		if not Raycast.Instance:IsA("BasePart") then
			return
		end

		if Raycast.Instance.Transparency == 1 then
			RaycastParam:AddToFilter(Raycast.Instance)
			Raycast = ShootRay(Origin, Direction, MaxDistance)
		end
	end
	--debug.profileend()
	return Raycast
end

local function GetMaterialStat(MaterialName: string, MaterialDensity, MaterialReflectiveness)
	if not MaterialDensity[MaterialName] or not MaterialReflectiveness[MaterialName] then
		if script:GetAttribute("MaterialWarn") then
			warn("Material '"..MaterialName.."' does not have a Density or Reflectiveness set; defaulting to 'Plastic'")
		end

		MaterialName = "Plastic"
	end

	return MaterialDensity[MaterialName], MaterialReflectiveness[MaterialName]
end

local function CreateRayVisual(Origin: Vector3, Direction: Vector3, Magnitude: number, Color: Color3, Transparency: number)
	Color = Color or Color3.new(0,1,0)
	Transparency = Transparency or 0
	local CastVisual = CastVisuals.new(Color, game.Workspace:FindFirstChild("SoundReverbV2DebugRays"))
	CastVisual:Draw(Origin, Direction, Magnitude, Transparency)
end

local function getConstants()
	local currentStr = script:GetAttribute("ConstantsTable")

	if currentStr ~= lastConstantsStr then
		lastConstantsStr = currentStr
		local parts = string.split(currentStr, "|")
		constants = {
			MaxReflections = tonumber(parts[1]),
			MaxDistance = tonumber(parts[2]),
			MaterialDensity = HttpService:JSONDecode(parts[3]), -- Decode back to table
			MaterialReflectiveness = HttpService:JSONDecode(parts[4]),
			DebugMode = script:GetAttribute("DebugMode")
		}
	end

	return constants
end

return function(EmitPosition, TaskIndex)
	local ConstantsTable = getConstants()
	ConstantsTable.EmitPosition = EmitPosition
	local RaySample: SoundRayResult = {
		Bounces = 0;
		AbsorptionAmount = 0;
		DensityAmount = 0;
		TotalDistance = 0;
	}

	local LastRaycast
	local Direction: Vector3
	local RandomS = Random.new(math.random(-1000,1000))

	for Reflections = 0, ConstantsTable.MaxReflections, 1 do
		local Normal
		local Origin = ConstantsTable.EmitPosition
		if LastRaycast then
			Origin = LastRaycast.Position
			Normal = LastRaycast.Normal
		end

		if Normal then
			Direction = Reflect(Direction, Normal)
		else
			Direction = RandomDirection(RandomS)
		end

		local Raycast = ShootRay(Origin, Direction, ConstantsTable.MaxDistance)
		if not Raycast then
			if ConstantsTable.DebugMode then
				task.synchronize()
				CreateRayVisual(Origin, Direction, ConstantsTable.MaxDistance, Color3.new(1,0,0), 0.5)
				task.desynchronize()
			end

			return {RaySample}
		end

		local MaterialDensity, MaterialReflectiveness = GetMaterialStat(Raycast.Material.Name, ConstantsTable.MaterialDensity, ConstantsTable.MaterialReflectiveness)

		local AbsorptionChance = (1-MaterialReflectiveness) - .0001 -- (-.0001 since forcefield has a reflectivity of 1, and Random:NextNumber() includes 0.)

		RaySample.TotalDistance += Raycast.Distance

		if AbsorptionChance > RandomS:NextNumber() then
			if ConstantsTable.DebugMode then
				task.synchronize()
				CreateRayVisual(Origin, Direction, Raycast.Distance, Color3.new(.5,0,1), 0)
				task.desynchronize()
			end

			RaySample.AbsorptionAmount += 1-MaterialReflectiveness
			RaySample.DensityAmount += MaterialDensity

			MaterialReflectiveness = nil
			MaterialDensity = nil
			Raycast = nil
			Normal = nil
			AbsorptionChance = nil
			Origin = nil
			return {RaySample}
		end

		RaySample.Bounces += 1
		RaySample.AbsorptionAmount += ((1-MaterialReflectiveness/2))/ConstantsTable.MaxReflections
		RaySample.DensityAmount += (MaterialDensity/2)/ConstantsTable.MaxReflections


		if ConstantsTable.DebugMode then
			task.synchronize()
			CreateRayVisual(Origin, Direction, Raycast.Distance, Color3.new(0,1,0), 0)
			task.desynchronize()
		end

		LastRaycast = Raycast
	end

	Direction = nil
	LastRaycast = nil
	RandomS = nil
	return {RaySample}
end
