local GhostData = {}
local Ghost = {}
local roomNames = {
	"BEDROOM 1",
	"BEDROOM 2",
	"GARAGE",
	"MASTER BEDROOM",
	"DEN",
	"BASEMENT",
	"KITCHEN",
	"GUEST ROOM",
	"HALLWAY"
}

local Ghosts = {
	{
		Name = "Spirit",
		Evidence = {
			"EMF Level 5",
			"Ghost Writing",
			"Spirit Box"
		},

	},
	{
		Name = "Mare",
		Evidence = {
			"Ghost Orbs",
			"Ghost Writing",
			"Spirit Box"
		},

	},
	{
		Name = "Revenant",
		Evidence = {
			"Ghost Orbs",
			"Ghost Writing",
			"Freezing Temperatures"
		},

	},
	{
		Name = "Shade",
		Evidence = {
			"EMF Level 5",
			"Ghost Writing",
			"Freezing Temperatures"
		},

	},
	{
		Name = "Onryo",
		Evidence = {
			"Ghost Orbs",
			"Spirit Box",
			"Freezing Temperatures"
		},

	},
	{
		Name = "The Twins",
		Evidence = {
			"EMF Level 5",
			"Freezing Temperatures",
			"Spirit Box"
		},

	},
	{
		Name = "Moroi",
		Evidence = {
			"Freezing Temperatures",
			"Ghost Writing",
			"Spirit Box"
		},

	},


}

local GhostValues = game.ServerStorage.ServerValues.GhostValues

function GhostData.GetGhostData()
	return Ghost
end

function GhostData.SetUpGhostData()
	Ghost = Ghosts[Random.new(os.time()):NextInteger(1,#Ghosts)]
	if Random.new(os.time()):NextInteger(1,2) == 1 then
		Ghost["Age"] = "Young"
	else
		Ghost["Age"] = "Old"
	end
	Ghost["Room"] = roomNames[Random.new(os.time()):NextInteger(1,#roomNames)]
	
	for i,v in ipairs(Ghost["Evidence"]) do
		GhostValues.Evidence["Evidence"..i].Value = v
	end
	GhostValues.Evidence.StartingRoom.Value = Ghost["Room"]
end

GhostData.SetUpGhostData()

return GhostData
