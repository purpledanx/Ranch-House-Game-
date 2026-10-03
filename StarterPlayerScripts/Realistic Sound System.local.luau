local player = game.Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local Sounds = {}
local ReplicatedStorage = game.ReplicatedStorage
local Janitor = require(ReplicatedStorage.Modules.Util.Janitor)
local RunService = game:GetService("RunService")
local RenderStepPriority = 1
local janitor = Janitor.new()

local UniqueID = 0

local Filter = {}

local function Lerp(a, b, t)
	return a + (b - a) * t
end

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

for i,v in ipairs(game.Workspace.InvWall:GetChildren()) do
	if v:IsA("BasePart") then
		table.insert(Filter,v)
	end
end

table.insert(Filter,game.Workspace.House.Walk)

local Parms = OverlapParams.new()
Parms.FilterType = Enum.RaycastFilterType.Exclude
Parms:AddToFilter(Filter)

local function GetPosition(Sound:Sound)
	if Sound.Parent:IsA("Model") then
		if Sound.Parent.PrimaryPart then
			return Sound.Parent.PrimaryPart.Position
		else
			return Sound.Parent.WorldPivot.Position
		end
	end
	if Sound.Parent:IsA("BasePart") then
		return Sound.Parent.Position
	end
	return nil
end

local function FindAudioPlayer(v,Parent:Instance)
	for i,obj:Wire in ipairs(Parent.Parent:GetDescendants()) do
		if obj:IsA("Wire") and obj.TargetInstance == v and obj.SourceInstance:IsA("AudioPlayer") then
			return obj.SourceInstance
		end
		if obj:IsA("Wire") and obj.TargetInstance ~= v then
			if obj.SourceInstance:IsA("AudioPlayer") then
				return obj.SourceInstance
			else
				FindAudioPlayer(obj.SourceInstance)
				break
			end
		end
		if obj:IsA("Wire") and obj.TargetInstance == v then
			FindAudioPlayer(obj.SourceInstance)
			break
		end
	end
end

local function SendRay(Sound,BaseVolume)
	local NumberOfWalls = 0
	local HitPosition = nil
	local WallsWentThrough = setmetatable({}, {__mode = "vk"})
	local Fader:AudioFader
	local OverlapParts = nil
	local SoundGroup:SoundGroup
	local Distance:Vector3 = Vector3.new()

	if Sound:IsA("Sound") and Sound.Parent:IsA("BasePart") and (character:WaitForChild("Head").Position-GetPosition(Sound)).Magnitude > 5 and not Sound.Parent:IsDescendantOf(character) then
		HitPosition = GetPosition(Sound)
		WallsWentThrough = {}
		
		Parms:AddToFilter(Sound.Parent)
		
		Distance = (character.Head.Position-HitPosition).Magnitude
		OverlapParts = game.Workspace:GetPartBoundsInBox(CFrame.new(Vector3.new(HitPosition):Lerp(character.Head.Position,0.5)), Vector3.new(0.1,0.1, Distance),Parms)
		for i,v in ipairs(OverlapParts) do
			if v:IsA("BasePart") then
				table.insert(WallsWentThrough,v)
			end
		end
		
		task.synchronize()

		NumberOfWalls = #WallsWentThrough
		print(Sound)
		print(WallsWentThrough)
		SoundGroup = nil
		if game:GetService("SoundService"):FindFirstChild(Sound.Name) then
			SoundGroup = game:GetService("SoundService"):FindFirstChild(Sound.Name)
		else
			SoundGroup = Instance.new("SoundGroup",game:GetService("SoundService"))
			SoundGroup.Volume = 1
			SoundGroup.Name = Sound.Name
		end
		Sound.SoundGroup = SoundGroup
		if BaseVolume/NumberOfWalls < 0.1 then
			Sound.Volume = 0
		else
			if NumberOfWalls == 0 then
				Sound.Volume = Lerp(Sound.Volume,BaseVolume,0.01)
			else
				Sound.Volume = Lerp(Sound.Volume,BaseVolume/NumberOfWalls,0.01)
			end
		end
	elseif Sound:IsA("AudioEmitter") and Sound.Parent and Sound.Parent:IsA("BasePart") and not Sound.Parent:IsDescendantOf(character) then
		HitPosition = GetPosition(Sound)
		WallsWentThrough = {}

		Parms:AddToFilter(Sound.Parent)

		Distance = (character:WaitForChild("Head").Position-HitPosition).Magnitude
		OverlapParts = game.Workspace:GetPartBoundsInBox(CFrame.new(Vector3.new(HitPosition):Lerp(character:WaitForChild("Head").Position,0.5)), Vector3.new(0.1,0.1, Distance),Parms)
		
		for i,v in ipairs(OverlapParts) do
			if v:IsA("BasePart") and v.Transparency < 0.5 then
				table.insert(WallsWentThrough,v)
			end
		end
		
		task.synchronize()
		NumberOfWalls = #WallsWentThrough
		Fader = nil
		if Sound.Parent:FindFirstChildOfClass("AudioFader") then
			Fader = Sound.Parent:FindFirstChildOfClass("AudioFader")
		else
			Fader = Instance.new("AudioFader",Sound.Parent)
			Fader.Volume = 1
			Fader.Name = Sound.Parent.Name.."Fader"

			local Other:Wire = nil
			for i,v in ipairs(Sound.Parent:GetChildren()) do
				if v:IsA("Wire") and v.TargetInstance == Sound then
					Other = v
					break
				end
			end

			local Wire = Instance.new("Wire",Sound.Parent)
			Wire.Name = Other.SourceInstance.Name.." To "..Fader.Name
			Wire.SourceInstance = Other.SourceInstance
			Wire.TargetInstance = Fader

			local Wire2 = Instance.new("Wire",Sound.Parent)
			Wire2.Name = Fader.Name.." To "..Sound.Name
			Wire2.SourceInstance = Fader
			Wire2.TargetInstance = Sound

			Other:Destroy()
		end
		
		local volume = math.pow(2+NumberOfWalls,(-Distance)/10)
		
		if volume < 0.02 then
			Fader.Volume = 0
		else
			Fader.Volume = volume
		end
		if Distance > 100 then
			Fader.Volume = 0
		end
	end
end

for i,v in ipairs(game.Workspace:GetDescendants()) do
	if v:IsA("Sound") and v.Parent:IsA("BasePart") then
		table.insert(Sounds,v)
	end
	if v:IsA("AudioEmitter") then
		table.insert(Sounds,v)
	end
end

for i,v:Sound|AudioEmitter in ipairs(Sounds) do
	UniqueID+=1
	if v:IsA("Sound") then
		local BaseVolume = v.Volume
		v:SetAttribute("ID","A"..UniqueID)
		v:AddTag("ID")
		RunService:BindToRenderStep("A"..UniqueID,RenderStepPriority,function()
			if v.IsPlaying then
				SendRay(v,BaseVolume)
			end
		end)
	elseif v:IsA("AudioEmitter") then
		v:SetAttribute("ID","A"..UniqueID)
		v:AddTag("ID")
		
		RunService:BindToRenderStep("A"..UniqueID,RenderStepPriority,function()
			SendRay(v,1)
		end)
	end
end

game.Workspace.DescendantAdded:Connect(function(v)
	UniqueID+=1
	if v and v:IsA("Sound") and v.Parent:IsA("BasePart") then
		if not table.find(Sounds,v) then
			table.insert(Sounds,v)
		end
		v:SetAttribute("ID","A"..UniqueID)
		v:AddTag("ID")
		RunService:BindToRenderStep("A"..UniqueID,RenderStepPriority,function()
			if v.IsPlaying then
				SendRay(v,v.Volume)
			end
		end)
	elseif v and v:IsA("AudioEmitter") and v.Parent:IsA("BasePart") then
		if not table.find(Sounds,v) then
			table.insert(Sounds,v)
		end
		v:SetAttribute("ID","A"..UniqueID)
		v:AddTag("ID")
		RunService:BindToRenderStep("A"..UniqueID,RenderStepPriority,function()
			SendRay(v,1)
		end)
	end
end)

game.Workspace.DescendantRemoving:Connect(function(v)
	if v.Parent and v and v:IsA("Sound") and v.Parent:IsA("BasePart") and table.find(Sounds,v) then
		table.remove(Sounds,table.find(Sounds,v))
		RunService:UnbindFromRenderStep(v:GetAttribute("ID"))
	elseif v:IsA("AudioEmitter") and v.Parent and v.Parent:IsA("BasePart") and table.find(Sounds,v) then
		table.remove(Sounds,table.find(Sounds,v))
		RunService:UnbindFromRenderStep(v:GetAttribute("ID"))
	end
end)

