-- CarController (ModuleScript)
-- Caminho: StarterPlayer > StarterPlayerScripts > Controllers > CarController
-- Direção do carro, no cliente de quem dirige (o servidor passa a física do carro para o motorista).
-- Lê o controle do VehicleSeat (WASD/setas no PC, analógico no celular, gatilhos no controle)
-- e move o chassi: acelera, freia, dá ré, faz curva e acompanha a altura do chão.
-- Também gira as rodas (e esterça as da frente) e abre as portas de todos os carros que este jogador vê.
-- Valores do carro (velocidade, aceleração...) vêm de GameConfig.Cars.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))

local CarController = {}

local player = Players.LocalPlayer
local drive = nil -- estado de quem dirige: { car, chassis, lv, ao, spec, speed, yaw }
local spin = {} -- spin[car] = ângulo das rodas
local doorOpen = {} -- doorOpen[car] = 0 (fechada) a 1 (aberta)
local steerAngle = 0

local function specOf(car)
	for _, spec in pairs(GameConfig.Cars) do
		if spec.Name == car:GetAttribute("Spec") then
			return spec
		end
	end
	return GameConfig.Cars[GameConfig.CarModel]
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

local function approach(value, target, step)
	if value < target then
		return math.min(value + step, target)
	end
	return math.max(value - step, target)
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

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
			speed = 0,
			yaw = yawOf(chassis.CFrame),
		}
	end
	local d, spec = drive, drive.spec
	if not d.lv or not d.ao then
		return
	end
	local throttle = seat.ThrottleFloat
	local steer = seat.SteerFloat

	-- Velocidade: acelera, freia (tecla para trás andando para frente), dá ré e perde velocidade solto
	if throttle > 0.05 then
		if d.speed < 0 then
			d.speed = approach(d.speed, 0, spec.Brake * dt)
		else
			d.speed = approach(d.speed, spec.MaxSpeed * throttle, spec.Acceleration * dt)
		end
	elseif throttle < -0.05 then
		if d.speed > 0 then
			d.speed = approach(d.speed, 0, spec.Brake * dt)
		else
			d.speed = approach(d.speed, -spec.ReverseSpeed * -throttle, spec.Acceleration * 0.6 * dt)
		end
	else
		d.speed = approach(d.speed, 0, spec.Drag * dt)
	end

	-- Bateu em algo: a velocidade cai para a velocidade real
	local forward = CFrame.Angles(0, d.yaw, 0).LookVector
	local real = chassis.AssemblyLinearVelocity:Dot(forward)
	if math.abs(d.speed - real) > 12 then
		d.speed = d.speed + (real - d.speed) * math.min(1, dt * 4)
	end

	-- Curva: só vira andando; em ré o volante inverte, como num carro de verdade
	local grip = math.clamp(math.abs(d.speed) / 18, 0, 1)
	local direction = d.speed >= 0 and 1 or -1
	-- em alta velocidade vira um pouco menos (mais estável)
	local turn = spec.TurnRate * (1 - 0.35 * math.clamp(math.abs(d.speed) / spec.MaxSpeed, 0, 1))
	d.yaw -= steer * turn * grip * direction * dt
	steerAngle = steer

	-- Altura: flutua na altura certa acima do chão (calçada e meio-fio não travam)
	local vy = -25
	local gy = groundY(chassis, car)
	if gy then
		vy = math.clamp((gy + spec.Hover - chassis.Position.Y) * 10, -40, 40)
	end
	forward = CFrame.Angles(0, d.yaw, 0).LookVector
	d.lv.VectorVelocity = forward * d.speed + Vector3.new(0, vy, 0)
	d.ao.CFrame = CFrame.Angles(0, d.yaw, 0)
end

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
					motor.Transform = CFrame.Angles(-math.rad(70) * k, 0, -side * math.rad(18) * k)
				end
			end
			local mine = drive and drive.car == car
			for _, name in ipairs({ "FrontLeft", "FrontRight", "RearLeft", "RearRight" }) do
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
		end
	end
end

function CarController.init()
	RunService.Heartbeat:Connect(stepDrive)
	RunService.Stepped:Connect(function(_, dt)
		stepWheels(dt)
	end)
end

return CarController
