-- I think I modified this one?
-- I don't exactly remember who made this but thank you

-- // Visual Config
local CONE_HEIGHT = 0.5
local LINE_THICKNESS = 3
local TRANSPARENCY = 0
local ALWAYS_ON_TOP = false

-- // CastVisualiser Class
local CastVisualiser = {}

-- // Private Methods \\ --

-- // Public Methods \\ --
function CastVisualiser:Hide()
	self.CastOriginPart.Parent = nil
end

function CastVisualiser:Draw(Origin: Vector3, Direction: Vector3, Magnitude: Vector3, Transparnecy: number)
	local self: CastVisualiserPrivate = self
	
	self.LineVisual.CFrame = CFrame.lookAt(Origin, (Direction.Unit*Magnitude)+Origin)

	self.LineVisual.Length = Magnitude
	self.LineVisual.Transparency = Transparnecy
	
	self.ConeVisual.CFrame = CFrame.lookAt(Origin, (Direction.Unit*Magnitude)+Origin) * CFrame.new(0, 0, -Magnitude)
end

export type CastVisualiser = typeof(CastVisualiser)
type CastVisualiserPrivate = CastVisualiser & {
	Color: Color3,
	WorldRoot: WorldRoot,
	CastOriginPart: BasePart,
	
	LineVisual: LineHandleAdornment,
	ConeVisual: ConeHandleAdornment,
	BoxVisual: BoxHandleAdornment,
	SphereVisual: SphereHandleAdornment,
}


-- // Main
local Visuals = {}

--[[

	CastVisualiser Visuals.new(Color: Color3?, WorldRoot: WorldRoot?)
		Creates and returns a CastVisualiser class.

--]]

local Meta = {__index = CastVisualiser}

function Visuals.new(Color: Color3?, Parent: Instance?): CastVisualiser
	local self: CastVisualiserPrivate = setmetatable({
		Color = Color or Color3.new(0, 0, 1),
		WorldRoot = workspace,
	}, Meta)
	
	-- Origin Part
	local CastOriginPart = Parent:FindFirstChild("CastOriginPart")
	
	if not CastOriginPart then
		CastOriginPart = Instance.new("Part")
		CastOriginPart.Name = "CastOriginPart"
		CastOriginPart.Transparency = 1
		CastOriginPart.CanCollide = false
		CastOriginPart.CanQuery = false
		CastOriginPart.CanTouch = false
		CastOriginPart.Anchored = true
		CastOriginPart.Size = Vector3.one / 100
		CastOriginPart.Parent = Parent
	end

	self.CastOriginPart = CastOriginPart
	
	-- Visuals
	local LineHandleAdornment = Instance.new("LineHandleAdornment")
	LineHandleAdornment.Color3 = self.Color
	LineHandleAdornment.AlwaysOnTop = ALWAYS_ON_TOP
	LineHandleAdornment.Transparency = TRANSPARENCY
	LineHandleAdornment.Thickness = LINE_THICKNESS
	LineHandleAdornment.ZIndex = 1
	LineHandleAdornment.Adornee = CastOriginPart
	LineHandleAdornment.Parent = CastOriginPart
	self.LineVisual = LineHandleAdornment
	
	local ConeHandleAdornmnet = Instance.new("ConeHandleAdornment")
	ConeHandleAdornmnet.Color3 = self.Color
	ConeHandleAdornmnet.AlwaysOnTop = ALWAYS_ON_TOP
	ConeHandleAdornmnet.Transparency = TRANSPARENCY
	ConeHandleAdornmnet.Radius = 0.2
	ConeHandleAdornmnet.Height = CONE_HEIGHT
	ConeHandleAdornmnet.SizeRelativeOffset = Vector3.new(0, 0, CONE_HEIGHT * 2)
	ConeHandleAdornmnet.ZIndex = 1
	ConeHandleAdornmnet.Adornee = CastOriginPart
	ConeHandleAdornmnet.Parent = CastOriginPart
	self.ConeVisual = ConeHandleAdornmnet
	
	return self
end

function CastVisualiser:Destroy()
	self.CastOriginPart:Destroy()
	self.ConeVisual:Destroy()
	self.LineVisual:Destroy()
	self = nil
end

return Visuals