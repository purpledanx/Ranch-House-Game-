local module = {}
local RoomRegions = game.Workspace.House.RoomRegions
local ReplicatedStorage = game.ReplicatedStorage
local GhostSpawingPoints = game.Workspace.House.GhostSpawingPoints
local PathfindingService = game:GetService("PathfindingService")
--local SimplePathModule = require(script.Parent.SimplePath)

local PathFindingParms = {
	AgentRadius = 2,
	AgentHeight = 6,
	AgentCanJump = false,
	AgentCanClimb = false,
	WaypointSpacing = 4,
	Costs = {
		--Door = 10000,
		--Plastic = 100,
	}
}

local GhostModel:Model = nil
local GhostData = nil
local GhostSetUp:boolean = false
local GhostHumanoid:Humanoid = nil
local waypoints = nil
local nextWaypointIndex = nil
local isWalking = false
local reachedConnection:RBXScriptConnection = nil
local blockedConnection:RBXScriptConnection = nil
local path:Path = PathfindingService:CreatePath(PathFindingParms)
local oldDestination:Vector3 = Vector3.new(0,0,100000000000)

local function WithinDistance(VectorA:Vector3,VectorB:Vector3,Distance:number)
	if math.abs((VectorB-VectorA).Magnitude) <= Distance then
		return true
	else
		return false
	end
end

local function GoToDestination(destination:Vector3)
	if not WithinDistance(oldDestination,destination,1) then
		oldDestination = destination
		local success, errorMessage = pcall(function()
			path:ComputeAsync(GhostModel.PrimaryPart.Position, destination)
		end)

		if success and path.Status == Enum.PathStatus.Success then
			print("Path Success")
			waypoints = path:GetWaypoints()

			blockedConnection = path.Blocked:Connect(function(blockedWaypointIndex)
				if blockedWaypointIndex >= nextWaypointIndex then
					GoToDestination(destination)
					blockedConnection:Disconnect()
				end
			end)

			if not isWalking then
				reachedConnection = GhostHumanoid.MoveToFinished:Connect(function(reached)
					if reached and nextWaypointIndex < #waypoints then
						print("moving")
						nextWaypointIndex += 1
						GhostHumanoid:MoveTo(waypoints[nextWaypointIndex].Position)
					else
						print("Disconnect")
						isWalking = false
						reachedConnection:Disconnect()
						blockedConnection:Disconnect()
					end
				end)
				isWalking = true
			end

			nextWaypointIndex = 2
			GhostHumanoid:MoveTo(waypoints[nextWaypointIndex].Position)
		else
			isWalking = false
			warn("Path not computed!", errorMessage)
		end
	else
		isWalking = false
		oldDestination = destination
	end
end

function module:GhostWalkToPoint(Destination:Vector3)
	GoToDestination(Destination)
end

function module:TurnInvisible(Invisible:boolean)
	if Invisible then
		for i,v in ipairs(GhostModel:GetDescendants()) do
			if v:IsA("BasePart") then
				v.Transparency = 1
			end
		end
	else
		for i,v in ipairs(GhostModel:GetDescendants()) do
			if v:IsA("BasePart") then
				v.Transparency = 0
			end
		end
	end
end

return module
