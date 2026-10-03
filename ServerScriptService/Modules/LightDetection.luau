local module = {}

local Lighting = game.Lighting
local Run_Service = game:GetService("RunService")

for i,v in ipairs(game.Workspace.House.RoomRegions:GetChildren()) do
	if v:IsA("BasePart") then
		v:AddTag("Blacklist")
	end
end
game.Workspace.House.Walk:AddTag("Blacklist")
game.Workspace.House.Walls.MainWall:AddTag("Blacklist")
for i,v in ipairs(game.Workspace.House.Hitbox:GetChildren()) do
	if v:IsA("BasePart") then
		v:AddTag("Blacklist")
	end
end

local function SpotLight(x : Vector3,dir : Vector3,p : Vector3,ang : number,range : number) -- Cone
	local Unit = (p - x).Unit
	local Mag = (p - x).Magnitude

	local Dot = dir:Dot(Unit)

	return math.deg(math.acos(Dot)) < ang/2 and range > Mag
end

local function Side4D(p1:Vector3,p2:Vector3,p3:Vector3,p4:Vector3,p:Vector3,first)
	first = first or nil
	local lightcenter = (p1+p2+p3+p4)/4

	local up = (p2 - p1)
	local right = (p2 - p4)

	local forwards = up:Cross(right)

	local dir2 = (lightcenter - p)
	local dot = forwards:Dot(dir2)
	
	if first then
		--A1.WorldPosition = lightcenter
	end
	
	return dot >= 0
end 

local function SurfaceLight(p1,p2,p3,p4,p5,p6,p7,p8,p)
	local x,x1,x2,x3,x4,x5 = Side4D(p1,p2,p3,p4,p) ,Side4D(p1,p5,p6,p2,p) ,Side4D(p2,p6,p7,p3,p,true) ,Side4D(p3,p7,p8,p4,p) ,Side4D(p4,p8,p5,p1,p) ,Side4D(p5,p8,p7,p6,p) 

	return x and x1 and x2 and x3 and x4 and x5
end

local function PointLight(x,p,r)
	return (x - p).Magnitude < r
end

local function CheckObfuscated(t)
	local temp = table.clone(t)
	for i,part: BasePart in temp do
		if part:IsA("BasePart") then
			if part:HasTag("Blacklist") then
				temp[i] = nil
			end
			if part.CastShadow == false and table.find(temp,part) then
				temp[i] = nil
			end
			if part.Transparency >= 0.5 and table.find(temp,part) then
				temp[i] = nil
			end
		end
	end

	return temp
end

local function GetVectorFromNormal(BasePart : BasePart | Attachment,Normal)
	local Dirs = {}

	if BasePart:IsA("BasePart") then
		Dirs = {
			[Enum.NormalId.Top] = BasePart.CFrame.UpVector,
			[Enum.NormalId.Bottom] = -BasePart.CFrame.UpVector,
			[Enum.NormalId.Right] = BasePart.CFrame.RightVector,
			[Enum.NormalId.Left] = -BasePart.CFrame.RightVector,
			[Enum.NormalId.Front] = BasePart.CFrame.LookVector,
			[Enum.NormalId.Back] = -BasePart.CFrame.LookVector,
		}
	else
		Dirs = {
			[Enum.NormalId.Top] = BasePart.WorldCFrame.UpVector,
			[Enum.NormalId.Bottom] = -BasePart.WorldCFrame.UpVector,
			[Enum.NormalId.Right] = BasePart.WorldCFrame.RightVector,
			[Enum.NormalId.Left] = -BasePart.WorldCFrame.RightVector,
			[Enum.NormalId.Front] = BasePart.WorldCFrame.LookVector ,
			[Enum.NormalId.Back] = -BasePart.WorldCFrame.LookVector,
		}
	end

	return Dirs[Normal]
end

local OVP = OverlapParams.new()
OVP.FilterType = Enum.RaycastFilterType.Exclude

local function CheckInSunlight(Point : Vector3)
	local sunlightDir = Lighting:GetSunDirection()
	local sp = Point + sunlightDir * 500
	local scf = CFrame.lookAt(sp,sp + sunlightDir)
	local ssize = Vector3.new(1,1,1000)

	local Det = workspace:GetPartBoundsInBox(CFrame.new(Point),Vector3.one/10)[1]
	OVP.FilterDescendantsInstances = {Det}

	local Sunlight = if Lighting.GlobalShadows then CheckObfuscated(workspace:GetPartBoundsInBox(scf,ssize,OVP)) else {}

	if Sunlight and 18 > Lighting.ClockTime and Lighting.ClockTime > 8 then
		return true
	end

	return false
end

local function getAxisFromValue(value: number): Enum.Axis
	for _, axis: Enum.Axis in Enum.Axis:GetEnumItems() do
		if axis.Value == value then
			return axis
		end
	end
	error("No axis EnumItem with this value exists.")
end

local function findFaceAndLightCorners(part: BasePart, light: SurfaceLight): {Vector3}
	local corners: {Vector3} = {}

	local normalAxisValue = light.Face.Value % 3
	local normalAxis = getAxisFromValue(normalAxisValue)
	local otherAxis1 = getAxisFromValue((normalAxisValue + 1) % 3)
	local otherAxis2 = getAxisFromValue((normalAxisValue + 2) % 3)
	
	local x = math.sin(math.rad(light.Angle/2)) * light.Range * 2
	local d = light.Range
	
	for dir1Sign = -1, 1, 2 do
		for dir2Sign = -1, 1, 2 do
			-- face corners
			local localSpaceCorner = .5 * (
				part.Size[normalAxis.Name] * Vector3.FromNormalId(light.Face)
					+ dir1Sign * part.Size[otherAxis1.Name] * Vector3.FromAxis(otherAxis1)
					+ dir2Sign * part.Size[otherAxis2.Name] * Vector3.FromAxis(otherAxis2)
			)
			table.insert(corners, localSpaceCorner)

			-- projected corners
			local localSpaceCorner = (
				part.Size[normalAxis.Name]/2 * Vector3.FromNormalId(light.Face)
					+ Vector3.FromNormalId(light.Face) * d
					+ dir1Sign * (part.Size[otherAxis1.Name]/2 + x) * Vector3.FromAxis(otherAxis1)
					+ dir2Sign * (part.Size[otherAxis2.Name]/2 + x) * Vector3.FromAxis(otherAxis2)
			)
			table.insert(corners, localSpaceCorner)
		end
	end
	return corners
end

local function getFaceCorners(part: Part, normalId: Enum.NormalId): {Vector3}
	local cornerPoints: {Vector3} = {}

	local normalAxisValue: number = normalId.Value % 3
	local normalAxis: Enum.Axis = getAxisFromValue(normalAxisValue)
	local otherAxis1: Enum.Axis = getAxisFromValue((normalAxisValue + 1) % 3)
	local otherAxis2: Enum.Axis = getAxisFromValue((normalAxisValue + 2) % 3)	
	for dir1Sign: number = -1, 1, 2 do
		for dir2Sign: number = -1, 1, 2 do
			local localSpaceCorner: Vector3 = .5 * (
				part.Size[normalAxis.Name] * Vector3.FromNormalId(normalId)
					+ dir1Sign * part.Size[otherAxis1.Name] * Vector3.fromAxis(otherAxis1)
					+ dir2Sign * part.Size[otherAxis2.Name] * Vector3.fromAxis(otherAxis2)
			)
			local worldSpaceCorner: Vector3 = part.CFrame * localSpaceCorner
			table.insert(cornerPoints, worldSpaceCorner)
		end
	end
	return cornerPoints
end

local function ChangeToFace(Position,corner,Face)
	if Face == Enum.NormalId.Top or Face == Enum.NormalId.Back or Face == Enum.NormalId.Right then
		Position[1] = corner[5]
		Position[2] = corner[1]
		Position[3] = corner[2]
		Position[4] = corner[6]
		Position[5] = corner[7]
		Position[6] = corner[3]
		Position[7] = corner[4]
		Position[8] = corner[8]
	elseif Face == Enum.NormalId.Bottom or Face == Enum.NormalId.Front or Face == Enum.NormalId.Left then
		Position[1] = corner[1]
		Position[2] = corner[5]
		Position[3] = corner[6]
		Position[4] = corner[2]
		Position[5] = corner[3]
		Position[6] = corner[7]
		Position[7] = corner[8]
		Position[8] = corner[4]
	end
end

local AllLights : {Light} = {}

workspace.DescendantAdded:Connect(function(child : Light)
	if child:IsA("Light") then
		table.insert(AllLights,child)
	end
end)

workspace.DescendantRemoving:Connect(function(child : Light)
	if child:IsA("Light") then
		table.remove(AllLights,table.find(AllLights,child))
	end
end)

for _,v : Light in workspace:GetDescendants() do
	if v:IsA("Light") then
		table.insert(AllLights,v)
	end
end

export type LightObject = {
	LightLevel: number,
	Lights: {Light},
	Sunlight: boolean,
	InLight: boolean
}

function module.DetectLightAtPoint(Point: Vector3)
	local Detected = {
		Lights = {},
		Sunlight = false,
		InLight = false,
		LightLevel = 0,
	} :: LightObject

	local SunLight = CheckInSunlight(Point)

	if SunLight then
		Detected.Sunlight = true
		Detected.LightLevel = 15
	end

	for _,Light in AllLights do
		local LightParent = Light.Parent
		local LightPos = LightParent:IsA("BasePart") and LightParent.Position or (LightParent:IsA("Attachment") and LightParent.WorldPosition or nil)

		if not LightPos then continue end
		if not Light.Enabled then continue end

		local Brightness = Light.Brightness/2
		local range = Light.Range

		local magnitude = (Point - LightPos).Magnitude
		local unit = (LightPos - Point).Unit

		local p = Point:Lerp(LightPos,0.5)
		local cf = CFrame.lookAt(p,p + unit)
		local size = Vector3.new(0.01,0.01,magnitude)

		local Det = table.unpack(workspace:GetPartBoundsInBox(CFrame.new(Point),Vector3.one/10))
		OVP.FilterDescendantsInstances = {Det,LightParent}

		local obfuscated = if Light.Shadows then CheckObfuscated(workspace:GetPartBoundsInBox(cf,size,OVP)) else {}

		if #obfuscated > 0 then continue end

		if Light:IsA("PointLight") then
			local InRadius = PointLight(LightPos,Point,Light.Range)

			if InRadius then
				table.insert(Detected.Lights,Light)
				Detected.LightLevel = math.min((Detected.LightLevel + (range - magnitude) * (1+Brightness/magnitude))*2,15)
			end
		end

		if Light:IsA("SpotLight") then
			local dir = GetVectorFromNormal(LightParent,Light.Face)
			local InCone = SpotLight(LightPos,dir,Point,Light.Angle,range)

			if InCone and magnitude < range - range/12 then
				table.insert(Detected.Lights,Light)
				Detected.LightLevel = math.min((Detected.LightLevel + (range - magnitude) * (1+Brightness/magnitude))*2,15)
			end
		end

		if Light:IsA("SurfaceLight") then
			local dir = CFrame.lookAt(LightPos,LightPos + GetVectorFromNormal(LightParent,Light.Face))

			if LightParent:IsA("BasePart") then	
				local ParentSize = LightParent.Size/2
				dir *= CFrame.new(1,1,-ParentSize.Z)

				local corner = findFaceAndLightCorners(LightParent,Light)

				local Position = {}

				ChangeToFace(Position,corner,Light.Face)

				for i = 1,8,1 do
					Position[i] = LightParent.CFrame:PointToWorldSpace(Position[i])
				end
				
				local InsideCube = SurfaceLight(Position[1],Position[2],Position[3],Position[4],Position[5],Position[6],Position[7],Position[8],Point)

				if InsideCube and magnitude < range*1.1 then
					table.insert(Detected.Lights,Light)
					Detected.LightLevel = math.min((Detected.LightLevel + (range - magnitude) * (1+Brightness/magnitude))*2,15)
				end
			else
				local dir = GetVectorFromNormal(LightParent,Light.Face)
				local InCone = SpotLight(LightPos,dir,Point,Light.Angle,range)

				if InCone and magnitude  < range - range/5 then
					table.insert(Detected.Lights,Light)
					Detected.LightLevel = math.min((Detected.LightLevel + (range - magnitude) * (1+Brightness/magnitude))*2,15)
				end
			end
		end
	end

	Detected.InLight = #Detected.Lights > 0 or Detected.Sunlight

	return Detected
end

return module
