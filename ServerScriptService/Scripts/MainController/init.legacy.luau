-- DataStore
local Game_Difficulty = nil

-- Module variables

-- Room variables
local livingRoom = game.Workspace.House.RoomRegions["LIVING ROOM"]
local Kitchen = game.Workspace.House.RoomRegions.KITCHEN
local Bedroom1 = game.Workspace.House.RoomRegions["BEDROOM 1"]
local Bedroom2 = game.Workspace.House.RoomRegions["BEDROOM 2"]
local Bedroom3 = game.Workspace.House.RoomRegions["GUEST ROOM"]
local Bedroom4 = game.Workspace.House.RoomRegions["MASTER BEDROOM"]
local Outside = game.Workspace.House.RoomRegions["OUTSIDE"]
local Garadge = game.Workspace.House.RoomRegions.GARAGE
local Den = game.Workspace.House.RoomRegions.DEN
local Basement = game.Workspace.House.RoomRegions.BASEMENT
local Bathroom = game.Workspace.House.RoomRegions.BATHROOM
local Hallway = game.Workspace.House.RoomRegions.HALLWAY
local Truck = game.Workspace.House.RoomRegions.TRUCK

-- Remotes and Boolean variables

local hauntedRoomEvent = game.ReplicatedStorage.EMFHaunted
local TemperatureEvent = game.ReplicatedStorage.TempatureEvent
local SpiritBoxEvent = game.ReplicatedStorage.SpiritBoxEvent
local ghostage = ""
local ghostagepicker = nil
local playerinhauntedroom = false
local shouldGoFreezing = false
local emf3event = false
local gamerunning = true
local randomHauntedRoom
local isRoomHaunted
-- Spirit Box Variable

local lastResponse = ""

-- Ghost variables
local ghostType = ""
local ghostEvidence = {}

-- Variables
local ColdBreathLoop


-- Ghost handler

local rep = game:GetService("ReplicatedStorage")

game.ReplicatedStorage.GWPlacement.OnServerEvent:Connect(function(player, lastOverlayPosition)
	local book = game.ReplicatedStorage.OpenedBook:Clone()
	book.Parent = game.Workspace.BookPlacement

	book:SetPrimaryPartCFrame(CFrame.new(lastOverlayPosition))

	book.Paper.CFrame = book.Paper.CFrame
	for _, part in ipairs(book:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = true
		end
	end
end)


-- EMF handler

local function emf3eventfinder()
	local num = math.random(1, 10)
	if num == 4 then 
		emf3event = true
	end
end

local enteredRooms = {}

-- New room touched handler

local function handleRoomTouched(part, roomName)
	local character = part.Parent
	local player = game.Players:GetPlayerFromCharacter(character)
	if player then
		local userId = player.UserId
		local lastRoomName = enteredRooms[userId]

		if not lastRoomName or lastRoomName ~= roomName.Name then
			playerinhauntedroom = true

			local evidence1 = ghostEvidence[1]
			local evidence2 = ghostEvidence[2]
			local evidence3 = ghostEvidence[3]

			print(evidence1)
			print(evidence2)
			print(evidence3)

			if evidence1 == "Freezing Temperatures" or evidence2 == "Freezing Temperatures" or evidence3 == "Freezing Temperatures" then
				shouldGoFreezing = true
				character.Head.BreathPart.Breath.Enabled = true
				ColdBreathLoop = task.spawn(function()
					while isRoomHaunted do
						character.Head.BreathPart.Breath.Enabled = true
						wait(0.25)
						character.Head.BreathPart.Breath.Enabled = false
						wait(Random.new():NextInteger(200,400)/100)
					end
				end)
			end

			if shouldGoFreezing then
				TemperatureEvent:FireClient(player, true, shouldGoFreezing)
			else
				TemperatureEvent:FireClient(player, true, shouldGoFreezing)
			end

			if emf3event == true then
				hauntedRoomEvent:FireClient(player, true, 3)
				print("Fired")
			else
				hauntedRoomEvent:FireClient(player, true, 2)
				print("Fired")
			end
			game.ReplicatedStorage.GWInRoom:FireClient(player, true)
		else
			if ColdBreathLoop then
				task.cancel(ColdBreathLoop)
			end
			game.ReplicatedStorage.GWInRoom:FireClient(player, false)
			playerinhauntedroom = false
			TemperatureEvent:FireClient(player, false, false)
			print(player.Name .. " entered the " .. roomName.Name .. ", it's not haunted.")
			game.ReplicatedStorage.UpdateRoomName:FireClient(player, roomName.Name)
			hauntedRoomEvent:FireClient(player, false, 1)
			print("Fired")
		end

		enteredRooms[userId] = roomName.Name
	end
end

-- Room Touched Functions

local function onLivingRoomTouched(part)
	handleRoomTouched(part, livingRoom)
end

local function onKitchenTouched(part)
	handleRoomTouched(part, Kitchen)
end

local function onBedroom1Touched(part)
	handleRoomTouched(part, Bedroom1)
end

local function onBedroom2Touched(part)
	handleRoomTouched(part, Bedroom2)
end

local function onBedroom3Touched(part)
	handleRoomTouched(part, Bedroom3)
end

local function onBedroom4Touched(part)
	handleRoomTouched(part, Bedroom4)
end

local function onDenTouched(part)
	handleRoomTouched(part, Den)
end

local function onBathroomTouched(part)
	handleRoomTouched(part, Bathroom)
end

local function onHallwayTouched(part)
	handleRoomTouched(part, Hallway)
end

local function onGaradgeTouched(part)
	handleRoomTouched(part, Garadge)
end

local function onBasementTouched(part)
	handleRoomTouched(part, Basement)
end

local function onOutsideTouched(part)
	handleRoomTouched(part, Outside)
end

local function onTruckTouched(part)
	handleRoomTouched(part, Truck)
end

-- Ghost Wriing Decal Handler

local function disabledecal()
	local book = game.Workspace.BookPlacement:FindFirstChild("OpenedBook")
	local paper = book:FindFirstChild("Paper")
	local w1 = paper:FindFirstChild("W1")
	local w2 = paper:FindFirstChild("W2")
	local w3 = paper:FindFirstChild("W3")
	local w4 = paper:FindFirstChild("W4")
	local w5 = paper:FindFirstChild("W5")

	w1.Transparency = 1
	w2.Transparency = 1
	w3.Transparency = 1
	w4.Transparency = 1
	w5.Transparency = 1
end

-- Ghost Writing Event

game.ReplicatedStorage.GhostWriting.OnServerEvent:Connect(function(player, placed)
	local evidence1 = ghostEvidence[1]
	local evidence2 = ghostEvidence[2]
	local evidence3 = ghostEvidence[3]
	if evidence1 == "Ghost Writing" or evidence2 == "Ghost Writing" or evidence3 == "Ghost Writing" then
		local book = game.Workspace.BookPlacement:FindFirstChild("OpenedBook")
		local paper = book:FindFirstChild("Paper")
		local w1 = paper:FindFirstChild("W1")
		local w2 = paper:FindFirstChild("W2")
		local w3 = paper:FindFirstChild("W3")
		local w4 = paper:FindFirstChild("W4")
		local w5 = paper:FindFirstChild("W5")
		local Scribble1 = paper:FindFirstChild("scribble1")
		local Scribble2 = paper:FindFirstChild("scribble2")
		local Scribble3 = paper:FindFirstChild("scribble3")
		local Scribble4 = paper:FindFirstChild("scribble4")
		if placed then
			print("placed in room")
			local waitingtime = math.random(1,10)
			print(waitingtime)
			if placed then
				wait(waitingtime)
				print("waiting time over!")
				local decal = math.random(1,5)
				print(decal)
				if decal == 1 then
					disabledecal()
					Scribble1:Play()
					wait(2)
					w1.Transparency = 0
				elseif decal == 2 then
					disabledecal()
					Scribble4:Play()
					wait(2)
					w2.Transparency = 0
				elseif decal == 3 then
					disabledecal()
					Scribble3:Play()
					wait(2)
					w3.Transparency = 0
				elseif decal == 4 then
					disabledecal()
					Scribble2:Play()
					wait(2)
					w4.Transparency = 0
				elseif decal == 5 then
					disabledecal()
					Scribble4:Play()
					wait(2)
					w5.Transparency = 0
				else
					print("error")
				end
			else
				print("not placed in room")
			end
		end
	else
		print("Not Ghost Writing")
	end
end)

-- ORB evidence handler

game.ReplicatedStorage.GetOrbRoom.OnServerEvent:Connect(function(player)
	local evidence1 = ghostEvidence[1]
	local evidence2 = ghostEvidence[2]
	local evidence3 = ghostEvidence[3]
	if evidence1 == "Ghost Orbs" or evidence2 == "Ghost Orbs" or evidence3 == "Ghost Orbs" then
		print(randomHauntedRoom)
		game.ReplicatedStorage.OrbRoomReceived:FireAllClients(randomHauntedRoom)
	end
end)

emf3eventfinder()