local module = {}
local playerdata = {}
local ChangeLog = require(script.Parent.ChangeLog)

function module.AddUpdateData(PlayerID:string,data)
	playerdata[PlayerID] = data
end

function module.GetData(PlayerID:string)
	return playerdata[PlayerID]
end

function module.RemoveData(PlayerID:string)
	playerdata[PlayerID] = nil
end

return module
