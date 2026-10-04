local module = {}
local TS = game:GetService("TweenService")
local TI = TweenInfo.new(0.7)
local TIH = TweenInfo.new(0.2)
local Network = require(game.ReplicatedStorage.Modules.Util.Network)
local Doors = game.Workspace.House.Doors

-- Per-door state tracking
local doorStates = {}

local function playSound(parent, soundId)
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = 0.5
	sound.Parent = parent
	sound:Play()
	game.Debris:AddItem(sound, 2)
end

for i,v in ipairs(Doors:GetChildren()) do
	local state = {
		cd = false,
		open = false,
		once = false,
		prompt = nil,
		hinge = nil,
		handleF = nil,
		handleB = nil,
		isD8 = (v.Name == "D8"),
	}

	local Prox = Instance.new("ProximityPrompt")
	Prox.RequiresLineOfSight = false
	Prox.ActionText = "Open"
	Prox.MaxActivationDistance = 4

	if state.isD8 then
		if v:IsA("Model") and v.Model1.Door.FrontHandle then
			Prox.Parent = v.Model1.Door.FrontHandle
			state.hinge = v.Model1.Door.Hinge
			state.handleF = v.Model1.Door.Model.BackHandle
			state.prompt = Prox
			state.hingeOrigin = state.hinge.CFrame
			state.handleFOrigin = state.handleF.CFrame
		end
	else
		if v:IsA("Model") and v.Model1.Door.Prompt then
			Prox.Parent = v.Model1.Door.Prompt
			state.hinge = v.Model1.Hinge
			state.handleF = v.Model1.HandleHingeF
			state.handleB = v.Model1.HandleHingeB
			state.prompt = Prox
			state.hingeOrigin = state.hinge.CFrame
			state.handleFOrigin = state.handleF.CFrame
			state.handleBOrigin = state.handleB.CFrame
		end
	end

	if state.prompt then
		Prox.Triggered:Connect(function()
			if state.cd then return end
			if not state.open then
				if state.isD8 and not state.once then
					game.ServerStorage.BindableEvents.DoorOpen:Fire()
					state.once = true
				end
				module.OpenDoor(v.Name)
			else
				module.CloseDoor(v.Name)
			end
		end)
	end

	doorStates[v.Name] = state
end

function module.OpenDoor(doorname:string)
	local state = doorStates[doorname]
	if not state or state.cd then return end

	local door = Doors:FindFirstChild(doorname)
	if not door then warn("Door not found") return end

	state.cd = true
	local Hinge = state.hinge
	local HandleHingeF = state.handleF
	local prompt = state.prompt

	local HandleDownF = {CFrame = HandleHingeF.CFrame * CFrame.Angles(math.rad(-40), 0, 0)}
	local OpenDoor = {CFrame = state.hingeOrigin * CFrame.Angles(0, math.rad(90), 0)}

	prompt.ActionText = "Close"
	playSound(prompt.Parent, "rbxassetid://14215966565")

	HandleHingeF.Anchored = true
	local handleTween = TS:Create(HandleHingeF, TIH, HandleDownF)
	handleTween:Play()
	handleTween.Completed:Wait()
	HandleHingeF.Anchored = false

	if state.handleB then
		local HandleHingeB = state.handleB
		local HandleDownB = {CFrame = HandleHingeB.CFrame * CFrame.Angles(math.rad(40), 0, 0)}
		HandleHingeB.Anchored = true
		local handleTweenB = TS:Create(HandleHingeB, TIH, HandleDownB)
		handleTweenB:Play()
		handleTweenB.Completed:Wait()
		HandleHingeB.Anchored = false
	end

	local doorTween = TS:Create(Hinge, TI, OpenDoor)
	doorTween:Play()
	doorTween.Completed:Wait()

	state.open = true
	state.cd = false
end

function module.CloseDoor(doorname:string)
	local state = doorStates[doorname]
	if not state or state.cd then return end

	local door = Doors:FindFirstChild(doorname)
	if not door then warn("Door not found") return end

	state.cd = true
	local Hinge = state.hinge
	local HandleHingeF = state.handleF
	local prompt = state.prompt

	local CloseDoor = {CFrame = state.hingeOrigin}

	prompt.ActionText = "Open"
	playSound(prompt.Parent, "rbxassetid://14216042454")

	-- Close the door first (handles move with it since they're welded)
	local doorTween = TS:Create(Hinge, TI, CloseDoor)
	doorTween:Play()
	doorTween.Completed:Wait()

	-- Now return handles to their neutral position
	HandleHingeF.Anchored = true
	local HandleReturnF = {CFrame = state.handleFOrigin}
	local handleTween = TS:Create(HandleHingeF, TIH, HandleReturnF)
	handleTween:Play()
	handleTween.Completed:Wait()
	HandleHingeF.Anchored = false

	if state.handleB then
		local HandleHingeB = state.handleB
		HandleHingeB.Anchored = true
		local HandleReturnB = {CFrame = state.handleBOrigin}
		local handleTweenB = TS:Create(HandleHingeB, TIH, HandleReturnB)
		handleTweenB:Play()
		handleTweenB.Completed:Wait()
		HandleHingeB.Anchored = false
	end

	state.open = false
	state.cd = false
end

return module
