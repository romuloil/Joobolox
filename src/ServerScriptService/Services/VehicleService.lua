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

local CAR = GameConfig.Cars[GameConfig.CarModel]

local function vehiclesFolder()
	local f = Workspace:FindFirstChild("Vehicles")
	if not f then
		f = Instance.new("Folder")
		f.Name = "Vehicles"
		f.Parent = Workspace
	end
	return f
end

local function destroyCar(player)
	local c = cars[player]
	cars[player] = nil
	if c and c.model then
		c.model:Destroy()
	end
end

local function charactersList()
	local list = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(list, p.Character)
		end
	end
	local npcs = Workspace:FindFirstChild("NPCs")
	if npcs then
		table.insert(list, npcs)
	end
	return list
end

-- Procura um lugar livre para o carro perto do jogador (no chão, sem encostar em parede/cerca)
local function findCarSpot(root)
	local ray = RaycastParams.new()
	ray.FilterType = Enum.RaycastFilterType.Exclude
	ray.FilterDescendantsInstances = charactersList()
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = charactersList()
	overlap.RespectCanCollide = true
	local look = root.CFrame.LookVector
	local yaw = math.atan2(-look.X, -look.Z)
	local rotation = CFrame.Angles(0, yaw, 0)
	local right = rotation.RightVector
	local forward = rotation.LookVector
	for _, offset in ipairs({ Vector3.zero, right * 9, -right * 9, forward * 12, -forward * 12, right * 18, -right * 18 }) do
		local p = root.Position + offset
		local hit = Workspace:Raycast(p + Vector3.new(0, 6, 0), Vector3.new(0, -30, 0), ray)
		if hit then
			local center = Vector3.new(p.X, hit.Position.Y + CAR.Hover, p.Z)
			-- caixa do carro, começando um pouco acima do chão (calçada e meio-fio não contam)
			local box = CFrame.new(center + Vector3.new(0, 0.6, 0)) * rotation
			local parts = Workspace:GetPartBoundsInBox(box, Vector3.new(CAR.Width + 0.6, 3, CAR.Length + 0.6), overlap)
			if #parts == 0 and not ZoneService.zoneAt(center) then
				return CFrame.new(center) * rotation
			end
		end
	end
	return nil
end

local function sitInCar(player, humanoid)
	if player:GetAttribute("Detained") or isStunned(player) then
		return false
	end
	local c = cars[player]
	if not c or not c.driver.Parent or c.driver.Occupant then
		return false
	end
	if bikes[player] then
		dismount(player)
	end
	c.driver:Sit(humanoid)
	return true
end

local function spawnCar(player, humanoid, root)
	local spot = findCarSpot(root)
	if not spot then
		notice(player, "Sem espaço para o carro aqui. Vá para a rua!")
		return
	end
	destroyCar(player)
	local model, driver, passenger = CarBuilder.build(CAR, spot)
	model.Name = player.Name .. "_" .. CAR.Name
	model:SetAttribute("Owner", player.UserId)
	model.Parent = vehiclesFolder()
	SeatService.setup(passenger, "Carona")
	cars[player] = { model = model, driver = driver }

	local chassis = model.PrimaryPart
	-- Portas abrem um instante quando alguém entra ou sai (o cliente anima)
	local doorToken = 0
	local function flashDoors()
		doorToken += 1
		local token = doorToken
		model:SetAttribute("DoorsOpen", true)
		task.delay(1.6, function()
			if token == doorToken and model.Parent then
				model:SetAttribute("DoorsOpen", false)
			end
		end)
	end
	-- Quem senta no banco do motorista passa a controlar a física do carro
	driver:GetPropertyChangedSignal("Occupant"):Connect(function()
		flashDoors()
		local occupant = driver.Occupant
		local who = occupant and Players:GetPlayerFromCharacter(occupant.Parent)
		if occupant and (who ~= player or player:GetAttribute("Detained") or isStunned(player)) then
			occupant.Sit = false -- só o dono dirige
			return
		end
		if who then
			pcall(function()
				chassis:SetNetworkOwner(who)
			end)
			uiUpdate:FireClient(player, "CarState", { driving = true })
		else
			-- saiu: o carro fica parado onde está, virado para o mesmo lado
			local drive = chassis:FindFirstChildOfClass("LinearVelocity")
			local upright = chassis:FindFirstChildOfClass("AlignOrientation")
			if drive then
				drive.VectorVelocity = Vector3.zero
			end
			if upright then
				local look = chassis.CFrame.LookVector
				upright.CFrame = CFrame.Angles(0, math.atan2(-look.X, -look.Z), 0)
			end
			pcall(function()
				chassis:SetNetworkOwner(nil)
			end)
			uiUpdate:FireClient(player, "CarState", { driving = false })
		end
	end)

	-- Entrar de novo: E perto da porta do motorista (só o dono)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "DrivePrompt"
	prompt.ActionText = "Dirigir"
	prompt.ObjectText = CAR.Name
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.MaxActivationDistance = 9
	prompt.RequiresLineOfSight = false
	prompt.Parent = driver
	prompt.Triggered:Connect(function(who)
		if who ~= player then
			notice(who, "Esse carro é de " .. player.DisplayName .. ".")
			return
		end
		local _, hum = SecurityService.getLivingCharacter(player)
		if hum and not hum.SeatPart then
			sitInCar(player, hum)
		end
	end)

	sitInCar(player, humanoid)
end

local function exitCar(player, humanoid)
	local c = cars[player]
	if not c then
		return
	end
	local seatWeld = c.driver:FindFirstChild("SeatWeld")
	if seatWeld then
		seatWeld:Destroy()
	end
	humanoid.Sit = false
	task.wait()
	local character = player.Character
	local chassis = c.model.PrimaryPart
	if character and chassis then
		-- desce pela porta do motorista (lado esquerdo)
		character:PivotTo(chassis.CFrame * CFrame.new(-(CAR.Width / 2 + 2.5), 1, 0))
	end
end

local function toggleCar(player)
	if player:GetAttribute("Detained") or isStunned(player) then
		return
	end
	local character, humanoid, root = SecurityService.getLivingCharacter(player)
	if not character then
		return
	end
	local c = cars[player]
	if c and humanoid.SeatPart == c.driver then
		exitCar(player, humanoid)
		return
	end
	if humanoid.SeatPart then
		return -- sentado em outro banco
	end
	if ZoneService.isInside(player) then
		notice(player, "Aqui dentro não dá para usar o carro.")
		return
	end
	-- Carro perto: entra nele. Longe (ou nenhum): chama um novo do seu lado.
	local chassis = c and c.model.PrimaryPart
	if chassis and (chassis.Position - root.Position).Magnitude < 40 and sitInCar(player, humanoid) then
		return
	end
	if bikes[player] then
		dismount(player)
	end
	spawnCar(player, humanoid, root)
end

-- Velocidade impossível = trava o carro (o motorista controla a física, então o servidor confere)
local function watchCarSpeed()
	while true do
		task.wait(1)
		for player, c in pairs(cars) do
			local chassis = c.model and c.model.PrimaryPart
			if chassis and chassis.AssemblyLinearVelocity.Magnitude > CAR.MaxSpeed * 1.6 then
				warn(("[VehicleService] Velocidade estranha no carro de %s; carro parado."):format(player.Name))
				local _, humanoid = SecurityService.getLivingCharacter(player)
				if humanoid and humanoid.SeatPart == c.driver then
					exitCar(player, humanoid)
				end
				chassis.AssemblyLinearVelocity = Vector3.zero
			end
		end
	end
end

local function onVehicleRequest(player, action)
	-- 1. limite de frequência antes de qualquer coisa
	if not SecurityService.checkRate(player, "VehicleRequest", BIKE.ToggleCooldown) then
		return
	end
	-- 2. tipo do argumento
	if not SecurityService.isShortString(action, 16) then
		return
	end
	if player:GetAttribute("Detained") or isStunned(player) then
		notice(player, "Você não pode usar veículos durante a detenção ou imobilização.")
		return
	end
	-- 3. ação conhecida
	if action == "ToggleBike" then
		if bikes[player] and bikes[player].Parent then
			dismount(player)
		else
			mount(player)
		end
	elseif action == "ToggleCar" then
		if SecurityService.checkRate(player, "Car", GameConfig.CarCooldown) then
			toggleCar(player)
		end
	end
end

-- Usado pelo SeatService: desce da bike antes de sentar num banco
function VehicleService.dismount(player)
	if bikes[player] then
		dismount(player)
	end
end

-- Retira também o carro já estacionado, antes de levar o jogador à prisão.
function VehicleService.prepareForDetention(player)
	local character, humanoid = SecurityService.getLivingCharacter(player)
	local seat = humanoid and humanoid.SeatPart
	local weld = seat and seat:FindFirstChild("SeatWeld")
	if weld and weld:IsA("Weld") then
		if (weld.Part0 and weld.Part0:IsDescendantOf(character))
			or (weld.Part1 and weld.Part1:IsDescendantOf(character)) then
			weld:Destroy()
		end
	end
	if humanoid then
		humanoid.Sit = false
		humanoid.WalkSpeed = GameConfig.WalkSpeed
	end
	if bikes[player] then
		dismount(player)
	end
	destroyCar(player)
	uiUpdate:FireClient(player, "CarState", { driving = false })
end

function VehicleService.init(remotes)
	uiUpdate = remotes[GameConfig.Remotes.UIUpdate]
	remotes[GameConfig.Remotes.VehicleRequest].OnServerEvent:Connect(onVehicleRequest)

	local function onPlayerAdded(player)
		player.CharacterAdded:Connect(function()
			-- personagem novo começa a pé (a bicicleta antiga sumiu junto com o corpo)
			bikes[player] = nil
			sendState(player, false)
		end)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in ipairs(Players:GetPlayers()) do
		onPlayerAdded(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		bikes[player] = nil
		destroyCar(player)
	end)

	-- Entrou num local de trabalho de bike: desce na hora
	ZoneService.onChange(function(player, inside)
		if inside and bikes[player] then
			dismount(player)
			notice(player, "Bike guardada: aqui é local de trabalho.")
		end
	end)
	task.spawn(watchCarSpeed)
end

return VehicleService
