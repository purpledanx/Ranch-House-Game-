local module = {}

local lightFolder = game.Workspace.House.LightSwitches
local light9Module = require(lightFolder.BD1LightSwitch.switch.ProximityPrompt.ModuleScript)
local light10Module = require(lightFolder.GaradgeLightSwitch.switch.ProximityPrompt.ModuleScript)
local light8Module = require(lightFolder.BD2LightSwitch.switch.ProximityPrompt.ModuleScript)
local light7Module = require(lightFolder.BD3LightSwitch.switch.ProximityPrompt.ModuleScript)
local light6Module = require(lightFolder.BD4LightSwitch.switch.ProximityPrompt.ModuleScript)
local light5Module = require(lightFolder.DenLightSwitch.switch.ProximityPrompt.ModuleScript)
local light4Module = require(lightFolder.HallwayLightSwitch.switch.ProximityPrompt.ModuleScript)
local light3Module = require(lightFolder.KitchenLightSwitch.switch.ProximityPrompt.ModuleScript)
local light2Module = require(lightFolder.Bathroom1LightSwitch.switch.ProximityPrompt.ModuleScript)
local light1Module = require(lightFolder.LivingRoomLightSwitch.switch.ProximityPrompt.ModuleScript)
local active = false

local function lightLoop()
	active = true
	while active do
		local timeamount = math.random(30, 120)
		local lightpicked = math.random(1, 9)
		local turnon = math.random(1,15)
		print("waiting: " .. timeamount.." seconds until eflickering light")
		wait(timeamount)
		print("Flickered light")
		if lightpicked == 1 then
			if turnon == 3 then
				light1Module.toggle()
			else
				light1Module.toggle()
				wait(0.1)
				light1Module.toggle()
			end
		elseif lightpicked == 2 then
			if turnon == 3 then
				light2Module.toggle()
			else
				light2Module.toggle()
				wait(0.1)
				light2Module.toggle()
			end
		elseif lightpicked == 3 then
			if turnon == 3 then
				light3Module.toggle()
			else
				light3Module.toggle()
				wait(0.1)
				light3Module.toggle()
			end
		elseif lightpicked == 4 then
			if turnon == 3 then
				light4Module.toggle()
			else
				light4Module.toggle()
				wait(0.1)
				light4Module.toggle()
			end
		elseif lightpicked == 5 then
			if turnon == 3 then
				light5Module.toggle()
			else
				light5Module.toggle()
				wait(0.1)
				light5Module.toggle()
			end
		elseif lightpicked == 6 then
			if turnon == 3 then
				light6Module.toggle()
			else
				light6Module.toggle()
				wait(0.1)
				light6Module.toggle()
			end
		elseif lightpicked == 7 then
			if turnon == 3 then
				light7Module.toggle()
			else
				light7Module.toggle()
				wait(0.1)
				light7Module.toggle()
			end
		elseif lightpicked == 8 then
			if turnon == 3 then
				light8Module.toggle()
			else
				light8Module.toggle()
				wait(0.1)
				light8Module.toggle()
			end
		elseif lightpicked == 9 then
			if turnon == 3 then
				light9Module.toggle()
			else
				light9Module.toggle()
				wait(0.1)
				light9Module.toggle()
			end
		elseif lightpicked == 10 then
			if turnon == 3 then
				light10Module.toggle()
			else
				light10Module.toggle()
				wait(0.1)
				light10Module.toggle()
			end
		end
	end
end

module.lightLoop = lightLoop()
return module
