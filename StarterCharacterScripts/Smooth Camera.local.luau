-- Services
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local InputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

--Modules
local Network = require(ReplicatedStorage.Modules.Util.Network)

-- Variables
local CanViewBody = true
local CinematicMode = false
local Running = true
local FreeMouse = false
local MoveForward, MoveLeft, MoveBack, MoveRight, ShiftPressed = false, false, false, false, false
local PKeyPressed = false

local MouseToggleSettings = {allowed = true; activationKey = Enum.KeyCode.V;}

local WalkSpeeds = {
	enabled = false; -- Walk Speed Directions Cause Why Not :3
	walkSpeed = 6;
	backwardSpeed = 4;
	sideSpeed = 5;
	diagonalSpeed = 5;
	runSpeed = 0;
	runningFOV = 85;
}

local KeyBindings = {
	[Enum.KeyCode.W] = function() MoveForward = true end,
	[Enum.KeyCode.A] = function() MoveLeft = true end,
	[Enum.KeyCode.S] = function() MoveBack = true end,
	[Enum.KeyCode.D] = function() MoveRight = true end,
	[Enum.KeyCode.LeftShift] = function() ShiftPressed = true end,
	[Enum.KeyCode.P] = function() PKeyPressed = true end
}

local MouseSensitivity = 1.2
local Smoothness = 0.3
local FieldOfView = 90
local EasingTime = 0.06
local Counter, Dampener = 1, 3
local AllowedRange, MaxBlur = 15, 150

local Camera = game.Workspace.CurrentCamera
Camera.CameraType = Enum.CameraType.Scriptable
local PreviousLookVector = Camera.CFrame.LookVector

local HeadOffset = CFrame.new(0,1,0.5)
local CamPos, TargetCamPos = Camera.CoordinateFrame.p, Camera.CoordinateFrame.p
local AngleX, TargetAngleX = 0, 0
local AngleY, TargetAngleY = 0, 0

local CameraBlurInfo = TweenInfo.new(0.25, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)

local Player = Players.LocalPlayer
local Character = Player.Character or Player.CharacterAdded:Wait()
local Mouse = Player:GetMouse()
Mouse.Icon = "http://www.roblox.com/asset/?id=9947313248"
local Neck = Character.Head:FindFirstChild("Neck", true)
local Humanoid = Character:FindFirstChildOfClass("Humanoid")
local HumanoidRootPart = Character:FindFirstChild("HumanoidRootPart")

local YOffset = Neck.C0.Y
local CFNew, CFAng = CFrame.new, CFrame.Angles
local asin = math.asin

local BlurEffect = game.Lighting:WaitForChild("Blur")

local Part = nil
local Coroutine = nil
local Head = Character:WaitForChild("Head")
local DefaultFOV = FieldOfView

Humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)
Humanoid.AutoRotate = false

local Bobbing, Func1, Func2, Func3, Func4, Val, Val2 = nil, 0, 0, 0, 0, 0, 0
local Int, Int2 = 10, 10
local Vect3 = Vector3.new()

UserSettings().GameSettings.RotationType = Enum.RotationType.CameraRelative

-- Functions
local function DegreesToDot() 
	return math.cos(math.rad(AllowedRange)) 
end

local function Lerp(a, b, t)
	return a * (1-t) + (b*t)
end

function UpdateCharacterTransparency()
	for _, v in ipairs(Character:GetDescendants()) do
		if CanViewBody then
			if v.Name == "Head" and v.Parent == Character then
				v.LocalTransparencyModifier = 1
				v.CanCollide = false
			end
		else
			if v:IsA("Part") or v:IsA("UnionOperation") or v:IsA("MeshPart") then
				v.LocalTransparencyModifier = 1
				v.CanCollide = false
			end
		end
		if v:IsA("Decal") then
			v:Destroy()
		end
		if v:IsA("Accessory") then
			v:FindFirstChild("Handle").LocalTransparencyModifier = 1
			v:FindFirstChild("Handle").CanCollide = false
		end
		if v:IsA("Hat") then
			v:FindFirstChild("Handle").LocalTransparencyModifier = 1
			v:FindFirstChild("Handle").CanCollide = false
		end
	end
end

local function UpdateAngles(delta)
	local adjustedDelta = Vector2.new(delta.X / MouseSensitivity, delta.Y / MouseSensitivity) * Smoothness
	local newX = TargetAngleX - adjustedDelta.Y
	TargetAngleX = math.clamp(newX, -80, 80)
	TargetAngleY = (TargetAngleY - adjustedDelta.X) % 360
	
	adjustedDelta = nil
	newX = nil
end

local function UpdateNeck(CameraDirection, IsR15)
	local CommonC0 = CFNew(0, YOffset, 0)
	if IsR15 then
		Neck.C0 = CommonC0 * CFAng(0, -asin(CameraDirection.X), 0) * CFAng(asin(CameraDirection.Y), 0, 0)
	else
		Neck.C0 = CommonC0 * CFAng(3 * math.pi / 2, 0, math.pi) * CFAng(0, 0, -asin(CameraDirection.X)) * CFAng(-asin(CameraDirection.Y), 0, 0)
	end
end

local function UpdateCameraWhileRunning()
	CamPos = CamPos + (TargetCamPos - CamPos) * 0.28
	AngleX = AngleX + (TargetAngleX - AngleX) * 0.35
	local Dist = (TargetAngleY - AngleY + 180) % 360 - 180
	AngleY = (AngleY + Dist * 0.35) % 360

	Camera.CoordinateFrame = CFrame.new(Head.Position)
		* CFrame.Angles(0, math.rad(AngleY), 0)
		* CFrame.Angles(math.rad(AngleX), 0, 0)
		* HeadOffset
	
	HumanoidRootPart.CFrame = CFrame.new(HumanoidRootPart.CFrame.Position) * CFrame.Angles(0, math.rad(AngleY), 0)
	UpdateCharacterTransparency()
end

local function HandleHeadBobbing(deltaTime)
	deltaTime = deltaTime * 30
	if Humanoid.Health <= 0 then
		Bobbing:Disconnect()
		return
	end
	local RootMagnitude = HumanoidRootPart and Vector3.new(HumanoidRootPart.Velocity.X, 0, HumanoidRootPart.Velocity.Z).Magnitude or 0
	local CalcRootMagnitude = math.min(RootMagnitude, 50)
	if deltaTime > 3 then
		Func1 = 0
		Func2 = 0
	else
		Func1 = Lerp(Func1, math.cos(tick() * 0.5 * math.random(10, 15)) * (math.random(5, 20) / 200) * deltaTime, 0.05 * deltaTime)
		Func2 = Lerp(Func2, math.cos(tick() * 0.5 * math.random(5, 10)) * (math.random(2, 10) / 200) * deltaTime, 0.05 * deltaTime)
	end
	Camera.CFrame = Camera.CFrame 
		* CFrame.fromEulerAnglesXYZ(0, 0, math.rad(Func3)) 
		* CFrame.fromEulerAnglesXYZ(math.rad(Func4 * deltaTime), math.rad(Val * deltaTime), Val2) 
		* CFrame.Angles(0, 0, math.rad(Func4 * deltaTime * (CalcRootMagnitude / 5))) 
		* CFrame.fromEulerAnglesXYZ(math.rad(Func1), math.rad(Func2), math.rad(Func2 * 10))
	Val2 = math.clamp(Lerp(Val2, -Camera.CFrame:VectorToObjectSpace((HumanoidRootPart.Velocity or Vector3.new()) / math.max(Humanoid.WalkSpeed, 0.01)).X * 0.08, 0.1 * deltaTime), -0.35, 0.2)
	Func3 = Lerp(Func3, math.clamp(InputService:GetMouseDelta().X, -5, 5), 0.25 * deltaTime)
	Func4 = Lerp(Func4, math.sin(tick() * Int) / 5 * math.min(1, Int2 / 10), 0.25 * deltaTime)
	if RootMagnitude > 1 then
		Val = Lerp(Val, math.cos(tick() * 0.5 * Int) * (Int / 200), 0.25 * deltaTime)
	else
		Val = Lerp(Val, 0, 0.05 * deltaTime)
	end
	if RootMagnitude > 12 then
		Int = 20
		Int2 = 18
	elseif RootMagnitude > 0.1 then
		Int = 6
		Int2 = 14
	else
		Int2 = 0
	end
	Vect3 = Lerp(Vect3, Camera.CFrame.LookVector, 0.125 * deltaTime)
end

local function ToggleFreeMouse(inputObject)
	if inputObject.KeyCode == MouseToggleSettings.activationKey and inputObject.UserInputType == Enum.UserInputType.Keyboard then
		FreeMouse = not FreeMouse and MouseToggleSettings.allowed or false
	end
end

local function ToggleCinematicMode()
	if ShiftPressed and PKeyPressed then
		if not CinematicMode then
			CinematicMode = true
			Part = Instance.new("Part", Camera)
			Part.Size = Vector3.new(1, 1, 1)
			Part.Anchored = true
			Part.CanCollide = false
			Part.Transparency = 1

			Coroutine = task.spawn(function()
				while Part do
					task.wait()
					Part.CFrame = Camera.CFrame
				end
			end)

			local light = Instance.new("PointLight", Part)
			light.Color = Color3.new(1, 1, 1)
			light.Brightness = 3
			light.Range = 60
		else
			CinematicMode = false
			if Part then
				Part:Destroy()
				Part = nil
			end
			if Coroutine then
				task.cancel(Coroutine)
				Coroutine = nil
			end
		end
	end
end

local function HandleWalkSpeed()
	local NewWalkSpeed = WalkSpeeds.walkSpeed
	if MoveForward and not MoveBack then
		NewWalkSpeed = ShiftPressed and WalkSpeeds.runSpeed or WalkSpeeds.walkSpeed
		if MoveLeft or MoveRight then
			NewWalkSpeed = WalkSpeeds.diagonalSpeed
		end
	elseif MoveBack and not MoveForward then
		NewWalkSpeed = ShiftPressed and WalkSpeeds.runSpeed or WalkSpeeds.backwardSpeed
		if MoveLeft or MoveRight then
			NewWalkSpeed = WalkSpeeds.backwardSpeed - (WalkSpeeds.diagonalSpeed - WalkSpeeds.backwardSpeed)
		end
	elseif MoveLeft or MoveRight then
		NewWalkSpeed = WalkSpeeds.sideSpeed
		if ShiftPressed then
			NewWalkSpeed = WalkSpeeds.runSpeed
		end
	end
	Humanoid.WalkSpeed = Lerp(Humanoid.WalkSpeed, NewWalkSpeed, EasingTime)
	FieldOfView = Lerp(FieldOfView, ShiftPressed and WalkSpeeds.runningFOV or DefaultFOV, EasingTime)
end

local function UpdateBlurEffect()
	local DotProduct = PreviousLookVector:Dot(Camera.CFrame.LookVector)
	local BlurAmount = (1 - DotProduct) * (MaxBlur / 2)
	TweenService:Create(BlurEffect, CameraBlurInfo, {Size = (DotProduct >= DegreesToDot()) and 0 or BlurAmount}):Play()
end

-- Code
InputService.InputBegan:Connect(function(inputObject)
	if inputObject.UserInputType == Enum.UserInputType.Keyboard then
		ToggleFreeMouse(inputObject)

		local action = KeyBindings[inputObject.KeyCode]
		if action then
			action()
		end

		--ToggleCinematicMode()
	end
end)

InputService.InputEnded:Connect(function(inputObject)
	if inputObject.UserInputType == Enum.UserInputType.Keyboard then
		local action = KeyBindings[inputObject.KeyCode]
		if action then
			action()
		end
	end
end)

if InputService.TouchEnabled then
	MouseSensitivity = 0.7
	InputService.TouchMoved:Connect(function(inputObject, gameProcessedEvent)
		if inputObject.UserInputType == Enum.UserInputType.Touch and not gameProcessedEvent then
			UpdateAngles(inputObject.Delta)
		end
	end)
else
	InputService.InputChanged:Connect(function(inputObject)
		if inputObject.UserInputType == Enum.UserInputType.MouseMovement then
			UpdateAngles(inputObject.Delta)
		end
	end)
end

Bobbing = RunService.RenderStepped:Connect(HandleHeadBobbing)

local function UpdatePlayersTorso(player, neckC0, waistC0, NeckPosition)
	local character = player.Character
	if not character then return end

	local neck = character.Head:FindFirstChild("Neck", true)
	local waist = character:FindFirstChild("Waist", true) 

	if waist and waistC0 then
		TweenService:Create(waist, TweenInfo.new(0.1), {C0 = NeckPosition}):Play()
	end
end

local function UpdateNeckAndWaist(CameraDirection, IsR15)
	local Waist = Character:WaitForChild("UpperTorso"):FindFirstChild("Waist", true)
	local WaistMultiplier = CFAng(asin(CameraDirection.Y), 0, 0)
	
	Network:FireServer("Look", Neck.C0, Waist and Waist.C0 or nil, WaistMultiplier)
end

RunService.RenderStepped:Connect(function()
	local CameraDirection = HumanoidRootPart.CFrame:ToObjectSpace(Camera.CFrame).LookVector
	local RigType = Character.Humanoid.RigType
	local IsR15 = RigType == Enum.HumanoidRigType.R15

	if Neck then
		UpdateNeck(CameraDirection, IsR15)
	end

	if not CinematicMode then
		if Running then
			UpdateCameraWhileRunning()
		else
			InputService.MouseBehavior = Enum.MouseBehavior.Default
		end

		Running = (Camera.Focus.p - Camera.CoordinateFrame.p).Magnitude >= 1

		if FreeMouse or (InputService.TouchEnabled or not MouseToggleSettings.allowed) then
			InputService.MouseBehavior = Enum.MouseBehavior.Default
		elseif not InputService.TouchEnabled then
			InputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		end

		Camera.FieldOfView = FieldOfView

		if WalkSpeeds.enabled then
			HandleWalkSpeed()
		end
	end

	if Counter % Dampener == 0 then
		UpdateBlurEffect()
	end

	PreviousLookVector = Camera.CFrame.LookVector
	Counter = Counter + 1
	
	UpdateNeckAndWaist(CameraDirection, IsR15)
end)

Network:BindEvents({
	Look = {
		MatchParams = {},
		function(player, neckC0, waistC0, NeckPosition)
			if player.UserId ~= Player.UserId then
				UpdatePlayersTorso(player, neckC0, waistC0, NeckPosition)
			end
		end
	}
})