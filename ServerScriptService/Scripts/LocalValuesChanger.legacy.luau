local RP = game.ReplicatedStorage

for i,v in ipairs(game.ServerStorage.ServerValues:GetChildren()) do
	v.Changed:Connect(function(value)
		if RP.ServerValues:FindFirstChild(v.Name) then
			RP.ServerValues[v.Name].Value = value
		end
	end)
end