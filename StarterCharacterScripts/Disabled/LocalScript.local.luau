local Player = game.Players.LocalPlayer
local Character = Player.Character
local Humanoid = Character.Humanoid

local Camera = game.Workspace.CurrentCamera

Camera.FieldOfView = 100
Humanoid.CameraOffset = Vector3.new(0, 0, -1)

for _, BasePart in pairs(Character:GetChildren()) do
	if BasePart:IsA("BasePart") and BasePart.Name ~= "Head" then
		BasePart:GetPropertyChangedSignal("LocalTransparencyModifier"):Connect(function()
			BasePart.LocalTransparencyModifier = BasePart.Transparency
		end)
		BasePart.LocalTransparencyModifier = BasePart.Transparency
	end
end