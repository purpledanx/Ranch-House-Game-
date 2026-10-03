local module = {}
local active = false
local sound = game.Workspace.Sounds
local sound1 = sound.SoundPart1["knock knock"]
local sound2 = sound.SoundPart2["knock knock"]
local sound3 = sound.SoundPart3["knock knock"]
local sound4 = sound.SoundPart4["knock knock"]

local function nockstart()
	active = true
	while active do
		local timewait = math.random(60,180)
		local soundnum = math.random(1,4)
		print("waiting:"..timewait.."seconds")
		wait(timewait)
		if soundnum == 1 then
			sound1:Play()
		elseif soundnum == 2 then
			sound2:Play()
		elseif soundnum == 3 then
			sound3:Play()
		elseif soundnum == 4 then
			sound4:Play()
		end
	end
end
module.nockstart = nockstart()
return module
