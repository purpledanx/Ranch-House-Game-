local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ReverbModule = require(ReplicatedStorage.Modules.Sounds.DynamicAudioV2)
local player = Players.LocalPlayer
local house = workspace:WaitForChild("House")
local hitbox = house:WaitForChild("Hitbox")
local roomRegions = house:WaitForChild("RoomRegions")

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
local UniqueID = 0

local Character = player.Character

if Character then
	table.insert(Filter, Character)
end

for _, v in ipairs(hitbox:GetChildren()) do
	if v:IsA("BasePart") then
		table.insert(Filter,v)
	end
end

for _, v in ipairs(roomRegions:GetChildren()) do
	if v:IsA("BasePart") then
		table.insert(Filter,v)
	end
end

for _, v in ipairs(workspace:GetChildren()) do
	if v.Name == "PathThrough" then
		table.insert(Filter,v)
	end
end

for _, v in ipairs(workspace:GetDescendants()) do
	if v:IsA("Sound") and v.Parent and v.Parent:IsA("BasePart") then
		table.insert(Sounds,v)
	end
	if v:IsA("AudioEmitter") then
		table.insert(Sounds,v)
	end
end

local function FindAudioPlayer(object: Instance): AudioPlayer?
	if object:IsA("AudioPlayer") then
		return object
	end

	if object:IsA("Wire") then
		local source = object.SourceInstance
		return source and FindAudioPlayer(source) or nil
	end

	if object:IsA("AudioEmitter") then
		for _, wire in ipairs(object:GetConnectedWires("Input")) do
			local audioPlayer = FindAudioPlayer(wire)
			if audioPlayer then
				return audioPlayer
			end
		end
	end

	return nil
end

local function Sound(v:Sound)
	local source = v.Parent
	if not source or not source:IsA("BasePart") then
		return
	end

	local RayParam = ReverbModule.newRayParams(source, MaxBounce, Rays, Distance, IgnoreTransparent, Debug)
	local SoundParm = ReverbModule.newSoundParams(LerpTime,1,ThreeDNMuffle)
	local ReverbObj = ReverbModule.new(RayParam, SoundParm, Filter)
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
	local source = v.Parent
	if not source or not source:IsA("BasePart") then
		return
	end

	local RayParam = ReverbModule.newRayParams(source, MaxBounce, Rays, Distance, IgnoreTransparent, Debug)
	local SoundParm = ReverbModule.newSoundParams(LerpTime,1,ThreeDNMuffle)
	local ReverbObj = ReverbModule.new(RayParam,SoundParm, Filter)
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

for _, v in ipairs(Sounds) do
	UniqueID+=1
	if v.Parent and v.Parent:IsA("BasePart") then
		if v:IsA("Sound") then
			Sound(v)
		elseif v:IsA("AudioEmitter") then
			Emitter(v)
		end
	end
end

workspace.DescendantAdded:Connect(function(v)
	UniqueID+=1
	if v:IsA("Sound") and v.Parent and v.Parent:IsA("BasePart") then
		if not table.find(Sounds,v) then
			table.insert(Sounds,v)
		end
		Sound(v)
	elseif v:IsA("AudioEmitter") and v.Parent and v.Parent:IsA("BasePart") then
		if not table.find(Sounds,v) then
			table.insert(Sounds,v)
		end
		Emitter(v)
	end
end)

workspace.DescendantRemoving:Connect(function(v)
	local soundIndex = table.find(Sounds, v)
	if v.Parent and v.Parent:IsA("BasePart") and soundIndex then
		if ReverbObjs[v] ~= nil then
			ReverbObjs[v]:StopUpdate()
			ReverbObjs[v]:RemoveSound(v, true)
			ReverbObjs[v] = nil
			local connectionId = v:GetAttribute("IDB")
			if type(connectionId) == "string" then
				local connection = Connections[connectionId]
				if connection then
					connection:Disconnect()
					Connections[connectionId] = nil
				end
			end
		end
		table.remove(Sounds, soundIndex)
	end
end)
