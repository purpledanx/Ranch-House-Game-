local VersionNumber = 2
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local HttpService = game:GetService("HttpService")
local GoodSignal = require(script.GoodSignal)
local ParallelScheduler = require(script.ParallelScheduler)
local RaycastBounceModule = script["Calculate Raycast Bounce"]

local Player = game:GetService("Players").LocalPlayer
local Character = Player.Character or Player.CharacterAdded:Wait()

local SoundReverbV2 = {
	MaterialDensity = {
		--//1 == Most Dense --//0 == Least Dense
		-- Natural terrain materials
		Mud = 0.45,
		Ground = 0.5,
		Sand = 0.35,
		Salt = 0.4,
		Ice = 0.65,
		Snow = 0.2,
		Sandstone = 0.7,
		Rock = 0.85,
		Basalt = 0.9,
		CrackedLava = 0.75,
		Limestone = 0.8,
		Slate = 0.82,
		Granite = 0.92,
		Marble = 0.85,

		-- Vegetation materials
		Grass = 0.08,
		LeafyGrass = 0.12,

		-- Construction materials
		Pavement = 0.72,
		Asphalt = 0.88,
		Concrete = 0.75,
		Cobblestone = 0.68,
		Brick = 0.82,

		-- Wood materials
		Wood = 0.55,
		WoodPlanks = 0.52,

		-- Plastic materials
		Plastic = 0.3,
		SmoothPlastic = 0.48,

		-- Metal materials
		Metal = 1,
		CorrodedMetal = 0.95,
		DiamondPlate = 0.98,

		-- Glass and transparent materials
		Glass = 0.62,
		ForceField = 0,

		-- Fabric and soft materials
		Fabric = 0.25,
		Carpet = 0.28,

		-- Special/glow materials
		Neon = 0.15,
		Foil = 0.85,
		Pebble = 0.6,
		Glacier = 0.7,
	};

	MaterialReflectiveness = {
		--//1 == Most Reflective --//0 == Least Reflective
		--//chance that a ray will get absorbed == 1-Reflectiveness

		-- Natural terrain materials
		Mud = 0.18,
		Ground = 0.25,
		Sand = 0.42,
		Salt = 0.28,
		Ice = 0.75,
		Snow = 0.14,
		Sandstone = 0.3,
		Rock = 0.35,
		Basalt = 0.25,
		CrackedLava = 0.15,
		Limestone = 0.4,
		Slate = 0.45,
		Granite = 0.5,
		Marble = 0.95,

		-- Vegetation materials
		Grass = 0.1,
		LeafyGrass = 0.35,

		-- Construction materials
		Pavement = 0.32,
		Asphalt = 0.3,
		Concrete = 0.87,
		Cobblestone = 0.3,
		Brick = 0.74,

		-- Wood materials
		Wood = 0.38,
		WoodPlanks = 0.52,

		-- Plastic materials
		Plastic = 0.38,
		SmoothPlastic = 0.68,

		-- Metal materials
		Metal = 0.85,
		CorrodedMetal = 0.55,
		DiamondPlate = 0.82,

		-- Glass and transparent materials
		Glass = 0.9,
		ForceField = 1,

		-- Fabric and soft materials
		Fabric = 0.12,
		Carpet = 0.08,

		-- Special/glow materials
		Neon = 0.95,
		Foil = 0.88,
		Pebble = 0.35,
		Glacier = 0.78,
	};
}

local ReverbObject = {}
ReverbObject.__index = ReverbObject

type RayParams = {
	Position: Vector3 | BasePart;
	MaxReflections: number;
	RaysPerStep: number;
	MaxDistance: number;
	IgnoreTransparentParts: boolean;
	DebugMode: boolean;
}

type SoundParams = {
	LerpTime: number;
	GroupVolume: number;
	Do3DMuffle: boolean;
}

type SoundRayResult = {
	HitArray: {BasePart};
	Bounces: number;
	AbsorptionAmount: number;
	DensityAmount: number;
	TotalDistance: number;
}

export type ObjectMeta = {
	_ReferenceCamera: Camera;
	_RayParams: RayParams;
	_SoundParams: SoundParams;
	_SteppedUpdate: RBXScriptConnection;
	_DebugFolder: Folder?;
	_RandomSeed: Random;
	_EmitObject: BasePart?;
	_EmitPosition: Vector3;
	FilterDescendantsInstances: {any};
	LatestResult: {EqualizerSoundEffect: {any}, ReverbSoundEffect: {any}};
	LastPerformanceTick: number;
	StepComplete: RBXScriptSignal;
	AutoApplyList: {Sound};
	BounceTable: {};
}

if RunService:IsServer() then
	error("SoundReverbV2 can only be required on the client.")
end

local function Lerp(a, b, t)
	return a + (b - a) * t
end

local function Normalize(Value, Min, Max)
	return (Value - Min)/(Max-Min)
end

local function computeUniqueIdentifier(object)
	local fullPath = object.Name
	local current = object.Parent
	while current and current ~= game do
		fullPath = current.Name .. "`" .. fullPath
		current = current.Parent
	end
	-- Create a hash based on the full path
	return HttpService:GenerateGUID(false) .. "-" .. tostring(#fullPath)
end


local function getFullName(object)
	local result = object.Name .. "#" .. computeUniqueIdentifier(object)
	object = object.Parent
	while object and object ~= game do
		result = object.Name .. "#" .. computeUniqueIdentifier(object) .. "`" .. result
		object = object.Parent
	end
	return result
end

local function StringToInstance(Table: {string}): {Instance}
	local newTable = setmetatable({}, {__mode = "vk"})
	for i, v in pairs(Table) do
		local segments = v:split("`")
		local current = game.Workspace

		for _, segment in ipairs(segments) do
			local name, id = segment:match("^(.*)#(.*)$")
			if current then
				local found = nil
				for _, child in ipairs(current:GetChildren()) do
					-- Match name and regenerate the unique identifier
					if child.Name == name and computeUniqueIdentifier(child) == id then
						found = child
						break
					end
				end
				current = found
			end
		end

		newTable[i] = current
	end
	return newTable
end

local function InstanceToString(Table: {Instance}): {string}
	local newTable = table.clone(Table)
	for i, v in ipairs(newTable) do
		newTable[i] = getFullName(v)
	end
	return newTable
end

function SoundReverbV2.newRayParams(PositionOrPart: Vector3 | BasePart, MaxReflections: number, RaysPerStep: number, MaxDistance: number, IgnoreTransparentParts: boolean, DebugMode: boolean): ReverbParams
	local RayParams: RayParams = {}
	RayParams.Position = PositionOrPart or Vector3.new()
	RayParams.MaxReflections = MaxReflections or 4
	RayParams.RaysPerStep = RaysPerStep or 40
	RayParams.MaxDistance = MaxDistance or 500
	RayParams.IgnoreTransparentParts = IgnoreTransparentParts or true
	RayParams.DebugMode = DebugMode or false

	return RayParams
end

function SoundReverbV2.newSoundParams(LerpTime: number, GroupVolume: number, Do3DMuffle: boolean): SoundParams
	local SoundParams: SoundParams = {}
	SoundParams.LerpTime = LerpTime or 0.15
	SoundParams.GroupVolume = GroupVolume or .5
	SoundParams.Do3DMuffle = Do3DMuffle or true

	return SoundParams
end

function SoundReverbV2.new(RayParams: RayParams?, SoundParams: SoundParams?, Filter)
	local self = setmetatable({
		_ReferenceCamera = workspace.CurrentCamera;
		_RayParams = RayParams or SoundReverbV2.newRayParams();
		_SoundParams = SoundParams or SoundReverbV2.newSoundParams();
		_SteppedUpdate = nil;
		_DebugFolder = nil;
		_RandomSeed = Random.new(math.round(os.clock()));
		_EmitPosition = nil;
		_EmitObject = nil;
		FilterDescendantsInstances = {};
		LatestResult = {
			EqualizerSoundEffect = setmetatable({}, {__mode = "v"});
			ReverbSoundEffect = setmetatable({}, {__mode = "v"});
		};
		LastPerformanceTick = 0;
		StepComplete = GoodSignal.new();
		AutoApplyList = {};
		BounceTable = ParallelScheduler:LoadModule(RaycastBounceModule);
	}, ReverbObject)

	self.FilterDescendantsInstances = Filter

	self.BounceTable:SetMaxWorkers(258)

	self._DebugFolder = workspace:FindFirstChild("SoundReverbV2DebugRays")

	if not self._DebugFolder and self._RayParams.DebugMode then
		self._DebugFolder = Instance.new("Folder", workspace)
		self._DebugFolder.Name = "SoundReverbV2DebugRays"
	end

	if typeof(self._RayParams.Position) == "Vector3" then
		self._EmitPosition = self._RayParams.Position
	elseif typeof(self._RayParams.Position) == "Instance" then
		assert(self._RayParams.Position:IsA("BasePart"), "Expected BasePart; got '"..self._RayParams.Position.ClassName.."'.")

		self._EmitObject = self._RayParams.Position
		self._EmitPosition = self._EmitObject.Position
	else
		error("Expected BasePart or Vector3; got '"..typeof(self._RayParams.Position).."'.")
	end

	local ConstantsTable = {}

	local ConstantsTable = table.concat({
		tostring(RayParams.MaxReflections),
		tostring(RayParams.MaxDistance),
		HttpService:JSONEncode(SoundReverbV2.MaterialDensity), -- Encode the table
		HttpService:JSONEncode(SoundReverbV2.MaterialReflectiveness),
	}, "|")
	RaycastBounceModule:SetAttribute("DebugMode", RayParams.DebugMode)
	RaycastBounceModule:SetAttribute("ConstantsTable", ConstantsTable)

	return self
end

function ReverbObject:_UpdateStep()

	--local clock = os.clock()
	local self: ObjectMeta = self
	local Filter = table.clone(self.FilterDescendantsInstances)

	local function _3DSound()
		local _, Listener = SoundService:GetListener()

		if Listener then
			if Listener:IsA("BasePart") then
				Listener = Listener.CFrame
			end
		else
			Listener = self._ReferenceCamera.CFrame
		end


		local Facing = Listener.LookVector
		local Vector = (self._EmitPosition - Listener.Position).unit
		Facing = Vector3.new(Facing.X,0,Facing.Z)
		Vector = Vector3.new(Vector.X,0,Vector.Z)

		local Angle = math.acos(Facing:Dot(Vector)/(Facing.magnitude*Vector.magnitude))

		return -(10 * ((Angle/math.pi)^2))
	end

	local function CanSeeCam(Filter: {})
		local RaycastParam = RaycastParams.new()
		RaycastParam.FilterType = Enum.RaycastFilterType.Exclude
		RaycastParam.FilterDescendantsInstances = Filter

		local MiddleOfViewport = self._ReferenceCamera.ViewportSize/2
		local SightOrigin = self._ReferenceCamera.CFrame.Position
		local Direction =  (self._EmitPosition - SightOrigin).Unit * ((self._EmitPosition - SightOrigin).Magnitude + .01)

		local SightRaycast = workspace:Raycast(SightOrigin, Direction, RaycastParam)

		if SightRaycast then
			if not SightRaycast.Instance:IsA("BasePart") then
				return false
			end

			if not self._RayParams.IgnoreTransparentParts then
				return false
			end

			local TruthValue
			if SightRaycast.Instance.Transparency == 1 then
				table.insert(Filter, SightRaycast.Instance)
				TruthValue = CanSeeCam(Filter)
			end

			return TruthValue
		end

		if SightRaycast then
			return false
		end

		return true
	end

	local function GetDistanceWeight(Distance: number)
		return math.pow(math.log(math.clamp(Distance, 1, self._RayParams.MaxDistance), 2.7), 1.6)-.8
	end
	--Calling to fire the raycasts
	local RaySampleArray = {}
	setmetatable(RaySampleArray, {__mode = "vk"})
	for RayCount = 1, self._RayParams.RaysPerStep do
		self.BounceTable:ScheduleWork(self._EmitPosition)
	end
	local Status = self.BounceTable:GetStatus()

	if not Status.IsWorking then
		Status = nil
		local ResultTable = setmetatable({}, {__mode = "vk"})
		local success, errorr = pcall(function()
			ResultTable = self.BounceTable:Work()
		end)

		if success and ResultTable then
			--print(ResultTable)
			for i,v in ResultTable do
				table.insert(RaySampleArray, v[1])
			end
			--print(RaySampleArray)
			local FinalResult = {}
			setmetatable(FinalResult, {__mode = "vk"})
			if self.AutoApplyList[1]:IsA("Sound") then
				local AveragedSample = {
					TotalBounces = 0;
					Density = 0;
					Absorption = 0;
					Distance = 0;
					AverageBounces = 0;
					DistanceWeight = 0;
					TotalDistance = 0;
				}
				setmetatable(AveragedSample, {__mode = "vk"})
				for _, RaySample: SoundRayResult in RaySampleArray do
					AveragedSample.Density += RaySample.DensityAmount / (RaySample.Bounces+1) / self._RayParams.RaysPerStep
					AveragedSample.Absorption += RaySample.AbsorptionAmount / (RaySample.Bounces+1) / self._RayParams.RaysPerStep
					AveragedSample.DistanceWeight += GetDistanceWeight(RaySample.TotalDistance/(RaySample.Bounces+1)) / self._RayParams.RaysPerStep
					AveragedSample.TotalDistance += RaySample.TotalDistance
					AveragedSample.TotalBounces += RaySample.Bounces / self._RayParams.RaysPerStep
					AveragedSample.AverageBounces += RaySample.Bounces / (RaySample.Bounces+1) / self._RayParams.RaysPerStep
				end
				FinalResult = {
					EqualizerSoundEffect = {
						HighGain = 0;
						MidGain = 0;
						LowGain = 0
					};

					ReverbSoundEffect = {
						Density = 0;
						WetLevel = 0;
						Diffusion = 0;
						DecayTime = 0;
					};
				}

				local targetValues = {
					Density = AveragedSample.Density,
					DecayTime = -.3 + (0.5 * AveragedSample.DistanceWeight),
					WetLevel = -20 + (30 * AveragedSample.AverageBounces) + (5 * (-4+AveragedSample.DistanceWeight)),
					Diffusion = (1 - AveragedSample.AverageBounces) * (1-AveragedSample.Absorption)
				}
				setmetatable(targetValues, {__mode = "vk"})
				-- Smoothly update FinalResult.ReverbSoundEffect
				for key, target in pairs(targetValues) do
					FinalResult.ReverbSoundEffect[key] = target
				end

				FinalResult.EqualizerSoundEffect.HighGain = -AveragedSample.Density + _3DSound()
				FinalResult.EqualizerSoundEffect.MidGain = -AveragedSample.Density + _3DSound()
				FinalResult.EqualizerSoundEffect.LowGain = -AveragedSample.Density + _3DSound()

				local distance = (self._ReferenceCamera.CFrame.Position - self._EmitPosition).Magnitude
				local mufflingFactor = distance / 40  -- Adjust this divisor for the desired muffling effect range

				-- If muffling is enabled, adjust the gains based on visibility and distance
				if self._SoundParams.Do3DMuffle then
					if not CanSeeCam(Filter) then
						FinalResult.EqualizerSoundEffect.HighGain -= ( -1 * 20 * mufflingFactor)
						FinalResult.EqualizerSoundEffect.MidGain -= (-1 * 10 * mufflingFactor)
						FinalResult.EqualizerSoundEffect.LowGain -= (-1 * 5 * mufflingFactor)
					else
						-- Less muffling if the camera can see the emitter
						FinalResult.EqualizerSoundEffect.HighGain -= ( -1 * 2 * mufflingFactor)
						FinalResult.EqualizerSoundEffect.MidGain -= (-1 * 1.5 * mufflingFactor)
						FinalResult.EqualizerSoundEffect.LowGain -= (-1 * mufflingFactor)
					end
				end
			elseif self.AutoApplyList[1]:IsA("AudioEmitter") then
				local AveragedSample = {
					TotalBounces = 0;
					Density = 0;
					Absorption = 0;
					DistanceWeight = 0;
					TotalDistance = 0;
					AverageBounces = 0;
				}
				setmetatable(AveragedSample, {__mode = "vk"})
				for _, RaySample: SoundRayResult in RaySampleArray do
					AveragedSample.Density += RaySample.DensityAmount / (RaySample.Bounces+1) / self._RayParams.RaysPerStep
					AveragedSample.Absorption += RaySample.AbsorptionAmount / (RaySample.Bounces+1) / self._RayParams.RaysPerStep
					AveragedSample.DistanceWeight += GetDistanceWeight(RaySample.TotalDistance/(RaySample.Bounces+1)) / self._RayParams.RaysPerStep
					AveragedSample.TotalDistance += RaySample.TotalDistance
					AveragedSample.TotalBounces += RaySample.Bounces / self._RayParams.RaysPerStep
					AveragedSample.AverageBounces += RaySample.Bounces / (RaySample.Bounces+1) / self._RayParams.RaysPerStep
				end
				--print(AveragedSample)
				-- Final results

				FinalResult = {
					EqualizerSoundEffect = {
						HighGain = 0;
						MidGain = 0;
						LowGain = 0
					};

					ReverbSoundEffect = {
						Density = 0;
						WetLevel = 0;
						Diffusion = 0;
						DecayRatio = 0;
						DecayTime = 0;
						EarlyDelayTime = 0;
						LateDelayTime = 0;
						HighCutFrequency = 0;
						LowShelfFrequency = 0;
						LowShelfGain = 0;
						ReferenceFrequency = 0;
					};
				}

				-- Target values for reverb effect
				local targetValues = {
					WetLevel = -20 + (8 * AveragedSample.AverageBounces) + (3 * AveragedSample.DistanceWeight) - (10 * AveragedSample.Absorption),
					DecayTime = -.3 + (AveragedSample.DistanceWeight) * ((1-AveragedSample.Absorption) * 0.6),
					Density = AveragedSample.Density,
					Diffusion = (1-AveragedSample.Absorption),
					DecayRatio = math.clamp(1.0 - (AveragedSample.Absorption * 0.7) - ((1.0 - AveragedSample.Density) * 0.2), 0.1, 1.0),
					EarlyDelayTime = 0.02 + (0.005 * AveragedSample.DistanceWeight),
					LateDelayTime = 0.04 + (0.01 * AveragedSample.DistanceWeight),
					HighCutFrequency = 20000 - (AveragedSample.Absorption * 5000),
					LowShelfFrequency = 250 + (AveragedSample.Density * 50),
					LowShelfGain = -AveragedSample.Density * 5,
					ReferenceFrequency = 5000 + (AveragedSample.DistanceWeight * 1000),
				}
				setmetatable(targetValues, {__mode = "vk"})

				-- Smoothly update FinalResult.ReverbSoundEffect
				for key, target in pairs(targetValues) do
					FinalResult.ReverbSoundEffect[key] = target
				end

				-- Equalizer Adjustments
				FinalResult.EqualizerSoundEffect.HighGain = -AveragedSample.Density + _3DSound()
				FinalResult.EqualizerSoundEffect.MidGain = -AveragedSample.Density + _3DSound()
				FinalResult.EqualizerSoundEffect.LowGain = -AveragedSample.Density + _3DSound()

				local distance = (self._ReferenceCamera.CFrame.Position - self._EmitPosition).Magnitude
				local mufflingFactor = distance / 40  -- Adjust this divisor for the desired muffling effect range

				-- If muffling is enabled, adjust the gains based on visibility and distance

				if self._SoundParams.Do3DMuffle then
					if not CanSeeCam(Filter) then
						FinalResult.EqualizerSoundEffect.HighGain -= ( -1 * 20 * mufflingFactor)
						FinalResult.EqualizerSoundEffect.MidGain -= (-1 * 10 * mufflingFactor)
						FinalResult.EqualizerSoundEffect.LowGain -= (-1 * 5 * mufflingFactor)
					else
						-- Less muffling if the camera can see the emitter
						FinalResult.EqualizerSoundEffect.HighGain -= ( -1 * 2 * mufflingFactor)
						FinalResult.EqualizerSoundEffect.MidGain -= (-1 * 1.5 * mufflingFactor)
						FinalResult.EqualizerSoundEffect.LowGain -= (-1 * mufflingFactor)
					end
				end
				--print("It takes "..((os.clock()-clock)*1000).." many ms")
			end
			self.LatestResult = FinalResult
		else
			warn("Raycast or Filter didn't return! Line 532")
		end
	end
end

function ReverbObject:AddSound(Sound: Sound)
	local self: ObjectMeta = self

	if table.find(self.AutoApplyList, Sound) then
		warn("'"..Sound.Name.."' is already on auto apply list.")
		return
	end

	table.insert(self.AutoApplyList, Sound)
end

function ReverbObject:RemoveSound(Sound: Sound, RemoveReverb: boolean)
	local self: ObjectMeta = self

	RemoveReverb = RemoveReverb or true

	if not table.find(self.AutoApplyList, Sound) then
		warn("Could not find '"..Sound.Name.."' on auto apply list.")
		return
	end

	if RemoveReverb then
		for i, Object in Sound:GetChildren() do
			if Object:IsA("SoundGroup") then
				Object:Destroy()
			end
		end
	end

	table.remove(self.AutoApplyList, table.find(self.AutoApplyList, Sound))
end

function ReverbObject:ApplyToSound(Sound: Sound|AudioEmitter, dt: number)
	local self: ObjectMeta = self
	--print(Sound)
	if Sound:IsA("Sound") then
		if not Sound:IsDescendantOf(Player.Character) then
			local SoundGroup: SoundGroup = Sound:FindFirstChildOfClass("SoundGroup")

			if not SoundGroup then
				SoundGroup = Instance.new("SoundGroup", Sound)
				SoundGroup.Name = "SoundReverbV"..VersionNumber.."Group"
			end

			SoundGroup.Volume = self._SoundParams.GroupVolume
			Sound.SoundGroup = SoundGroup

			local EqualizerInstance:EqualizerSoundEffect = SoundGroup:FindFirstChildOfClass("EqualizerSoundEffect")
			local ReverbInstance = SoundGroup:FindFirstChildOfClass("ReverbSoundEffect")

			if not EqualizerInstance then
				EqualizerInstance = Instance.new("EqualizerSoundEffect", SoundGroup)
				EqualizerInstance.Name = "SoundReverbV"..VersionNumber.."Equalizer"
				EqualizerInstance.Enabled = false
			end

			if not ReverbInstance then
				ReverbInstance = Instance.new("ReverbSoundEffect", SoundGroup)
				ReverbInstance.Name = "SoundReverbV"..VersionNumber.."Reverb"
			end


			for Property, Value in self.LatestResult.EqualizerSoundEffect do
				EqualizerInstance[Property] = Lerp(EqualizerInstance[Property], Value, 1/self._SoundParams.LerpTime * dt)
			end

			for Property, Value in self.LatestResult.ReverbSoundEffect do
				ReverbInstance[Property] = Lerp(ReverbInstance[Property], Value, 1/self._SoundParams.LerpTime * dt)
			end
		end
	elseif Sound:IsA("AudioEmitter") then
		local EqualizerInstance = Sound.Parent:FindFirstChildOfClass("AudioEqualizer")
		local ReverbInstance = Sound.Parent:FindFirstChildOfClass("AudioReverb")
		local Wire:Wire = nil

		if not EqualizerInstance then
			EqualizerInstance = Instance.new("AudioEqualizer", Sound.Parent)
			EqualizerInstance.Name = "SoundReverbV"..VersionNumber.."Equalizer"

			Wire = Instance.new("Wire",Sound.Parent)
			Wire.Name = EqualizerInstance.Name.." To "..Sound.Name
			Wire.SourceInstance = EqualizerInstance
			Wire.TargetInstance = Sound
		end

		if not ReverbInstance then
			ReverbInstance = Instance.new("AudioReverb", Sound.Parent)
			ReverbInstance.Name = "SoundReverbV"..VersionNumber.."Reverb"

			Wire = Instance.new("Wire",Sound.Parent)
			Wire.Name = ReverbInstance.Name.." To "..EqualizerInstance.Name
			Wire.SourceInstance = ReverbInstance
			Wire.TargetInstance = EqualizerInstance
		end

		if Wire then
			for i,v in ipairs(Sound.Parent:GetChildren()) do
				if v:IsA("Wire") and v.TargetInstance == Sound then
					v.Name = Sound.Parent.Name.."Fader".." To "..ReverbInstance.Name
					v.TargetInstance = ReverbInstance
					break
				end
			end
		end


		for Property, Value in self.LatestResult.EqualizerSoundEffect do
			EqualizerInstance[Property] = Lerp(EqualizerInstance[Property], Value, 1/self._SoundParams.LerpTime * dt)
		end

		for Property, Value in self.LatestResult.ReverbSoundEffect do
			ReverbInstance[Property] = Lerp(ReverbInstance[Property], Value, 1/self._SoundParams.LerpTime * dt)
		end

	end
end

function ReverbObject:StartUpdate()
	local self: ObjectMeta = self
	if self._SteppedUpdate then
		return
	end

	self._SteppedUpdate = RunService.RenderStepped:Connect(function (dt)
		local StartTime = os.clock()

		-- Defer destruction to next frame (after worker creates new parts)
		if self._PartsToDestroy then
			debug.profilebegin("Destroy Parts")
			for _, Object in self._PartsToDestroy do
				Object:Destroy()
			end
			debug.profileend()
			self._PartsToDestroy = nil
		end

		-- Mark current parts for destruction NEXT frame
		if self._DebugFolder and self._DebugFolder:FindFirstChild("CastOriginPart") then
			self._PartsToDestroy = self._DebugFolder.CastOriginPart:GetChildren()
		end

		if self._EmitObject then
			self._EmitPosition = self._EmitObject.Position
		end

		for _, Sound in self.AutoApplyList do
			self:ApplyToSound(Sound, dt)
		end

		self:_UpdateStep()
		self.LastPerformanceTick = (os.clock() - StartTime)*1e3
		self.StepComplete:Fire()
	end)
end

function ReverbObject:StopUpdate()
	local self: ObjectMeta = self

	if not self._SteppedUpdate then
		return
	end

	self._SteppedUpdate:Disconnect()
	self._SteppedUpdate = nil
end

function ReverbObject:UpdatePosition(Vector: Vector3)
	if self._EmitObject then
		warn("Emit object is already set; don't use UpdatePosition.")
	end

	self._EmitPosition = Vector
end

function ReverbObject:SetEmitObject(BasePart: BasePart)
	self._EmitObject = BasePart 
end

function ReverbObject:UpdateRayParams(RayParams: RayParams)
	self._RayParams = RayParams
end

function ReverbObject:UpdateSoundParams(SoundParams: SoundParams)
	self._SoundParams = SoundParams
end

function ReverbObject:SetReferenceCamera(CameraObject: Camera)
	local self: ObjectMeta = self
	assert(CameraObject.ClassName == "Camera", "Expected Camera; Got "..CameraObject.ClassName.."'.")
	self._ReferenceCamera = CameraObject
end

return SoundReverbV2