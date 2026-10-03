local player = game.Players.LocalPlayer
local ReplicatedStorage = game.ReplicatedStorage
local ReverbModule = require(ReplicatedStorage.Modules.Sounds.DynamicAudioV2)
local RunService = game:GetService("RunService")
local Sounds = {}
local Filter = {}
local ReverbObjs = {}
local Connections = {}
local MaxBounce = 3
local Rays = 16
local Distance = 600
local IgnoreTransparent = true
local Debug = false
local LerpTime = 0.15
local ThreeDNMuffle = true
local RenderStepPrioriy = 1

local UniqueID = 0

local Character = player.Character

if Character then
	table.insert(Filter, Character)
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

for i,v in ipairs(game.Workspace:GetChildren()) do
	if v.Name == "PathThrough" then
		table.insert(Filter,v)
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

local function RoundTo(Number: number, NumberOfDecimalPlaces: number)
	local RoundTo = 10^(NumberOfDecimalPlaces or 0)
	local Rounded = math.floor(Number * RoundTo + 0.5) / RoundTo
	return Rounded
end

local function FindAudioPlayer(Object:AudioEmitter|Wire)
	if not Object:IsA("Wire") then
		local list = Object:GetConnectedWires("Input")

		for i,v:AudioPlayer in ipairs(list) do
			if v:IsA("AudioPlayer") then
				return v
			else
				return FindAudioPlayer(v)
			end
		end
	elseif Object:IsA("Wire") then
		if Object.SourceInstance:IsA("AudioPlayer") then
			return Object.SourceInstance
		else
			return FindAudioPlayer(Object.SourceInstance)
		end
	end
	
	return nil
end

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

local function Sound(v:Sound)
	local BaseVolume = v.Volume
	local RayParam = ReverbModule.newRayParams(v.Parent, MaxBounce, Rays, Distance, IgnoreTransparent, Debug)
	local SoundParm = ReverbModule.newSoundParams(LerpTime,1,ThreeDNMuffle)
	local ReverbObj: ReverbModule.ObjectMeta = ReverbModule.new(RayParam, SoundParm, Filter)
	ReverbObj:AddSound(v)
	ReverbObjs[v] = ReverbObj
	v:SetAttribute("IDB","B"..UniqueID)
	v:AddTag("IDB")
	if v.Playing then
		ReverbObj:StartUpdate()
	else
		ReverbObj:StopUpdate()
	end
	Connections["B"..UniqueID] = RunService.RenderStepped:Connect(function()
		if v.Playing then
			ReverbObj:StartUpdate()
		else
			ReverbObj:StopUpdate()
		end
	end)
	RayParam = nil
	SoundParm = nil
end

local function Emitter(v:AudioEmitter)
	local RayParam = ReverbModule.newRayParams(v.Parent, MaxBounce, Rays, Distance, IgnoreTransparent, Debug)
	local SoundParm = ReverbModule.newSoundParams(LerpTime,1,ThreeDNMuffle)
	local ReverbObj: ReverbModule.ObjectMeta = ReverbModule.new(RayParam,SoundParm, Filter)
	local AudioPlayer = nil
	local Updating = false
	ReverbObj:AddSound(v)
	ReverbObjs[v] = ReverbObj

	AudioPlayer = FindAudioPlayer(v)
	
	if AudioPlayer then
		if AudioPlayer and AudioPlayer.IsPlaying then
			ReverbObj:StartUpdate()
		else
			ReverbObj:StopUpdate()
		end
		v:SetAttribute("IDB","B"..UniqueID)
		v:AddTag("IDB")
		
		local function Update()
			if AudioPlayer and AudioPlayer.IsPlaying then
				if Updating == false then
					Updating = true
					print("sdf")
					ReverbObj:StartUpdate()
				end
			else
				Updating = false
				ReverbObj:StopUpdate()
			end
		end
		
		Connections["B"..UniqueID] = RunService.RenderStepped:Connect(Update)
		RayParam = nil
		SoundParm = nil
	else
		RayParam = nil
		SoundParm = nil
		ReverbObjs[v]:StopUpdate()
		ReverbObjs[v]:RemoveSound(v, true)
		ReverbObjs[v] = nil
	end
end

for i,v:Sound in ipairs(Sounds) do
	UniqueID+=1
	if v.Parent:IsA("BasePart") then
		if v:IsA("Sound") then
			Sound(v)
		elseif v:IsA("AudioEmitter") then
			Emitter(v)
		end
	end
end

game.Workspace.DescendantAdded:Connect(function(v)
	UniqueID+=1
	if v and v:IsA("Sound") and v.Parent:IsA("BasePart") then
		if not table.find(Sounds,v) then
			table.insert(Sounds,v)
		end
		Sound(v)
	elseif v and v:IsA("AudioEmitter") and v.Parent:IsA("BasePart") then
		if not table.find(Sounds,v) then
			table.insert(Sounds,v)
		end
		Emitter(v)
	end
end)

game.Workspace.DescendantRemoving:Connect(function(v)
	if v.Parent and v and v.Parent:IsA("BasePart") and table.find(Sounds,v) then
		if ReverbObjs[v] ~= nil then
			ReverbObjs[v]:StopUpdate()
			ReverbObjs[v]:RemoveSound(v, true)
			ReverbObjs[v] = nil
			Connections[v:GetAttribute("IDB")]:Disconnect()
			Connections[v:GetAttribute("IDB")] = nil
		end
		table.remove(Sounds,table.find(Sounds,v))
	end
end)