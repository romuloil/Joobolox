-- VehicleService (ModuleScript)
-- Caminho: ServerScriptService > Services > VehicleService
-- Bicicleta inicial gratuita e carro (Marco 4.3: um modelo, para andar rápido pela cidade).
-- Dentro dos locais de trabalho (ZoneService) não dá para usar bike nem carro.
-- O jogador "monta" a bicicleta: um modelo é preso ao personagem e a velocidade
-- de caminhada aumenta. Funciona igual no PC e no celular, porque usa o próprio
-- controle de movimento do Roblox. A bike é montada do tamanho do boneco
-- (RigMeasure) e o BikeAnimator, no cliente, faz a pedalada e gira rodas e pedais.
-- O servidor decide tudo: quem pode montar, a velocidade e o cooldown.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))
local RigMeasure = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("RigMeasure"))
local SecurityService = require(script.Parent:WaitForChild("SecurityService"))
local ZoneService = require(script.Parent:WaitForChild("ZoneService"))
local CarBuilder = require(script.Parent:WaitForChild("CarBuilder"))
local SeatService = require(script.Parent:WaitForChild("SeatService"))
local WorkRoleService = require(script.Parent:WaitForChild("WorkRoleService"))

local VehicleService = {}

local BIKE = GameConfig.Bike
local uiUpdate -- RemoteEvent para avisar a interface

-- bikes[player] = Model da bicicleta montada (só existe enquanto montado)
local bikes = {}
-- cars[player] = { model, driver } (o carro fica parado onde o jogador saiu)
local cars = {}

local function notice(player, text)
	uiUpdate:FireClient(player, "Notice", { text = text })
end

local function isStunned(player)
	local untilAt = player:GetAttribute("StunnedUntil")
	return type(untilAt) == "number" and untilAt > Workspace:GetServerTimeNow()
end

local function newBikePart(bike, name, size, color, shape)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then
		p.Shape = shape
	end
	-- A bicicleta é só visual: não colide, não pesa e não atrapalha o personagem
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Massless = true
	p.Anchored = false
	p.Parent = bike
	return p
end

-- Distância do centro do HumanoidRootPart até o chão
local function rootHeightAboveGround(humanoid, root)
	if humanoid.RigType == Enum.HumanoidRigType.R6 then
		return 3
	end
	return humanoid.HipHeight + root.Size.Y / 2
end

local function weldTo(base, part)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = base
	weld.Part1 = part
	weld.Parent = part
end

local function buildBike(character, humanoid, root)
	local bike = Instance.new("Model")
	bike.Name = "StarterBike"

	-- Medidas do boneco (com valores padrão se o avatar for diferente)
	local m = RigMeasure.measure(character)
	local hip = m and (m.hip.Left + m.hip.Right) / 2 or Vector3.new(0, -1, 0)
	local legLen = m and (m.legL1 + m.legL2) or 2
	local shoulder = m and (m.shoulder.Left + m.shoulder.Right) / 2 or Vector3.new(0, 0.5, 0)
	local armLen = m and (m.armL1 + m.armL2) or 1.8

	-- Pontos principais, em coordenadas do HumanoidRootPart (frente = -Z, esquerda = -X)
	local r = BIKE.WheelRadius
	local ground = -rootHeightAboveGround(humanoid, root)
	local axleY = ground + r
	local crankR = 0.22 * legLen
	local bb = Vector3.new(0, math.max(hip.Y - 0.62 * legLen, ground + 0.15 + crankR), hip.Z - 0.2 * legLen)
	local rearAxle = Vector3.new(0, axleY, bb.Z + 1.7)
	local frontAxle = Vector3.new(0, axleY, bb.Z - 1.9)
	local seatPos = Vector3.new(0, hip.Y - 0.25 + BIKE.SeatOffsetY, hip.Z + 0.3)
	local seatPostTop = seatPos - Vector3.new(0, 0.2, 0)
	local barCenter = Vector3.new(0, shoulder.Y - 0.6 * armLen, shoulder.Z - 0.7 * armLen)
	local headTop = Vector3.new(0, barCenter.Y - 0.35, frontAxle.Z + 0.45)
	local function onFork(t)
		return frontAxle:Lerp(headTop, t)
	end

	local function attach(base, part, localCf)
		part.CFrame = base.CFrame * localCf
		weldTo(base, part)
		return part
	end
	local function piece(name, size, color, cf, shape)
		return attach(root, newBikePart(bike, name, size, color, shape), cf)
	end
	local function tube(name, a, b, thickness, color)
		return piece(name, Vector3.new(thickness, thickness, (b - a).Magnitude + thickness * 0.5), color or BIKE.FrameColor, CFrame.lookAt((a + b) / 2, b))
	end
	-- Peça que gira (roda ou pedivela): presa por Motor6D, que o cliente anima
	local function spinner(name, center, size)
		local hub = newBikePart(bike, name, size, BIKE.MetalColor, Enum.PartType.Cylinder)
		hub.CFrame = root.CFrame * CFrame.new(center)
		local motor = Instance.new("Motor6D")
		motor.Name = name .. "Motor"
		motor.Part0 = root
		motor.Part1 = hub
		motor.C0 = CFrame.new(center)
		motor.Parent = hub
		return hub
	end

	-- Rodas: pneu em anel (segmentos), raios e cubo
	local function wheel(name, center)
		local hub = spinner(name, center, Vector3.new(0.35, 0.3, 0.3))
		local segments = 14
		local segLen = 2 * math.pi * r / segments * 1.1
		for i = 1, segments do
			local phi = i * 2 * math.pi / segments
			attach(hub, newBikePart(bike, "Tire", Vector3.new(0.26, 0.2, segLen), BIKE.WheelColor), CFrame.Angles(phi, 0, 0) * CFrame.new(0, r - 0.1, 0))
		end
		for i = 0, 2 do
			attach(hub, newBikePart(bike, "Spoke", Vector3.new(0.05, (r - 0.15) * 2, 0.05), BIKE.MetalColor), CFrame.Angles(i * math.pi / 3, 0, 0))
		end
		return hub
	end
	wheel("FrontWheel", frontAxle)
	local rearHub = wheel("RearWheel", rearAxle)
	attach(rearHub, newBikePart(bike, "Sprocket", Vector3.new(0.08, 0.36, 0.36), BIKE.MetalColor, Enum.PartType.Cylinder), CFrame.new(0.28, 0, 0))

	-- Quadro
	local side = 0.2
	tube("SeatTube", bb, seatPostTop, 0.18)
	tube("TopTube", seatPostTop, onFork(0.85), 0.18)
	tube("DownTube", bb, onFork(0.55), 0.2)
	for _, x in ipairs({ -side, side }) do
		local offset = Vector3.new(x, 0, 0)
		tube("ChainStay", bb + offset * 0.5, rearAxle + offset, 0.12)
		tube("SeatStay", seatPostTop, rearAxle + offset, 0.1)
		tube("ForkBlade", frontAxle + offset, onFork(0.75), 0.12)
	end
	tube("HeadTube", onFork(0.7), headTop, 0.22)
	tube("Stem", headTop, barCenter, 0.14, BIKE.MetalColor)

	-- Guidão e manoplas (as mãos vão nas manoplas)
	local gripX = 0.85
	tube("Handlebar", barCenter - Vector3.new(gripX, 0, 0), barCenter + Vector3.new(gripX, 0, 0), 0.12, BIKE.MetalColor)
	piece("GripLeft", Vector3.new(0.4, 0.18, 0.18), BIKE.AccentColor, CFrame.new(barCenter - Vector3.new(gripX, 0, 0)))
	piece("GripRight", Vector3.new(0.4, 0.18, 0.18), BIKE.AccentColor, CFrame.new(barCenter + Vector3.new(gripX, 0, 0)))

	-- Selim
	piece("Seat", Vector3.new(0.7, 0.22, 0.9), BIKE.AccentColor, CFrame.new(seatPos))
	piece("SeatNose", Vector3.new(0.32, 0.18, 0.6), BIKE.AccentColor, CFrame.new(seatPos + Vector3.new(0, -0.02, -0.65)))

	-- Farol e refletor
	local light = piece("Headlight", Vector3.new(0.3, 0.3, 0.2), Color3.fromRGB(255, 240, 180), CFrame.new(headTop + Vector3.new(0, -0.1, -0.2)))
	light.Material = Enum.Material.Neon
	local reflector = piece("Reflector", Vector3.new(0.25, 0.15, 0.08), Color3.fromRGB(220, 40, 40), CFrame.new(seatPostTop + Vector3.new(0, -0.1, 0.25)))
	reflector.Material = Enum.Material.Neon

	-- Pedivela: coroa, braços e pedais (giram juntos)
	local crank = spinner("Crank", bb, Vector3.new(0.5, 0.26, 0.26))
	attach(crank, newBikePart(bike, "Chainring", Vector3.new(0.08, 0.7, 0.7), Color3.fromRGB(70, 70, 75), Enum.PartType.Cylinder), CFrame.new(0.28, 0, 0))
	attach(crank, newBikePart(bike, "CrankArmRight", Vector3.new(0.1, crankR, 0.14), BIKE.MetalColor), CFrame.new(0.36, -crankR / 2, 0))
	attach(crank, newBikePart(bike, "CrankArmLeft", Vector3.new(0.1, crankR, 0.14), BIKE.MetalColor), CFrame.new(-0.36, crankR / 2, 0))
	attach(crank, newBikePart(bike, "PedalRight", Vector3.new(0.36, 0.1, 0.28), BIKE.WheelColor), CFrame.new(0.52, -crankR, 0))
	attach(crank, newBikePart(bike, "PedalLeft", Vector3.new(0.36, 0.1, 0.28), BIKE.WheelColor), CFrame.new(-0.52, crankR, 0))

	-- Corrente (parada; só visual)
	local chainX = Vector3.new(0.28, 0, 0)
	tube("ChainTop", bb + chainX + Vector3.new(0, 0.35, 0), rearAxle + chainX + Vector3.new(0, 0.18, 0), 0.06, Color3.fromRGB(40, 40, 45))
	tube("ChainBottom", bb + chainX - Vector3.new(0, 0.35, 0), rearAxle + chainX - Vector3.new(0, 0.18, 0), 0.06, Color3.fromRGB(40, 40, 45))

	bike:SetAttribute("WheelRadius", r)
	bike:SetAttribute("CrankRadius", crankR)
	bike.Parent = character
	return bike
end

local function sendState(player, mounted)
	uiUpdate:FireClient(player, "BikeState", { mounted = mounted })
end

local function dismount(player)
	local bike = bikes[player]
	bikes[player] = nil
	if bike then
		bike:Destroy()
	end
	local _, humanoid = SecurityService.getLivingCharacter(player)
	if humanoid then
		humanoid.WalkSpeed = GameConfig.WalkSpeed
	end
	sendState(player, false)
end

local function mount(player)
	if player:GetAttribute("Detained") or isStunned(player) then
		return
	end
	local character, humanoid, root = SecurityService.getLivingCharacter(player)
	if not character then
		return
	end
	if humanoid.Sit or humanoid.SeatPart then
		return -- não monta sentado em banco ou veículo
	end
	if ZoneService.isInside(player) then
		notice(player, "Aqui dentro não dá para usar a bike.")
		return
	end
	bikes[player] = buildBike(character, humanoid, root)
	humanoid.WalkSpeed = BIKE.Speed
	sendState(player, true)
end

---------------------------------------------------------------------------
-- Carro
---------------------------------------------------------------------------

local PERSONAL_CAR = GameConfig.Cars[GameConfig.CarModel]
local workplaces, personalGarage = {}, nil
local configuredPrompts = {}

local function blocked(player)
	return player:GetAttribute("Detained") or isStunned(player)
end

local function vehiclesFolder()
	local f = Workspace:FindFirstChild("Vehicles")
	if not f then f = Instance.new("Folder"); f.Name, f.Parent = "Vehicles", Workspace end
	return f
end

local function carState(player, record, driving)
	if uiUpdate and player.Parent == Players then
		uiUpdate:FireClient(player, "CarState", {
			driving = driving == true, workRole = record and record.role or nil,
			name = record and record.spec.Name or nil,
		})
	end
end

local function destroyCar(player)
	local c = cars[player]
	cars[player] = nil
	if c then
		for _, seat in ipairs({ c.driver, c.passenger }) do
			local occupant = seat and seat.Occupant
			if occupant then occupant.Sit = false end
		end
		if c.model then c.model:Destroy() end
	end
	carState(player, nil, false)
end

local function validRole(player, record)
	return not record.role or WorkRoleService.hasRole(player, record.role)
end

function VehicleService.getCar(player)
	local record = cars[player]
	if record and record.model and record.model.Parent then return record end
	return nil
end

function VehicleService.isDrivingWorkVehicle(player, role)
	local record = VehicleService.getCar(player)
	local _, humanoid = SecurityService.getLivingCharacter(player)
	local accepted = record ~= nil and record.role == role and validRole(player, record)
		and not blocked(player) and humanoid ~= nil and humanoid.SeatPart == record.driver
	return accepted == true, record
end

function VehicleService.destroyWorkVehicle(player, role)
	local record = VehicleService.getCar(player)
	if record and record.role and (role == nil or record.role == role) then
		destroyCar(player)
		return true
	end
	return false
end

local function charactersList(player)
	local list = {}
	for _, p in ipairs(Players:GetPlayers()) do if p.Character then table.insert(list, p.Character) end end
	local npcs = Workspace:FindFirstChild("NPCs")
	if npcs then table.insert(list, npcs) end
	local own = cars[player]
	if own and own.model then table.insert(list, own.model) end
	return list
end

local function clearSpot(player, markerCf, spec)
	local ignore = charactersList(player)
	local ray = RaycastParams.new()
	ray.FilterType, ray.FilterDescendantsInstances = Enum.RaycastFilterType.Exclude, ignore
	local p = markerCf.Position
	local hit = Workspace:Raycast(p + Vector3.new(0, 12, 0), Vector3.new(0, -60, 0), ray)
	if not hit then return nil end
	local center = Vector3.new(p.X, hit.Position.Y + spec.Hover, p.Z)
	local cf = CFrame.new(center) * markerCf.Rotation
	local overlap = OverlapParams.new()
	overlap.FilterType, overlap.FilterDescendantsInstances = Enum.RaycastFilterType.Exclude, ignore
	overlap.RespectCanCollide = true
	-- Inclui o teto do sedã, além do chassi. As placas do chão ficam abaixo da caixa.
	local parts = Workspace:GetPartBoundsInBox(cf * CFrame.new(0, 2.3, 0),
		Vector3.new(spec.Width + 1, 7, spec.Length + 1), overlap)
	if #parts > 0 or ZoneService.zoneAt(center) then return nil end
	return cf
end

local function findCarSpot(player, root, spec)
	local look = root.CFrame.LookVector
	local rotation = CFrame.Angles(0, math.atan2(-look.X, -look.Z), 0)
	local right, forward = rotation.RightVector, rotation.LookVector
	for _, offset in ipairs({ right * 9, -right * 9, forward * 12, -forward * 12, right * 18, -right * 18 }) do
		local found = clearSpot(player, CFrame.new(root.Position + offset) * rotation, spec)
		if found then return found end
	end
	return nil
end

local function nearPrompt(player, prompt)
	local _, _, root = SecurityService.getLivingCharacter(player)
	local parent = prompt and prompt.Parent
	local target = parent and (parent:IsA("BasePart") and parent.Position or parent:IsA("Attachment") and parent.WorldPosition)
	return root and target and (root.Position - target).Magnitude <= 11
end

local function nearAny(player, prompts)
	for _, prompt in ipairs(prompts or {}) do if nearPrompt(player, prompt) then return true end end
	return false
end

local function padSpot(player, pads, spec)
	for _, pad in ipairs(pads or {}) do
		if pad and pad:IsA("BasePart") and pad.Parent then
			local found = clearSpot(player, pad.CFrame, spec)
			if found then return found end
		end
	end
	return nil
end

local function sitInCar(player, humanoid)
	if blocked(player) then return false end
	local c = VehicleService.getCar(player)
	if not c or not validRole(player, c) or not c.driver.Parent or c.driver.Occupant then return false end
	if bikes[player] then dismount(player) end
	c.driver:Sit(humanoid)
	return true
end

local function spawnCar(player, humanoid, spec, spot, role)
	if blocked(player) or (role and not WorkRoleService.hasRole(player, role)) then return false end
	local ok, model, driver, passenger = pcall(CarBuilder.build, spec, spot)
	if not ok then warn("[VehicleService] Falha ao construir veículo: " .. tostring(model)); return false end
	if blocked(player) or (role and not WorkRoleService.hasRole(player, role)) then model:Destroy(); return false end
	destroyCar(player)
	model.Name = player.Name .. "_" .. spec.Name
	model:SetAttribute("Owner", player.UserId)
	model:SetAttribute("WorkRole", role)
	model:SetAttribute("Spec", spec.Name)
	model.Parent = vehiclesFolder()
	SeatService.setup(passenger, "Carona")
	local record = { model = model, driver = driver, passenger = passenger, spec = spec, role = role }
	cars[player] = record
	local chassis = model.PrimaryPart
	local doorToken = 0
	local function flashDoors()
		doorToken += 1
		local token = doorToken
		model:SetAttribute("DoorsOpen", true)
		task.delay(1.6, function() if token == doorToken and model.Parent then model:SetAttribute("DoorsOpen", false) end end)
	end
	driver:GetPropertyChangedSignal("Occupant"):Connect(function()
		if cars[player] ~= record or not model.Parent then return end
		flashDoors()
		local occupant = driver.Occupant
		local who = occupant and Players:GetPlayerFromCharacter(occupant.Parent)
		if occupant and (who ~= player or blocked(player) or not validRole(player, record)) then occupant.Sit = false; return end
		if who then
			pcall(function() chassis:SetNetworkOwner(who) end)
			carState(player, record, true)
		else
			local velocity = chassis:FindFirstChildOfClass("LinearVelocity")
			local upright = chassis:FindFirstChildOfClass("AlignOrientation")
			if velocity then velocity.VectorVelocity = Vector3.zero end
			if upright then local look = chassis.CFrame.LookVector; upright.CFrame = CFrame.Angles(0, math.atan2(-look.X, -look.Z), 0) end
			pcall(function() chassis:SetNetworkOwner(nil) end)
			carState(player, record, false)
		end
	end)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name, prompt.ActionText, prompt.ObjectText = "DrivePrompt", "Dirigir", spec.Name
	prompt.KeyboardKeyCode, prompt.MaxActivationDistance, prompt.RequiresLineOfSight = Enum.KeyCode.E, 9, false
	prompt.Parent = driver
	prompt.Triggered:Connect(function(who)
		if who ~= player then notice(who, "Esse veículo pertence a " .. player.DisplayName .. "."); return end
		if not nearPrompt(player, prompt) or not SecurityService.checkRate(player, "DrivePrompt", 0.5) then return end
		local _, hum = SecurityService.getLivingCharacter(player)
		if hum and not hum.SeatPart then sitInCar(player, hum) end
	end)
	if bikes[player] then dismount(player) end
	sitInCar(player, humanoid)
	carState(player, record, humanoid.SeatPart == driver)
	return true, record
end

local function exitCar(player, humanoid)
	local c = VehicleService.getCar(player)
	if not c then return end
	local seatWeld = c.driver:FindFirstChild("SeatWeld")
	if seatWeld then seatWeld:Destroy() end
	humanoid.Sit = false
	task.wait()
	local character = player.Character
	local chassis = c.model and c.model.PrimaryPart
	if character and chassis and c.model.Parent then character:PivotTo(chassis.CFrame * CFrame.new(-(c.spec.Width / 2 + 2.5), 1, 0)) end
end

function VehicleService.requestWorkVehicle(player, role)
	if type(role) ~= "string" or blocked(player) then return false end
	local entry = workplaces[role]
	local specId = GameConfig.WorkCars and GameConfig.WorkCars[role]
	local spec = specId and GameConfig.Cars[specId]
	if not entry or not spec or not WorkRoleService.hasRole(player, role) or not nearAny(player, entry.vehiclePrompts) then
		notice(player, "Retire o veículo na garagem do seu emprego, enquanto estiver em serviço.")
		return false
	end
	if not SecurityService.checkRate(player, "WorkVehiclePickup", 1) then return false end
	local _, humanoid = SecurityService.getLivingCharacter(player)
	if not humanoid then return false end
	if humanoid.SeatPart then notice(player, "Saia do veículo antes de retirar outro na garagem."); return false end
	local spot = padSpot(player, entry.vehicleSpawns, spec)
	if not spot then notice(player, "As vagas estão ocupadas. Libere uma vaga antes de retirar o veículo."); return false end
	return spawnCar(player, humanoid, spec, spot, role)
end

function VehicleService.requestPersonalAtGarage(player)
	if blocked(player) or not personalGarage or not nearPrompt(player, personalGarage.prompt) then return false end
	if not SecurityService.checkRate(player, "PersonalGarage", 1) then return false end
	local _, humanoid = SecurityService.getLivingCharacter(player)
	if not humanoid then return false end
	if humanoid.SeatPart then notice(player, "Saia do veículo antes de retirar outro na garagem."); return false end
	-- O Vortex é o único veículo pessoal já concedido no protótipo. O posto nunca
	-- entrega um táxi/viatura e não concede outros modelos ou compras.
	local spot = padSpot(player, personalGarage.spawns, PERSONAL_CAR)
	if not spot then notice(player, "A garagem está ocupada. Aguarde uma vaga livre."); return false end
	return spawnCar(player, humanoid, PERSONAL_CAR, spot, nil)
end

function VehicleService.configureWorkplaces(entries, garage)
	workplaces, personalGarage = entries or {}, garage
	for role, entry in pairs(workplaces) do
		for _, prompt in ipairs(entry.vehiclePrompts or {}) do
			if not configuredPrompts[prompt] then
				configuredPrompts[prompt] = true; prompt.Enabled = true
				prompt.Triggered:Connect(function(player) VehicleService.requestWorkVehicle(player, role) end)
			end
		end
	end
	if garage and garage.prompt and not configuredPrompts[garage.prompt] then
		configuredPrompts[garage.prompt] = true; garage.prompt.Enabled = true
		garage.prompt.Triggered:Connect(VehicleService.requestPersonalAtGarage)
	end
end

local function toggleCar(player)
	if blocked(player) then return end
	local character, humanoid, root = SecurityService.getLivingCharacter(player)
	if not character then return end
	local c = VehicleService.getCar(player)
	if c and not validRole(player, c) then destroyCar(player); c = nil end
	if c and humanoid.SeatPart == c.driver then exitCar(player, humanoid); return end
	if humanoid.SeatPart then return end
	if ZoneService.isInside(player) then notice(player, "Aqui dentro não dá para usar o carro."); return end
	local chassis = c and c.model.PrimaryPart
	if chassis and (chassis.Position - root.Position).Magnitude < 18 and sitInCar(player, humanoid) then return end
	if c and c.role then
		notice(player, "Seu veículo de trabalho fica onde foi estacionado. Busque-o ou retire outro na garagem do emprego.")
		return
	end
	local spot = findCarSpot(player, root, PERSONAL_CAR)
	if not spot then notice(player, "Sem espaço para o carro aqui. Vá para a rua!"); return end
	spawnCar(player, humanoid, PERSONAL_CAR, spot, nil)
end

local function watchCarSpeed()
	while true do
		task.wait(1)
		for player, c in pairs(cars) do
			if not c.model.Parent or not validRole(player, c) then destroyCar(player)
			else
				local chassis = c.model.PrimaryPart
				local speed = chassis and chassis.AssemblyLinearVelocity.Magnitude
				if speed and (speed ~= speed or speed > c.spec.MaxSpeed * 1.6) then
					local _, humanoid = SecurityService.getLivingCharacter(player)
					if humanoid and humanoid.SeatPart == c.driver then exitCar(player, humanoid) end
					if chassis.Parent then chassis.AssemblyLinearVelocity = Vector3.zero end
				end
			end
		end
	end
end

local function onVehicleRequest(player, action)
	if not SecurityService.checkRate(player, "VehicleRequest", BIKE.ToggleCooldown) or not SecurityService.isShortString(action, 16) then return end
	if blocked(player) then notice(player, "Você não pode usar veículos durante a detenção ou imobilização."); return end
	if action == "ToggleBike" then
		if bikes[player] and bikes[player].Parent then dismount(player) else mount(player) end
	elseif action == "ToggleCar" and SecurityService.checkRate(player, "Car", GameConfig.CarCooldown) then toggleCar(player) end
end

function VehicleService.dismount(player)
	if bikes[player] then dismount(player) end
end

function VehicleService.prepareForDetention(player)
	local character, humanoid = SecurityService.getLivingCharacter(player)
	local seat = humanoid and humanoid.SeatPart
	local weld = seat and seat:FindFirstChild("SeatWeld")
	if weld and weld:IsA("Weld") then
		if (weld.Part0 and weld.Part0:IsDescendantOf(character)) or (weld.Part1 and weld.Part1:IsDescendantOf(character)) then weld:Destroy() end
	end
	if humanoid then humanoid.Sit = false; humanoid.WalkSpeed = GameConfig.WalkSpeed end
	if bikes[player] then dismount(player) end
	destroyCar(player)
end

function VehicleService.init(remotes)
	uiUpdate = remotes[GameConfig.Remotes.UIUpdate]
	remotes[GameConfig.Remotes.VehicleRequest].OnServerEvent:Connect(onVehicleRequest)
	local function onPlayerAdded(player)
		local function watchCharacter(character)
			bikes[player] = nil; destroyCar(player); sendState(player, false)
			local function watchDeath(humanoid)
				if humanoid and humanoid.Died then
					humanoid.Died:Connect(function()
						if player.Character == character then bikes[player] = nil; destroyCar(player); sendState(player, false) end
					end)
				end
			end
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if humanoid then watchDeath(humanoid)
			else task.spawn(function() watchDeath(character:WaitForChild("Humanoid", 10)) end) end
		end
		player.CharacterAdded:Connect(watchCharacter)
		if player.Character then watchCharacter(player.Character) end
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in ipairs(Players:GetPlayers()) do onPlayerAdded(player) end
	Players.PlayerRemoving:Connect(function(player) bikes[player] = nil; destroyCar(player) end)
	ZoneService.onChange(function(player, inside)
		if inside and bikes[player] then dismount(player); notice(player, "Bike guardada: aqui é local de trabalho.") end
	end)
	WorkRoleService.onChanged(function(player, newRole)
		local c = VehicleService.getCar(player)
		if c and c.role and c.role ~= newRole then destroyCar(player) end
	end)
	task.spawn(watchCarSpeed)
end

return VehicleService
