local module = {}
local Lights = game.Workspace.House.Lights
local LightSwitches = game.Workspace.House.LightSwitches
local TI = TweenInfo.new(0.15)
local TS = game:GetService("TweenService")
local LightList = {
	[LightSwitches.BD1LightSwitch] = {Lights.BD1Light1,Lights.BD1Light2},
	[LightSwitches.BD2LightSwitch] = {Lights.BD2Light1,Lights.BD2Light2},
	[LightSwitches.BD3LightSwitch] = {Lights.BD3Light1,Lights.BD3Light2},
	[LightSwitches.BD4LightSwitch] = {Lights.BD4Light1,Lights.BD4Light2},
	[LightSwitches.Bathroom1LightSwitch] = {Lights.Bathroom1Light,Lights.Bathroom2Light},
	[LightSwitches.DenLightSwitch] = {Lights.DenLight},
	[LightSwitches.HallwayLightSwitch] = {Lights.HallwayLight1,Lights.HallwayLight2,Lights.HallwayLight3,Lights.HallwayLight4},
	[LightSwitches.KitchenLightSwitch] = {Lights.KitchenLight1,Lights.KitchenLight2},
	[LightSwitches.LivingRoomLightSwitch] = {Lights.LivingLight}
}

function module.TurnOnLight(LightSwitch:Model)
	if LightSwitch:IsA("Model") and LightSwitch.Parent == LightSwitches then
		for i,v in LightList[LightSwitch] do
			v.Union.SurfaceLight.Enabled = true
			v.Part.Material = Enum.Material.Neon
			LightSwitch.switch.ProximityPrompt.ActionText = "Off"
			v.switch.SFX:Play()
		end
	else
		warn("Not a LightSwitch! Name: "..LightSwitch.Name)
	end
end

function module.TurnOffLight(LightSwitch:Model)
	if LightSwitch:IsA("Model") and LightSwitch.Parent == LightSwitches then
		for i,v in LightList[LightSwitch] do
			v.Union.SurfaceLight.Enabled = false
			v.Part.Material = Enum.Material.SmoothPlastic
			LightSwitch.switch.ProximityPrompt.ActionText = "On"
			v.switch.SFX:Play()
		end
	else
		warn("Not a LightSwitch! Name: "..LightSwitch.Name)
	end
end

return module
