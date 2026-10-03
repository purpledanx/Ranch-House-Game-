local module = {}
local Servers = {}
local CheckParameters = {
	"Public",
	"Private",
	"Ranch House",
	"ServerName",
	"PlayerCount",
	"Difficulty",
	"Map",
	"Privacy",
	"VoiceEnabled",
	"N/A",
	"",
}

local MemoryExperation = 43200
local MemoryStoreService = game:GetService("MemoryStoreService")
local sortedMap = MemoryStoreService:GetSortedMap("ServerMap")

function module:GetServers()
	return Servers
end

function module:CheckServers(ServerId:string)
	if table.find(Servers,ServerId) then
		return true
	else
		return false
	end
end

function module:RemoveServer(ServerId:string)
	Servers[ServerId] = nil
end

function module:GlobalToLocalServer(ServerId:string)
	local data = module:GetGlobalServerData(ServerId)
	print(data)
	if data then
		module:Add_UpdateServer(data["PartyName"],ServerId,data["PlayerCount"],data["Difficulty"],data["Privacy"],data["Map"],data["Players"],data["AccessCode"],data["VoiceEnabled"])
		print(Servers[ServerId])
		return true
	else
		return false
	end
end

function module:ChangeServerValue(ServerId:string,ValueToChange:string,Value:any)
	if table.find(CheckParameters,ValueToChange) then
		Servers[ServerId][ValueToChange] = Value
	else
		return false
	end
end

function module:Add_UpdateServer(PartyName:string, ServerId:string, PlayerCount:number, Difficulty:string, Privacy:string, Map:string, Players, AccessCode:string, VoiceEnabled:boolean)
	if table.find(CheckParameters,Privacy) and table.find(CheckParameters,Map) then
		Servers[ServerId] = {
			["PartyName"] = PartyName,
			["PlayerCount"] = PlayerCount,
			["Difficulty"] = Difficulty,
			["Privacy"] = Privacy,
			["Map"] = Map,
			["Players"] = Players,
			["AccessCode"] = AccessCode,
			["VoiceEnabled"] = VoiceEnabled,
		}
		print(Servers[ServerId])
	else
		return false
	end
end

function module:AddGlobalServer(PartyName:string, ServerId:string, PlayerCount:number, Difficulty:string, Privacy:string, Map:string, Players, AccessCode:string, VoiceEnabled:boolean)
	if table.find(CheckParameters,Privacy) and table.find(CheckParameters,Map) then
		local success, eror = pcall(function()
			sortedMap:SetAsync(ServerId,{
				["PartyName"] = PartyName,
				["PlayerCount"] = PlayerCount,
				["Difficulty"] = Difficulty,
				["Privacy"] = Privacy,
				["Map"] = Map,
				["Players"] = Players,
				["AccessCode"] = AccessCode,
				["VoiceEnabled"] = VoiceEnabled
			},MemoryExperation)
		end)

		if success then
			return true
		else
			return false
		end
	else
		return false
	end
end

function module:ChangeGlobalServerValue(ServerId:string, ValueToChange:string, Value:any)
	local function Update(input)
		input[ValueToChange] = Value
		print(input)
		return input
	end
	if not table.find(CheckParameters,ValueToChange) then
		return false
	else
		local success, eror = pcall(function()
			sortedMap:UpdateAsync(ServerId,Update(),MemoryExperation)
		end)

		if success then
			return true
		else
			return false
		end
	end
end

function module:UpdateGlobalServer(PartyName:string, ServerId:string, PlayerCount:number, Difficulty:string, Privacy:string, Map:string, Players, AccessCode:string, VoiceEnabled:boolean)
	local function Update(input)
		return input
	end
	if not table.find(CheckParameters,Privacy) and not table.find(CheckParameters,Map) then
		return false
	else
		local success, eror = pcall(function()
			sortedMap:UpdateAsync(ServerId,Update({
				["PartyName"] = PartyName,
				["PlayerCount"] = PlayerCount,
				["Difficulty"] = Difficulty,
				["Privacy"] = Privacy,
				["Map"] = Map,
				["Players"] = Players,
				["AccessCode"] = AccessCode,
				["VoiceEnabled"] = VoiceEnabled
			}),MemoryExperation)
		end)

		if success then
			return true
		else
			return false
		end
	end
end

function module:CheckGlobalServer(ServerId:string)
	local success, data = pcall(function()
		return sortedMap:GetAsync(ServerId)
	end)

	if success and data then
		return true
	else
		return false
	end
end

function module:GetGlobalServerData(ServerId:string)
	local success, data = pcall(function()
		return sortedMap:GetAsync(ServerId)
	end)

	if success and data then
		return data
	else
		return false
	end
end

function module:RemoveGlobalServer(ServerId:string)
	local success, eror = pcall(function()
		sortedMap:RemoveAsync(ServerId)
	end)

	if success then
		return true
	else
		return false
	end
end

function module:CheckIfServerIsReal(PartyId)
	for i,v in Servers do
		if i == PartyId then
			return true
		end
	end
end

function module:CheckInfo(PartyId,Class:string,Value:string)
	if table.find(CheckParameters,Class) then
		if Servers[PartyId][Class] == Value then
			return true
		else
			return false
		end
	end
end

function module:GetPartyInfo(PartyId)
	if Servers[PartyId] then
		return Servers[PartyId]
	else
		return false
	end
end

return module
