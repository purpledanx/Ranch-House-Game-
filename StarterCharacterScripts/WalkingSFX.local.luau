local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MaterialSounds = 
	{
		[Enum.Material.Grass] = "rbxassetid://507863105",
		[Enum.Material.Metal] = "rbxassetid://379482691",
		[Enum.Material.DiamondPlate] = "rbxassetid://944089664",		
		[Enum.Material.Pebble] = "rbxassetid://944090255",
		[Enum.Material.Wood] = "rbxassetid://177940988",
		[Enum.Material.WoodPlanks] = "rbxassetid://211987063",
		[Enum.Material.Plastic] = "rbxassetid://944075408",
		[Enum.Material.SmoothPlastic] = "rbxassetid://944075408",
		[Enum.Material.Sand] = "rbxassetid://944090255",
		[Enum.Material.Brick] = "rbxassetid://4981969796",
		[Enum.Material.Cobblestone] = "rbxassetid://4981969796",
		[Enum.Material.Concrete] = "rbxassetid://944075408",
		[Enum.Material.CorrodedMetal] = "rbxassetid://4981969796",
		[Enum.Material.Fabric] = "rbxassetid://133705377",
		[Enum.Material.Foil] = "rbxassetid://4981969796",
		[Enum.Material.ForceField] = "rbxassetid://4981969796",
		[Enum.Material.Glass] = "rbxassetid://944075408",
		[Enum.Material.Granite] = "rbxassetid://944075408",
		[Enum.Material.Ice] = "rbxassetid://4981969796",
		[Enum.Material.Marble] = "rbxassetid://944075408",
		[Enum.Material.Neon] = "rbxassetid://4981969796",
		[Enum.Material.Slate] = "rbxassetid://944075408",
	}
local FootStepModule = require(ReplicatedStorage.Modules.Sounds.FootstepModule)

local player = game.Players.LocalPlayer
local Character = player.Character
local Humanoid:Humanoid = Character:WaitForChild("Humanoid")
local HumanoidRootPart = Character:WaitForChild("HumanoidRootPart")
local FootStepsSound = HumanoidRootPart:WaitForChild("Running")
FootStepModule:CreateSoundGroup(game.SoundService,"FootSteps")

local FloorMaterial = nil
FootStepsSound.SoundId = ""

local SoundGroup = Instance.new("SoundGroup",game:GetService("SoundService"))
SoundGroup.Name = "Walking"
SoundGroup.Volume = 1

local function FootStepSound()
	FloorMaterial = Humanoid.FloorMaterial
	local soundlist = FootStepModule:GetTableFromMaterial(FloorMaterial)
	if soundlist and #soundlist ~= nil then
		task.spawn(function()
			local Sound:Sound = Instance.new("Sound",Character.PrimaryPart)
			Sound.SoundGroup = SoundGroup
			Sound.RollOffMaxDistance = 15
			Sound.RollOffMinDistance = 1
			Sound.Volume = 0.3
			Sound.Name = FloorMaterial.Name
			Sound.SoundId = soundlist[Random.new():NextInteger(1,#soundlist)]
			Sound:Play()
			Sound.Ended:Wait()
			Sound:Destroy()
		end)
	end
end

ReplicatedStorage.BindableEvents.Footstep.Event:Connect(FootStepSound)