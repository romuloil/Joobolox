-- CarController (ModuleScript)
-- Caminho: StarterPlayer > StarterPlayerScripts > Controllers > CarController
-- Direção do carro, no cliente de quem dirige (o servidor passa a física do carro para o motorista).
-- Lê o controle do VehicleSeat (WASD/setas no PC, analógico no celular, gatilhos no controle)
-- e move o chassi: acelera, freia, dá ré, faz curva e acompanha a altura do chão.
-- Também gira as rodas (e esterça as da frente) e abre as portas de todos os carros que este jogador vê.
-- Valores do carro (velocidade, aceleração...) vêm de GameConfig.Cars.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))
local MobileButtons = require(script.Parent:WaitForChild("MobileButtons"))

local CarController = {}

local player = Players.LocalPlayer
local drive = nil -- estado de quem dirige: { car, chassis, lv, ao, spec, speed, yaw }
local spin = {} -- spin[car] = ângulo das rodas
local doorOpen = {} -- doorOpen[car] = 0 (fechada) a 1 (aberta)
local steerAngle = 0
local handbrakeHeld = false -- freio de mão (Shift no PC, botão "Freio" no celular, X no controle)
local stepWater -- Marco 10.32 (definida mais abaixo)
local wheelieHeld = false -- grau da moto (Q no PC, botão "Grau" no celular, Y no controle)

local function specOf(car)
	for _, spec in pairs(GameConfig.Cars) do
		if spec.Name == car:GetAttribute("Spec") then
			return spec
		end
	end
	return GameConfig.Cars.L5
end

local function yawOf(cf)
	local look = cf.LookVector
	return math.atan2(-look.X, -look.Z)
end

local function currentSeat()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local seat = humanoid and humanoid.SeatPart
	if seat and seat:IsA("VehicleSeat") and seat:GetAttribute("CarSeat") then
		return seat
	end
	return nil
end

local STOPPED = 0.5 -- abaixo disso (studs/s) o carro conta como parado

local function approach(value, target, step)
	if value < target then
		return math.min(value + step, target)
	end
	return math.max(value - step, target)
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true -- Marco 10.32: o chão é o fundo do mar, não a superfície da água
local waterParams = RaycastParams.new()
waterParams.FilterType = Enum.RaycastFilterType.Exclude
waterParams.IgnoreWater = false

-- Marco 10.32: altura da superfície da água (Terrain) em cima do carro, ou nil se não tem água
local function waterLevel(position, ignore)
	waterParams.FilterDescendantsInstances = ignore
	local hit = Workspace:Raycast(position + Vector3.new(0, 20, 0), Vector3.new(0, -60, 0), waterParams)
	if hit and hit.Material == Enum.Material.Water then
		return hit.Position.Y
	end
	return nil
end

local function groundY(chassis, car)
	local ignore = { car }
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(ignore, p.Character)
		end
	end
	local npcs = Workspace:FindFirstChild("NPCs")
	if npcs then
		table.insert(ignore, npcs)
	end
	rayParams.FilterDescendantsInstances = ignore
	local hit = Workspace:Raycast(chassis.Position + Vector3.new(0, 4, 0), Vector3.new(0, -30, 0), rayParams)
	return hit and hit.Position.Y
end

-- Paredes (Marco 6.3, refeito): quem resolve a batida é este código, não a física empurrando.
--   * Antes de andar, uma caixa um pouco MENOR que o chassi (SKIN de folga em cada lado) é
--     lançada na direção do movimento (Blockcast). Como ela começa sempre fora da parede, a
--     batida é vista certinho: o carro chega a encostar, a parte da velocidade que entraria na
--     parede é cortada e o resto desliza ao longo dela.
--   * Para trás (ré) a caixa é lançada para trás, então uma parede na frente nunca impede a ré.
--   * Girar o volante encostado numa parede: se o giro faria o carro entrar nela, ele não gira
--     (testa a posição girada antes; não prende o carro).
--   * Se mesmo assim o carro ficar dentro de algo, ele é empurrado para fora pelo lado mais perto
--     (só a velocidade que entraria MAIS na parede é cortada: ré e volante continuam valendo).
--     Preso por mais de meio segundo, volta para o último lugar livre (Marco 6.4).
-- A caixa de teste começa um pouco acima do chão, para calçada e meio-fio não contarem como parede.
local castParams = RaycastParams.new()
castParams.FilterType = Enum.RaycastFilterType.Exclude
castParams.RespectCanCollide = true
local overlapParams = OverlapParams.new()
overlapParams.FilterType = Enum.RaycastFilterType.Exclude
overlapParams.RespectCanCollide = true
castParams.CollisionGroup = "Veiculos" -- ignora o que o carro atravessa (jogadores, NPCs)
overlapParams.CollisionGroup = "Veiculos"
local CAST_LIFT = 0.3
local SKIN = 0.3

local probe -- peça invisível (só deste cliente) para testar uma posição antes de ir para ela
local function probeAt(cf, size)
	if not probe then
		probe = Instance.new("Part")
		probe.Name = "CarProbe"
		probe.Anchored = true
		probe.CanCollide = false
		probe.CanTouch = false
		probe.CanQuery = false
		probe.Transparency = 1
		probe.Parent = Workspace.CurrentCamera
	end
	probe.Size = size
	probe.CFrame = cf
	return probe
end

local function testSize(chassis)
	return Vector3.new(chassis.Size.X - SKIN * 2, chassis.Size.Y - CAST_LIFT * 2, chassis.Size.Z - SKIN * 2)
end

-- true se o carro, nesta posição/direção, ficaria dentro de alguma coisa
local function blockedAt(chassis, cf)
	castParams.FilterDescendantsInstances = rayParams.FilterDescendantsInstances
	overlapParams.FilterDescendantsInstances = rayParams.FilterDescendantsInstances
	local p = probeAt(cf * CFrame.new(0, CAST_LIFT, 0), testSize(chassis))
	return #Workspace:GetPartsInPart(p, overlapParams) > 0
end

-- Direção (no chão) para o carro sair de dentro de uma peça: do ponto da peça mais perto do
-- centro do carro até o centro. Se o centro estiver dentro dela, sai pelo lado mais perto.
local function pushOutOf(part, pos)
	local rel = part.CFrame:PointToObjectSpace(pos)
	local half = part.Size / 2
	local out = rel - Vector3.new(math.clamp(rel.X, -half.X, half.X), rel.Y, math.clamp(rel.Z, -half.Z, half.Z))
	if out.Magnitude < 0.01 then
		if half.X - math.abs(rel.X) < half.Z - math.abs(rel.Z) then
			out = Vector3.new(rel.X >= 0 and 1 or -1, 0, 0)
		else
			out = Vector3.new(0, 0, rel.Z >= 0 and 1 or -1)
		end
	end
	local w = part.CFrame:VectorToWorldSpace(out)
	w = Vector3.new(w.X, 0, w.Z)
	return w.Magnitude > 0.01 and w.Unit or nil
end

-- Devolve: velocidade corrigida, empurrão para fora (só nesta batida) e se bateu
local function blockWalls(chassis, velocity, dt)
	local size = testSize(chassis)
	-- caixa sempre reta (sem a inclinação da moto nem o grau), senão a traseira "entra" no chão
	local box = CFrame.new(chassis.Position) * CFrame.Angles(0, drive.yaw, 0) * CFrame.new(0, CAST_LIFT, 0)
	castParams.FilterDescendantsInstances = rayParams.FilterDescendantsInstances
	overlapParams.FilterDescendantsInstances = rayParams.FilterDescendantsInstances
	local inside = Workspace:GetPartsInPart(probeAt(box, size), overlapParams)
	local push = Vector3.zero
	local blocked = false
	if #inside > 0 then
		-- Ficou dentro de algo: tira só a parte da velocidade que entra mais nele (a ré e o
		-- volante continuam funcionando) e empurra para fora
		drive.stuck = (drive.stuck or 0) + dt
		for _, part in ipairs(inside) do
			local n = pushOutOf(part, chassis.Position)
			if n then
				local into = -velocity:Dot(n)
				if into > 0 then
					velocity += n * into
				end
				push += n
			end
		end
		if push.Magnitude > 0.01 then
			push = push.Unit * 10
		end
		blocked = true
		-- preso por mais de meio segundo: volta para o último lugar livre
		if drive.stuck > 0.5 and drive.safe then
			chassis.CFrame = drive.safe
			chassis.AssemblyLinearVelocity = Vector3.zero
			drive.yaw = yawOf(drive.safe)
			drive.stuck = 0
			return Vector3.zero, Vector3.zero, true
		end
	else
		drive.stuck = 0
		drive.safe = chassis.CFrame
	end
	-- Antes de andar: a caixa é lançada na direção do movimento; até 2 paredes (canto)
	for _ = 1, 2 do
		if velocity.Magnitude < 0.5 then
			break
		end
		local hit = Workspace:Blockcast(box, size, velocity.Unit * (velocity.Magnitude * dt + SKIN + 1), castParams)
		-- distância ~0 = a caixa já começou encostada/dentro (tratado acima); chão não é parede
		if not hit or hit.Distance < 0.05 or math.abs(hit.Normal.Y) > 0.6 then
			break
		end
		local n = Vector3.new(hit.Normal.X, 0, hit.Normal.Z)
		if n.Magnitude < 0.01 then
			break
		end
		n = n.Unit
		local into = -velocity:Dot(n) -- velocidade indo para dentro da parede
		if into <= 0 then
			break
		end
		local allowed = math.max(0, hit.Distance - SKIN - 0.05) / dt -- pode chegar até encostar, sem entrar
		if into <= allowed then
			break
		end
		velocity += n * (into - allowed)
		blocked = true
	end
	return velocity, push, blocked
end

-- Marco 9.16: física de drift "de verdade" (só nos carros com spec.RealDrift, a BMW dos admins).
-- Dois jeitos de andar:
--   * com aderência: modelo de bicicleta (frente e trás, pneus que saturam). O volante é pesado:
--     gira devagar e abre menos quanto mais rápido. Acelerando forte numa curva a traseira fica mais
--     leve, mas o carro não sai de lado sozinho;
--   * no drift: começa com o freio de mão + volante (ou se a traseira escapar sozinha). O carro
--     segura um ângulo de lado enquanto tem gás; o volante para dentro da curva abre mais o ângulo,
--     o contra-esterço fecha e tira do drift, soltar o gás termina aos poucos. Freio de mão no
--     meio do drift abre mais. A velocidade cai pouco, para o drift fluir.
-- Ajustado num simulador em Python antes (tools/driftsim.py).
local function tireForce(slip, stiffness, peak, slide)
	if peak <= 0 then
		return 0
	end
	local x = stiffness * math.abs(slip) / peak
	if x <= 1 then
		return stiffness * slip
	end
	local f = peak * (slide + (1 - slide) * math.exp(-(x - 1) * 1.5))
	return slip >= 0 and f or -f
end

local function wrapAngle(a)
	return (a + math.pi) % (2 * math.pi) - math.pi
end

-- ângulo (como o yaw) para onde a velocidade aponta
local function velAngle(v)
	return math.atan2(-v.X, -v.Z)
end

local function stepGrip(d, spec, R, throttle, steer, handbrake, dt)
	local look = CFrame.Angles(0, d.yaw, 0)
	-- velocidades no corpo do carro: x para a frente, y para a ESQUERDA; r = giro (anti-horário +)
	local vx = d.vel:Dot(look.LookVector)
	local vy = -d.vel:Dot(look.RightVector)
	local r = d.yawRate or 0
	local a, b = R.FrontAxle, R.RearAxle
	local L = a + b
	local total = math.sqrt(vx * vx + vy * vy)
	-- volante pesado: abre menos quanto mais rápido; de lado, as rodas da frente seguem a direção
	-- do carro (contra-esterço automático) e o jogador ainda abre mais ou menos
	local lock = math.rad(R.MaxSteer) / (1 + math.max(vx, 0) / R.SteerRef)
	local help = 0
	if vx > 5 and total > R.LowSpeed then
		-- para onde o carro está indo em relação ao bico (só conta quando a traseira escapa;
		-- antes usava a frente e, numa curva normal, a ajuda virava ainda mais: "virava sozinha")
		local fa = math.atan2(vy, vx)
		fa = math.sign(fa) * math.max(0, math.abs(fa) - math.rad(3))
		help = R.Assist * math.clamp(fa, -math.rad(60), math.rad(60))
		lock += math.min(math.abs(fa), math.rad(25)) * 0.5
	end
	if help * -steer > 0 then
		help *= 0.4 -- o jogador já está contra-esterçando: a ajuda diminui
	end
	local maxLock = math.rad(R.MaxSteer + 20)
	d.delta = approach(d.delta or 0, math.clamp(-steer * lock + help, -maxLock, maxLock), math.rad(R.SteerSpeed) * dt)
	local delta = d.delta
	local cosD, sinD = math.cos(delta), math.sin(delta)
	local steps = math.max(1, math.ceil(dt * 240))
	local h = dt / steps
	for _ = 1, steps do
		-- força para a frente (tração traseira), freio, ré e motor solto
		local fx
		if throttle > 0.05 then
			if vx < -STOPPED then
				fx = spec.Brake * throttle
			else
				fx = vx < spec.MaxSpeed and spec.Acceleration * throttle or 0
			end
		elseif throttle < -0.05 then
			if vx > STOPPED then
				fx = -spec.Brake * -throttle
			else
				fx = vx > -spec.ReverseSpeed and spec.Acceleration * 0.6 * throttle or 0
			end
		else
			fx = -math.sign(vx) * math.min(math.abs(vx) / h, spec.Drag)
		end
		if handbrake then
			fx = -math.sign(vx) * math.min(math.abs(vx) / h, R.HandbrakeDecel)
		end
		total = math.sqrt(vx * vx + vy * vy)
		if total < R.LowSpeed or (vx < -1 and math.abs(vy) < 4) then
			-- devagar ou de ré: o carro vai para onde as rodas apontam (manobra normal)
			vx += fx * h
			r += (vx * math.tan(delta) / L - r) * math.min(1, h * 6)
			vy *= math.exp(-6 * h)
		else
			local ux = math.max(vx, 6)
			local slipF = delta - math.atan2(vy + a * r, ux)
			local slipR = -math.atan2(vy - b * r, ux)
			local rearGrip = R.RearGrip * (handbrake and R.HandbrakeGrip or 1)
			-- círculo de atrito: o que o pneu de trás gasta empurrando, perde de lado (só acima de
			-- PowerSlideFrom; arrancando o carro não sai de lado)
			local ramp = math.clamp((vx - R.PowerSlideFrom) / (R.PowerSlideFull - R.PowerSlideFrom), 0, 1)
			local push = (throttle > 0.05 and vx > 0) and spec.Acceleration * throttle * R.PowerSlide * ramp or 0
			local rearSide = math.max(math.sqrt(math.max(0, rearGrip * rearGrip - push * push)), rearGrip * 0.35)
			local fyF = tireForce(slipF, R.FrontStiffness, R.FrontGrip, R.FrontSlide)
			local fyR = tireForce(slipR, R.RearStiffness, rearSide, R.RearSlide)
			vx += (fx - fyF * sinD + vy * r) * h
			vy += (fyF * cosD + fyR - vx * r) * h
			r += ((a * fyF * cosD - b * fyR) / R.Inertia - r * R.YawDamping) * h
		end
		r = math.clamp(r, -4, 4)
	end
	return vx, vy, r
end

local function stepRealDrift(d, spec, chassis, throttle, steer, handbrake, dt)
	local R = spec.RealDrift
	local v = d.vel.Magnitude
	local r
	if d.drift then
		local beta = wrapAngle(d.yaw - velAngle(d.vel))
		if v < 1 then
			beta = 0
		end
		-- lado do drift = para onde o bico está virado em relação à velocidade (troca sozinho na
		-- transição de um lado para o outro)
		if math.abs(beta) > math.rad(1) then
			d.side = math.sign(beta)
		end
		local side = d.side
		local into = math.max(0, -steer * side)
		local counter = math.max(0, steer * side)
		-- freio de mão abre o ângulo aos poucos (um toque rápido abre pouco) e volta quando solta;
		-- no começo do drift o ângulo cresce devagar (o peso do carro passando para o lado)
		d.hbBoost = approach(d.hbBoost or 0, handbrake and R.HandbrakeAngle or 0, (handbrake and 60 or 40) * dt)
		d.entry = math.min(1, (d.entry or 1) + dt / 0.5)
		if throttle < 0.3 and not handbrake then
			d.fade = math.min(1, d.fade + dt / 0.7) -- soltou o gás: o drift acaba aos poucos
		else
			d.fade = math.max(0, d.fade - dt / 0.3)
		end
		local target
		if counter > 0.3 then
			-- contra-esterço: o carro balança para o outro lado (transição), sem travar; passando do
			-- meio, o mesmo volante vira "para dentro" do lado novo
			target = -side * math.rad(R.DriftAngle * R.SwitchAngle) * counter
		else
			target = side * (math.rad(R.DriftAngle + R.DriftInto * into) * (0.4 + 0.6 * d.entry) + math.rad(d.hbBoost))
		end
		target *= 1 - d.fade
		-- o ângulo vai até o alvo como uma mola (o carro tem peso)
		d.brate += (R.DriftSpring * (target - beta) - R.DriftDamp * d.brate) * dt
		beta += d.brate * dt
		-- a direção da velocidade faz a curva para o lado do bico (contínuo na troca de lado)
		local lat = (R.DriftLat + R.DriftLatInto * into) * math.clamp(beta / math.rad(15), -1, 1)
		local om = lat / math.max(v, 8)
		local phi = velAngle(d.vel) + om * dt
		if v < 1 then
			phi = d.yaw
		end
		if handbrake then
			v = math.max(0, v - R.HandbrakeDecelDrift * dt)
		elseif throttle > 0.05 then
			local top = spec.MaxSpeed * 0.9
			v = v < top and math.min(top, v + spec.Acceleration * R.DriftAccel * throttle * dt) or v - R.DriftDrag * dt
		else
			v = math.max(0, v - spec.Drag * dt)
		end
		v = math.max(0, v - R.DriftDrag * math.abs(math.sin(beta)) * dt)
		r = om + d.brate
		d.yaw = phi + beta
		d.vel = CFrame.Angles(0, phi, 0).LookVector * v
		-- as rodas da frente mostram o contra-esterço
		d.delta = approach(d.delta or 0, math.clamp(-beta * 0.5 - steer * math.rad(12), -math.rad(40), math.rad(40)), math.rad(R.SteerSpeed * 2) * dt)
		-- o drift acaba soltando o gás (o ângulo volta a zero) ou devagar demais
		if (math.abs(beta) < math.rad(R.ExitSlip) and d.fade > 0.8) or v < R.ExitSpeed then
			d.drift = false
			r = om + d.brate * 0.2 -- sai do drift sem jogar a traseira para o outro lado
		end
	else
		local vx, vy
		vx, vy, r = stepGrip(d, spec, R, throttle, steer, handbrake, dt)
		local newYaw = d.yaw + r * dt
		-- gira o carro (sem entrar numa parede)
		local here = CFrame.new(chassis.Position)
		if blockedAt(chassis, here * CFrame.Angles(0, newYaw, 0)) and not blockedAt(chassis, here * CFrame.Angles(0, d.yaw, 0)) then
			newYaw = d.yaw
			r = 0
		end
		d.yaw = newYaw
		local turned = CFrame.Angles(0, d.yaw, 0)
		d.vel = turned.LookVector * vx - turned.RightVector * vy
		if d.vel.Magnitude > spec.MaxSpeed * 1.05 then
			d.vel = d.vel.Unit * spec.MaxSpeed * 1.05
		end
		-- entra no drift: freio de mão + volante andando, gás e volante cheio em alta por um
		-- tempinho (power over), ou a traseira escapou sozinha
		v = d.vel.Magnitude
		if throttle > 0.8 and math.abs(steer) > 0.9 and v > R.PowerOverSpeed then
			d.pot = (d.pot or 0) + dt
		else
			d.pot = 0
		end
		local beta = -math.atan2(vy, math.max(vx, 0.1))
		local enter
		if v > R.EnterSpeed and vx > 0 then
			if handbrake and math.abs(steer) > 0.5 then
				enter = -math.sign(steer)
			elseif d.pot > R.PowerOverTime then
				enter = -math.sign(steer)
			elseif math.abs(beta) > math.rad(R.EnterSlip) and v > R.SlipEnterSpeed then
				enter = math.sign(beta)
			end
		end
		if enter then
			d.drift = true
			d.side = enter
			d.brate = r * 0.3
			d.fade = 0
			d.entry = 0
			d.hbBoost = 0
			d.pot = 0
		end
	end
	d.yawRate = r
	steerAngle = math.clamp(-(d.delta or 0) / math.rad(25), -1.6, 1.6)
	local look = CFrame.Angles(0, d.yaw, 0)
	return d.vel:Dot(look.LookVector), d.vel:Dot(look.RightVector)
end

local function stepDrive(dt)
	local seat = currentSeat()
	if not seat then
		drive = nil
		return
	end
	local car = seat.Parent
	local chassis = car and car:FindFirstChild("Chassis")
	if not chassis then
		return
	end
	if not drive or drive.car ~= car then
		local spec = specOf(car)
		drive = {
			car = car,
			chassis = chassis,
			lv = chassis:FindFirstChildOfClass("LinearVelocity"),
			ao = chassis:FindFirstChildOfClass("AlignOrientation"),
			spec = spec,
			vel = Vector3.zero, -- velocidade no chão (pode apontar de lado = drift)
			yaw = yawOf(chassis.CFrame),
			grip = spec.Grip or 9,
		}
	end
	local d, spec = drive, drive.spec
	if not d.lv or not d.ao or not d.lv.Parent then
		-- Marco 7.5: as peças da física podem chegar um instante depois do carro (retirar da
		-- garagem e já sair dirigindo); procura de novo em vez de desistir até sair do carro
		d.lv = chassis:FindFirstChildOfClass("LinearVelocity")
		d.ao = chassis:FindFirstChildOfClass("AlignOrientation")
		if not d.lv or not d.ao then
			return
		end
	end
	-- Altura do chão (também prepara a lista do que ignorar: o próprio carro, pessoas, NPCs)
	local gy = groundY(chassis, car)

	local throttle = seat.ThrottleFloat
	local steer = seat.SteerFloat
	local handbrake = handbrakeHeld

	-- Marco 10.32: água. Entrando no mar o carro perde força (quanto mais fundo, mais lento) e, com
	-- a água no capô, o motor afoga: não acelera mais e o carro afunda devagar até o fundo. Para
	-- voltar a andar, tire o carro de novo na Garagem (o servidor marca o atributo "Afogado").
	local water = gy and waterLevel(chassis.Position, rayParams.FilterDescendantsInstances)
	local wade = water and math.max(0, water - gy) or 0
	if wade > spec.Hover + (spec.Moto and 0.5 or 1.2) and not d.drowned then
		d.drowned = true -- na hora, sem esperar o servidor
	end
	local drowned = d.drowned or car:GetAttribute("Afogado") == true
	if drowned then
		throttle = 0
		steer *= 0.15
		handbrake = false
	end

	local look = CFrame.Angles(0, d.yaw, 0)
	local forward, right = look.LookVector, look.RightVector

	-- Bateu em algo de verdade: a velocidade vira a velocidade real
	local real = chassis.AssemblyLinearVelocity
	real = Vector3.new(real.X, 0, real.Z)
	if (real - d.vel).Magnitude > 12 then
		d.vel = d.vel:Lerp(real, math.min(1, dt * 4))
	end
	local speed, lateral, direction
	if spec.RealDrift then
		speed, lateral = stepRealDrift(d, spec, chassis, throttle, steer, handbrake, dt)
		direction = speed >= 0 and 1 or -1
	else
		speed = d.vel:Dot(forward) -- para frente/trás
		lateral = d.vel:Dot(right) -- de lado (deslizando)

		-- Velocidade: acelera, freia, dá ré, freio de mão e perde velocidade solto
		if handbrake then
			speed = approach(speed, 0, (spec.HandbrakeDecel or 20) * dt)
		elseif throttle > 0.05 then
			if speed < -STOPPED then
				speed = approach(speed, 0, spec.Brake * dt)
			else
				speed = approach(math.max(speed, 0), spec.MaxSpeed * throttle, spec.Acceleration * dt)
			end
		elseif throttle < -0.05 then
			-- "parado" = menos de STOPPED: aí o S engata a ré (antes um restinho de 0,0000001
			-- para a frente fazia o S ficar freando para sempre e a ré não engatava)
			if speed > STOPPED then
				speed = approach(speed, 0, spec.Brake * dt)
			else
				speed = approach(math.min(speed, 0), -spec.ReverseSpeed * -throttle, spec.Acceleration * 0.6 * dt)
			end
		else
			speed = approach(speed, 0, spec.Drag * dt)
		end

		-- Aderência: com freio de mão a traseira solta; acelerando de lado, o drift continua;
		-- soltando tudo, o carro volta a ter aderência aos poucos
		local drifting = math.abs(lateral) > 6
		local targetGrip = spec.Grip or 9
		if handbrake then
			targetGrip = spec.DriftGrip or 1
		elseif drifting and throttle > 0.3 then
			targetGrip = spec.DriftHoldGrip or 2.4
		end
		d.grip += (targetGrip - d.grip) * math.min(1, dt * (handbrake and 10 or 2.5))
		-- o que perde de lado vira um pouco de velocidade para frente (sai do drift embalado)
		local newLateral = lateral * math.exp(-d.grip * dt)
		if math.abs(speed) > 2 then
			speed += math.abs(lateral - newLateral) * 0.25 * (speed > 0 and 1 or -1)
		end
		lateral = newLateral

		-- Curva: só vira andando; em ré o volante inverte; no drift gira mais
		local grip = math.clamp(math.abs(speed) / 18, 0, 1)
		direction = speed >= 0 and 1 or -1
		local turn = spec.TurnRate * (1 - 0.35 * math.clamp(math.abs(speed) / spec.MaxSpeed, 0, 1))
		-- Marco 10.28: boost abaixo de 1 (veículo pesado) só no freio de mão; numa curva forte o carro
		-- já escorrega de lado sozinho, e isso cortava o giro em plena curva ("o volante travava")
		local boost = spec.DriftTurnBoost or 1.5
		if handbrake or (drifting and boost > 1) then
			turn *= boost
		end
		local newYaw = d.yaw - steer * turn * grip * direction * dt
		-- não gira para dentro de uma parede (testa a posição girada antes)
		if newYaw ~= d.yaw then
			local here = CFrame.new(chassis.Position)
			if blockedAt(chassis, here * CFrame.Angles(0, newYaw, 0)) and not blockedAt(chassis, here * CFrame.Angles(0, d.yaw, 0)) then
				newYaw = d.yaw
			end
		end
		d.yaw = newYaw
		steerAngle = steer

		-- a velocidade continua apontando para onde ia; o carro girou: é isso que faz deslizar
		d.vel = forward * speed + right * lateral
		if d.vel.Magnitude > spec.MaxSpeed then
			d.vel = d.vel.Unit * spec.MaxSpeed
		end
	end

	-- Marco 10.32: a água segura o carro (resistência) e, afogado, ele só vai parando
	if wade > 0.35 then
		local cap = spec.MaxSpeed * math.clamp(1 - wade / (spec.Hover + 1.8), 0.12, 1)
		local mag = d.vel.Magnitude
		if mag > cap then
			d.vel = d.vel.Unit * (cap + (mag - cap) * math.exp(-2.5 * dt))
		end
	end
	if drowned then
		d.vel *= math.exp(-0.9 * dt)
	end

	-- Paredes: não entra nelas, desliza ao longo
	local push, blocked
	d.vel, push, blocked = blockWalls(chassis, d.vel, dt)
	if blocked then
		d.vel *= 0.97
		if d.yawRate then
			d.yawRate *= 0.5 -- drift de verdade: bateu de lado, perde o giro e sai do drift
			d.drift = false
		end
	end

	-- Altura: flutua na altura certa acima do chão (calçada e meio-fio não travam)
	-- Grau (Marco 7.2): segurando o botão andando para a frente, a moto empina na roda de trás.
	-- Ela sobe um pouco junto, para a roda de trás continuar no chão.
	local pitch = 0
	if spec.Moto and wheelieHeld and speed > 8 then
		pitch = math.rad(spec.WheelieAngle or 30)
	end
	d.pitch = (d.pitch or 0) + (pitch - (d.pitch or 0)) * math.min(1, dt * (pitch > 0 and 3 or 6))
	-- Marco 7.5: a conta usa a posição de verdade da roda de trás. Empinando em volta do ponto
	-- onde ela encosta no chão, o centro sobe zr*sen(a) e desce Hover*(1-cos(a)) (antes só subia,
	-- e a roda saía um pouquinho do chão). O chão é medido embaixo da roda de trás, então numa
	-- calçada mais alta ela também não entra no chão.
	local rise = 0
	local floorY = gy
	if d.pitch > 0.01 then
		if not d.rearZ then
			local hub = car:FindFirstChild("Rear")
			local motor = hub and hub:FindFirstChild("WheelMotor")
			d.rearZ = motor and motor.C0.Position.Z or spec.Length * 0.36
		end
		rise = d.rearZ * math.sin(d.pitch) - spec.Hover * (1 - math.cos(d.pitch))
		local back = CFrame.Angles(0, d.yaw, 0):VectorToWorldSpace(Vector3.new(0, 0, d.rearZ))
		local hit = Workspace:Raycast(chassis.Position + back + Vector3.new(0, 4, 0), Vector3.new(0, -30, 0), rayParams)
		if hit then
			floorY = hit.Position.Y
		end
	end
	local vy = -25
	if floorY then
		vy = math.clamp((floorY + spec.Hover + rise - chassis.Position.Y) * 10, -40, 40)
	end
	if drowned and floorY then
		-- afundando devagar, assentando no fundo
		vy = math.clamp((floorY + spec.Hover * 0.7 - chassis.Position.Y) * 1.5, -3, 2)
	end
	d.sink = (d.sink or 0) + ((drowned and 1 or 0) - (d.sink or 0)) * math.min(1, dt * 0.8)
	d.lv.VectorVelocity = d.vel + push + Vector3.new(0, vy, 0)
	-- Moto (Marco 7.1): inclina para dentro da curva, mais quanto mais rápido
	local lean = 0
	if spec.Moto then
		local fast = math.clamp(math.abs(speed) / (spec.MaxSpeed * 0.6), 0, 1)
		lean = -steer * math.rad(spec.LeanAngle or 28) * fast * direction
	end
	d.lean = (d.lean or 0) + (lean - (d.lean or 0)) * math.min(1, dt * 6)
	local sinkTilt = d.sink > 0.01 and CFrame.Angles(math.rad(-6) * d.sink, 0, math.rad(4) * d.sink * math.sin(os.clock() * 0.7)) or CFrame.identity
	d.ao.CFrame = CFrame.Angles(0, d.yaw, 0) * CFrame.Angles(d.pitch, 0, 0) * CFrame.Angles(0, 0, d.lean) * sinkTilt
end

-- Fumaça dos pneus e marcas no chão quando o carro desliza (efeito só local, cada um vê o seu)
local skidFolder
local skidCount = 0
local lastSkid = {}

local function smokeFor(hub)
	local e = hub:FindFirstChild("TireSmoke")
	if not e then
		e = Instance.new("ParticleEmitter")
		e.Name = "TireSmoke"
		e.Color = ColorSequence.new(Color3.fromRGB(235, 235, 235))
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 4) })
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1) })
		e.Lifetime = NumberRange.new(0.8, 1.4)
		e.Rate = 35
		e.Speed = NumberRange.new(2, 4)
		e.SpreadAngle = Vector2.new(40, 40)
		e.Acceleration = Vector3.new(0, 3, 0)
		e.Enabled = false
		e.Parent = hub
	end
	return e
end

local function skidMark(car, hub, chassis, spec)
	if not skidFolder then
		skidFolder = Instance.new("Folder")
		skidFolder.Name = "MarcasDePneu"
		skidFolder.Parent = Workspace
	end
	if skidCount > 220 then
		return
	end
	local y = hub.Position.Y - spec.WheelRadius + 0.04
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = Vector3.new(0.9, 0.05, 1.4)
	p.Color = Color3.fromRGB(25, 25, 25)
	p.Material = Enum.Material.SmoothPlastic
	p.Transparency = 0.35
	p.CFrame = CFrame.new(hub.Position.X, y, hub.Position.Z) * chassis.CFrame.Rotation
	p.Parent = skidFolder
	skidCount += 1
	task.delay(6, function()
		p:Destroy()
		skidCount -= 1
	end)
end

local function stepSkids(car, chassis, spec)
	local v = chassis.AssemblyLinearVelocity
	local slide = math.abs(v:Dot(chassis.CFrame.RightVector))
	local on = slide > 7 and Vector3.new(v.X, 0, v.Z).Magnitude > 12
	local t = os.clock()
	for _, name in ipairs({ "RearLeft", "RearRight", "Rear" }) do
		local hub = car:FindFirstChild(name)
		if hub then
			smokeFor(hub).Enabled = on
			if on and t - (lastSkid[hub] or 0) > 0.05 then
				lastSkid[hub] = t
				skidMark(car, hub, chassis, spec)
			end
		end
	end
end

-- Sons dos veículos (Marco 9.9, cada um ouve no seu aparelho): motor de todos os carros
-- (o tom sobe com a velocidade e com o acelerador), sirene ligada com G e pipoco do escapamento.
-- Os números dos áudios ficam em GameConfig.Sounds.
local SOUNDS = GameConfig.Sounds
local audio = {} -- audio[car] = { engine, siren, speed, rev }

local function soundId(value)
	if type(value) == "number" then
		return "rbxassetid://" .. value
	end
	return tostring(value or "")
end

local function newSound(parent, name, id, volume, looped)
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = soundId(id)
	sound.Volume = volume
	sound.Looped = looped
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = 12
	sound.RollOffMaxDistance = SOUNDS.MaxDistance
	sound.Parent = parent
	return sound
end

local function playOnce(chassis, name, id, volume, pitch)
	if not id or id == 0 or id == "" then
		return -- sem som escolhido
	end
	local sound = newSound(chassis, name, id, volume, false)
	sound.PlaybackSpeed = pitch
	sound:Play()
	game:GetService("Debris"):AddItem(sound, 4)
end

-- Marco 9.12: carros com perfil de som (GameConfig.Sounds.Profiles: Dodge, M5, R18, Moto) têm
-- dois áudios gravados, o motor parado (Idle) e acelerando (Accel). Os dois tocam juntos e o jogo
-- passa de um para o outro conforme o pé no acelerador e a velocidade, sem cortes.
-- Os outros carros usam um áudio só (Engine, TruckEngine), com o tom subindo com a velocidade.
-- Marco 9.12: marchas de mentira para o som. A velocidade (0 a 1 da máxima) é dividida em
-- faixas; dentro de cada marcha a rotação sobe aos poucos e, na troca, cai de novo. Assim o
-- ronco vai subindo progressivo em vez de pular para o máximo ao apertar W.
local GEARS = { 0, 0.12, 0.27, 0.45, 0.66, 1.01 }

local function engineRpm(ratio)
	for g = 1, #GEARS - 1 do
		local lo, hi = GEARS[g], GEARS[g + 1]
		if ratio < hi then
			local t = (ratio - lo) / (hi - lo)
			return g == 1 and 0.15 + t * 0.75 or 0.4 + t * 0.6
		end
	end
	return 1
end

local function stepAudio(car, chassis, spec, speed, dt)
	local a = audio[car]
	if not a or not a.engine.Parent then
		a = { speed = speed, rev = 0, load = 0, mix = 0, boost = 0, turboWait = 0, rpm = 0.15 }
		a.kind = spec.EngineSound or "Engine"
		a.profile = SOUNDS.Profiles[a.kind]
		if a.profile then
			a.engine = newSound(chassis, "SomMotor", a.profile.Idle, 0, true)
			a.accel = newSound(chassis, "SomMotorAcelerando", a.profile.Accel, 0, true)
			a.accel:Play()
		else
			a.engine = newSound(chassis, "SomMotor", SOUNDS[a.kind] or SOUNDS.Engine, 0, true)
		end
		a.engine:Play()
		if spec.Siren then
			a.siren = newSound(chassis, "SomSirene", SOUNDS[spec.SirenSound or "Siren"], SOUNDS.SirenVolume, true)
		end
		audio[car] = a
	end
	-- "acelerada": ganhando velocidade, o motor ronca mais alto e mais agudo por um instante
	local gain = (math.abs(speed) - math.abs(a.speed)) / math.max(dt, 1 / 240)
	a.speed = speed
	a.rev += (math.clamp(gain / math.max(spec.Acceleration, 1), 0, 1) - a.rev) * math.min(1, dt * 5)
	local ratio = math.clamp(math.abs(speed) / spec.MaxSpeed, 0, 1)
	local seat = car:FindFirstChildWhichIsA("VehicleSeat")
	local someone = seat ~= nil and seat.Occupant ~= nil
	-- pé no acelerador: o do banco (quem dirige) ou, nos carros dos outros, o ganho de velocidade
	local pedal = seat and math.abs(seat.ThrottleFloat) or 0
	a.load += (math.max(pedal, a.rev) - a.load) * math.min(1, dt * 6)
	local on = (someone or ratio > 0.02) and car:GetAttribute("Afogado") ~= true -- Marco 10.32: motor afogado não faz barulho
	local fade = math.min(1, dt * 4)
	-- rotação suave: sobe devagar e cai um pouco mais rápido na troca de marcha
	local rpmTarget = engineRpm(ratio)
	a.rpm += (rpmTarget - a.rpm) * math.min(1, dt * (rpmTarget > a.rpm and 2.5 or 5))
	if a.profile then
		local volume = (a.profile.Volume or 0.4) * (SOUNDS.EngineMaster or 1)
		-- o som acelerando entra conforme a velocidade (o pé só ajuda um pouco), devagar
		a.mix += (math.clamp(ratio * 1.6 + a.load * 0.15, 0, 1) - a.mix) * math.min(1, dt * 1.5)
		local idleTarget = on and volume * (1 - a.mix) or 0
		local accelTarget = on and volume * a.mix * (0.55 + a.load * 0.3 + a.rpm * 0.15) or 0
		a.engine.Volume += (idleTarget - a.engine.Volume) * fade
		a.accel.Volume += (accelTarget - a.accel.Volume) * fade
		a.engine.PlaybackSpeed = 0.95 + a.rpm * 0.2
		a.accel.PlaybackSpeed = (a.profile.Pitch or 1) * (0.72 + a.rpm * 0.38)
	else
		local volume = (SOUNDS.EngineVolume[a.kind] or 0.4) * (SOUNDS.EngineMaster or 1)
		local target = on and volume * (0.55 + ratio * 0.45 + a.rev * 0.35) or 0
		a.engine.Volume += (target - a.engine.Volume) * fade
		a.engine.PlaybackSpeed = (SOUNDS.EnginePitch[a.kind] or 1) * (0.75 + a.rpm * 0.45 + ratio * 0.35)
	end
	-- Turbo (Marco 9.12, esportivos com spec.Turbo): enche com o pé embaixo em velocidade alta
	-- (mais de 1,5 s) e solta o "psssh" quando o motorista tira o pé. Não toca toda hora.
	if spec.Turbo then
		a.turboWait -= dt
		if a.load > 0.75 and ratio > 0.45 then
			a.boost = math.min(1, a.boost + dt / 1.5)
		elseif a.load < 0.25 then
			if a.boost >= 1 and a.turboWait <= 0 then
				a.turboWait = 3
				playOnce(chassis, "SomTurbo", SOUNDS.Turbo, SOUNDS.TurboVolume * (SOUNDS.EngineMaster or 1), 0.95 + math.random() * 0.1)
			end
			a.boost = 0
		end
	end
	if a.siren then
		local sirenOn = car:GetAttribute("SirenOn") == true
		if sirenOn and not a.siren.IsPlaying then
			a.siren:Play()
		elseif not sirenOn and a.siren.IsPlaying then
			a.siren:Stop()
		end
	end
end

-- pipoco: cada carro pode ter o seu (spec.BackfireSound = "Backfire" ou "Backfire2")
local function playBackfire(chassis, spec)
	playOnce(chassis, "SomPipoco", SOUNDS[spec.BackfireSound or "Backfire"], SOUNDS.BackfireVolume, 0.9 + math.random() * 0.25)
end

-- Fogo no escapamento (Marco 6.4, só visual, cada um vê nos carros que têm spec.Exhausts):
-- estalos de fogo ao soltar o acelerador em alta (o carro perde velocidade de repente) e
-- de vez em quando acelerando forte.
local fire = {} -- fire[car] = { emitters, light, speed, accel, cooldown, popping }

local function newFire(chassis, spec)
	local f = { emitters = {}, speed = 0, accel = 0, cooldown = 0, popping = 0 }
	for _, pos in ipairs(spec.Exhausts) do
		local att = Instance.new("Attachment")
		att.Name = "ExhaustFire"
		-- posição em relação ao chão -> chassi; a "parte de cima" do anexo aponta para trás (+Z)
		att.CFrame = CFrame.new(pos.X, pos.Y - spec.Hover, pos.Z) * CFrame.Angles(math.rad(90), 0, 0)
		att.Parent = chassis
		local e = Instance.new("ParticleEmitter")
		e.Texture = "rbxasset://textures/particles/fire_main.dds"
		e.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(150, 190, 255)),
			ColorSequenceKeypoint.new(0.25, Color3.fromRGB(255, 220, 120)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 90, 20)),
		})
		e.LightEmission = 1
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(0.4, 0.9), NumberSequenceKeypoint.new(1, 0.1) })
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
		e.Lifetime = NumberRange.new(0.08, 0.16)
		e.Speed = NumberRange.new(14, 22)
		e.SpreadAngle = Vector2.new(8, 8)
		e.EmissionDirection = Enum.NormalId.Top
		e.Rate = 0
		e.LockedToPart = false
		e.Parent = att
		table.insert(f.emitters, e)
		if not f.light then
			local light = Instance.new("PointLight")
			light.Color = Color3.fromRGB(255, 150, 60)
			light.Range = 10
			light.Brightness = 0
			light.Parent = att
			f.light = light
		end
	end
	return f
end

local function stepFire(car, chassis, spec, speed, dt)
	if not spec.Exhausts then
		return
	end
	local f = fire[car]
	if not f or not f.light.Parent then
		f = newFire(chassis, spec)
		fire[car] = f
	end
	-- aceleração suavizada (positiva = ganhando velocidade)
	local accel = (speed - f.speed) / math.max(dt, 1 / 240)
	f.speed = speed
	f.accel += (accel - f.accel) * math.min(1, dt * 8)
	f.cooldown -= dt
	f.light.Brightness = math.max(0, f.light.Brightness - dt * 20)
	local fast = speed > spec.MaxSpeed * 0.4
	local pops = spec.Pops -- Marco 9.16: carro com pops and bangs mais fortes (BMW dos admins)
	if fast and f.accel < -9 and f.popping <= 0 then
		f.popping = pops and pops.Time or 0.7 -- soltou o acelerador em alta: estala por um tempinho
	end
	f.popping -= dt
	local pop = false
	if f.cooldown <= 0 then
		if f.popping > 0 and fast then
			pop = math.random() < (pops and pops.Chance or 0.55)
		elseif speed > 15 and f.accel > spec.Acceleration * 0.6 then
			pop = math.random() < 0.04
		end
		if pop then
			f.cooldown = 0.07 + math.random() * 0.12
			local burst = pops and pops.Burst or { 3, 6 }
			for _, e in ipairs(f.emitters) do
				e:Emit(math.random(burst[1], burst[2]))
			end
			f.light.Brightness = 3
			if os.clock() - (f.lastSound or 0) > 0.18 then
				f.lastSound = os.clock()
				playBackfire(chassis, spec)
			end
		end
	end
end

-- Giroflex da viatura (Marco 7.1, só visual): vermelho e azul piscam alternados com o carro
-- andando; parado, ficam apagados
local sirens = {} -- sirens[car] = lista de peças com o atributo "Siren"
local SIREN_OFF = Color3.fromRGB(60, 60, 66)

local function stepSiren(car, spec, speed)
	if not spec.Siren then
		return
	end
	-- Marco 7.5: a lista é refeita de vez em quando. Antes ela era feita uma vez só, e se as
	-- luzes ainda não tinham chegado no aparelho (carro longe, carregando) o giroflex nunca piscava
	local list = sirens[car]
	if not list or os.clock() > list.refresh then
		local old = {}
		for _, s in ipairs(list or {}) do
			old[s.part] = s.color
		end
		list = { refresh = os.clock() + 2 }
		for _, p in ipairs(car:GetDescendants()) do
			if p:IsA("BasePart") and p:GetAttribute("Siren") then
				local base = old[p] or p.Color
				table.insert(list, { part = p, color = base, side = p:GetAttribute("Siren") })
			end
		end
		sirens[car] = list
	end
	local on = math.abs(speed) > 2 or car:GetAttribute("SirenOn") == true -- Marco 9.9: G liga parado também
	local phase = math.floor(os.clock() * 5) % 2 == 0 and "Red" or "Blue"
	for _, s in ipairs(list) do
		local lit = on and s.side == phase
		s.part.Color = lit and s.color or SIREN_OFF
		s.part.Material = lit and Enum.Material.Neon or Enum.Material.SmoothPlastic
	end
end

-- Marco 10.32: espirro de água ao entrar no mar, rastro andando na água e bolhas do carro afogado
-- (visual, em todos os aparelhos; a água é conferida 5 vezes por segundo por carro)
local splash = {} -- splash[car] = { t, wade, emit, bubbles }
local splashIgnore = {}
local function waterFx(chassis)
	local att = Instance.new("Attachment")
	att.Name = "AguaFx"
	att.Parent = chassis
	local spray = Instance.new("ParticleEmitter")
	spray.Name = "Espirro"
	spray.Texture = "rbxasset://textures/particles/smoke_main.dds"
	spray.Color = ColorSequence.new(Color3.fromRGB(235, 248, 255), Color3.fromRGB(170, 215, 235))
	spray.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(1, 1) })
	spray.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 3.5) })
	spray.Lifetime = NumberRange.new(0.5, 1.1)
	spray.Speed = NumberRange.new(10, 22)
	spray.SpreadAngle = Vector2.new(70, 70)
	spray.Acceleration = Vector3.new(0, -45, 0)
	spray.EmissionDirection = Enum.NormalId.Top
	spray.Rate = 0
	spray.Parent = att
	local bubbles = Instance.new("ParticleEmitter")
	bubbles.Name = "Bolhas"
	bubbles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	bubbles.Color = ColorSequence.new(Color3.fromRGB(220, 240, 255))
	bubbles.Size = NumberSequence.new(0.35)
	bubbles.Lifetime = NumberRange.new(1, 2)
	bubbles.Speed = NumberRange.new(3, 6)
	bubbles.SpreadAngle = Vector2.new(25, 25)
	bubbles.EmissionDirection = Enum.NormalId.Top
	bubbles.Rate = 0
	bubbles.Parent = att
	return spray, bubbles
end

stepWater = function(car, chassis, spec, speed, dt)
	local w = splash[car]
	if not w then
		w = { t = math.random() * 0.2, wade = 0 }
		splash[car] = w
	end
	w.t -= dt
	if w.t <= 0 then
		w.t = 0.2
		splashIgnore[1] = car
		local ground = Workspace:Raycast(chassis.Position + Vector3.new(0, 4, 0), Vector3.new(0, -30, 0), rayParams)
		local level = ground and waterLevel(chassis.Position, splashIgnore)
		local wade = level and math.max(0, level - ground.Position.Y) or 0
		if wade > 0.4 and not w.spray then
			w.spray, w.bubbles = waterFx(chassis)
		end
		if w.spray then
			local fast = math.abs(speed)
			if wade > 0.4 and w.wade <= 0.4 and fast > 12 then
				w.spray:Emit(math.floor(math.clamp(fast, 12, 60))) -- entrou no mar: tchibum
			end
			w.spray.Rate = (wade > 0.4 and fast > 6) and math.clamp(fast * 1.5, 10, 70) or 0
			w.bubbles.Rate = car:GetAttribute("Afogado") and wade > 1 and 12 or 0
			if level then
				w.spray.Parent.WorldPosition = Vector3.new(chassis.Position.X, level, chassis.Position.Z)
			end
		end
		w.wade = wade
	end
end

local WHEEL_NAMES = { "FrontLeft", "FrontRight", "RearLeft", "RearRight", "Front", "Rear" }

-- Rodas girando de todos os carros visíveis (só visual)
local function stepWheels(dt)
	local folder = Workspace:FindFirstChild("Vehicles")
	if not folder then
		return
	end
	for _, car in ipairs(folder:GetChildren()) do
		local chassis = car:FindFirstChild("Chassis")
		if chassis then
			local spec = specOf(car)
			local speed = chassis.AssemblyLinearVelocity:Dot(chassis.CFrame.LookVector)
			stepFire(car, chassis, spec, speed, dt)
			stepSkids(car, chassis, spec) -- Marco 9.16: fumaça e marcas de pneu de lado (tinham sumido)
			-- rodando para frente, o topo da roda vai para a frente (-Z): ângulo negativo em X
			spin[car] = ((spin[car] or 0) - speed * dt / spec.WheelRadius) % (math.pi * 2)
			-- portas abrem para cima e um pouco para fora
			local target = car:GetAttribute("DoorsOpen") and 1 or 0
			doorOpen[car] = (doorOpen[car] or 0) + (target - (doorOpen[car] or 0)) * math.min(1, dt * 6)
			for _, doorName in ipairs({ "DoorLeft", "DoorRight" }) do
				local door = car:FindFirstChild(doorName)
				local motor = door and door:FindFirstChild("DoorMotor")
				if motor then
					local side = motor:GetAttribute("Side") or 1
					local k = doorOpen[car]
					if motor:GetAttribute("Style") == "swing" then
						motor.Transform = CFrame.Angles(0, side * math.rad(65) * k, 0) -- abre para o lado
					else
						motor.Transform = CFrame.Angles(-math.rad(70) * k, 0, -side * math.rad(18) * k) -- abre para cima
					end
				end
			end
			local mine = drive and drive.car == car
			stepWater(car, chassis, spec, speed, dt)
			stepSiren(car, spec, speed)
			stepAudio(car, chassis, spec, speed, dt)
			for _, name in ipairs(WHEEL_NAMES) do
				local hub = car:FindFirstChild(name)
				local motor = hub and hub:FindFirstChild("WheelMotor")
				if motor then
					local steerY = (mine and name:sub(1, 5) == "Front") and -steerAngle * math.rad(25) or 0
					motor.Transform = CFrame.Angles(0, steerY, 0) * CFrame.Angles(spin[car], 0, 0)
				end
			end
		end
	end
	for car in pairs(spin) do
		if not car.Parent then
			spin[car] = nil
			doorOpen[car] = nil
			fire[car] = nil
			sirens[car] = nil
			audio[car] = nil
			splash[car] = nil
		end
	end
end

-- Freio de mão: só existe enquanto a pessoa dirige. A prioridade alta faz o Shift puxar o
-- freio em vez de ligar a "trava do mouse" do Roblox enquanto está no carro.
local HANDBRAKE = "FreioDeMao"
local bound = false

local function onHandbrake(_, state)
	handbrakeHeld = state == Enum.UserInputState.Begin
	return Enum.ContextActionResult.Sink
end

-- Sirene (Marco 9.9): G liga/desliga, só para quem dirige viatura ou caminhão de bombeiros
local SIREN = "Sirene"
local sirenBound = false
local vehicleRequest = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild(GameConfig.Remotes.VehicleRequest)

local function onSiren(_, state)
	if state == Enum.UserInputState.Begin then
		vehicleRequest:FireServer("Siren")
	end
	return Enum.ContextActionResult.Sink
end

-- Grau: só existe enquanto a pessoa pilota uma moto
local WHEELIE = "GrauMoto"
local wheelieBound = false

local function onWheelie(_, state)
	wheelieHeld = state == Enum.UserInputState.Begin
	return Enum.ContextActionResult.Sink
end

-- Enquanto dirige, os avisos "Sentar"/"Dirigir" do próprio carro somem (só para quem dirige)
local hiddenPrompts = {}
local function hideOwnPrompts(car)
	for prompt in pairs(hiddenPrompts) do
		if not car or not prompt:IsDescendantOf(car) then
			prompt.Enabled = true
			hiddenPrompts[prompt] = nil
		end
	end
	if car then
		for _, prompt in ipairs(car:GetDescendants()) do
			if prompt:IsA("ProximityPrompt") and prompt.Enabled then
				prompt.Enabled = false
				hiddenPrompts[prompt] = true
			end
		end
	end
end

local function updateBinding()
	local seat = currentSeat()
	local driving = seat ~= nil
	if driving and not bound then
		bound = true
		ContextActionService:BindActionAtPriority(HANDBRAKE, onHandbrake, false, 3000, Enum.KeyCode.LeftShift, Enum.KeyCode.RightShift, Enum.KeyCode.ButtonX)
		hideOwnPrompts(seat.Parent)
	elseif not driving and bound then
		bound = false
		handbrakeHeld = false
		ContextActionService:UnbindAction(HANDBRAKE)
		hideOwnPrompts(nil)
	end
	local withSiren = driving and specOf(seat.Parent).Siren == true
	if withSiren and not sirenBound then
		sirenBound = true
		ContextActionService:BindActionAtPriority(SIREN, onSiren, false, 3000, SOUNDS.SirenKey, Enum.KeyCode.ButtonL1)
	elseif not withSiren and sirenBound then
		sirenBound = false
		ContextActionService:UnbindAction(SIREN)
	end
	local onMoto = driving and specOf(seat.Parent).Moto == true
	if onMoto and not wheelieBound then
		wheelieBound = true
		ContextActionService:BindActionAtPriority(WHEELIE, onWheelie, false, 3000, Enum.KeyCode.Q, Enum.KeyCode.ButtonY)
	elseif not onMoto and wheelieBound then
		wheelieBound = false
		wheelieHeld = false
		ContextActionService:UnbindAction(WHEELIE)
	end
	MobileButtons.show("freio", bound)
	MobileButtons.show("sirene", sirenBound)
	MobileButtons.show("grau", wheelieBound)
end

-- Marco 10.14: no celular Freio, Sirene e Grau são botões redondos em volta do pulo (MobileButtons)
local function addMobileButtons()
	MobileButtons.add("freio", {
		icon = "🛑",
		title = "Freio",
		slots = { 1, 2 },
		hold = true,
		onPress = function(began)
			onHandbrake(nil, began and Enum.UserInputState.Begin or Enum.UserInputState.End)
		end,
	})
	MobileButtons.add("sirene", {
		icon = "🚨",
		title = "Sirene",
		slots = { 2, 4 },
		onPress = function()
			onSiren(nil, Enum.UserInputState.Begin)
		end,
	})
	MobileButtons.add("grau", {
		icon = "🏍",
		title = "Grau",
		slots = { 2, 4 },
		hold = true,
		onPress = function(began)
			onWheelie(nil, began and Enum.UserInputState.Begin or Enum.UserInputState.End)
		end,
	})
end

function CarController.init()
	addMobileButtons()
	RunService.Heartbeat:Connect(function(dt)
		updateBinding()
		stepDrive(dt)
	end)
	RunService.Stepped:Connect(function(_, dt)
		stepWheels(dt)
	end)
end

return CarController
