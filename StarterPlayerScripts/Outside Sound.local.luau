local player = game.Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Info = TweenInfo.new(1,Enum.EasingStyle.Sine)
task.wait(0.4)
local BaseVolume = game.Workspace.Sounds["Scary Forest Ambience"].Volume
local locationUI = player.PlayerGui.HUD.Location

RunService.RenderStepped:Connect(function()
	local Distance = (game.Workspace.House.RoomRegions.GARAGE.Position-character.PrimaryPart.Position).Magnitude
	if locationUI.TextLabel.Text == "OUTSIDE" then
		local tween = TweenService:Create(game.Workspace.Sounds["Scary Forest Ambience"],Info,{Volume = BaseVolume * Distance/100})
		tween:Play()
		--game.Workspace.Sounds["Scary Forest Ambience"].Volume = BaseVolume * Distance/100
	elseif locationUI.TextLabel.Text == "TRUCK" and game.ReplicatedStorage.ServerValues.GameStarted.Value then
		local tween = TweenService:Create(game.Workspace.Sounds["Scary Forest Ambience"],Info,{Volume = BaseVolume * Distance/300})
		tween:Play()
		--game.Workspace.Sounds["Scary Forest Ambience"].Volume = BaseVolume * Distance/300
	else
		local tween = TweenService:Create(game.Workspace.Sounds["Scary Forest Ambience"],Info,{Volume = 0})
		tween:Play()
		--game.Workspace.Sounds["Scary Forest Ambience"].Volume = 0
	end
end)