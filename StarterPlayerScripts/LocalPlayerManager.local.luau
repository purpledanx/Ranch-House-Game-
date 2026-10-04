--Player
local player = game.Players.LocalPlayer
local mouse = player:GetMouse()
local character = player.Character or player.CharacterAdded:Wait()
--Places

local TeleportService = game:GetService("TeleportService")
local ChatService = game:GetService("Chat")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local UserInputService = game:GetService("UserInputService")
local VoiceChat = game:GetService("VoiceChatInternal")

--Modules

local LocalGhostManager = require(ReplicatedStorage.Modules.Managers:WaitForChild("LocalGhostManager"))
local Network = require(ReplicatedStorage.Modules.Util.Network)

--Variables

local GhostData = nil
local GhostRoom = nil

local PlayerInsideGhostRoom = false

--Get Teleport Data
if TeleportService:GetLocalPlayerTeleportData() == nil then
	Network:FireServer("SendPartyId", "D7GHK6")
else
	local TeleportData = TeleportService:GetLocalPlayerTeleportData()
	if TeleportData[2] == true then
		Network:FireServer("SendPartyId", TeleportData[1], TeleportData[2])
	end
	print(TeleportService:GetLocalPlayerTeleportData())
end

--Variables
local PlayerGui = player:WaitForChild("PlayerGui")
local ToolPickupGUI = ReplicatedStorage.Assets.UIs:WaitForChild("ToolPickupGUI")
local zoneNameLabel = PlayerGui:WaitForChild("HUD").Location.TextLabel
local TI = TweenInfo.new(1, Enum.EasingStyle.Linear)
local tweenPlaying = false 
local lastzone = nil
local lastRoomName = nil
local ColdBreathLoop = nil
local vc_enabled = true;
local roomdb = false

local function updateZoneName(newZoneName)
	if newZoneName == "Outside" then
		game:GetService("SoundService").AmbientReverb = Enum.ReverbType.Plain
	elseif newZoneName == "Truck" then
		game:GetService("SoundService").AmbientReverb = Enum.ReverbType.Hallway
	else
		game:GetService("SoundService").AmbientReverb = Enum.ReverbType.LivingRoom
	end
	
	zoneNameLabel.Text = "" .. newZoneName
	zoneNameLabel.TextTransparency = 1

	local tween = TweenService:Create(zoneNameLabel, TI, {TextTransparency = 0.83})
	tween:Play()
	tween.Completed:Wait()
	tweenPlaying = false
end

local function ToolPickupGuiClicked()
	if mouse.Target then
		if mouse.Target.Parent:GetAttribute("tool") then
			if mouse.Target.Parent then
				Network:FireServer("PickupItem", mouse.Target.Parent)
			end
		end
	end
end

local function RoomTouched(roomName)
	if lastRoomName ~= roomName and not roomdb then
		roomdb = true
		if GhostRoom == roomName then
			PlayerInsideGhostRoom = true
		else
			PlayerInsideGhostRoom = false
		end
		task.spawn(function()
			updateZoneName(roomName)
		end)
		
		Network:FireServer("PlayerLocation", PlayerInsideGhostRoom)
		Network:FireServer("ColdBreath", lastRoomName, roomName)
		
		lastRoomName = roomName
		roomdb = false
	end
end

local function findFirstAncestorWithToolAttribute(instance: Instance): Instance?
	if not instance then return nil end

	local current: Instance? = instance
	while current do
		if current:GetAttribute("tool") ~= nil then
			return current
		end
		current = current.Parent
	end

	return nil
end

local function InputChanged()
	if mouse.Target then
		local tool = findFirstAncestorWithToolAttribute(mouse.Target)
		if tool then
			if tool.Name == "EMF" then
				ToolPickupGUI.Enabled = true
				ToolPickupGUI.Adornee = tool.Hover
			elseif tool.Name == "Spirit Box" then
				ToolPickupGUI.Enabled = true
				ToolPickupGUI.Adornee = tool.Hover
			elseif tool.Name == "Thermometer" then
				ToolPickupGUI.Enabled = true
				ToolPickupGUI.Adornee = tool.Hover
			else
				ToolPickupGUI.Enabled = true
				ToolPickupGUI.Adornee = tool
			end
		else
			ToolPickupGUI.Enabled = false
			ToolPickupGUI.Adornee = nil
		end
	end
end

local function InputEnded(input,isProcessed)
	if input.KeyCode == Enum.KeyCode.E and not isProcessed then
		if mouse.Target then
			if mouse.Target.Parent:GetAttribute("tool") then
				player.Character:FindFirstChild("Humanoid"):UnequipTools()
				print("Target is: "..mouse.Target.Parent.Name)
				Network:FireServer("PickupItem", mouse.Target, mouse.Hit)
			end
		end
	end
	
	if not isProcessed and input.KeyCode == Enum.KeyCode.G and player.Character:FindFirstChildOfClass("Tool") then
		Network:FireServer("DroppedTool", player.Character:FindFirstChildOfClass("Tool"))
	end
	
	if input.KeyCode == Enum.KeyCode["T"] then 
		vc_enabled = (not vc_enabled)
		print("voice "..tostring(vc_enabled))
		VoiceChat:PublishPause(vc_enabled)
	end
end

local function SetBubbleChatSettings()
	ChatService:SetBubbleChatSettings({Transparency = 1, VerticalStudsOffset = 1.5, BackgroundColor3 = Color3.fromRGB(180, 210, 228)}) 
end

local function DoorCollision(door:MeshPart)
	door.CanCollide = true
end 

Network:BindEvents({
	GhostData = {
		MatchParams = {},
		function(player, data)
			print(data)
			GhostData = data
			GhostRoom = data.Room
		end
	}
})

UserInputService.InputEnded:Connect(InputEnded)

--UserInputService.InputBegan:Connect(InputStarted)

UserInputService.InputChanged:Connect(InputChanged)

ToolPickupGUI.TextButton.MouseButton1Click:Connect(ToolPickupGuiClicked)

local RoomRegions = game.Workspace.House.RoomRegions

-- Cache each region's CFrame and half-size once (regions are static)
local cachedRegions = {}
for _, region: Part in ipairs(RoomRegions:GetChildren()) do
	table.insert(cachedRegions, {
		name = region.Name,
		cframe = region.CFrame,
		halfSize = region.Size / 2,
	})
end

-- Cache torso reference, refresh on respawn
local torso = nil
local function refreshTorso()
	local char = player.Character
	if not char then return end
	torso = char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")
end
refreshTorso()
player.CharacterAdded:Connect(function()
	task.wait(0.5)
	refreshTorso()
end)

task.spawn(function()
	while task.wait(0.1) do
		if torso then
			local pos = torso.Position
			for _, region in ipairs(cachedRegions) do
				local localPos = region.cframe:PointToObjectSpace(pos)
				local half = region.halfSize
				if localPos.X > -half.X and localPos.X < half.X
					and localPos.Y > -half.Y and localPos.Y < half.Y
					and localPos.Z > -half.Z and localPos.Z < half.Z then
					RoomTouched(region.name)
					break
				end
			end
		end
	end
end)