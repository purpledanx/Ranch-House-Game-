local tweenService = game:GetService("TweenService")

local Camera = workspace.CurrentCamera
local Player = game.Players.LocalPlayer

local Character = Player.Character
local Root = Character:WaitForChild("HumanoidRootPart")
local Neck = Character:FindFirstChild("Neck", true)

game.ReplicatedStorage.RemoteEvents:WaitForChild("Look").OnClientEvent:Connect(function(otherPlayer, neckCFrame)
	local Neck = otherPlayer.Character:FindFirstChild("Neck", true)
	
	if Neck then
		print("Playing")
		tweenService:Create(Neck, TweenInfo.new(0.5, Enum.EasingStyle.Cubic, Enum.EasingDirection.InOut, 0, false, 0), {C0 = neckCFrame}):Play()
	end
end)

while task.wait(0.5) do
	game.ReplicatedStorage.RemoteEvents:WaitForChild("Look"):FireServer(Neck.C0)
end