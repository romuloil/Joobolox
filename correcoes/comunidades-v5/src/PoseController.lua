-- PoseController (ModuleScript)
-- Caminho: StarterPlayer > StarterPlayerScripts > Controllers > PoseController
-- Marco 10.26: animações feitas por código (o Roblox só toca animação do próprio dono do jogo, então
-- as da loja não funcionam aqui). Quem tem a tag "PoseBanco" e o atributo "Pose" (NPCKit.pose, no
-- servidor) mexe as juntas aqui, em todos os aparelhos. Para trocar por uma animação de verdade, é
-- só tocar a sua no lugar da pose com o mesmo nome.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local RigMeasure = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("RigMeasure"))

local PoseController = {}

-- graus por junta: R/L = direita/esquerda; S ombro, E cotovelo, H quadril, K joelho; W cintura, N pescoço
-- root = quanto o corpo desce; wave = { junta, eixo (1 x, 2 y, 3 z), amplitude, velocidade }
local POSES = {
	maos = { -- rendido, mãos para cima
		RS = { 170, 0, -8 }, LS = { 170, 0, 8 }, RE = { 18, 0, 0 }, LE = { 18, 0, 0 }, N = { 6, 0, 0 },
		wave = { { "RS", 1, 3, 9 }, { "LS", 1, 3, 10 } },
	},
	refem = { -- ajoelhado, mãos na cabeça
		root = 1.7, RH = { 8, 0, 0 }, LH = { 8, 0, 0 }, RK = { -95, 0, 0 }, LK = { -95, 0, 0 },
		RS = { 155, 0, 28 }, LS = { 155, 0, -28 }, RE = { 115, 0, 0 }, LE = { 115, 0, 0 }, W = { -10, 0, 0 }, N = { -14, 0, 0 },
		wave = { { "W", 1, 1.2, 7 } },
	},
	amarrado = { -- ajoelhado, mãos para trás
		root = 1.7, RH = { 8, 0, 0 }, LH = { 8, 0, 0 }, RK = { -95, 0, 0 }, LK = { -95, 0, 0 },
		RS = { -32, 0, 14 }, LS = { -32, 0, -14 }, RE = { 18, 0, 0 }, LE = { 18, 0, 0 }, N = { -18, 0, 0 },
		wave = { { "N", 2, 8, 1.3 } },
	},
	amarrar = { -- agachado, mexendo as mãos para a frente
		root = 1.4, RH = { 55, 0, 0 }, LH = { -10, 0, 0 }, RK = { -70, 0, 0 }, LK = { -95, 0, 0 },
		W = { -22, 0, 0 }, RS = { 62, 0, 0 }, LS = { 62, 0, 0 }, RE = { 30, 0, 0 }, LE = { 30, 0, 0 },
		wave = { { "RS", 1, 14, 9 }, { "LS", 1, -14, 9 }, { "LE", 1, 12, 11 } },
	},
	pegar = { -- curvado, puxando coisas com as duas mãos
		root = 0.6, RH = { 30, 0, 0 }, LH = { 30, 0, 0 }, RK = { -40, 0, 0 }, LK = { -40, 0, 0 }, W = { -38, 0, 0 },
		RS = { 70, 0, 0 }, LS = { 70, 0, 0 }, RE = { 25, 0, 0 }, LE = { 25, 0, 0 },
		wave = { { "RS", 1, 24, 7 }, { "LS", 1, -24, 7 } },
	},
	digitar = { -- em pé, digitando
		RS = { 58, 0, -8 }, LS = { 58, 0, 8 }, RE = { 42, 0, 0 }, LE = { 42, 0, 0 }, W = { -8, 0, 0 }, N = { -12, 0, 0 },
		wave = { { "RE", 1, 6, 17 }, { "LE", 1, -6, 19 } },
	},
	agachar = { -- agachado, mãos no que está montando
		root = 1.4, RH = { 55, 0, 0 }, LH = { -10, 0, 0 }, RK = { -70, 0, 0 }, LK = { -95, 0, 0 },
		W = { -14, 0, 0 }, RS = { 76, 0, 0 }, LS = { 76, 0, 0 }, RE = { 15, 0, 0 }, LE = { 15, 0, 0 },
		wave = { { "RS", 3, 7, 5 }, { "LS", 3, -7, 5 } },
	},
	girar = { -- girando o volante do cofre
		RS = { 85, 0, -6 }, LS = { 85, 0, 6 }, RE = { 15, 0, 0 }, LE = { 15, 0, 0 },
		wave = { { "RS", 1, 22, 2.4 }, { "LS", 1, -22, 2.4 }, { "W", 2, 10, 2.4 } },
	},
	forca = { -- forçando uma porta
		RS = { 95, 0, 0 }, LS = { 95, 0, 0 }, W = { -18, 0, 0 }, RH = { 22, 0, 0 }, LH = { -18, 0, 0 },
		wave = { { "W", 1, 7, 6 } },
	},
	-- Marco 10.31: academia da praia (bob = { quanto o corpo sobe/desce, velocidade })
	barra = { -- pendurado na barra fixa, fazendo barra
		root = -2.6, bob = { 1.1, 3 }, RS = { 172, 0, -10 }, LS = { 172, 0, 10 }, RK = { -25, 0, 0 }, LK = { -25, 0, 0 },
		wave = { { "RE", 1, 35, 3 }, { "LE", 1, 35, 3 }, { "RS", 1, -12, 3 }, { "LS", 1, -12, 3 } },
	},
	argola = { -- pendurado nas argolas
		root = -1.8, bob = { 0.9, 2.6 }, RS = { 165, 0, -22 }, LS = { 165, 0, 22 }, RH = { 40, 0, 0 }, LH = { 40, 0, 0 },
		wave = { { "RE", 1, 30, 2.6 }, { "LE", 1, 30, 2.6 }, { "W", 3, 6, 1.3 } },
	},
	paralela = { -- mergulho nas paralelas
		root = -0.8, bob = { 0.9, 3.2 }, RS = { -12, 0, 8 }, LS = { -12, 0, -8 }, RK = { -70, 0, 0 }, LK = { -70, 0, 0 }, RH = { 15, 0, 0 }, LH = { 15, 0, 0 },
		wave = { { "RE", 1, 30, 3.2 }, { "LE", 1, 30, 3.2 } },
	},
	peso = { -- levantando a barra acima da cabeça
		RS = { 150, 0, -25 }, LS = { 150, 0, 25 }, RE = { 40, 0, 0 }, LE = { 40, 0, 0 }, RH = { 10, 0, 0 }, LH = { -10, 0, 0 },
		wave = { { "RS", 1, 22, 2.8 }, { "LS", 1, 22, 2.8 }, { "RE", 1, 38, 2.8 }, { "LE", 1, 38, 2.8 } },
	},
	gritar = { -- braço para cima, mandando todo mundo deitar
		RS = { 150, 0, -12 }, RE = { 10, 0, 0 }, LS = { 25, 0, 8 }, N = { 14, 0, 0 },
		wave = { { "RS", 1, 18, 10 } },
	},
	-- Marco 10.32: surfe (o corpo inteiro já vem deitado/de lado pelo HumanoidRootPart)
	remar = { -- deitado na prancha, braçadas alternadas e a cabeça olhando para a frente
		RS = { 115, 0, -6 }, LS = { 115, 0, 6 }, RE = { 10, 0, 0 }, LE = { 10, 0, 0 }, N = { 48, 0, 0 },
		RH = { -4, 0, 0 }, LH = { -4, 0, 0 }, RK = { -8, 0, 0 }, LK = { -8, 0, 0 },
		wave = { { "RS", 1, 58, 4.2 }, { "LS", 1, -58, 4.2 }, { "RK", 1, 10, 6 }, { "LK", 1, -10, 6 } },
	},
	surfar = { -- agachado de lado na prancha, braços abertos para equilibrar, olhando para onde vai
		root = 0.75, RH = { 40, 0, 0 }, LH = { 40, 0, 0 }, RK = { -62, 0, 0 }, LK = { -62, 0, 0 },
		W = { -12, -22, 0 }, N = { 0, -48, 0 }, RS = { 12, 0, 68 }, LS = { 12, 0, -68 }, RE = { 22, 0, 0 }, LE = { 22, 0, 0 },
		wave = { { "W", 3, 4, 1.7 }, { "RS", 3, 9, 2.1 }, { "LS", 3, -9, 2.3 } },
	},
	frescobol = { -- raquete na frente, batendo na bolinha (mesmo ritmo da bola: 1,4 s)
		RS = { 70, 0, 12 }, RE = { 35, 0, 0 }, LS = { 20, 0, -10 }, RH = { 6, 0, 0 }, LH = { -6, 0, 0 },
		wave = { { "RS", 1, 28, 4.49 }, { "RE", 1, 18, 4.49 }, { "W", 2, 8, 4.49 } },
	},
	castelo = { -- criança ajoelhada fazendo castelinho
		root = 1.05, RH = { 8, 0, 0 }, LH = { 8, 0, 0 }, RK = { -95, 0, 0 }, LK = { -95, 0, 0 }, W = { -20, 0, 0 },
		RS = { 45, 0, 0 }, LS = { 45, 0, 0 }, RE = { 30, 0, 0 }, LE = { 30, 0, 0 }, N = { -18, 0, 0 },
		wave = { { "RS", 1, 16, 3 }, { "LS", 1, -16, 3 } },
	},
}

local R15 = {
	RS = { "RightUpperArm", "RightShoulder" }, LS = { "LeftUpperArm", "LeftShoulder" },
	RE = { "RightLowerArm", "RightElbow" }, LE = { "LeftLowerArm", "LeftElbow" },
	RH = { "RightUpperLeg", "RightHip" }, LH = { "LeftUpperLeg", "LeftHip" },
	RK = { "RightLowerLeg", "RightKnee" }, LK = { "LeftLowerLeg", "LeftKnee" },
	W = { "UpperTorso", "Waist" }, N = { "Head", "Neck" }, ROOT = { "LowerTorso", "Root" },
}
local R6 = {
	RS = { "Torso", "Right Shoulder" }, LS = { "Torso", "Left Shoulder" },
	RH = { "Torso", "Right Hip" }, LH = { "Torso", "Left Hip" },
	N = { "Torso", "Neck" }, ROOT = { "HumanoidRootPart", "RootJoint" },
}

local states = {} -- states[model] = { motors, weight }

---------------------------------------------------------------------------
-- Marco 10.32: academia da praia com as mãos NO aparelho. O servidor põe o boneco no lugar certo
-- (pendurado, apoiado ou deitado) e manda "PoseAlvo" (a barra / o banco). Aqui cada braço é
-- calculado (ombro -> cotovelo -> mão) para a mão ficar na barra enquanto o corpo sobe e desce.
-- Só R15 (R6 não tem cotovelo: usa a pose da tabela acima).
---------------------------------------------------------------------------

local function rotBetween(a, b)
	local dot = math.clamp(a:Dot(b), -1, 1)
	if dot > 0.99999 then
		return CFrame.identity
	end
	local axis = a:Cross(b)
	if axis.Magnitude < 1e-6 then
		axis = math.abs(a.X) < 0.9 and a:Cross(Vector3.xAxis) or a:Cross(Vector3.yAxis)
	end
	return CFrame.fromAxisAngle(axis.Unit, math.acos(dot))
end

-- braço de um lado: mão em "target", cotovelo apontando para "pole" (direção no mundo)
local function solveArm(UT, m, right, target, pole, w)
	local j = m.joints
	local sh = right and j.RightShoulder or j.LeftShoulder
	local el = right and j.RightElbow or j.LeftElbow
	local wr = right and j.RightWrist or j.LeftWrist
	local J = UT * sh.C0
	local S = J.Position
	local L1, L2 = m.armL1, m.armL2
	local v = target - S
	local d = math.clamp(v.Magnitude, 0.05, (L1 + L2) * 0.999)
	local dir = v.Magnitude > 1e-4 and v.Unit or -J.UpVector
	local a = (L1 * L1 - L2 * L2 + d * d) / (2 * d)
	local h = math.sqrt(math.max(L1 * L1 - a * a, 0))
	local p = pole - dir * pole:Dot(dir)
	p = p.Magnitude > 1e-4 and p.Unit or J.LookVector
	local E = S + dir * a + p * h
	local T = S + dir * d
	local r1 = (sh.C1:Inverse() * el.C0.Position).Unit
	local T1 = rotBetween(r1, J:VectorToObjectSpace((E - S).Unit))
	local upper = J * T1 * sh.C1:Inverse()
	local J2 = upper * el.C0
	local r2 = (el.C1:Inverse() * wr.C0.Position).Unit
	local T2 = rotBetween(r2, J2:VectorToObjectSpace((T - E).Unit))
	sh.Transform = sh.Transform:Lerp(T1, w)
	el.Transform = el.Transform:Lerp(T2, w)
end

local function phase(now, period)
	return (1 - math.cos(now * 2 * math.pi / period)) / 2
end

-- cada aparelho: root = quanto o corpo sobe (espaço do HumanoidRootPart), legs = graus das pernas,
-- hands(UT) = mão direita, mão esquerda, cotovelo direito, cotovelo esquerdo e (supino) a barra
local GYM = {
	barra = function(c)
		local p = phase(c.now, 2.4)
		local a = c.alvo
		local r, look = a.RightVector, a.LookVector
		return {
			root = Vector3.new(0, c.arm * 0.6 * p, 0),
			legs = { RH = { 12, 0, 0 }, LH = { 12, 0, 0 }, RK = { -40, 0, 0 }, LK = { -40, 0, 0 } },
			hands = function()
				return a.Position + r * c.shW * 1.4, a.Position - r * c.shW * 1.4, r + look * 0.5, -r + look * 0.5
			end,
		}
	end,
	argola = function(c)
		local p = phase(c.now, 2.8)
		local a = c.alvo
		local r, look = a.RightVector, a.LookVector
		return {
			root = Vector3.new(0, c.arm * 0.5 * p, 0),
			legs = { RH = { 80, 0, 0 }, LH = { 80, 0, 0 }, RK = { -6, 0, 0 }, LK = { -6, 0, 0 } }, -- "L" nas argolas
			hands = function()
				return a.Position + r * 1.2, a.Position - r * 1.2, r + look * 0.7, -r + look * 0.7
			end,
		}
	end,
	paralela = function(c)
		local p = phase(c.now, 2.2)
		local a = c.alvo
		local r, look = a.RightVector, a.LookVector
		return {
			root = Vector3.new(0, -c.arm * 0.45 * p, 0),
			legs = { RH = { -12, 0, 0 }, LH = { -12, 0, 0 }, RK = { -80, 0, 0 }, LK = { -80, 0, 0 } },
			hands = function()
				local z = c.hrp.Position
				local base = Vector3.new(a.Position.X, a.Position.Y, a.Position.Z) + look * look:Dot(z - a.Position)
				return base + r * 1.6, base - r * 1.6, -look + r * 0.2, -look - r * 0.2
			end,
		}
	end,
	peso = function(c)
		local p = phase(c.now, 2.6)
		local a = c.alvo
		local r = a.RightVector
		local up = c.hrp.LookVector -- deitado: o rosto olha para cima
		return {
			root = Vector3.zero,
			legs = { RH = { 8, 0, 0 }, LH = { 8, 0, 0 }, RK = { -85, 0, 0 }, LK = { -85, 0, 0 } },
			hands = function(UT, m)
				local j = m.joints
				local mid = ((UT * j.RightShoulder.C0).Position + (UT * j.LeftShoulder.C0).Position) / 2
				local h = 0.8 + (c.arm * 0.93 - 0.8) * (1 - p)
				local bar = mid + up * h
				local half = c.shW * 1.6
				return bar + r * half, bar - r * half, r - up * 0.6, -r - up * 0.6, CFrame.fromMatrix(bar, r, up)
			end,
		}
	end,
}

local function nearestBarbell(pos)
	local best, bestD = nil, 6
	for _, m in ipairs(CollectionService:GetTagged("BarraSupino")) do
		local home = m:GetAttribute("Home")
		if typeof(home) == "CFrame" and (home.Position - pos).Magnitude < bestD then
			best, bestD = m, (home.Position - pos).Magnitude
		end
	end
	return best
end

local function gymStep(model, st, spec, w, now)
	local m = st.measure
	local hrp = model:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end
	local j = m.joints
	local c = { alvo = st.alvo, hrp = hrp.CFrame, now = now, arm = m.armL1 + m.armL2, shW = math.abs(m.shoulder.Right.X) }
	local g = spec(c)
	j.Root.Transform = j.Root.Transform:Lerp(CFrame.new(g.root), w)
	j.Waist.Transform = j.Waist.Transform:Lerp(CFrame.identity, w)
	for key, a in pairs(g.legs) do
		local motor = st.motors[key]
		if motor then
			motor.Transform = motor.Transform:Lerp(CFrame.Angles(math.rad(a[1]), math.rad(a[2]), math.rad(a[3])), w)
		end
	end
	local LT = hrp.CFrame * j.Root.C0 * j.Root.Transform * j.Root.C1:Inverse()
	local UT = LT * j.Waist.C0 * j.Waist.Transform * j.Waist.C1:Inverse()
	local R, L, poleR, poleL, prop = g.hands(UT, m)
	solveArm(UT, m, true, R, poleR, w)
	solveArm(UT, m, false, L, poleL, w)
	-- supino: a barra vai do suporte até as mãos (só no aparelho de cada um, todos veem igual)
	if prop then
		st.prop = st.prop or nearestBarbell(st.alvo.Position)
		local home = st.prop and st.prop:GetAttribute("Home")
		if home then
			st.prop:PivotTo(home:Lerp(prop, w))
		end
	end
	if w <= 0 and st.prop then
		local home = st.prop:GetAttribute("Home")
		if home then
			st.prop:PivotTo(home)
		end
		st.prop = nil
	end
end

-- Marco 10.31: "pegar" também vem do servidor nos assaltos. Se neste aparelho a animação publicada
-- (GrabAnim, prioridade Action4) carregou e está tocando nesse boneco, ela manda e a pose sai;
-- se não carregou (dono diferente, por exemplo), a pose por código aparece para todo mundo.
local SOFT = { pegar = true }
local function realAnimPlaying(model)
	local hum = model:FindFirstChildOfClass("Humanoid")
	local animator = hum and hum:FindFirstChildOfClass("Animator")
	if not animator then
		return false
	end
	for _, t in ipairs(animator:GetPlayingAnimationTracks()) do
		if t.Priority == Enum.AnimationPriority.Action4 and t.Length > 0 then
			return true
		end
	end
	return false
end

local function motorsOf(model)
	local map = model:FindFirstChild("UpperTorso") and R15 or R6
	local out = {}
	for key, ref in pairs(map) do
		local part = model:FindFirstChild(ref[1])
		local motor = part and part:FindFirstChild(ref[2])
		if motor and (motor:IsA("Motor6D") or motor:IsA("AnimationConstraint")) then -- os rigs novos usam AnimationConstraint
			out[key] = motor
		end
	end
	return out
end

local function step(dt)
	local now = os.clock()
	for _, model in ipairs(CollectionService:GetTagged("PoseBanco")) do
		local name = model:GetAttribute("Pose")
		if name and SOFT[name] and realAnimPlaying(model) then
			name = nil
		end
		local st = states[model]
		if name or (st and st.weight > 0) then
			if not st then
				st = { motors = motorsOf(model), weight = 0 }
				states[model] = st
				model.Destroying:Once(function()
					states[model] = nil
				end)
			end
			if name then
				st.last = name
			end
			st.weight = math.clamp(st.weight + dt * (name and 7 or -7), 0, 1)
			local pose = POSES[st.last]
			-- Marco 10.32: aparelho da academia com o lugar das mãos (PoseAlvo)
			local alvo = model:GetAttribute("PoseAlvo")
			if typeof(alvo) == "CFrame" then
				st.alvo = alvo
			end
			local gym = GYM[st.last]
			if gym and st.alvo then
				if st.measure == nil then
					st.measure = RigMeasure.measure(model) or false
				end
				if st.measure and st.measure.rigType == "R15" then
					gymStep(model, st, gym, st.weight, now)
					pose = nil -- já fez tudo
				end
			end
			if st.weight <= 0 and not name then
				st.alvo = nil
			end
			if pose then
				-- só as juntas da pose; o resto continua na animação normal
				local w = st.weight
				local extra = {}
				for _, wave in ipairs(pose.wave or {}) do
					local e = extra[wave[1]] or { 0, 0, 0 }
					e[wave[2]] += wave[3] * math.sin(now * wave[4])
					extra[wave[1]] = e
				end
				for key, motor in pairs(st.motors) do
					local a = pose[key]
					local e = extra[key]
					if key == "ROOT" then
						if pose.root or pose.bob then
							local drop = (pose.root or 0) + (pose.bob and pose.bob[1] * math.sin(now * pose.bob[2]) or 0)
							motor.Transform = CFrame.identity:Lerp(CFrame.new(0, -drop, 0), w) * motor.Transform
						end
					elseif a or e then
						a = a or { 0, 0, 0 }
						e = e or { 0, 0, 0 }
						local cf = CFrame.Angles(math.rad(a[1] + e[1]), math.rad(a[2] + e[2]), math.rad(a[3] + e[3]))
						motor.Transform = motor.Transform:Lerp(cf, w)
					end
				end
			end
		end
	end
end

function PoseController.init()
	-- PreSimulation: roda depois do Animator (no Stepped a animação normal apagava a pose)
	RunService.PreSimulation:Connect(step)
end

return PoseController
