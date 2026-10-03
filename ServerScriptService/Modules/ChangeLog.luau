local module = {}
local ChangeLog = {}

function module.AddLog(Name:string,Script:BaseScript,Change:string)
	if Name and Script and Change then
		ChangeLog[Name] = {os.time(),Script,Change}
	end
end

function module.RemoveLog(Name:string,RemoveAll:boolean)
	if Name then
		if RemoveAll then
			for i,v in ipairs(ChangeLog) do
				if v == Name then
					table.remove(ChangeLog,Name)
				end
			end
		else
			table.remove(ChangeLog,Name)
		end
	end
end

function module.GetLog()
	return ChangeLog
end

return module
