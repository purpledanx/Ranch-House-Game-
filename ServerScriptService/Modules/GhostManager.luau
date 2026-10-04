local module = {}

local GhostObj = {}
GhostObj.__index = GhostObj

local RoomRegions = game.Workspace.House.RoomRegions
local GhostSpawingPoints = game.Workspace.House.GhostSpawingPoints
local PathfindingService = game:GetService("PathfindingService")
local RoomValues = game.ServerStorage.ServerValues.RoomValues
local ServerStorage = game.ServerStorage
local ServerValues = ServerStorage.ServerValues
local GhostDataModule = require(script.Parent.GhostDataModule)
local SimplePathModule = require(script.Parent.SimplePath)
local PathFindingParms = {
	AgentRadius = 2,
	AgentHeight = 6,
	AgentCanJump = false,
	AgentCanClimb = false,
	WaypointSpacing = 3,
	Costs = {
		Door = 100000,
		Sand = 0.01,
		Blacklist = 1,
		Plastic = 1.5,
	}
}
local path:Path = nil
local oldDestination:Vector3 = Vector3.new(0,0,100000000000)

for i,v in ipairs(game.Workspace["PathFinding Blacklist"]:GetDescendants()) do
	if v:IsA("BasePart") then
		local modifier = Instance.new("PathfindingModifier")
		modifier.Parent = v
		modifier.Label = "Blacklist"
		modifier.PassThrough = true
	end
end

type Settings = {
	TIME_VARIANCE:number;

	COMPARISON_CHECKS:number;

	JUMP_WHEN_STUCK:boolean;
}

type Events = {
	Reached:BindableEvent;
	WaypointReached:BindableEvent;
	Blocked:BindableEvent;
	Error:BindableEvent;
	Stopped:BindableEvent;
}

type Position = {
	_last:Vector3;
	_count:number;
}

type PathObj = {
	__settings: Settings;
	_events: Events;
	_agent: Model;
	_humanoid: Humanoid;
	_path: Path;
	_status: string;
	_t: number;
	_position: Position;
	_IdleAnim: AnimationTrack;
	_WalkAnim: AnimationTrack;
}

local Path = {
	StatusType = {
		Idle = "Idle";
		Active = "Active";
	};
	ErrorType = {
		LimitReached = "LimitReached";
		TargetUnreachable = "TargetUnreachable";
		ComputationError = "ComputationError";
		AgentStuck = "AgentStuck";
	};
}

type EvidenceData = {
	Evidence1:string,
	Evidence2:string,
	Evidence3:string,
}

type Data = {
	Age:string,
	Room:string,
	Evidence:EvidenceData,
	Name:string
}

type ObjectMeta = {
	GhostModel:Model,
	GhostHumanoid:Humanoid,
	GhostData:Data,
	GhostSetUp:boolean,
	pathObject:PathObj,
}

type ghostParms = {
	GhostNumber:number,
	room:string,
}

local function WithinDistance(VectorA:Vector3,VectorB:Vector3,Distance:number)
	if math.abs((VectorB-VectorA).Magnitude) <= Distance then
		return true
	else
		return false
	end
end

function module.newGhostParms(GhostNumber:number,room:string)
	GhostNumber = GhostNumber or nil
	room = room or ""
	
	local ghostParms: ghostParms = {}
	ghostParms.GhostNumber = GhostNumber
	ghostParms.room = string.upper(room)
	
	return ghostParms
end

function module.new(parms)
	local parms:ghostParms = parms
	
	parms.GhostNumber = tostring(parms.GhostNumber)
	local GhostModels = ServerStorage.Assets.GhostModels
	local Ghost = 0
	if parms.GhostNumber ~= nil then
		Ghost = GhostModels["Ghost "..parms.GhostNumber]
	else
		Ghost = GhostModels:GetChildren()[Random.new():NextInteger(1,#GhostModels)]
	end	
	local GhostModel = Ghost:Clone()
	
	local self = setmetatable({
		GhostModel = GhostModel,
		GhostHumanoid = GhostModel:FindFirstChildOfClass("Humanoid"),
		GhostData = GhostDataModule.GetGhostData(),
		GhostSetUp = false,
		pathObject = nil,
	},GhostObj)
	
	if parms.room ~= "" then
		self.GhostData.Room = parms.room
	end
	
	ServerValues.GhostValues.Evidence.StartingRoom.Value = self.GhostData.Room
	if self.GhostData.Evidence[1] == "Freezing Temperatures" or self.GhostData.Evidence[2] == "Freezing Temperatures" or self.GhostData.Evidence[3] == "Freezing Temperatures" then
		ServerValues.RoomValues[self.GhostData.Room].Freezing.Value = true
		ServerValues.RoomValues[self.GhostData.Room].Temperture.Value = -5
	end
	
	print("Ghost Type: " .. self.GhostData.Name)
	print("Evidence 1: " .. self.GhostData.Evidence[1])
	print("Evidence 2: " .. self.GhostData.Evidence[2])
	print("Evidence 3: " .. self.GhostData.Evidence[3])
	print("Room is: "..self.GhostData.Room)
	
	self.GhostModel.PrimaryPart.Position = GhostSpawingPoints[self.GhostData["Room"]].Position + Vector3.new(0,2,0)
	self.GhostModel.Parent = game.Workspace
	self.GhostSetUp = true
	self.pathObject = SimplePathModule.new(self.GhostModel,PathFindingParms)
	self.ValidWalkingSpace = game.Workspace.House.Walk
	self.testpart = Instance.new("Part")
	self.testpart.Parent = game.Workspace
	self.testpart.Anchored = true
	self.testpart.Transparency = 1
	self.testpart.Size = Vector3.new(1,1,1)
	
	return self
end

function GhostObj:PathGhost()
	local self: ObjectMeta = self
	if self.GhostSetUp then
		local list = {}
		local character:Model = SimplePathModule.GetNearestCharacter(self.GhostModel.PrimaryPart.Position)

		if character and self.GhostModel and (character.UpperTorso.Position-self.GhostModel.PrimaryPart.Position).Magnitude > 1 then
			self.testpart.Position = character.UpperTorso.Position
			self.ValidWalkingSpace.CanCollide = true
			list = self.testpart:GetTouchingParts()
			self.ValidWalkingSpace.CanCollide = false
			self.testpart.Position = Vector3.new(10000,100000,100000)

			if table.find(list,self.ValidWalkingSpace) then
				self.pathObject:Run(character.UpperTorso.Position)
			end
		end
	else
		warn("Ghost Not Set Up!")
	end
end

function module:TurnInvisible(Invisible:boolean)
	local self: ObjectMeta = self
	if self.GhostSetUp then
		if Invisible then
			for i,v in ipairs(self.GhostModel:GetDescendants()) do
				if v:IsA("BasePart") then
					v.Transparency = 1
				end
			end
		else
			for i,v in ipairs(self.GhostModel:GetDescendants()) do
				if v:IsA("BasePart") then
					v.Transparency = 0
				end
			end
		end
	else
		warn("Ghost Not SetUp!")
	end
end

return module
