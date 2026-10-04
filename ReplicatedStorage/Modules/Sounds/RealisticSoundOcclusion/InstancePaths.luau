-- SharedTable transport cannot contain Instances. Paths also disambiguate equal names.
local HttpService = game:GetService("HttpService")
local Paths = {}

function Paths.Encode(object)
	if not object then return "" end
	local path = {}
	local current = object
	while current and current ~= workspace do
		local parent = current.Parent
		if not parent then return "" end
		local occurrence = 0
		for _, sibling in ipairs(parent:GetChildren()) do
			if sibling.Name == current.Name then occurrence += 1 end
			if sibling == current then break end
		end
		table.insert(path, 1, {current.Name, occurrence})
		current = parent
	end
	if current ~= workspace then return "" end
	return HttpService:JSONEncode(path)
end

function Paths.Decode(encoded)
	if encoded == "" then return nil end
	local current = workspace
	for _, segment in ipairs(HttpService:JSONDecode(encoded)) do
		local occurrence = 0
		local found
		for _, child in ipairs(current:GetChildren()) do
			if child.Name == segment[1] then
				occurrence += 1
				if occurrence == segment[2] then found = child; break end
			end
		end
		if not found then return nil end
		current = found
	end
	return current
end

function Paths.EncodeList(objects)
	local encoded = {}
	for _, object in ipairs(objects) do table.insert(encoded, Paths.Encode(object)) end
	return HttpService:JSONEncode(encoded)
end

function Paths.DecodeList(encoded)
	local objects = {}
	for _, path in ipairs(HttpService:JSONDecode(encoded)) do
		local object = Paths.Decode(path)
		if object then table.insert(objects, object) end
	end
	return objects
end

return Paths
