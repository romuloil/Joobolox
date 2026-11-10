-- WeaponPose (ModuleScript)
-- Caminho: StarterPlayer > StarterPlayerScripts > Controllers > WeaponPose
-- Marco 10.12: pose de quem segura arma de fogo, igual na vida real.
--   * Fuzil (e submetralhadora): mão direita no cabo, coronha no ombro, mão esquerda embaixo do cano.
--   * Pistola: as duas mãos no cabo, braços esticados na frente do peito.
--   * Sem mirar a arma fica abaixada ("pronta"); mirando (ou logo depois de atirar) ela sobe e
--     acompanha para cima/baixo para onde a pessoa olha.
-- Roda em TODOS os aparelhos para TODOS os bonecos (cada um calcula a pose de todo mundo): o servidor
-- só repassa a inclinação da mira ("MiraPitch") e se a pessoa está mirando ("Mirando"), atributos
-- no boneco. R15 usa IKControl (o próprio Roblox dobra o cotovelo); R6 aponta os braços.
-- Marco 10.20: com arma, o balanço dos braços da animação de andar/correr é zerado antes do IK.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local WeaponPose = {}

local player = Players.LocalPlayer
local states = {} -- states[character] = { ... }
local lastShot = {} -- lastShot[userId] = os.clock() do último tiro visto
local localAim = { pitch = 0, aiming = false } -- o seu boneco usa o valor daqui (sem esperar o servidor)

local RAISE_AFTER_SHOT = 1.4 -- segundos com a arma levantada depois de atirar sem mirar

-- Poses (em "ombros": 1 = metade da distância entre os ombros). Posição do cabo da arma a partir do
-- meio dos ombros (x direita, y cima, z frente negativa) e a inclinação dela (graus, + para cima).
local POSES = {
	fuzil = {
		up = { pos = Vector3.new(0.38, -0.12, -0.95), pitch = 0, yaw = 0 }, -- coronha no ombro, mira na altura do olho
		down = { pos = Vector3.new(0.42, -0.62, -0.85), pitch = -38, yaw = 22 },
		left = CFrame.new(0, -0.08, -1.15), -- mão esquerda: embaixo do cano, à frente do cabo
		pole = Vector3.new(1.6, -1.4, 0.4),
		poleL = Vector3.new(-1.4, -1.6, -0.2),
	},
	-- Marco 10.30: perfuratriz (pesada, duas mãos). Mão direita no lado direito de trás dela, a
	-- esquerda do outro lado, mais na frente. "up" = encostada na porta furando; "down" = carregando.
	perfuratriz = {
		up = { pos = Vector3.new(0.6, -0.6, -1.05), pitch = 0, yaw = 0 },
		down = { pos = Vector3.new(0.75, -1.05, -0.6), pitch = -22, yaw = 6 },
		left = CFrame.new(-1.3, 0.3, -0.75),
		pole = Vector3.new(1.6, -1.2, 0.6),
		poleL = Vector3.new(-1.7, -1.2, 0.2),
	},
	pistola = {
		up = { pos = Vector3.new(0.12, -0.02, -1.95), pitch = 0, yaw = 0 },
		down = { pos = Vector3.new(0.28, -0.75, -1.25), pitch = -40, yaw = 8 },
		left = CFrame.new(-0.14, -0.14, 0.06), -- mão esquerda segurando por baixo da direita
		pole = Vector3.new(1.3, -1.2, 0.3),
		poleL = Vector3.new(-1.3, -1.2, 0.3),
	},
}

local function kindOf(tool)
	if tool:GetAttribute("Use") == "perfuratriz" then
		return "perfuratriz"
	end
	local k = tool:GetAttribute("Kind")
	if k == "pistola" or k == "fuzil" then
		return k
	end
	return tool:GetAttribute("AmmoKind") == "pistola" and "pistola" or "fuzil"
end

local function gunOf(character)
	local tool = character:FindFirstChildOfClass("Tool")
	local use = tool and tool:GetAttribute("Use")
	if use == "gun" or use == "perfuratriz" then
		return tool
	end
	return nil
end

local function lerpAngle(a, b, t)
	return a + (b - a) * t
end

---------------------------------------------------------------------------
-- R15: IKControl
---------------------------------------------------------------------------

local function newAttachment(name, parent)
	local a = parent:FindFirstChild(name)
	if not a then
		a = Instance.new("Attachment")
		a.Name = name
		a.Parent = parent
	end
	return a
end

local function setupR15(character, humanoid)
	local torso = character:FindFirstChild("UpperTorso")
	local rUpper, lUpper = character:FindFirstChild("RightUpperArm"), character:FindFirstChild("LeftUpperArm")
	local rHand, lHand = character:FindFirstChild("RightHand"), character:FindFirstChild("LeftHand")
	local rs = torso and torso:FindFirstChild("RightShoulderRigAttachment")
	local ls = torso and torso:FindFirstChild("LeftShoulderRigAttachment")
	if not (torso and rUpper and lUpper and rHand and lHand and rs and ls) then
		return nil
	end
	local rGrip = rHand:FindFirstChild("RightGripAttachment") or newAttachment("RightGripAttachment", rHand)
	local lGrip = lHand:FindFirstChild("LeftGripAttachment") or newAttachment("LeftGripAttachment", lHand)
	local st = {
		rig = "R15",
		grip = rGrip,
		hand = rHand,
		torso = torso,
		rs = rs,
		ls = ls,
		targetR = newAttachment("PoseArmaD", torso),
		targetL = newAttachment("PoseArmaE", torso),
		poleR = newAttachment("PoseCotoveloD", torso),
		poleL = newAttachment("PoseCotoveloE", torso),
	}
	local function ik(name, root, effector, target, pole, kind, priority)
		local c = humanoid:FindFirstChild(name)
		if not c then
			c = Instance.new("IKControl")
			c.Name = name
		end
		c.Type = kind
		c.ChainRoot = root
		c.EndEffector = effector
		c.Target = target
		c.Pole = pole
		c.Priority = priority
		c.SmoothTime = 0 -- sem atraso: a mão gruda na arma no mesmo quadro
		c.Weight = 0
		c.Enabled = true
		c.Parent = humanoid
		return c
	end
	-- Marco 10.20 (bug do Luís: andando/correndo com a arma o braço "bugava"): as juntas dos braços
	-- (ombro, cotovelo, pulso) guardam o balanço da animação de andar/correr, e o IK partia dessa
	-- pose diferente a cada quadro, então o cotovelo pulava. Agora, com arma na mão, essas juntas são
	-- zeradas antes do IK (step roda no Stepped, depois da animação): o IK sempre parte da mesma pose.
	st.armMotors = {}
	for _, pair in ipairs({ { "RightUpperArm", "RightShoulder" }, { "RightLowerArm", "RightElbow" }, { "RightHand", "RightWrist" }, { "LeftUpperArm", "LeftShoulder" }, { "LeftLowerArm", "LeftElbow" }, { "LeftHand", "LeftWrist" } }) do
		local part = character:FindFirstChild(pair[1])
		local motor = part and part:FindFirstChild(pair[2])
		if motor and motor:IsA("Motor6D") then
			table.insert(st.armMotors, motor)
		end
	end
	st.ikR = ik("PoseIKDireita", rUpper, rGrip, st.targetR, st.poleR, Enum.IKControlType.Transform, 2)
	st.ikL = ik("PoseIKEsquerda", lUpper, lGrip, st.targetL, st.poleL, Enum.IKControlType.Position, 1)
	return st
end

---------------------------------------------------------------------------
-- R6: aponta os braços (Motor6D.Transform, a cada quadro, depois da animação)
---------------------------------------------------------------------------

local function setupR6(character)
	local torso = character:FindFirstChild("Torso")
	local rsM = torso and torso:FindFirstChild("Right Shoulder")
	local lsM = torso and torso:FindFirstChild("Left Shoulder")
	if not (torso and rsM and lsM and rsM:IsA("Motor6D") and lsM:IsA("Motor6D")) then
		return nil
	end
	local arm = character:FindFirstChild("Right Arm")
	return { rig = "R6", torso = torso, rsM = rsM, lsM = lsM, hand = arm, grip = arm and arm:FindFirstChild("RightGripAttachment") }
end

-- Transform do ombro para o braço (eixo -Y dele) apontar para "dir" (mundo)
local function pointArm(motor, dir, weight)
	local p0 = motor.Part0
	if not p0 or dir.Magnitude < 0.01 then
		return
	end
	local joint = p0.CFrame * motor.C0
	local want = joint:VectorToObjectSpace(dir.Unit)
	local base = (motor.C1:Inverse()).Rotation * Vector3.new(0, -1, 0)
	local axis = base:Cross(want)
	local dot = math.clamp(base:Dot(want), -1, 1)
	local angle = math.acos(dot) * weight
	if axis.Magnitude < 1e-4 then
		return
	end
	motor.Transform = CFrame.fromAxisAngle(axis.Unit, angle)
end

---------------------------------------------------------------------------
-- Cálculo da pose
---------------------------------------------------------------------------

-- CFrame do cabo da arma no espaço do tronco (R15: UpperTorso; R6: Torso)
local function gunFrame(center, scale, pose, raise, pitch)
	local up, down = pose.up, pose.down
	local pos = down.pos:Lerp(up.pos, raise) * scale
	local p = lerpAngle(down.pitch, up.pitch, raise) + pitch * (0.35 + 0.65 * raise)
	local y = lerpAngle(down.yaw, up.yaw, raise)
	-- gira em volta do meio dos ombros: assim a arma inteira sobe/desce com a mira
	return CFrame.new(center) * CFrame.Angles(math.rad(pitch * raise), 0, 0) * CFrame.new(pos) * CFrame.Angles(math.rad(p - pitch * raise), math.rad(y), 0)
end

-- Marco 10.12 (teste do Luís: correndo e atirando o cano "tremia" e a arma ia pro chão por um
-- quadro): a arma não fica mais presa na mão. Neste aparelho o encaixe RightGrip passa a prender a
-- arma no TRONCO, na pose; as mãos (IK) é que vão até ela. Assim ela não depende de onde a mão
-- estava no quadro anterior e fica firme. Sem arma ou sem pose, volta a prender na mão.
local function alignGun(st, tool, torsoCf)
	local weld = st.hand and st.hand:FindFirstChild("RightGrip")
	if not (weld and weld:IsA("Weld") and weld.Part1 and weld.Part1.Parent == tool) then
		return
	end
	if st.weight > 0.5 then
		if weld.Part0 ~= st.torso then
			weld.Part0 = st.torso
		end
		weld.C0 = torsoCf
		weld.C1 = tool.Grip
	elseif weld.Part0 ~= st.hand and st.grip then
		weld.Part0 = st.hand
		weld.C0 = st.grip.CFrame
		weld.C1 = tool.Grip
	end
end

local function update(character, st, dt)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local tool = gunOf(character)
	local alive = humanoid and humanoid.Health > 0 and not humanoid.SeatPart and not humanoid.PlatformStand and not character:GetAttribute("Pose") -- Marco 10.26
	local want = (tool and alive) and 1 or 0
	st.weight = st.weight + (want - st.weight) * math.min(1, dt * 12)
	if st.weight < 0.01 and want == 0 then
		st.weight = 0
		if st.ikR then
			st.ikR.Weight = 0
			st.ikL.Weight = 0
		end
		return
	end
	-- mirando? (o seu boneco: na hora; os outros: pelo servidor)
	local aiming, pitch
	local p = Players:GetPlayerFromCharacter(character)
	local drill = tool and tool:GetAttribute("Use") == "perfuratriz"
	if drill then
		-- Marco 10.30: furando = encostada no ponto do corte (inclinação até ele); senão, carregando
		aiming = character:GetAttribute("Perfurando") == true
		pitch = 0
		local target = character:GetAttribute("AlvoFuro")
		local head = character:FindFirstChild("Head")
		if aiming and typeof(target) == "Vector3" and head then
			local d = target - (head.Position - Vector3.new(0, 1, 0))
			local flat = Vector3.new(d.X, 0, d.Z).Magnitude
			pitch = math.clamp(math.deg(math.atan2(d.Y, math.max(flat, 0.5))), -35, 40)
		end
	elseif p == player then
		aiming, pitch = localAim.aiming, localAim.pitch
	else
		aiming = character:GetAttribute("Mirando") == true
		pitch = character:GetAttribute("MiraPitch") or 0
	end
	if not drill and p and lastShot[p.UserId] and os.clock() - lastShot[p.UserId] < RAISE_AFTER_SHOT then
		aiming = true
	end
	st.raise = st.raise + ((aiming and 1 or 0) - st.raise) * math.min(1, dt * 11)
	st.pitch = st.pitch + (pitch - st.pitch) * math.min(1, dt * 14)
	local kind = tool and kindOf(tool) or st.kind or "fuzil"
	st.kind = kind
	local pose = POSES[kind]

	if st.rig == "R15" then
		local r, l = st.rs.Position, st.ls.Position
		local center = (r + l) / 2
		local scale = math.max(0.5, (r - l).Magnitude / 2)
		local cf = gunFrame(center, scale, pose, st.raise, st.pitch)
		if kind == "perfuratriz" and character:GetAttribute("Empurrando") then
			-- tremendo enquanto fura
			local t = os.clock() * 55
			cf = cf * CFrame.new(math.sin(t) * 0.035, math.cos(t * 1.3) * 0.035, math.sin(t * 0.7) * 0.05) * CFrame.Angles(math.rad(math.sin(t * 1.1) * 1.2), 0, 0)
		end
		st.targetR.CFrame = cf
		local leftCf = cf * CFrame.new(pose.left.Position * scale)
		st.targetL.CFrame = leftCf
		st.poleR.Position = center + pose.pole * scale
		st.poleL.Position = center + pose.poleL * scale
		for _, motor in ipairs(st.armMotors) do
			motor.Transform = st.weight >= 0.99 and CFrame.identity or motor.Transform:Lerp(CFrame.identity, st.weight)
		end
		st.ikR.Weight = st.weight
		st.ikL.Weight = st.weight
		if tool then
			alignGun(st, tool, cf)
		end
	else
		local torso = st.torso
		local scale = torso.Size.X / 2
		local center = Vector3.new(0, torso.Size.Y * 0.3, 0)
		local cf = torso.CFrame * gunFrame(center, scale, pose, st.raise, st.pitch)
		local rJoint = (torso.CFrame * st.rsM.C0).Position
		local lJoint = (torso.CFrame * st.lsM.C0).Position
		pointArm(st.rsM, cf.Position - rJoint, st.weight)
		pointArm(st.lsM, (cf * CFrame.new(pose.left.Position * scale)).Position - lJoint, st.weight)
		if tool then
			alignGun(st, tool, torso.CFrame:ToObjectSpace(cf))
		end
	end
end

local function stateFor(character)
	local st = states[character]
	if st ~= nil then
		return st or nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil
	end
	if humanoid.RigType == Enum.HumanoidRigType.R15 then
		st = setupR15(character, humanoid)
	else
		st = setupR6(character)
	end
	if not st then
		states[character] = false
		return nil
	end
	st.weight, st.raise, st.pitch = 0, 0, 0
	states[character] = st
	character.AncestryChanged:Connect(function()
		if not character.Parent then
			states[character] = nil
		end
	end)
	return st
end

local function step(_, dt)
	for _, p in ipairs(Players:GetPlayers()) do
		local character = p.Character
		if character and character.Parent and (gunOf(character) or states[character]) then
			local st = stateFor(character)
			if st then
				local ok, err = pcall(update, character, st, dt)
				if not ok then
					warn("[WeaponPose] " .. tostring(err))
					states[character] = false
				end
			end
		end
	end
end

-- O seu boneco: inclinação da mira (graus) e se está mirando agora
function WeaponPose.setLocal(pitch, aiming)
	localAim.pitch = pitch
	localAim.aiming = aiming
end

-- Alguém atirou: a arma dele fica levantada um pouquinho
function WeaponPose.shot(userId)
	if userId then
		lastShot[userId] = os.clock()
	end
end

function WeaponPose.init()
	RunService.Stepped:Connect(step)
	Players.PlayerRemoving:Connect(function(p)
		lastShot[p.UserId] = nil
	end)
end

return WeaponPose
