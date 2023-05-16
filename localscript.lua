-- there may be a few weird things about the code but you get the idea

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
	Face : {Target : number, Busy : boolean},
	RestColor : Color3,
	RestTween : Tween,
	CameraTween : Tween,
	BarTweens : {Tween},
	EyeTweens : {[Part] : {Dot : Tween, Close : Tween, Open : Tween, Tilt : Tween, Straight : Tween}},
	ParticleInfo : {[ParticleEmitter] : {Rate : number}}
}
} = {} -- store organized info on the balls (and tweens instead of creating them every time since that won't be needed)

local SGui = script.ScreenGui
local Bar = SGui.Bar

local Charge = 0
local Busy = false

local TWEENINFOLINEAR = TweenInfo.new(1/3, Enum.EasingStyle.Linear)
local TWEENINFOLINEARQUICK = TweenInfo.new(1/8, Enum.EasingStyle.Linear)
local TWEENINFOGLOW = TweenInfo.new(0.5, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local TWEENBARREST = TweenService:Create(
	Bar.Fill,
	TWEENINFOGLOW,
	{Size = UDim2.fromScale(0, 1)}
)
local FACES = { -- define the faces, each table indicates the tweens that a certain face requires
	Normal = {"Straight", "Open"},
	Closed = {"Tilt", "Close"},
}
local GLOWTHRESHOLD = 159 -- exact color value before neon parts get the glow effect
local CAMERAOFFSET = Vector3.new(0, 5, -15)
local CAMERAFOV = 70
local EYESIZE = Trio.WCBBlue.Face.EyeLeft.Size
local KC = Enum.KeyCode

local function Lerp(a : number, b : number, alpha : number) -- linear interpolation method
	return a + ((b - a) * alpha)
end

local function tweensInTable(tab : {Tween}, method : string) -- use the same method on all tweens in a table
	for _, Tween in tab do
		Tween[method](Tween)
	end
end

local changeFace -- will be assigned in the "do" block below

do -- initialization
	for _, Ball : Part in Trio:GetChildren() do -- initialize tweens
		local H, S = Ball.Color:ToHSV() -- get hue and saturation
		local KEY = Ball == Trio.WCBRed and KC.A or Ball == Trio.WCBGreen and KC.S or KC.D -- janky line but it works
		local RESTCOLOR = Color3.fromHSV(H, S, GLOWTHRESHOLD) -- construct color with fixed brightness
		RESTCOLOR = Color3.fromRGB(RESTCOLOR.R, RESTCOLOR.G, RESTCOLOR.B) -- for some arcane reason fromHSV returns numbers from 0 - 255 instead of 0 - 1

		local ParticleInfo : {[ParticleEmitter] : any} = {} -- store original particleemitter variables here, so they can be manipulated accurately
		local EyeTweens : {[Part] : () -> ()} = {}

		for _, Emitter : ParticleEmitter in Ball:GetDescendants() do
			if not Emitter:IsA("ParticleEmitter") then
				continue
			end

			ParticleInfo[Emitter] = { -- the two particleemitter values that will be manipulated according to charge percentage
				Rate = Emitter.Rate,
				Lifetime = Emitter.Lifetime
			}
		end

		for _, Eye : Part in Ball.Face:GetChildren() do -- that's riiiight goofy little face animations
			local function tweenEyeCreate(type_ : number, propertytable : {[string] : any}) -- all eye tween objects are going to be really similar so this speeds things up
				return TweenService:Create(
					type_ ~= 1 and Eye or Eye.Weld,
					TWEENINFOLINEARQUICK,
					propertytable
				)
			end

			EyeTweens[Eye] = { 
				Dot = tweenEyeCreate(0, {Size = Vector3.new(EYESIZE.X, EYESIZE.X, EYESIZE.Z)}), -- these three change the shape of the eyes
				Close = tweenEyeCreate(0, {Size = Vector3.new(EYESIZE.Y, EYESIZE.X, EYESIZE.Z)}),
				Open = tweenEyeCreate(0, {Size = Vector3.new(EYESIZE.X, EYESIZE.Y, EYESIZE.Z)}),
				Tilt = tweenEyeCreate(1, {C1 = CFrame.Angles(0, 0, Eye.Name == "EyeLeft" and math.rad(20) or math.rad(-20))}), -- these two change the tilt of the eyes
				Straight = tweenEyeCreate(1, {C1 = CFrame.identity}),
			}
		end

		BallTable[Ball] = { -- yep . . here's all the cool information for each ball. the key to be pressed, colors, tweens, particles, everything
			Key = KEY,
			Color = Ball.Color,
			Face = {Target = FACES.Normal, Busy = false},
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
			EyeTweens = EyeTweens,
			ParticleInfo = ParticleInfo
		}

		Ball.Color = RESTCOLOR

		changeFace = function(ball : BasePart, face : {string}) -- in summary, do a tween transition to the target face
			local Table = BallTable[ball]

			if face == Table.Face.Target then -- if the argument face is already the target face, nothing should happen
				return
			end

			Table.Face.Target = face

			if Table.Face.Busy then
				return
			end

			local LastTarget = -1 -- this number has no significance, it's just so LastTarget ~= Table.Face.Target starts as true

			Table.Face.Busy = true -- debouncing -- since all this logic only needs to be handled in one changeFace thread at a time

			task.spawn(function() -- task.spawn this bit because there should be yielding inside the logic here, but it should not yield the changeFace caller
				for i, Tween : Tween in Table.EyeTweens[ball.Face.EyeLeft] do -- wait for eye tweens to finish (dot eyes will tween at the same time for the same length, so it's ok if i only check the left one)
					if Tween.PlaybackState == Enum.PlaybackState.Playing then
						Tween.Completed:Wait()
					end
				end

				while LastTarget ~= Table.Face.Target do -- it will keep transitioning until the target face has been reached AND it has not changed again
					LastTarget = Table.Face.Target

					Table.EyeTweens[ball.Face.EyeLeft].Dot:Play()
					Table.EyeTweens[ball.Face.EyeRight].Dot:Play()

					Table.EyeTweens[ball.Face.EyeLeft].Dot.Completed:Once(function()
						local FaceTable = Table.Face.Target

						for _, tweenname in FaceTable do -- play the relevant face tweens . .
							Table.EyeTweens[ball.Face.EyeLeft][tweenname]:Play()
							Table.EyeTweens[ball.Face.EyeRight][tweenname]:Play()
						end

						for _, tweenname in FaceTable do -- logically, this waits until all tweens are completed (with the knowledge that a tween will not play *after* it has been checked)
							local Tween = Table.EyeTweens[ball.Face.EyeLeft][tweenname]

							if Tween.PlaybackState == Enum.PlaybackState.Playing then
								Tween.Completed:Wait()
							end
						end
					end)
				end

				Table.Face.Busy = false -- transitioning is over, turn off the debounce
			end)
		end
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

				Camera.FieldOfView = Lerp(CAMERAFOV, TARGETFOV, ALPHA) -- gradually zoom in according to charge percentage
				Bar.Fill.Size = UDim2.fromScale(ALPHA, 1) -- bar indicates charge percentage

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

			changeFace(Ball, FACES.Closed)
			Table.RestTween:Cancel() -- cancel rest color tween if it's already playing beforehand
			TWEENBARREST:Cancel() -- and this one too

			Table.CameraTween:Play()
			tweensInTable(Table.BarTweens, "Play") -- yaaay i get to use the cool function

			Ball.Color = Table.Color
			Ball.Beep:Play()

			object.Changed:Once(function() -- only way a key press changes is if it's getting toggled (or released, in this case)
				changeFace(Ball, FACES.Normal)
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
