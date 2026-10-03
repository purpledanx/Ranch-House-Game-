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

local RaycastParam = RaycastParams.new()
RaycastParam.FilterType = Enum.RaycastFilterType.Exclude
RaycastParam:AddToFilter(Filter)

local ReferenceCameraViewPort = 0
local ReferenceCameraPosition = 0
local player = game.Players.LocalPlayer

if player.Character then
	RaycastParam:AddToFilter(player.Character)
	ReferenceCameraPosition = game.Workspace.CurrentCamera.CFrame.Position
	ReferenceCameraViewPort = game.Workspace.CurrentCamera.ViewportSize
end

local function FindParentModel(Part:BasePart)
	local Parent = Part.Parent
	if Parent:IsA("Model") then
		return Parent
	elseif Parent:IsA("BasePart") then
		return FindParentModel(Parent)
	else
		return nil
	end
end

local function StringToInstance(Table: {string}): {Instance}
	local newTable = {}
	setmetatable(newTable, {__mode = "vk"})
	for i,v in Table do
		local segments = v:split(".")
		local current = game.Workspace

		for _,location in pairs(segments) do
			current = current[location]
		end

		newTable[i] = current
	end
	return newTable
end

local function InstanceToString(Table: {Instance}): {string}
	local newTable = table.clone(Table)
	--print(newTable)
	for i,v in ipairs(newTable) do
		newTable[i] = v:GetFullName()
	end
	return newTable
end

local function RayCastClone(Table:RaycastResult)
	local newTable = {}
	setmetatable(newTable, {__mode = "vk"})
	newTable.Position = Table.Position or nil
	newTable.Instance = Table.Instance or nil
	newTable.Material = Table.Material or nil
	newTable.Distance = Table.Distance or nil
	newTable.Normal = Table.Normal or nil
	return newTable
end

local function RayCast(EmitPosition, TaskIndex)
	local MiddleOfViewport = ReferenceCameraViewPort/2
	local Direction =  (EmitPosition - ReferenceCameraPosition).Unit * ((EmitPosition - ReferenceCameraPosition).Magnitude + .01)
	
	local SightRaycast = workspace:Raycast(ReferenceCameraPosition, Direction, RaycastParam)
	
	if SightRaycast then
		if not SightRaycast.Instance:IsA("BasePart") then
			MiddleOfViewport = nil
			Direction = nil
			SightRaycast = nil
			return false
		end

		local TruthValue
		if SightRaycast.Instance.Transparency == 1 then
			RaycastParam:AddToFilter(SightRaycast.Instance)
			TruthValue = RayCast(ReferenceCameraPosition, EmitPosition)
		end
		MiddleOfViewport = nil
		Direction = nil
		SightRaycast = nil
		return TruthValue
	end
	if SightRaycast then
		MiddleOfViewport = nil
		Direction = nil
		SightRaycast = nil
		return false
	end
	MiddleOfViewport = nil
	Direction = nil
	SightRaycast = nil
	return true
end

return function(EmitPosition, TaskIndex)
	return RayCast(EmitPosition, TaskIndex)
end