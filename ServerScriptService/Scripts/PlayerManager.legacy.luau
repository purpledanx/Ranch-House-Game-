--Services--
local DataStoreService = game:GetService("DataStoreService")
local DataStore = DataStoreService:GetDataStore("Main")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")
--Other Stuff--
local ServerScriptService = game.ServerScriptService
local ReplicatedStorage = game.ReplicatedStorage
local ServerStorage = game.ServerStorage
local GameStarted = ServerStorage.ServerValues.GameStarted
local DataLoaded = ServerStorage.ServerValues.DataLoaded
--Modules--
--local GameServer = require(ServerScriptService.Modules.GameServer)
local GhostManager = require(ServerScriptService.Modules.GhostManager)
local DoorModule = require(ServerScriptService.Modules.DoorManager)
local GhostDataModule = require(ServerScriptService.Modules.GhostDataModule)
local Network = require(ReplicatedStorage.Modules.Util.Network)

--Variables--
local PlayerColdBreathLoops = {}

local function ColdBreath(player: Player, lastRoomName, roomName)
	roomName = string.upper(roomName)
	
	local character = player.Character or player.CharacterAdded:Wait()
	local breathPart = character:WaitForChild("Head"):WaitForChild("BreathPart")
	local roomValues = ServerStorage.ServerValues.RoomValues:FindFirstChild(roomName)

	if PlayerColdBreathLoops[player] then
		task.cancel(PlayerColdBreathLoops[player])
		PlayerColdBreathLoops[player] = nil
	end

	if roomValues and roomValues.Freezing.Value then
		breathPart.Breath.Enabled = true

		PlayerColdBreathLoops[player] = task.spawn(function()
			while task.wait() and roomValues.Freezing.Value do
				breathPart.Breath.Enabled = true
				task.wait(0.5)
				breathPart.Breath.Enabled = false
				task.wait(Random.new():NextInteger(200,400)/100)
			end

			breathPart.Breath.Enabled = false
		end)
	else
		breathPart.Breath.Enabled = false
	end
end

Network:BindEvents({
	ColdBreath = {
		MatchParams = {},
		function(player, lastRoomName, roomName)
			ColdBreath(player, lastRoomName, roomName)
		end
	}
})