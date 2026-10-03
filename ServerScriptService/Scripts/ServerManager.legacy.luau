--Services--
local DataStoreService = game:GetService("DataStoreService")
local DataStore = DataStoreService:GetDataStore("Main")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")
local VoiceChatService = game:GetService("VoiceChatService")

--Refrences--
local ServerScriptService = game.ServerScriptService
local ReplicatedStorage = game.ReplicatedStorage
local ServerStorage = game.ServerStorage
local GameStarted = ServerStorage.ServerValues.GameStarted
local DataLoaded = ServerStorage.ServerValues.DataLoaded
local BindableEvents = ServerStorage.BindableEvents

--Modules--
--local GameServer = require(ServerScriptService.Modules.GameServer)
local GhostManager = require(ServerScriptService.Modules.GhostManager)
local DoorModule = require(ServerScriptService.Modules.DoorManager)
local GhostDataModule = require(ServerScriptService.Modules.GhostDataModule)
local Network = require(ReplicatedStorage.Modules.Util.Network)

--Variables--
local Character:Model = nil
local Humanoid:Humanoid = nil
local ghostType = ""
local lastResponse = ""
local GhostData = GhostDataModule.GetGhostData()

local ghostAge = ""
local enteredRooms = {}
local PartyId = ""
local ServerData = {}
local ErrorTime = 0
local playernumberValues = 1

--Temp--

local DataAddedToGameServer = false

--Game Setup--

--Functions--
local function CreatePlayerValues(player:Player)
	local PlayerValues = ServerStorage.PlayerValues["Player"..playernumberValues]
	PlayerValues.Name = player.Name
	
	local PlayerInventory = Instance.new("Folder",PlayerValues)
	PlayerInventory.Name = "Inventory"
	
	local PlayerXP = Instance.new("NumberValue",PlayerValues)
	PlayerXP.Name = "PlayerXP"
	
	local isPartyLeader = Instance.new("BoolValue",PlayerValues)
	isPartyLeader.Name = "isPartyLeader"
	
	local BeingHunted = Instance.new("BoolValue",PlayerValues)
	BeingHunted.Name = "BeingHunted"

	local isHiding = Instance.new("BoolValue",PlayerValues)
	isHiding.Name = "isHiding"

	local CurrentPartyId = Instance.new("StringValue",PlayerValues)
	CurrentPartyId.Name = "CurrentPartyId"
	
	local Sanity = Instance.new("NumberValue",PlayerValues)
	Sanity.Value = 100
	Sanity.Name = "Sanity"
	
	playernumberValues+=1
end

local function CreateAudioAssets(player:Player)
	local PlayerAudio = player.PlayerGui:WaitForChild("PlayerAudio")
	PlayerAudio.AudioDeviceOutput.Player = player
	PlayerAudio.Wires.LeftToOutput.SourceInstance = player.Character:WaitForChild("LeftListener").LeftListener
	PlayerAudio.Wires.LeftToOutput.SourceInstance = player.Character:WaitForChild("RightListener").RightListener
	player.Character:WaitForChild("AudioEmitter").Parent = player.Character.Head
end

local function DropTool(player,tool)
	print("Received, dropping tool..")
	if tool and ServerStorage.Tools:FindFirstChild(tool.Name) and player.Character:FindFirstChild(tool.Name) then
		tool:Destroy()
		local clone = game.ServerStorage.ToolModels[tool.Name]:Clone()
		local character = player.Character
		local humanoidrootpart = character:FindFirstChild("HumanoidRootPart")

		if humanoidrootpart then
			local offset = Vector3.new(0, 0, -2)

			local playerLookVector = humanoidrootpart.CFrame.lookVector
			local spawnPosition = humanoidrootpart.Position - (playerLookVector * offset)
			clone.Parent = game.Workspace.Tools
			clone:SetPrimaryPartCFrame(CFrame.new(spawnPosition))
			clone:SetPrimaryPartCFrame(clone:GetPrimaryPartCFrame() * CFrame.Angles(0, math.rad(180), 0))
			wait(1)
			for _, part in ipairs(clone:GetDescendants()) do
				if part:IsA("BasePart") then
					part.Anchored = true
				end
			end
		end
	end
end

local function SendPartyId(player, DataId:string, Leader:boolean)
	if type(DataId) ~= "string" then
		PartyId = "Invalid Id"
		ServerStorage.PlayerValues:WaitForChild(player.Name).CurrentPartyId.Value = PartyId
		ServerStorage.PlayerValues:WaitForChild(player.Name).isPartyLeader.Value = Leader
		DataLoaded.Value = true
	else
		PartyId = DataId
		ServerStorage.ServerValues.PartyValues.PartyID.Value = PartyId
		ServerStorage.PlayerValues:WaitForChild(player.Name).CurrentPartyId.Value = PartyId
		ServerStorage.PlayerValues:WaitForChild(player.Name).isPartyLeader.Value = Leader
		DataLoaded.Value = true
	end
	print(PartyId)
end

local function equiptool(player:Player, item, mousetarget)	
	local clone = item:Clone()
	clone.Parent = player.Backpack
	print("Equipping")
	player.Character:FindFirstChildOfClass("Humanoid"):EquipTool(clone)
	mousetarget:Destroy()
end

local function PickupItem(player, mousetarget, mousehit)
	local item = game.ServerStorage.Tools:FindFirstChild(mousetarget.Parent.Name)
	if not item then warn("Couldnt Find Tool") return end
	
	local character:Model = player.Character
	local humanoid = character:FindFirstChild("Humanoid")
	local distanceFromItem = (player.Character.PrimaryPart.Position - mousehit.Position).magnitude
	print(distanceFromItem)
	-- check distance

	if distanceFromItem <= 5 then
		local backpack = player.Backpack
		local numItemsInBackpack = #backpack:GetChildren()
		print("player has "..numItemsInBackpack.." items in his backpack")
		-- check amount of tools in backpack
		if numItemsInBackpack < 4 then
			print("fetching")

			-- equip tool
			if item.Name == "GhostBook" then
				print("picking up")
				equiptool(player, item, mousetarget.Parent, humanoid)
				if game.Workspace.BookPlacement:FindFirstChild("OpenedBook") then
					game.Workspace.BookPlacement:FindFirstChild("OpenedBook"):Destroy()
				end
			else
				equiptool(player, item, mousetarget.Parent, humanoid)
			end
		end
	else
		warn("player is too far to pick up tool")
	end
end

local function ComputationError(ErrorType,Model:Model)
	if os.time() - ErrorTime  >= 1 then
		ErrorTime = os.time()
		local Room = game.ServerStorage.ServerValues.GhostValues.Evidence.StartingRoom.Value
		local GhostSpawingPoints = game.Workspace.House.GhostSpawingPoints

		Model.PrimaryPart.Position = GhostSpawingPoints[Room].Position
	end
end

--[[ VoiceChatInternal doesn't work
local function ChangeVoiceChatGui(VoiceEnabled:boolean,player)
	VoiceEnabled = VoiceEnabled or false
	if not VoiceEnabled then
		VoiceChatInternal:SubscribePauseAll(false)
		task.delay(2,function()
			RemoteEvents.SetBubbleChatSettings:FireAllClients()
		end)
	else
		VoiceChatInternal:SubscribePauseAll(true)
	end
end
]]

function Look(player, neckC0, waistC0, NeckPosition)
	--[[for key, value in pairs(game.Players:GetChildren()) do
		if value ~= player and (value.Character.Head.Position - player.Character.Head.Position).Magnitude < 10 then
			game.ReplicatedStorage.RemoteEvents.Look:FireClient(value, player, neckCFrame)
		end
	end]]
	
	Network:FireAllClients("Look", player, neckC0, waistC0, NeckPosition)
end

local function DoorOpen()
	local parms = GhostManager.newGhostParms(1,"BEDROOM 1")
	local obj = GhostManager.new(parms)
	local event:BindableEvent = BindableEvents:WaitForChild("Error")
	if event then
		event.Event:Connect(ComputationError)
		while task.wait(0.1) do
			obj:StartGhost()
		end
	end
end

--Connections--

Network:BindEvents({
	PickupItem = PickupItem,
	SendPartyId = SendPartyId,
	Look = Look,
	DroppedTool = DropTool,
})

BindableEvents.DoorOpen.Event:Connect(DoorOpen)

local function CreateBreathPart(character)
	print("Creating")
	local BreathPart = script.BreathPart:Clone()
	BreathPart.CanCollide = false
	BreathPart.CanQuery = false
	BreathPart.CastShadow = false
	BreathPart.Breath.Enabled = false
	BreathPart.Parent = character:WaitForChild("Head")
	local Weld = Instance.new("Weld")
	Weld.Parent = BreathPart
	Weld.Part0 = BreathPart
	Weld.Part1 = character.Head
end

game.Players.PlayerAdded:Connect(function(player)
	CreatePlayerValues(player)
	CreateAudioAssets(player)
	CreateBreathPart(player.Character)
	
	player.CharacterAdded:Connect(function(character)
		CreateBreathPart(character)
	end)
	
	--[[ VoiceChatInternal Doesn't work
	if DataLoaded.Value and not DataAddedToGameServer then
		DataAddedToGameServer = true
		GameServer:GlobalToLocalServer(PartyId)
		if GameServer:GetPartyInfo(PartyId) then
			ChangeVoiceChatGui(GameServer:GetPartyInfo(PartyId)["VoiceEnabled"],player)
		else
			ChangeVoiceChatGui(false,player)
		end
	end
	]]
	
	--Get data
	local Success, data = pcall(function()
		return DataStore:GetAsync(player.UserId)
	end)

	if Success and data then
		ServerStorage.PlayerValues:WaitForChild(player.Name).PlayerXP.Value = data["XP"]
	end
end)

game.Players.PlayerRemoving:Connect(function(player)
	local data = {}
	data["XP"] = ServerStorage.PlayerValues:WaitForChild(player.Name).PlayerXP.Value

	local Success, Failure = pcall(function()
		DataStore:SetAsync(player.UserId,data)
	end)
	ServerStorage.PlayerValues:WaitForChild(player.Name):Destroy()
end)

game:BindToClose(function()
	if not RunService:IsStudio() then

	end
end)