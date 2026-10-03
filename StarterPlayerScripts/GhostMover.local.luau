--Player

local player = game.Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
--Places

local ReplicatedStorage = game:GetService("ReplicatedStorage")

--Modules

--local SimpleMover = require(ReplicatedStorage.Module.SimplePath)

--Vairables
local PathFindingParms = {
	AgentRadius = 2,
	AgentHeight = 6,
	AgentCanJump = false,
	AgentCanClimb = false,
	WaypointSpacing = 4,
	Costs = {
		Door = 100000,
		Sand = 1,
	}
}

--Functions
local function StartGhost(Model:Model)
	
end

--<<Code>>--

