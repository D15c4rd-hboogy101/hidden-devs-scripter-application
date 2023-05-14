local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local Camera = workspace.CurrentCamera
local Player = Players.LocalPlayer

local Trio = workspace.Trio
local BallTable : {[typeof(Trio.WCBBlue)] : { -- all the balls will have the same kinds of children, setting the type to one is essentially setting it to all
	Key : Enum.KeyCode,
	Color : Color3,
	RestColor : Color3,
	RestTween : Tween,
	CameraTween : Tween,
	BarTweens : {Tween},
	ParticleInfo : {[ParticleEmitter] : {Rate : number}}
}
} = {} -- store organized info on the balls (and tweens instead of creating them every time since that won't be needed)

local SGui = script.ScreenGui
local Bar = SGui.Bar

local Charge = 0
local Busy = false

local TWEENINFOLINEAR = TweenInfo.new(1/3, Enum.EasingStyle.Linear)
local TWEENINFOGLOW = TweenInfo.new(0.5, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local TWEENBARREST = TweenService:Create(
	Bar.Fill,
	TWEENINFOGLOW,
	{Size = UDim2.fromScale(0, 1)}
)
local GLOWTHRESHOLD = 159 -- exact color value before neon parts get the glow effect
local CAMERAOFFSET = Vector3.new(0, 5, -15)
local CAMERAFOV = 70
local KC = Enum.KeyCode

local function Lerp(a : number, b : number, alpha : number) -- linear interpolation method
	return a + ((b - a) * alpha)
end

local function tweensInTable(tab : {Tween}, method : string) -- use the same method on all tweens in a table
	for _, Tween in tab do
		Tween[method](Tween)
	end
end

do -- initialization
	for _, Ball : Part in Trio:GetChildren() do -- initialize tweens
		local H, S = Ball.Color:ToHSV() -- get hue and saturation
		local KEY = Ball == Trio.WCBRed and KC.A or Ball == Trio.WCBGreen and KC.S or KC.D -- janky line but it works
		local RESTCOLOR = Color3.fromHSV(H, S, GLOWTHRESHOLD) -- construct color with fixed brightness
		RESTCOLOR = Color3.fromRGB(RESTCOLOR.R, RESTCOLOR.G, RESTCOLOR.B) -- for some arcane reason fromHSV returns numbers from 0 - 255 instead of 0 - 1
		
		local ParticleInfo : {[ParticleEmitter] : any} = {} -- store original particleemitter variables here, so they can be manipulated accurately
		
		for _, Emitter : ParticleEmitter in Ball:GetDescendants() do
			if not Emitter:IsA("ParticleEmitter") then
				continue
			end
			
			ParticleInfo[Emitter] = { -- two particleemitter values that will be manipulated according to charge percentage
				Rate = Emitter.Rate,
				Lifetime = Emitter.Lifetime
			}
		end
		
		BallTable[Ball] = { -- yep . . here's all the cool information for each ball. the key to be pressed, colors, tweens, particles, everything
			Key = KEY,
			Color = Ball.Color,
			RestColor = RESTCOLOR,
			CameraTween = TweenService:Create(
				Camera,
				TWEENINFOGLOW,
				{CFrame = CFrame.lookAt(Ball.Position + Vector3.new(0, 5, -15), Ball.Position)}
			),
			RestTween = TweenService:Create(
				Ball,
				TWEENINFOGLOW,
				{Color = RESTCOLOR}
			),
			BarTweens = { -- all of these tweens are for changing the color of the charge bar, and will be manipulated all at once
				TweenService:Create(
					Bar.UIStroke,
					TWEENINFOGLOW,
					{Color = Ball.Color}
				),
				TweenService:Create(
					Bar.Fill,
					TWEENINFOGLOW,
					{BackgroundColor3 = Ball.Color}
				),
				TweenService:Create(
					Bar.Label,
					TWEENINFOGLOW,
					{TextColor3 = Ball.Color}
				)
			},
			ParticleInfo = ParticleInfo
		}
		
		Ball.Color = RESTCOLOR
	end
	
	Camera.CameraType = Enum.CameraType.Scriptable
	Camera.CFrame = CFrame.lookAt(Trio.WCBGreen.Position + Vector3.new(0, 5, -15), Trio.WCBGreen.Position)
	
	SGui.Parent = Player.PlayerGui
end

ContextActionService:BindAction("inputs", function(_, state : Enum.UserInputState, object : InputObject) -- handle inputs with CAS
	if state ~= Enum.UserInputState.Begin or Busy then -- do not restart the function for changed or released inputs, or if a key is already held
		return
	end
	
	local CHARGETIME = 2.5 -- how long the "charging" process takes
	local TARGETFOV = 60 -- field of view that will be slowly reached
	
	local KEY = object.KeyCode -- read the key that was pressed . .

	for Ball, Table in BallTable do
		if KEY == Table.Key and not Busy then
			Busy = true -- debouncing -- do not want to charge two balls at the same time

			local RSE : RBXScriptConnection
			RSE = RunService.Stepped:Connect(function(_, delta)
				Charge = math.min(Charge + delta, CHARGETIME) -- increase charge according to time passed since last frame
				local ALPHA = Charge / CHARGETIME -- basically a percentage of how charged the ball is

				Camera.FieldOfView = Lerp(CAMERAFOV, TARGETFOV, ALPHA) -- gradually zoom in
				Bar.Fill.Size = UDim2.fromScale(ALPHA, 1)
				
				for Emitter, Values in Table.ParticleInfo do
					Emitter.Enabled = true
					
					for i, Value in Values do -- gradually set values from 0 to their normal values, contributing to a gradual charging effect
						if i == "Lifetime" then
							Emitter[i] = NumberRange.new(Lerp(Value.Min * 3, Value.Min, ALPHA)) -- going from high lifetime to low kinda makes it go slow to fast
						else
							Emitter[i] = Lerp(0, Value, ALPHA)
						end
					end
				end
			end)
			
			Table.RestTween:Cancel() -- cancel rest color tween if it's already playing beforehand
			TWEENBARREST:Cancel() -- and this one too
			Table.CameraTween:Play()
			tweensInTable(Table.BarTweens, "Play") -- yaaay i get to use that cool function
			
			Ball.Color = Table.Color
			Ball.Beep:Play()
			
			object.Changed:Once(function() -- only way a key press changes is if it's getting toggled (or released, in this case)
				Table.RestTween:Play()
				TWEENBARREST:Play()
				
				Ball.Beep:Stop()
				Ball.Click:Play()
				
				RSE:Disconnect()
				Camera.FieldOfView = CAMERAFOV
				
				for Emitter in Table.ParticleInfo do
					Emitter.Enabled = false
				end
				
				Charge = 0
				Busy = false
			end)
		end
	end
end, false, KC.A, KC.S, KC.D)

-- i know you wanted a minimum of 200 lines but i've kinda optimized the script
-- and there's only so much i can do with a weird ball charge thing
-- please accept me