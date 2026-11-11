-- BikeAnimator (ModuleScript)
-- Caminho: StarterPlayer > StarterPlayerScripts > Controllers > BikeAnimator
-- Anima TODAS as bicicletas que este jogador vê (a dele e a dos outros) e
-- a pose de segurar objetos dos empregos:
--   * rodas e pedivela giram de acordo com a velocidade;
--   * pernas seguem os pedais e mãos ficam no guidão (cinemática inversa simples).
-- Tudo é só visual e roda em cada cliente; o servidor não participa.
-- Funciona mexendo em Motor6D.Transform logo depois das animações do Roblox
-- (RunService.Stepped), então sobrepõe a animação de andar nas pernas e braços.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local RigMeasure = require(Shared:WaitForChild("RigMeasure"))

local BikeAnimator = {}

local PEDAL_SPEED = GameConfig.Bike.PedalSpeed
local riders = {} -- riders[character] = estado da animação

-- Gira uma junta para frente (+) ou para trás (-) no plano lateral do corpo.
-- R15: juntas alinhadas ao corpo, gira no eixo X.
-- R6: as juntas são viradas 90°, então gira no eixo Z (sinal invertido na esquerda).
local function swing(rig, joint, side, angle)
	if rig.rigType == "R15" then
		joint.Transform = CFrame.Angles(angle, 0, 0)
	else
		joint.Transform = CFrame.Angles(0, 0, side == "Right" and angle or -angle)
	end
end

-- Dois ossos (coxa+canela ou braço+antebraço) alcançando um alvo no plano Y/Z.
-- Retorna o ângulo do primeiro osso (0 = para baixo, + = para frente) e a dobra do segundo.
local function solve(l1, l2, pivot, target, bendForward)
	local dy, dz = target.Y - pivot.Y, target.Z - pivot.Z
	local base = math.atan2(-dz, -dy)
	if l2 <= 0 then
		return base, 0
	end
	local d = math.clamp(math.sqrt(dy * dy + dz * dz), math.abs(l1 - l2) + 0.05, l1 + l2 - 0.01)
	local a1 = math.acos(math.clamp((l1 * l1 + d * d - l2 * l2) / (2 * l1 * d), -1, 1))
	local inner = math.acos(math.clamp((l1 * l1 + l2 * l2 - d * d) / (2 * l1 * l2), -1, 1))
	local bend = math.pi - inner
	if bendForward then
		return base + a1, -bend -- joelho vai para frente, canela volta
	end
	return base - a1, bend -- cotovelo fica para baixo, antebraço sobe
end

local function startRider(character, bike)
	local rig = RigMeasure.measure(character)
	local crankHub = bike:FindFirstChild("Crank")
	local front = bike:FindFirstChild("FrontWheel")
	local rear = bike:FindFirstChild("RearWheel")
	-- Juntas do tronco/cabeça que ficam paradas enquanto pedala
	local still = {}
	local function add(part, name)
		local p = character:FindFirstChild(part)
		local j = p and p:FindFirstChild(name)
		if j and j:IsA("Motor6D") then
			table.insert(still, j)
		end
	end
	add("LowerTorso", "Root")
	add("UpperTorso", "Waist")
	add("Head", "Neck")
	add("HumanoidRootPart", "RootJoint") -- R6
	add("Torso", "Neck") -- R6
	riders[character] = {
		bike = bike,
		still = still,
		rig = rig,
		crankMotor = crankHub and crankHub:FindFirstChild("CrankMotor"),
		frontMotor = front and front:FindFirstChild("FrontWheelMotor"),
		rearMotor = rear and rear:FindFirstChild("RearWheelMotor"),
		gripLeft = bike:FindFirstChild("GripLeft"),
		gripRight = bike:FindFirstChild("GripRight"),
		wheelAngle = 0,
		crankAngle = 0,
	}
end

local function stopRider(character)
	local state = riders[character]
	riders[character] = nil
	-- Juntas que a animação de andar não controla (tornozelo, punho) voltam ao normal
	if state and state.rig and state.rig.rigType == "R15" then
		for _, name in ipairs({ "LeftAnkle", "RightAnkle", "LeftWrist", "RightWrist", "Waist" }) do
			local joint = state.rig.joints[name]
			if joint then
				joint.Transform = CFrame.new()
			end
		end
		local neck = character:FindFirstChild("Head") and character.Head:FindFirstChild("Neck")
		if neck then
			neck.Transform = CFrame.new()
		end
	end
end

local function animate(character, state, dt)
	local rig = state.rig
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not state.bike.Parent then
		return
	end

	-- Rodas e pedais giram conforme a velocidade no chão
	local v = root.AssemblyLinearVelocity
	local speed = Vector3.new(v.X, 0, v.Z).Magnitude
	local wheelRadius = state.bike:GetAttribute("WheelRadius") or 0.85
	local spin = speed / wheelRadius * dt
	state.wheelAngle = (state.wheelAngle - spin) % (2 * math.pi)
	state.crankAngle = (state.crankAngle - spin * PEDAL_SPEED) % (2 * math.pi)
	local wheelCf = CFrame.Angles(state.wheelAngle, 0, 0)
	if state.frontMotor then
		state.frontMotor.Transform = wheelCf
	end
	if state.rearMotor then
		state.rearMotor.Transform = wheelCf
	end
	if state.crankMotor then
		state.crankMotor.Transform = CFrame.Angles(state.crankAngle, 0, 0)
	end

	if not rig or not state.crankMotor then
		return
	end

	-- Tronco e cabeça parados: a animação de andar balança o tronco, o que levava
	-- os ombros (e as mãos) junto. Com o tronco fixo, as mãos ficam no guidão.
	for _, joint in ipairs(state.still) do
		joint.Transform = CFrame.new()
	end

	-- Pernas: cada pé vai até o seu pedal
	local bb = state.crankMotor.C0.Position
	local crankR = state.bike:GetAttribute("CrankRadius") or 0.45
	for _, side in ipairs({ "Right", "Left" }) do
		local a = state.crankAngle + (side == "Left" and math.pi or 0)
		local pedal = Vector3.new(0, bb.Y - crankR * math.cos(a), bb.Z - crankR * math.sin(a))
		local thigh, knee = solve(rig.legL1, rig.legL2, rig.hip[side], pedal, true)
		swing(rig, rig.joints[side .. "Hip"], side, thigh)
		if rig.rigType == "R15" then
			rig.joints[side .. "Knee"].Transform = CFrame.Angles(knee, 0, 0)
			rig.joints[side .. "Ankle"].Transform = CFrame.Angles(-(thigh + knee), 0, 0) -- pé reto
		end
	end

	-- Marco 9.8: a animação de andar não toca na bike (ela deixava o boneco "andando")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if animator then
		for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
			local anim = track.Animation
			local name = anim and anim.Name:lower() or ""
			if name:find("walk") or name:find("run") then
				track:Stop(0.1)
			end
		end
	end

	-- Marco 9.8: tronco inclinado para frente até as mãos alcançarem o guidão (igual à moto)
	local lean, waist = 0, nil
	local reach = (rig.armL1 + rig.armL2) * 0.95
	local gripL = state.gripLeft and root.CFrame:PointToObjectSpace(state.gripLeft.Position)
	if rig.rigType == "R15" and gripL and rig.joints.Waist and rig.joints.Root then
		local j = rig.joints
		waist = ((j.Root.C0 * j.Root.C1:Inverse()) * j.Waist.C0).Position
		for deg = 0, 40, 2 do
			lean = math.rad(deg)
			local sh = waist + CFrame.Angles(-lean, 0, 0):VectorToWorldSpace(rig.shoulder.Left - waist)
			if (Vector3.new(0, gripL.Y, gripL.Z) - Vector3.new(0, sh.Y, sh.Z)).Magnitude <= reach then
				break
			end
		end
		j.Waist.Transform = CFrame.Angles(-lean, 0, 0)
		local neck = character:FindFirstChild("Head") and character.Head:FindFirstChild("Neck")
		if neck then
			neck.Transform = CFrame.Angles(lean * 0.7, 0, 0) -- olha para a frente
		end
	end

	-- Braços: mãos nas manoplas
	for _, side in ipairs({ "Right", "Left" }) do
		local grip = side == "Left" and state.gripLeft or state.gripRight
		if grip then
			local target = root.CFrame:PointToObjectSpace(grip.Position)
			local shoulder = rig.shoulder[side]
			if waist then
				shoulder = waist + CFrame.Angles(-lean, 0, 0):VectorToWorldSpace(shoulder - waist)
			end
			local upper, elbow = solve(rig.armL1, rig.armL2, shoulder, target, false)
			swing(rig, rig.joints[side .. "Shoulder"], side, upper + lean) -- ângulo em relação ao tronco inclinado
			if rig.rigType == "R15" then
				rig.joints[side .. "Elbow"].Transform = CFrame.Angles(elbow, 0, 0)
				rig.joints[side .. "Wrist"].Transform = CFrame.new() -- mão alinhada ao antebraço, firme na manopla
			end
		end
	end
end

-- Segurar objeto (emprego): as duas mãos vão até o objeto na frente do corpo.
-- Só a pé; na bike as mãos ficam no guidão.
local carriers = setmetatable({}, { __mode = "k" }) -- carriers[character] = medida do boneco

local function holdItem(character, item)
	local rig = carriers[character]
	if not rig then
		rig = RigMeasure.measure(character)
		if not rig then
			return
		end
		carriers[character] = rig
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local target = root.CFrame:PointToObjectSpace(item.Position)
	for _, side in ipairs({ "Right", "Left" }) do
		local upper, elbow = solve(rig.armL1, rig.armL2, rig.shoulder[side], target, false)
		swing(rig, rig.joints[side .. "Shoulder"], side, upper)
		if rig.rigType == "R15" then
			rig.joints[side .. "Elbow"].Transform = CFrame.Angles(elbow, 0, 0)
			rig.joints[side .. "Wrist"].Transform = CFrame.new()
		end
	end
end

local function releaseItem(character)
	local rig = carriers[character]
	carriers[character] = nil
	if rig and rig.rigType == "R15" then
		for _, name in ipairs({ "LeftWrist", "RightWrist" }) do
			rig.joints[name].Transform = CFrame.new()
		end
	end
end

-- Moto (Marco 7.4): o piloto deita um pouco o tronco, põe as mãos no guidom e os pés nas
-- pedaleiras. Os pontos vêm dos Attachments GripLeft/GripRight/PegLeft/PegRight no chassi.
local pilots = setmetatable({}, { __mode = "k" }) -- pilots[character] = medida do boneco

local function rideMoto(character, chassis)
	local rig = pilots[character]
	if not rig then
		rig = RigMeasure.measure(character)
		if not rig then
			return
		end
		pilots[character] = rig
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local function local_(name)
		local a = chassis:FindFirstChild(name)
		return a and root.CFrame:PointToObjectSpace(a.WorldPosition)
	end
	local reach = (rig.armL1 + rig.armL2) * 0.93
	-- Inclina o tronco para frente até a mão alcançar o guidom (só R15: no R6 o tronco é uma peça só)
	local lean, waist = 0, nil
	local gripL = local_("GripLeft")
	if rig.rigType == "R15" and gripL then
		local j = rig.joints
		waist = ((j.Root.C0 * j.Root.C1:Inverse()) * j.Waist.C0).Position
		for deg = 0, 45, 3 do
			lean = math.rad(deg)
			local s = rig.shoulder.Left - waist
			local rotated = waist + CFrame.Angles(-lean, 0, 0):VectorToWorldSpace(s)
			if (Vector3.new(0, gripL.Y, gripL.Z) - Vector3.new(0, rotated.Y, rotated.Z)).Magnitude <= reach then
				break
			end
		end
		j.Root.Transform = CFrame.new()
		j.Waist.Transform = CFrame.Angles(-lean, 0, 0)
		local neck = character:FindFirstChild("Head") and character.Head:FindFirstChild("Neck")
		if neck then
			neck.Transform = CFrame.Angles(lean * 0.7, 0, 0) -- olha para a frente, não para o chão
		end
	end
	for _, side in ipairs({ "Right", "Left" }) do
		local grip = local_("Grip" .. side)
		if grip then
			local shoulder = rig.shoulder[side]
			if waist then
				shoulder = waist + CFrame.Angles(-lean, 0, 0):VectorToWorldSpace(shoulder - waist)
			end
			local upper, elbow = solve(rig.armL1, rig.armL2, shoulder, grip, false)
			swing(rig, rig.joints[side .. "Shoulder"], side, upper + lean) -- ângulo em relação ao tronco deitado
			if rig.rigType == "R15" then
				rig.joints[side .. "Elbow"].Transform = CFrame.Angles(elbow, 0, 0)
				rig.joints[side .. "Wrist"].Transform = CFrame.new()
			end
		end
		local peg = local_("Peg" .. side)
		if peg then
			local thigh, knee = solve(rig.legL1, rig.legL2, rig.hip[side], peg, true)
			swing(rig, rig.joints[side .. "Hip"], side, thigh)
			if rig.rigType == "R15" then
				rig.joints[side .. "Knee"].Transform = CFrame.Angles(knee, 0, 0)
				rig.joints[side .. "Ankle"].Transform = CFrame.Angles(-(thigh + knee), 0, 0)
			end
		end
	end
end

local function leaveMoto(character)
	local rig = pilots[character]
	pilots[character] = nil
	if rig and rig.rigType == "R15" then
		for _, name in ipairs({ "LeftAnkle", "RightAnkle", "LeftWrist", "RightWrist", "Waist" }) do
			rig.joints[name].Transform = CFrame.new()
		end
		local neck = character:FindFirstChild("Head") and character.Head:FindFirstChild("Neck")
		if neck then
			neck.Transform = CFrame.new()
		end
	end
end

-- Lanche da barraca do parque (Marco 7.4): braço direito dobrado segurando na frente do peito
local eaters = setmetatable({}, { __mode = "k" })

local function holdSnack(character)
	local rig = eaters[character]
	if not rig then
		rig = RigMeasure.measure(character)
		if not rig then
			return
		end
		eaters[character] = rig
	end
	if rig.rigType == "R15" then
		swing(rig, rig.joints.RightShoulder, "Right", math.rad(25))
		rig.joints.RightElbow.Transform = CFrame.Angles(math.rad(80), 0, 0)
		rig.joints.RightWrist.Transform = CFrame.new()
	else
		swing(rig, rig.joints.RightShoulder, "Right", math.rad(90))
	end
end

local function dropSnack(character)
	local rig = eaters[character]
	eaters[character] = nil
	if rig and rig.rigType == "R15" then
		rig.joints.RightWrist.Transform = CFrame.new()
	end
end

local function onStepped(_, dt)
	-- Pilotos de moto
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local seat = humanoid and humanoid.SeatPart
		local chassis = seat and seat.Name == "DriverSeat" and seat.Parent and seat.Parent:FindFirstChild("Chassis")
		if chassis and chassis:FindFirstChild("GripLeft") then
			rideMoto(character, chassis)
		elseif character and pilots[character] then
			leaveMoto(character)
		end
	end
	-- Procura bicicletas novas e remove as que sumiram
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local bike = character and character:FindFirstChild("StarterBike")
		local state = character and riders[character]
		-- (também refaz se as peças ainda não tinham chegado do servidor)
		if bike and (not state or state.bike ~= bike or not state.crankMotor) then
			startRider(character, bike)
		elseif not bike and state then
			stopRider(character)
		end
	end
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local busy = character and (riders[character] or pilots[character] or character:FindFirstChild("CarriedItem"))
		if character and character:FindFirstChild("Lanche") and not busy then
			holdSnack(character)
		elseif character and eaters[character] then
			dropSnack(character)
		end
	end
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local item = character and character:FindFirstChild("CarriedItem")
		if item and item:IsA("BasePart") and not riders[character] then
			holdItem(character, item)
		elseif character and carriers[character] then
			releaseItem(character)
		end
	end
	for character, state in pairs(riders) do
		if not character.Parent or not state.bike.Parent then
			stopRider(character)
		else
			animate(character, state, dt)
		end
	end
end

function BikeAnimator.init()
	RunService.Stepped:Connect(onStepped)
end

return BikeAnimator
