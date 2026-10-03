local module = {}
local TS = game:GetService("TweenService")
local TI = TweenInfo.new(0.7)
local TIH = TweenInfo.new(0.2)
local CD = false 
local Network = require(game.ReplicatedStorage.Modules.Util.Network)
local Doors = game.Workspace.House.Doors
local once = false

for i,v in ipairs(Doors:GetChildren()) do
	local Prox:ProximityPrompt = Instance.new("ProximityPrompt")
	if v.Name == "D8" then
		if v:IsA("Model") and v.Model1.Door.FrontHandle then
			Prox.Parent = v.Model1.Door.FrontHandle
			Prox.RequiresLineOfSight = false
			Prox.ActionText = "Open"
			Prox.MaxActivationDistance = 4
			Prox.Triggered:Connect(function()
				if Prox.ActionText == "Open" then
					if not once then
						game.ServerStorage.BindableEvents.DoorOpen:Fire()
						once = true
					end
					module.OpenDoor(v.Name)
				else
					module.CloseDoor(v.Name)
				end
			end)
		end
	else
		if v:IsA("Model") and v.Model1.Door.Prompt then
			Prox.Parent = v.Model1.Door.Prompt
			Prox.RequiresLineOfSight = false
			Prox.ActionText = "Open"
			Prox.MaxActivationDistance = 4
			Prox.Triggered:Connect(function()
				if Prox.ActionText == "Open" then
					module.OpenDoor(v.Name)
				else
					module.CloseDoor(v.Name)
				end
			end)
		end
	end
end

function module.OpenDoor(doorname:string)
	if not CD then
		local door = Doors:FindFirstChild(doorname)
		if door then
			if door.Name == "D8" then
				CD = true
				local Hinge = door.Model1.Door.Hinge
				local HandleHingeF = door.Model1.Door.Model.BackHandle
				local prompt:ProximityPrompt = door.Model1.Door.FrontHandle:FindFirstChildOfClass("ProximityPrompt")

				local HandleDownF = {}
				HandleDownF.CFrame = HandleHingeF.CFrame * CFrame.Angles(math.rad(-40), 0, 0)
				local OpenDoor = {}
				OpenDoor.CFrame = Hinge.CFrame * CFrame.Angles(0, math.rad(90), 0)
				prompt.ActionText = "Close"

				local opensound = Instance.new("Sound",prompt.Parent)
				opensound.SoundId = "rbxassetid://14215966565"
				opensound.RollOffMinDistance = 5
				opensound.RollOffMaxDistance = 20
				opensound:Play()
				game.Debris:AddItem(opensound,1)

				HandleHingeF.Anchored = true
				local tween = TS:Create(HandleHingeF, TIH, HandleDownF)
				tween:Play()
				HandleHingeF.Anchored = false
				local tween = TS:Create(Hinge, TI, OpenDoor)
				tween:Play()
				tween.Completed:Wait()
				CD = false
			else
				CD = true
				local Hinge = door.Model1.Hinge
				local HandleHingeF = door.Model1.HandleHingeF
				local HandleHingeB = door.Model1.HandleHingeB
				local prompt:ProximityPrompt = door.Model1.Door.Prompt:FindFirstChildOfClass("ProximityPrompt")

				local HandleDownF = {}
				HandleDownF.CFrame = HandleHingeF.CFrame * CFrame.Angles(math.rad(-40), 0, 0)
				local HandleDownB = {}
				HandleDownB.CFrame = HandleHingeB.CFrame * CFrame.Angles(math.rad(40), 0, 0)
				local OpenDoor = {}
				OpenDoor.CFrame = Hinge.CFrame * CFrame.Angles(0, math.rad(90), 0)
				prompt.ActionText = "Close"

				local opensound = Instance.new("Sound",prompt.Parent)
				opensound.SoundId = "rbxassetid://14215966565"
				opensound.RollOffMinDistance = 5
				opensound.RollOffMaxDistance = 20
				opensound:Play()
				game.Debris:AddItem(opensound,1)

				HandleHingeF.Anchored = true
				HandleHingeB.Anchored = true
				local tween = TS:Create(HandleHingeF, TIH, HandleDownF)
				tween:Play()
				local tween2 = TS:Create(HandleHingeB, TIH, HandleDownB)
				tween2:Play()
				tween2.Completed:Wait()
				HandleHingeF.Anchored = false
				HandleHingeB.Anchored = false
				local tween = TS:Create(Hinge, TI, OpenDoor)
				tween:Play()
				tween.Completed:Wait()
				CD = false
			end
		else
			warn("Door not found")
		end
	end
end

function module.CloseDoor(doorname:string)
	if not CD then
		local door = Doors:FindFirstChild(doorname)
		if door then
			if door.Name == "D8" then
				CD = true
				local Hinge = door.Model1.Door.Hinge
				local HandleHingeF = door.Model1.Door.Model.BackHandle
				local prompt:ProximityPrompt = door.Model1.Door.FrontHandle:FindFirstChildOfClass("ProximityPrompt")

				local HandleDownF = {}
				HandleDownF.CFrame = HandleHingeF.CFrame * CFrame.Angles(math.rad(-40), 0, 0)
				local CloseDoor = {}
				CloseDoor.CFrame = Hinge.CFrame * CFrame.Angles(0, 0, 0)
				prompt.ActionText = "Open"

				HandleHingeF.Anchored = true
				local tween = TS:Create(HandleHingeF, TIH, HandleDownF)
				tween:Play()
				HandleHingeF.Anchored = false
				local tween = TS:Create(Hinge, TI, CloseDoor)
				tween:Play()
				task.wait(0.5)
				local closesound = Instance.new("Sound",prompt.Parent)
				closesound.SoundId = "rbxassetid://14216042454"
				closesound.RollOffMinDistance = 5
				closesound.RollOffMaxDistance = 20
				closesound:Play()
				game.Debris:AddItem(closesound,1)
				tween.Completed:Wait()
				CD = false
			else
				CD = true
				local Hinge = door.Model1.Hinge
				local HandleHingeF = door.Model1.HandleHingeF
				local HandleHingeB = door.Model1.HandleHingeB
				local prompt:ProximityPrompt = door.Model1.Door.Prompt:FindFirstChildOfClass("ProximityPrompt")

				local HandleDownF = {}
				HandleDownF.CFrame = HandleHingeF.CFrame * CFrame.Angles(math.rad(-40), 0, 0)
				local HandleDownB = {}
				HandleDownB.CFrame = HandleHingeB.CFrame * CFrame.Angles(math.rad(40), 0, 0)
				local CloseDoor = {}
				CloseDoor.CFrame = Hinge.CFrame * CFrame.Angles(0, 0, 0)
				prompt.ActionText = "Open"

				HandleHingeF.Anchored = true
				HandleHingeB.Anchored = true
				local tween = TS:Create(HandleHingeF, TIH, HandleDownF)
				tween:Play()
				local tween2 = TS:Create(HandleHingeB, TIH, HandleDownB)
				tween2:Play()
				tween2.Completed:Wait()
				HandleHingeF.Anchored = false
				HandleHingeB.Anchored = false
				local tween = TS:Create(Hinge, TI, CloseDoor)
				tween:Play()
				task.wait(0.5)
				local closesound = Instance.new("Sound",prompt.Parent)
				closesound.SoundId = "rbxassetid://14216042454"
				closesound.RollOffMinDistance = 5
				closesound.RollOffMaxDistance = 20
				closesound:Play()
				game.Debris:AddItem(closesound,1)
				tween.Completed:Wait()
				CD = false
			end
		else
			warn("Door not found")
		end
	end
end

return module
