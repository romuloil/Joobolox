-- CarBuilder (ModuleScript)
-- Caminho: ServerScriptService > Services > CarBuilder
-- Monta um carro a partir dos dados de GameConfig.Cars (base para os próximos carros).
-- Estrutura:
--   * Chassis: caixa invisível que colide com paredes e calçadas; é ela que anda.
--     LinearVelocity (velocidade) + AlignOrientation (direção, sempre em pé) controlados por
--     quem dirige (CarController, no cliente do motorista).
--   * Carroceria, vidros, luzes, rodas: só visual (não colidem, não pesam), soldados no chassi.
--   * Rodas e portas presas por Motor6D: o cliente gira as rodas, esterça e abre as portas.
--   * VehicleSeat do motorista (esquerda) e Seat do carona (direita).
--   * Bancos "RearSeat" (atrás): o VehicleService liga o "Sentar" com E neles.
-- Frente do carro = -Z.
-- Dois jeitos de montar a carroceria (o chassi e a física são os mesmos):
--   * Modelo 3D em ServerStorage > CarModels (Marco 6.3: LXR L5, R18, Mengeot).
--   * Se o modelo não estiver lá: sedã feito de peças (grade dupla, faróis amarelos,
--     portas da frente que abrem para o lado), com as cores do spec.

local CarBuilder = {}

local function part(parent, props)
	local p = Instance.new(props.ClassName or "Part")
	p.Name = props.Name
	p.Size = props.Size
	p.Color = props.Color or Color3.new(1, 1, 1)
	p.Material = props.Material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if props.Shape then
		p.Shape = props.Shape
	end
	p.Transparency = props.Transparency or 0
	p.Reflectance = props.Reflectance or 0
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Massless = true
	p.Anchored = false
	p.CFrame = props.CFrame
	p.Parent = parent
	return p
end

local function weld(a, b)
	local w = Instance.new("WeldConstraint")
	w.Part0 = a
	w.Part1 = b
	w.Parent = b
end

-- Peça que gira/abre presa ao chassi por Motor6D no ponto "pivot" (coordenadas do chassi)
local function hinged(chassis, p, pivot, motorName)
	local localCf = chassis.CFrame:ToObjectSpace(p.CFrame)
	local motor = Instance.new("Motor6D")
	motor.Name = motorName
	motor.Part0 = chassis
	motor.Part1 = p
	motor.C0 = CFrame.new(pivot)
	motor.C1 = (CFrame.new(pivot):Inverse() * localCf):Inverse()
	motor.Parent = p
	return motor
end

-- Chassi: caixa invisível que colide e anda (igual para todos os carros)
local function newChassis(spec, cf)
	local car = Instance.new("Model")
	car.Name = spec.Name
	car.ModelStreamingMode = Enum.ModelStreamingMode.Atomic -- Marco 10.22: carro chega inteiro (streaming)
	local chassis = part(car, { Name = "Chassis", Size = Vector3.new(spec.Width - 0.4, 2.4, spec.Length - 0.6), CFrame = cf, Transparency = 1 })
	chassis.CanCollide = true
	chassis.CanQuery = true
	chassis.Massless = false
	chassis.RootPriority = 127 -- a base do carro é sempre o chassi (nunca quem senta)
	chassis.CustomPhysicalProperties = PhysicalProperties.new(0.7, 0, 0, 100, 1) -- sem atrito: desliza sobre a calçada
	car.PrimaryPart = chassis
	return car, chassis
end

-- Física, grupo de colisão e nome do modelo (final comum dos dois jeitos de montar)
local finish

-- Carro montado com peças (usado quando o modelo 3D não está em ServerStorage > CarModels)
local function buildFromParts(spec, cf)
	local car, chassis = newChassis(spec, cf)
	local L, W = spec.Length, spec.Width
	local r = spec.WheelRadius
	local g = -spec.Hover -- altura do chão, em coordenadas do chassi

	local function at(x, y, z)
		return cf * CFrame.new(x, y, z)
	end
	-- peça soldada no chassi; extra = { ClassName, Material, Transparency, Reflectance, Shape, rot }
	local function body(name, size, x, y, z, color, extra)
		extra = extra or {}
		local p = part(car, {
			ClassName = extra.ClassName,
			Name = name,
			Size = size,
			CFrame = at(x, y, z) * (extra.rot or CFrame.new()),
			Color = color,
			Material = extra.Material,
			Transparency = extra.Transparency,
			Reflectance = extra.Reflectance,
			Shape = extra.Shape,
		})
		weld(chassis, p)
		if color == spec.BodyColor then
			p:SetAttribute("Paint", true) -- a loja de pintura muda a cor destas peças
		end
		return p
	end
	local paint = { Reflectance = spec.Reflectance or 0.08 }
	local neon = { Material = Enum.Material.Neon }
	local BODY, TRIM, ACCENT, GLASS = spec.BodyColor, spec.TrimColor, spec.AccentColor, spec.GlassColor
	local BLACK = Color3.fromRGB(12, 12, 14)
	local RED = Color3.fromRGB(200, 25, 30)
	local front, back = -L / 2, L / 2
	-- Linhas da cabine (sedã de 4 portas): base do para-brisa, teto e base do vidro traseiro
	local shieldZ, roofFront, roofBack, deckZ = front + 5.6, front + 8.0, back - 6.2, back - 3.9
	local beltY, roofY = g + 3.6, g + 5.55

	-- Base, laterais altas e para-choques
	body("Sill", Vector3.new(W - 0.5, 0.7, L - 1.4), 0, g + 1.25, 0, BLACK)
	body("Body", Vector3.new(W - 0.6, 1.9, L - 0.8), 0, g + 2.6, 0, BODY, paint)
	body("Shoulder", Vector3.new(W - 0.9, 0.12, L - 2), 0, g + 3.42, 0, BODY, paint) -- vinco da lateral
	-- Capô longo com "power dome" no meio (duas entradas de ar)
	body("Hood", Vector3.new(W - 0.9, 0.5, shieldZ - front - 1.2), 0, beltY - 0.15, (front + 1.2 + shieldZ) / 2, BODY, paint)
	body("HoodNose", Vector3.new(W - 1.0, 0.5, 1.3), 0, beltY - 0.4, front + 0.75, BODY, { ClassName = "WedgePart", Reflectance = paint.Reflectance })
	body("HoodDome", Vector3.new(2.4, 0.22, shieldZ - front - 2.6), 0, beltY + 0.2, (front + 2.2 + shieldZ) / 2, BODY, paint)
	for _, s in ipairs({ -1, 1 }) do
		body("HoodVent", Vector3.new(0.7, 0.06, 1.4), s * 1.7, beltY + 0.11, front + 3.2, BLACK)
	end
	-- Tampa do porta-malas curta com aerofólio de lábio preto
	body("Trunk", Vector3.new(W - 0.9, 0.5, back - deckZ - 0.3), 0, beltY - 0.15, (deckZ + back - 0.3) / 2, BODY, paint)
	body("LipSpoiler", Vector3.new(W - 1.3, 0.22, 0.7), 0, beltY + 0.2, back - 0.55, BLACK, { Reflectance = 0.15 })

	-- Cabine: para-brisa inclinado, teto preto (fibra de carbono), vidro traseiro inclinado
	body("Windshield", Vector3.new(W - 1.7, roofY - beltY, roofFront - shieldZ), 0, (beltY + roofY) / 2, (shieldZ + roofFront) / 2, GLASS, {
		ClassName = "WedgePart",
		Material = Enum.Material.SmoothPlastic,
		Transparency = 0.3,
	})
	body("Roof", Vector3.new(W - 1.8, 0.28, roofBack - roofFront + 0.2), 0, roofY + 0.1, (roofFront + roofBack) / 2, TRIM, { Reflectance = 0.2 })
	body("RoofFin", Vector3.new(0.3, 0.35, 0.8), 0, roofY + 0.4, roofBack - 0.6, BLACK) -- antena "barbatana"
	body("RearGlass", Vector3.new(W - 1.7, roofY - beltY, deckZ - roofBack), 0, (beltY + roofY) / 2, (roofBack + deckZ) / 2, GLASS, {
		ClassName = "WedgePart",
		Material = Enum.Material.SmoothPlastic,
		Transparency = 0.3,
		rot = CFrame.Angles(0, math.pi, 0),
	})
	local doorFront, doorSplit = shieldZ + 1.4, shieldZ + 5.4 -- porta da frente / porta de trás
	for _, s in ipairs({ -1, 1 }) do
		local x = s * (W / 2 - 0.85)
		-- colunas pretas (A, B, C) e moldura preta dos vidros
		local h = roofY - beltY
		local lenA, lenC = (roofFront - shieldZ), (deckZ - roofBack)
		-- colunas inclinadas acompanham o para-brisa e o vidro traseiro
		body("PillarA", Vector3.new(0.3, math.sqrt(h * h + lenA * lenA), 0.35), x, (beltY + roofY) / 2, (shieldZ + roofFront) / 2, BLACK, { rot = CFrame.Angles(math.atan2(lenA, h), 0, 0) })
		body("PillarB", Vector3.new(0.3, roofY - beltY, 0.45), x, (beltY + roofY) / 2, doorSplit, BLACK)
		body("PillarC", Vector3.new(0.3, math.sqrt(h * h + lenC * lenC), 0.35), x, (beltY + roofY) / 2, (roofBack + deckZ) / 2, BLACK, { rot = CFrame.Angles(-math.atan2(lenC, h), 0, 0) })
		body("WindowTrim", Vector3.new(0.2, 0.12, deckZ - shieldZ - 1.5), s * (W / 2 - 0.8), beltY + 0.05, (shieldZ + deckZ) / 2, BLACK)
		-- porta de trás (fixa) com vidro, linha de vão e maçaneta
		body("RearDoorGlass", Vector3.new(0.12, roofY - beltY - 0.35, deckZ - doorSplit - 1.6), x, (beltY + roofY) / 2 - 0.1, (doorSplit + deckZ - 1.2) / 2, GLASS, { Material = Enum.Material.SmoothPlastic, Transparency = 0.3 })
		body("RearDoorSeam", Vector3.new(0.06, 1.9, 0.08), s * (W / 2 - 0.28), g + 2.6, doorSplit + 3.6, BLACK)
		body("RearHandle", Vector3.new(0.08, 0.14, 0.6), s * (W / 2 - 0.27), g + 3.1, doorSplit + 2.6, Color3.fromRGB(190, 190, 195))
		-- entrada de ar preta no para-lama da frente e retrovisor preto
		body("FenderGill", Vector3.new(0.08, 0.35, 1.0), s * (W / 2 - 0.27), g + 3.0, front + 4.6, BLACK)
		body("Mirror", Vector3.new(0.8, 0.45, 0.6), s * (W / 2 - 0.05), beltY + 0.35, doorFront + 0.3, BLACK)
		body("MirrorArm", Vector3.new(0.5, 0.12, 0.25), s * (W / 2 - 0.4), beltY + 0.2, doorFront + 0.3, BLACK)
		-- saia lateral preta
		body("SideSkirt", Vector3.new(0.15, 0.3, L - 7), s * (W / 2 - 0.24), g + 1.55, 0, BLACK)
	end

	-- Portas da frente (abrem para o lado, presas na dobradiça da frente)
	local doorLen = doorSplit - doorFront - 0.15
	local doorZ = doorFront + doorLen / 2
	for _, s in ipairs({ -1, 1 }) do
		local door = part(car, { Name = s < 0 and "DoorLeft" or "DoorRight", Size = Vector3.new(0.18, 1.9, doorLen), CFrame = at(s * (W / 2 - 0.24), g + 2.6, doorZ), Color = BODY, Reflectance = paint.Reflectance })
		door:SetAttribute("Paint", true)
		local doorGlass = part(car, { Name = "DoorGlass", Size = Vector3.new(0.12, roofY - beltY - 0.35, doorLen - 0.6), CFrame = at(s * (W / 2 - 0.85), (beltY + roofY) / 2 - 0.1, doorZ + 0.2), Color = GLASS, Material = Enum.Material.SmoothPlastic, Transparency = 0.3 })
		local handle = part(car, { Name = "Handle", Size = Vector3.new(0.08, 0.14, 0.6), CFrame = at(s * (W / 2 - 0.12), g + 3.1, doorZ + 1.0), Color = Color3.fromRGB(190, 190, 195) })
		body("DoorGap", Vector3.new(0.05, 1.9, doorLen - 0.1), s * (W / 2 - 0.33), g + 2.6, doorZ, Color3.fromRGB(14, 14, 16))
		weld(door, doorGlass)
		weld(door, handle)
		local motor = hinged(chassis, door, Vector3.new(s * (W / 2 - 0.2), g + 2.6, doorFront), "DoorMotor")
		motor:SetAttribute("Side", s)
		motor:SetAttribute("Style", "swing")
	end

	-- Frente: grade dupla grande ("rins") com moldura dourada, faróis finos com luz amarela em L
	for _, s in ipairs({ -1, 1 }) do
		body("GrilleFrame", Vector3.new(1.45, 1.25, 0.2), s * 0.8, g + 2.95, front + 0.22, spec.RimColor, { Material = Enum.Material.Metal })
		body("Grille", Vector3.new(1.25, 1.05, 0.22), s * 0.8, g + 2.95, front + 0.2, BLACK)
		for k = -2, 2 do
			body("GrilleBar", Vector3.new(0.05, 1.0, 0.24), s * 0.8 + k * 0.22, g + 2.95, front + 0.19, Color3.fromRGB(40, 40, 44))
		end
		body("HeadlightHousing", Vector3.new(2.1, 0.6, 0.25), s * 2.55, g + 3.2, front + 0.3, BLACK, { rot = CFrame.Angles(0, s * math.rad(-10), 0) })
		body("DRL", Vector3.new(1.7, 0.1, 0.27), s * 2.5, g + 3.05, front + 0.29, ACCENT, { Material = Enum.Material.Neon, rot = CFrame.Angles(0, s * math.rad(-10), s * math.rad(-8)) })
		body("DRLCorner", Vector3.new(0.1, 0.35, 0.27), s * 3.2, g + 3.25, front + 0.4, ACCENT, neon)
		body("Headlight", Vector3.new(0.8, 0.25, 0.26), s * 2.4, g + 3.3, front + 0.28, Color3.fromRGB(230, 245, 255), neon)
		-- entradas de ar laterais grandes no para-choque
		body("SideIntake", Vector3.new(1.4, 1.0, 0.2), s * 2.75, g + 1.95, front + 0.3, BLACK)
		body("IntakeFin", Vector3.new(1.4, 0.08, 0.22), s * 2.75, g + 1.95, front + 0.29, Color3.fromRGB(45, 45, 50))
	end
	body("LowerIntake", Vector3.new(3.0, 0.7, 0.2), 0, g + 1.9, front + 0.3, BLACK)
	body("Splitter", Vector3.new(W - 0.6, 0.15, 0.9), 0, g + 1.0, front + 0.55, BLACK)
	body("FrontPlate", Vector3.new(1.9, 0.45, 0.1), 0, g + 2.25, front + 0.15, Color3.new(1, 1, 1))

	-- Emblema LXR (frente e traseira) e nome L5 na tampa traseira
	local function badge(name, size, x, y, z, faceBack, text, color)
		local p = body(name, size, x, y, z, Color3.fromRGB(20, 20, 24))
		local gui = Instance.new("SurfaceGui")
		gui.Face = faceBack and Enum.NormalId.Back or Enum.NormalId.Front
		gui.CanvasSize = Vector2.new(200, 80)
		gui.Parent = p
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBlack
		label.TextScaled = true
		label.Text = text
		label.TextColor3 = color
		label.Parent = gui
		return p
	end
	badge("BadgeFront", Vector3.new(0.9, 0.35, 0.1), 0, beltY - 0.1, front + 0.6, false, "LXR", Color3.fromRGB(220, 225, 235))
	badge("BadgeRear", Vector3.new(0.9, 0.35, 0.1), 0, beltY - 0.25, back - 0.32, true, "LXR", Color3.fromRGB(220, 225, 235))
	badge("ModelBadge", Vector3.new(0.9, 0.3, 0.1), 2.3, g + 3.05, back - 0.32, true, "L5", ACCENT)

	-- Traseira: lanternas em L (com parte na tampa), difusor e 4 escapamentos
	for _, s in ipairs({ -1, 1 }) do
		body("Taillight", Vector3.new(2.0, 0.45, 0.15), s * 2.65, g + 3.2, back - 0.32, RED, neon)
		body("TaillightInner", Vector3.new(1.0, 0.3, 0.15), s * 1.3, g + 3.25, back - 0.33, Color3.fromRGB(150, 15, 20), neon)
		body("TaillightLine", Vector3.new(1.9, 0.07, 0.17), s * 2.6, g + 3.0, back - 0.31, Color3.fromRGB(255, 80, 80), neon)
		body("Reflector", Vector3.new(0.15, 0.7, 0.12), s * (W / 2 - 0.4), g + 1.9, back - 0.32, RED, neon)
		for _, ex in ipairs({ 1.85, 2.55 }) do
			body("Exhaust", Vector3.new(0.4, 0.55, 0.55), s * ex, g + 1.35, back - 0.15, Color3.fromRGB(40, 40, 44), {
				Shape = Enum.PartType.Cylinder,
				Material = Enum.Material.Metal,
				rot = CFrame.Angles(0, math.rad(90), 0),
			})
		end
	end
	body("Diffuser", Vector3.new(W - 1, 0.7, 0.4), 0, g + 1.35, back - 0.3, BLACK)
	for k = -2, 2 do
		body("DiffuserFin", Vector3.new(0.08, 0.6, 0.5), k * 0.45, g + 1.35, back - 0.25, Color3.fromRGB(35, 35, 40))
	end
	body("Plate", Vector3.new(1.9, 0.55, 0.1), 0, g + 2.55, back - 0.35, Color3.new(1, 1, 1))

	-- Interior: painel, volante, 2 bancos na frente e 2 atrás
	body("Dashboard", Vector3.new(W - 1.9, 0.7, 1), 0, beltY - 0.2, shieldZ + 0.7, Color3.fromRGB(30, 30, 34))
	body("Screen", Vector3.new(1.6, 0.6, 0.1), 0.2, beltY + 0.35, shieldZ + 1.0, Color3.fromRGB(40, 90, 150), neon)
	body("SteeringWheel", Vector3.new(0.12, 1.1, 1.1), -1.5, beltY - 0.3, shieldZ + 1.5, Color3.fromRGB(20, 20, 22), {
		Shape = Enum.PartType.Cylinder,
		rot = CFrame.Angles(0, math.rad(90), 0) * CFrame.Angles(0, 0, math.rad(25)),
	})
	local seatY = g + 1.2
	local frontSeatZ, rearSeatZ = shieldZ + 3.1, doorSplit + 1.6
	local seatColor = spec.SeatColor or Color3.fromRGB(40, 40, 44)
	local driver = part(car, { ClassName = "VehicleSeat", Name = "DriverSeat", Size = Vector3.new(1.8, 0.4, 1.8), CFrame = at(-1.5, seatY, frontSeatZ), Color = seatColor })
	driver.CanTouch = false -- só entra pelo botão "Carro" ou pelo E (dono)
	driver.MaxSpeed = 0 -- o VehicleSeat só lê o controle; quem move o carro é o CarController
	driver.Torque = 0
	driver.HeadsUpDisplay = false
	driver:SetAttribute("CarSeat", true)
	weld(chassis, driver)
	local passenger = part(car, { ClassName = "Seat", Name = "PassengerSeat", Size = Vector3.new(1.8, 0.4, 1.8), CFrame = at(1.5, seatY, frontSeatZ), Color = seatColor })
	weld(chassis, passenger)
	for _, x in ipairs({ -1.5, 1.5 }) do
		local rear = part(car, { ClassName = "Seat", Name = "RearSeat", Size = Vector3.new(1.8, 0.4, 1.8), CFrame = at(x, seatY, rearSeatZ), Color = seatColor })
		weld(chassis, rear)
		for _, z in ipairs({ frontSeatZ, rearSeatZ }) do
			body("SeatBack", Vector3.new(1.8, 2.2, 0.4), x, seatY + 1.2, z + 1.0, seatColor, { rot = CFrame.Angles(math.rad(-12), 0, 0) })
		end
	end

	-- Rodas grandes: pneu, roda dourada com raios duplos, pinça vermelha. Hub preso por Motor6D.
	local wheelY = g + r
	for _, wz in ipairs({ front + 3.4, back - 3.3 }) do
		for _, s in ipairs({ -1, 1 }) do
			local isFront = wz < 0
			local name = (isFront and "Front" or "Rear") .. (s < 0 and "Left" or "Right")
			local center = Vector3.new(s * (W / 2 - 0.3), wheelY, wz)
			local hub = part(car, { Name = name, Size = Vector3.new(0.4, 0.4, 0.4), CFrame = at(center.X, center.Y, center.Z), Transparency = 1 })
			local motor = Instance.new("Motor6D")
			motor.Name = "WheelMotor"
			motor.Part0 = chassis
			motor.Part1 = hub
			motor.C0 = CFrame.new(center)
			motor.Parent = hub
			local function onHub(pname, size, offset, color, extra)
				local p = part(car, {
					Name = pname,
					Size = size,
					CFrame = hub.CFrame * offset,
					Color = color,
					Shape = extra and extra.Shape,
					Material = extra and extra.Material,
				})
				weld(hub, p)
				return p
			end
			onHub("Tire", Vector3.new(1.2, r * 2, r * 2), CFrame.new(), Color3.fromRGB(22, 22, 24), { Shape = Enum.PartType.Cylinder })
			onHub("Rim", Vector3.new(1.25, r * 1.5, r * 1.5), CFrame.new(), Color3.fromRGB(30, 30, 32), { Shape = Enum.PartType.Cylinder })
			for k = 0, 9 do
				local a = k * math.pi / 5 + (k % 2) * 0.12 -- raios em pares
				onHub("Spoke", Vector3.new(1.3, r * 0.68, 0.14), CFrame.Angles(a, 0, 0) * CFrame.new(0, r * 0.36, 0), spec.RimColor, { Material = Enum.Material.Metal })
			end
			onHub("RimLip", Vector3.new(1.28, r * 0.42, r * 0.42), CFrame.new(), spec.RimColor, { Shape = Enum.PartType.Cylinder, Material = Enum.Material.Metal })
			-- pinça fica parada (presa no chassi, não gira)
			body("Caliper", Vector3.new(0.3, 0.7, 0.9), center.X - s * 0.3, center.Y + 0.4, center.Z + 0.45, spec.CaliperColor)
		end
	end
	finish(spec, cf, car, chassis)
	return car, driver, passenger
end

---------------------------------------------------------------------------
-- Ônibus de peças (Marco 9: Motorista de ônibus). spec.Shape = "Bus". Caixa comprida com
-- janelas grandes, porta da frente e do meio do lado direito, letreiro "UM TIJO" na frente,
-- bancos de verdade por dentro (o motorista na frente, à esquerda; os outros são "RearSeat",
-- onde jogadores e passageiros NPC sentam) e 4 rodas (atrás, pneu duplo).
---------------------------------------------------------------------------

local function buildBusFromParts(spec, cf)
	local car, chassis = newChassis(spec, cf)
	local L, W = spec.Length, spec.PartsWidth or spec.Width
	local r = spec.WheelRadius
	local g = -spec.Hover
	local function at(x, y, z)
		return cf * CFrame.new(x, y, z)
	end
	local function body(name, size, x, y, z, color, extra)
		extra = extra or {}
		local p = part(car, {
			ClassName = extra.ClassName,
			Name = name,
			Size = size,
			CFrame = at(x, y, z) * (extra.rot or CFrame.new()),
			Color = color,
			Material = extra.Material,
			Transparency = extra.Transparency,
			Reflectance = extra.Reflectance,
			Shape = extra.Shape,
		})
		weld(chassis, p)
		if color == spec.BodyColor then
			p:SetAttribute("Paint", true)
		end
		return p
	end
	local function text(p, face, value, color, bg)
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 30
		gui.LightInfluence = 0
		gui.Parent = p
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundColor3 = bg or Color3.new(0, 0, 0)
		label.BackgroundTransparency = bg and 0 or 1
		label.Font = Enum.Font.GothamBlack
		label.TextScaled = true
		label.TextColor3 = color
		label.Text = value
		label.Parent = gui
	end
	local BODY, STRIPE, GLASS = spec.BodyColor, spec.AccentColor, spec.GlassColor
	local DARK = Color3.fromRGB(28, 28, 32)
	local glass = { Material = Enum.Material.SmoothPlastic, Transparency = 0.45 }
	local neon = { Material = Enum.Material.Neon }
	local front, back = -L / 2, L / 2
	local floorY = g + 2.0 -- piso por dentro
	local beltY, topY, roofY = g + 4.6, g + 8.7, g + 10.6 -- base das janelas, topo das janelas, teto
	local frontAxle, rearAxle = front + 6.2, back - 8
	local frontDoor = { front + 0.8, front + 4.2 } -- porta da frente (lado direito), antes da roda
	local midDoor = { -0.5, 3.5 } -- porta do meio (lado direito)
	local side = W / 2 - 0.15

	-- piso, teto e ar-condicionado
	body("Piso", Vector3.new(W - 0.4, 0.4, L - 0.6), 0, floorY - 0.2, 0, Color3.fromRGB(70, 70, 76))
	body("Teto", Vector3.new(W, 0.5, L), 0, roofY + 0.25, 0, BODY)
	body("ArCondicionado", Vector3.new(W - 3, 0.9, 8), 0, roofY + 0.95, back - 7, Color3.fromRGB(225, 225, 228))
	body("TetoInterno", Vector3.new(W - 0.8, 0.1, L - 1.2), 0, roofY - 0.05, 0, Color3.fromRGB(235, 235, 230))

	-- laterais: saia com recorte das rodas, faixa verde, janelas com colunas, faixa de cima
	local function spans(list, a, b)
		-- trechos [a, b] sem os buracos da lista
		local out, z = {}, a
		table.sort(list, function(x, y)
			return x[1] < y[1]
		end)
		for _, h in ipairs(list) do
			if h[1] > z then
				table.insert(out, { z, math.min(h[1], b) })
			end
			z = math.max(z, h[2])
		end
		if z < b then
			table.insert(out, { z, b })
		end
		return out
	end
	local arches = { { frontAxle - r - 0.4, frontAxle + r + 0.4 }, { rearAxle - r - 0.4, rearAxle + r + 0.4 } }
	for _, sx in ipairs({ -1, 1 }) do
		local x = sx * side
		local holes = table.clone(arches)
		if sx > 0 then
			table.insert(holes, frontDoor)
			table.insert(holes, midDoor)
		end
		-- saia (do chão até a base das janelas), sem as rodas e as portas
		for _, sp in ipairs(spans(holes, front + 0.3, back - 0.3)) do
			local len = sp[2] - sp[1]
			body("Lateral", Vector3.new(0.3, beltY - (g + 1.2), len), x, (beltY + g + 1.2) / 2, (sp[1] + sp[2]) / 2, BODY)
			body("Faixa", Vector3.new(0.32, 0.9, len), x, g + 3.4, (sp[1] + sp[2]) / 2, STRIPE)
		end
		-- em cima das rodas (arco)
		for _, a in ipairs(arches) do
			body("Arco", Vector3.new(0.3, beltY - (g + r * 2 + 0.6), a[2] - a[1]), x, (beltY + g + r * 2 + 0.6) / 2, (a[1] + a[2]) / 2, BODY)
			-- caixa da roda por dentro (a roda é mais alta que o piso)
			local h = g + r * 2 + 0.4 - floorY
			body("CaixaRoda", Vector3.new(2.4, h, a[2] - a[1]), sx * (W / 2 - 1.25), floorY + h / 2, (a[1] + a[2]) / 2, DARK)
		end
		-- janelas (vidro corrido) e colunas
		local winFrom = front + 4.6
		local winHoles = sx > 0 and { midDoor } or {}
		for _, sp in ipairs(spans(winHoles, winFrom, back - 1)) do
			body("Janela", Vector3.new(0.2, topY - beltY, sp[2] - sp[1]), x, (beltY + topY) / 2, (sp[1] + sp[2]) / 2, GLASS, glass)
		end
		for z = winFrom, back - 1, 4.2 do
			body("Coluna", Vector3.new(0.34, topY - beltY, 0.35), x, (beltY + topY) / 2, z, DARK)
		end
		body("FaixaCima", Vector3.new(0.3, roofY - topY, L - 0.6), x, (topY + roofY) / 2, 0, BODY)
		if sx > 0 then
			-- portas: vidro escuro com faixa no meio
			for _, d in ipairs({ frontDoor, midDoor }) do
				body("Porta", Vector3.new(0.25, topY - (g + 1.4), d[2] - d[1] - 0.2), x, (topY + g + 1.4) / 2, (d[1] + d[2]) / 2, Color3.fromRGB(40, 50, 60), glass)
				body("PortaMeio", Vector3.new(0.3, topY - (g + 1.4), 0.15), x, (topY + g + 1.4) / 2, (d[1] + d[2]) / 2, DARK)
				body("Degrau", Vector3.new(1.2, 0.4, d[2] - d[1]), x - 0.6, g + 1.4, (d[1] + d[2]) / 2, Color3.fromRGB(60, 60, 64))
			end
		else
			-- lado do motorista: janela pequena na frente
			body("JanelaMotorista", Vector3.new(0.2, topY - beltY, 4), x, (beltY + topY) / 2, front + 2.4, GLASS, glass)
		end
		-- retrovisor
		body("Retrovisor", Vector3.new(0.3, 1.4, 0.7), sx * (W / 2 + 0.6), topY - 0.6, front + 0.4, DARK)
		body("RetrovisorBraco", Vector3.new(0.9, 0.15, 0.15), sx * (W / 2 + 0.2), topY + 0.1, front + 0.4, DARK)
	end
	-- lado direito da frente: coluna entre a porta e o para-brisa
	body("Lateral", Vector3.new(0.3, roofY - (g + 1.2), 0.5), side, (roofY + g + 1.2) / 2, front + 0.55, BODY)

	-- frente: para-brisa grande, letreiro, faróis e para-choque
	body("Frente", Vector3.new(W, beltY - 0.4 - (g + 1.2), 0.3), 0, (beltY - 0.4 + g + 1.2) / 2, front + 0.15, BODY)
	body("FaixaFrente", Vector3.new(W + 0.02, 0.9, 0.32), 0, g + 3.4, front + 0.15, STRIPE)
	body("ParaBrisa", Vector3.new(W - 0.5, topY - beltY + 0.9, 0.2), 0, (beltY - 0.4 + topY + 0.5) / 2, front + 0.2, GLASS, glass)
	local sign = body("Letreiro", Vector3.new(W - 1, 1.3, 0.3), 0, (topY + roofY) / 2 + 0.2, front + 0.12, Color3.fromRGB(15, 15, 18))
	text(sign, Enum.NormalId.Front, spec.SignText or "UM TIJO • CIRCULAR", Color3.fromRGB(255, 180, 30))
	body("ParaChoque", Vector3.new(W + 0.2, 0.9, 0.6), 0, g + 1.5, front + 0.1, DARK)
	for _, sx in ipairs({ -1, 1 }) do
		body("Farol", Vector3.new(1.4, 0.6, 0.2), sx * (W / 2 - 1.2), g + 2.6, front, Color3.fromRGB(255, 250, 230), neon)
		body("Pisca", Vector3.new(0.6, 0.6, 0.2), sx * (W / 2 - 2.4), g + 2.6, front, Color3.fromRGB(255, 160, 30), neon)
	end
	local logo = body("Logo", Vector3.new(3.2, 0.8, 0.1), 0, g + 4.0, front - 0.02, BODY)
	text(logo, Enum.NormalId.Front, "Um Tijo", STRIPE)

	-- traseira: painel, vidro, lanternas, para-choque, motor (grade)
	body("Traseira", Vector3.new(W, roofY - (g + 1.2), 0.3), 0, (roofY + g + 1.2) / 2, back - 0.15, BODY)
	body("FaixaTras", Vector3.new(W + 0.02, 0.9, 0.32), 0, g + 3.4, back - 0.15, STRIPE)
	body("VidroTras", Vector3.new(W - 2, 2.6, 0.2), 0, topY - 1.6, back - 0.3, GLASS, glass)
	body("GradeMotor", Vector3.new(W - 3, 1.4, 0.1), 0, g + 2.2, back + 0.02, DARK)
	body("ParaChoqueTras", Vector3.new(W + 0.2, 0.9, 0.6), 0, g + 1.5, back - 0.1, DARK)
	for _, sx in ipairs({ -1, 1 }) do
		body("Lanterna", Vector3.new(0.6, 2.2, 0.2), sx * (W / 2 - 0.6), g + 3.6, back, Color3.fromRGB(200, 25, 30), neon)
	end
	local num = body("Numero", Vector3.new(3, 1, 0.1), 0, roofY - 0.9, back + 0.01, Color3.fromRGB(15, 15, 18))
	text(num, Enum.NormalId.Back, "CIRCULAR", Color3.fromRGB(255, 180, 30))
	for _, sx in ipairs({ -1, 1 }) do
		local name = body("Nome", Vector3.new(0.1, 1.2, 8), sx * (side + 0.17), topY + 0.95, -2, BODY)
		text(name, sx > 0 and Enum.NormalId.Right or Enum.NormalId.Left, spec.SideText or "Um Tijo", STRIPE)
	end

	-- por dentro: painel, volante, catraca, divisória e barras amarelas
	body("Painel", Vector3.new(3.4, 1.2, 1.4), -(W / 2 - 2.2), floorY + 2.4, front + 1.2, DARK)
	body("Volante", Vector3.new(0.15, 1.6, 1.6), -(W / 2 - 2.2), floorY + 3.2, front + 2.1, Color3.fromRGB(20, 20, 22), {
		Shape = Enum.PartType.Cylinder,
		rot = CFrame.Angles(0, math.rad(90), 0) * CFrame.Angles(0, 0, math.rad(-40)),
	})
	body("Divisoria", Vector3.new(0.2, 2.6, 2.4), -(W / 2 - 3.9), floorY + 1.3, front + 4.4, DARK)
	body("Catraca", Vector3.new(1.0, 1.8, 0.8), 1.2, floorY + 0.9, front + 6.4, Color3.fromRGB(160, 160, 166), { Material = Enum.Material.Metal })
	local YELLOW = Color3.fromRGB(250, 200, 30)
	for z = front + 7, back - 3, 5 do
		for _, sx in ipairs({ -1, 1 }) do
			body("Barra", Vector3.new(0.2, roofY - floorY, 0.2), sx * 1.2, (roofY + floorY) / 2, z, YELLOW, { Material = Enum.Material.Metal })
		end
	end
	for _, sx in ipairs({ -1, 1 }) do
		body("BarraTeto", Vector3.new(0.15, 0.15, L - 6), sx * 1.2, roofY - 1.3, 2, YELLOW, { Material = Enum.Material.Metal })
	end

	-- bancos: motorista (VehicleSeat) e fileiras de 2 + 2
	local seatColor = spec.SeatColor or Color3.fromRGB(30, 80, 140)
	local cushionY = floorY + 1.3
	local driver = part(car, { ClassName = "VehicleSeat", Name = "DriverSeat", Size = Vector3.new(1.8, 0.4, 1.8), CFrame = at(-(W / 2 - 2.2), cushionY, front + 3.6), Color = DARK })
	driver.CanTouch = false
	driver.MaxSpeed = 0
	driver.Torque = 0
	driver.HeadsUpDisplay = false
	driver:SetAttribute("CarSeat", true)
	weld(chassis, driver)
	body("EncostoMotorista", Vector3.new(1.8, 2.4, 0.4), -(W / 2 - 2.2), cushionY + 1.3, front + 4.6, DARK)
	local passenger
	for _, z in ipairs({ front + 9.4, front + 12.2, front + 15, back - 13, back - 10.2, back - 7.4, back - 4.6, back - 1.8 }) do
		for _, x in ipairs({ -3.3, -1.5, 1.5, 3.3 }) do
			local nearDoor = x > 0 and z > midDoor[1] - 1.6 and z < midDoor[2] + 1.0
			local overArch = math.abs(x) > 2 and math.abs(z - rearAxle) < r + 1.4
			if not nearDoor and not overArch then
				local name = (not passenger and x > 0) and "PassengerSeat" or "RearSeat"
				local seat = part(car, { ClassName = "Seat", Name = name, Size = Vector3.new(1.6, 0.4, 1.6), CFrame = at(x, cushionY, z), Color = seatColor })
				weld(chassis, seat)
				if name == "PassengerSeat" then
					passenger = seat
				end
				body("Encosto", Vector3.new(1.6, 2.2, 0.35), x, cushionY + 1.2, z + 0.9, seatColor, { rot = CFrame.Angles(math.rad(-8), 0, 0) })
				body("PeBanco", Vector3.new(1.2, cushionY - floorY - 0.2, 0.4), x, (cushionY + floorY) / 2, z, DARK)
			end
		end
	end

	-- rodas: hub preso por Motor6D (o CarController gira); atrás, pneu duplo
	local wheelY = g + r
	for _, wz in ipairs({ frontAxle, rearAxle }) do
		for _, sx in ipairs({ -1, 1 }) do
			local isFront = wz < 0
			local name = (isFront and "Front" or "Rear") .. (sx < 0 and "Left" or "Right")
			local center = Vector3.new(sx * (W / 2 - (isFront and 0.9 or 1.15)), wheelY, wz)
			local hub = part(car, { Name = name, Size = Vector3.new(0.4, 0.4, 0.4), CFrame = at(center.X, center.Y, center.Z), Transparency = 1 })
			local motor = Instance.new("Motor6D")
			motor.Name = "WheelMotor"
			motor.Part0 = chassis
			motor.Part1 = hub
			motor.C0 = CFrame.new(center)
			motor.Parent = hub
			local tires = isFront and { 0 } or { -0.55, 0.55 }
			for _, off in ipairs(tires) do
				local t = part(car, { Name = "Tire", Size = Vector3.new(isFront and 1.2 or 1.0, r * 2, r * 2), CFrame = hub.CFrame * CFrame.new(off, 0, 0), Color = Color3.fromRGB(22, 22, 24), Shape = Enum.PartType.Cylinder })
				weld(hub, t)
			end
			local rim = part(car, { Name = "Rim", Size = Vector3.new(isFront and 1.3 or 2.2, r * 1.1, r * 1.1), CFrame = hub.CFrame, Color = spec.RimColor, Shape = Enum.PartType.Cylinder, Material = Enum.Material.Metal })
			weld(hub, rim)
			for k = 0, 4 do
				local bolt = part(car, { Name = "Bolt", Size = Vector3.new(isFront and 1.35 or 2.25, 0.2, 0.2), CFrame = hub.CFrame * CFrame.Angles(k * math.pi * 2 / 5, 0, 0) * CFrame.new(0, r * 0.3, 0), Color = Color3.fromRGB(80, 80, 86), Material = Enum.Material.Metal })
				weld(hub, bolt)
			end
		end
	end

	-- placas
	for sideName, pos in pairs(spec.Plates or {}) do
		local plate = part(car, { Name = "Placa" .. sideName, Size = Vector3.new(1.6, 0.52, 0.06), CFrame = cf * CFrame.new(pos.X, g + pos.Y, pos.Z), Color = Color3.fromRGB(245, 245, 245) })
		local gui = Instance.new("SurfaceGui")
		gui.Name = "PlacaGui"
		gui.Face = sideName == "Front" and Enum.NormalId.Front or Enum.NormalId.Back
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 120
		gui.Parent = plate
		local t = Instance.new("TextLabel")
		t.Name = "Texto"
		t.Size = UDim2.fromScale(1, 1)
		t.BackgroundTransparency = 1
		t.Font = Enum.Font.GothamBlack
		t.TextScaled = true
		t.TextColor3 = Color3.fromRGB(15, 15, 18)
		t.Text = ""
		t.Parent = gui
		weld(chassis, plate)
	end

	-- faróis acesos (luz para a frente)
	local att = Instance.new("Attachment")
	att.Name = "Farol1"
	att.Position = Vector3.new(0, g + 2.6, front - 0.3)
	att.Parent = chassis
	local spot = Instance.new("SpotLight")
	spot.Face = Enum.NormalId.Front
	spot.Angle = 70
	spot.Range = 40
	spot.Brightness = 3
	spot.Color = Color3.fromRGB(255, 246, 225)
	spot.Shadows = false
	spot.Parent = att

	car:SetAttribute("DoorSide", 1) -- portas do lado direito (BusService)
	finish(spec, cf, car, chassis)
	return car, driver, passenger
end

function finish(spec, cf, car, chassis)
	-- Física: velocidade e direção (o motorista controla; parado fica no lugar)
	local att = Instance.new("Attachment")
	att.Name = "DriveAttachment"
	att.Parent = chassis
	local lv = Instance.new("LinearVelocity")
	lv.Name = "Drive"
	lv.Attachment0 = att
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	lv.MaxForce = 1e6
	lv.VectorVelocity = Vector3.zero
	lv.Parent = chassis
	local ao = Instance.new("AlignOrientation")
	ao.Name = "Upright"
	ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
	ao.Attachment0 = att
	ao.MaxTorque = 1e6
	ao.Responsiveness = 30
	ao.RigidityEnabled = true -- Marco 6.4: firme, sem balançar nem ficar torto (Mengeot)
	ao.CFrame = cf.Rotation
	ao.Parent = chassis

	for _, p in ipairs(car:GetDescendants()) do
		if p:IsA("BasePart") then
			p.CollisionGroup = "Veiculos"
		end
	end
	car:SetAttribute("Spec", spec.Name)
end

---------------------------------------------------------------------------
-- Carro com modelo 3D (Marco 6.3)
-- O modelo fica em ServerStorage > CarModels (importado no Studio a partir dos .glb da pasta
-- "modelos"). Cada peça vem com nome "Papel_cor" (ex.: Paint_0d0d0f_3, Glass_000000_7,
-- WheelFrontLeft_Solid_202020_12) e uma pecinha "FrontMarker" no bico, que diz onde é a frente.
-- O modelo é girado, escalado para spec.Length e soldado no mesmo chassi invisível dos outros
-- carros: direção, drift e batidas continuam iguais.
---------------------------------------------------------------------------

local ServerStorage = game:GetService("ServerStorage")

-- Marco 7.1: motos têm só "Front" e "Rear" (os nomes de 4 rodas vêm antes: "WheelFrontLeft" não
-- pode ser lido como "WheelFront")
local WHEELS = { "FrontLeft", "FrontRight", "RearLeft", "RearRight", "Front", "Rear" }

-- Marco 9.8: acha o modelo mesmo com outro jeito de escrever o nome ("onibus_lxr", "Onibus LXR")
local function simpleName(name)
	return (name:lower():gsub("[^%w]", ""))
end

local warnedMissing = {}
local function templateFor(spec)
	if not spec.Model then
		return nil
	end
	local want = simpleName(spec.Model)
	local folder = ServerStorage:FindFirstChild("CarModels")
	local tpl = folder and folder:FindFirstChild(spec.Model)
	if not tpl then
		-- Marco 9.8: procura em qualquer pasta CarModels (pode ter duas) e dentro de grupos,
		-- com o nome escrito de outro jeito
		for _, d in ipairs(ServerStorage:GetDescendants()) do
			if (d:IsA("Model") or d:IsA("Folder")) and simpleName(d.Name) == want and d:FindFirstChildWhichIsA("BasePart", true) then
				tpl = d
				break
			end
		end
	end
	if not tpl and not warnedMissing[spec.Model] then
		warnedMissing[spec.Model] = true
		local names = {}
		for _, f in ipairs(ServerStorage:GetChildren()) do
			if f.Name == "CarModels" then
				for _, c in ipairs(f:GetChildren()) do
					table.insert(names, c.Name)
				end
			end
		end
		warn(("[CarBuilder] Modelo %s não está em ServerStorage > CarModels; %s vai ser de peças. CarModels tem: %s")
			:format(spec.Model, spec.Name, table.concat(names, ", ")))
	end
	return tpl
end

-- Caixa alinhada ao mundo que envolve as peças
local function bounds(parts)
	local mn = Vector3.new(math.huge, math.huge, math.huge)
	local mx = -mn
	for _, p in ipairs(parts) do
		local half = p.Size / 2
		for _, sx in ipairs({ -1, 1 }) do
			for _, sy in ipairs({ -1, 1 }) do
				for _, sz in ipairs({ -1, 1 }) do
					local c = p.CFrame * Vector3.new(half.X * sx, half.Y * sy, half.Z * sz)
					mn = Vector3.new(math.min(mn.X, c.X), math.min(mn.Y, c.Y), math.min(mn.Z, c.Z))
					mx = Vector3.new(math.max(mx.X, c.X), math.max(mx.Y, c.Y), math.max(mx.Z, c.Z))
				end
			end
		end
	end
	return mn, mx
end

local function hexColor(hex)
	local r, g, b = tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16)
	if r and g and b then
		return Color3.fromRGB(r, g, b)
	end
	return nil
end

-- Lê o nome da peça: roda (ou nil), papel e cor
local function parseName(name)
	local wheel
	for _, w in ipairs(WHEELS) do
		if name:sub(1, 5 + #w) == "Wheel" .. w then
			wheel = w
			name = name:sub(7 + #w)
			break
		end
	end
	local role, hex = name:match("^(%a+)_(%x%x%x%x%x%x)")
	return wheel, role, hex
end

-- O importador do Studio pode pôr a malha dentro de um grupo "Nome_Node": se o nome da peça não
-- tiver papel e cor, usa o nome do grupo de cima
local function partInfo(p)
	local wheel, role, hex = parseName(p.Name)
	if not role and p.Parent then
		wheel, role, hex = parseName(p.Parent.Name)
	end
	return wheel, role, hex
end

local function styleMeshPart(spec, p, role, hex)
	if spec.KeepTextures then
		-- Marco 9.7: modelo com textura própria (ônibus LXR): fica do jeito que veio.
		-- Marco 10.19: menos o vidro e o giroflex que vêm sem textura (ambulância): esses o nome pinta
		if role ~= "Glass" and role ~= "SirenRed" and role ~= "SirenBlue" then
			return
		end
	end
	for _, child in ipairs(p:GetChildren()) do
		if child:IsA("SurfaceAppearance") then
			child:Destroy() -- a cor vem do nome da peça (e do spec)
		end
	end
	local color = hex and hexColor(hex)
	p.Reflectance = 0
	p.Transparency = 0
	if role == "Paint" then
		p:SetAttribute("Paint", true)
		p.Color = spec.BodyColor
		p.Material = Enum.Material.SmoothPlastic
		p.Reflectance = spec.Reflectance or 0.08
	elseif role == "Glass" then
		p.Color = spec.GlassColor
		-- SmoothPlastic, não Glass: o material Glass esconde textos (SurfaceGui) atrás dele
		p.Material = Enum.Material.SmoothPlastic
		p.Reflectance = 0.15
		p.Transparency = math.clamp(spec.GlassTransparency or 0.15, 0, 0.6) -- baixo = fumê bem escuro
	elseif role == "Neon" then
		p.Color = color or Color3.new(1, 1, 1)
		p.Material = Enum.Material.Neon
	elseif role == "SirenRed" or role == "SirenBlue" then
		-- giroflex (Marco 7.1): o cliente faz piscar quem tem o atributo "Siren"
		p.Color = color or Color3.new(1, 0, 0)
		p.Material = Enum.Material.Neon
		p:SetAttribute("Siren", role == "SirenRed" and "Red" or "Blue")
	elseif role == "Headlight" then
		-- farol (Marco 7.5): lente acesa, branca quente (Marco 9.16: spec.HeadlightColor, ex.: xenon)
		p.Color = spec.HeadlightColor or Color3.fromRGB(255, 250, 230)
		p.Material = Enum.Material.Neon
		p:SetAttribute("Headlight", true)
	elseif role == "Metal" then
		p.Color = color or Color3.fromRGB(120, 120, 125)
		p.Material = Enum.Material.Metal
	elseif color then
		p.Color = color
		p.Material = Enum.Material.SmoothPlastic
	end
end

-- Banco de carro ou moto (Marco 7.5):
--   * quem senta não esbarra em nada (ZoneService "Passageiros"): antes as pernas raspavam no chão
--     e no meio-fio e os carros baixos travavam;
--   * boneco alto (cabelo grande, como o "bacon") com a cabeça saindo pelo teto: o encosto
--     inclina para trás, como num carro esportivo, só o necessário (até RECLINE_MAX). Inclinar
--     abaixa a cabeça e levanta os pés, então nada aparece embaixo do carro. Só se ainda faltar,
--     o banco desce um pouquinho (até SINK_MAX). Antes (Marco 7.4) ele afundava 1,6 e as pernas
--     apareciam embaixo do carro.
-- roofAbove = altura do teto por dentro acima do centro do banco (nil = moto, sem teto).
local RECLINE_MAX = math.rad(35)
local SINK_MAX = 0.35
local ZoneService -- carregado na primeira vez (evita ordem de require)

local function highestY(points, c0, c1inv)
	local top = -math.huge
	local m = c0 * c1inv
	for _, p in ipairs(points) do
		top = math.max(top, (m * p).Y)
	end
	return top
end

-- Marco 8.1: dentro do carro as mãos e antebraços ficam escondidos (em alguns carros
-- estreitos eles atravessavam a porta e apareciam do lado de fora). Na moto, não.
local ARM_PARTS = { "LeftHand", "RightHand", "LeftLowerArm", "RightLowerArm", "Left Arm", "Right Arm" }
-- Marco 9.3: no banco de trás (mais estreito) o braço inteiro fica escondido
local REAR_ARM_PARTS = { "LeftHand", "RightHand", "LeftLowerArm", "RightLowerArm", "LeftUpperArm", "RightUpperArm", "Left Arm", "Right Arm" }
local function hideArms(character, hide, wholeArm)
	for _, name in ipairs(wholeArm and REAR_ARM_PARTS or ARM_PARTS) do
		local p = character:FindFirstChild(name)
		if p and p:IsA("BasePart") then
			if hide then
				if p:GetAttribute("ArmAlpha") == nil then
					p:SetAttribute("ArmAlpha", p.Transparency)
				end
				p.Transparency = 1
			elseif p:GetAttribute("ArmAlpha") ~= nil then
				p.Transparency = p:GetAttribute("ArmAlpha")
				p:SetAttribute("ArmAlpha", nil)
			end
		end
	end
end

-- Marco 9.4: acessório (cabelo grande, chapéu) que ainda passa do teto depois de inclinar
-- fica invisível enquanto a pessoa está sentada; volta ao levantar.
local function setOverRoof(handle, hide)
	if hide then
		if handle:GetAttribute("RoofAlpha") == nil then
			handle:SetAttribute("RoofAlpha", handle.Transparency)
		end
		handle.Transparency = 1
	elseif handle:GetAttribute("RoofAlpha") ~= nil then
		handle.Transparency = handle:GetAttribute("RoofAlpha")
		handle:SetAttribute("RoofAlpha", nil)
	end
end

local function showAccessories(character)
	for _, d in ipairs(character:GetDescendants()) do
		if d:IsA("BasePart") and d:GetAttribute("RoofAlpha") ~= nil then
			setOverRoof(d, false)
		end
	end
end

local function setupSeat(seat, roofAbove, armsInside)
	local sitting
	seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		ZoneService = ZoneService or require(script.Parent:WaitForChild("ZoneService"))
		if sitting then
			ZoneService.setRiding(sitting, false)
			if armsInside then
				hideArms(sitting, false, true)
			end
			showAccessories(sitting)
			sitting = nil
		end
		local humanoid = seat.Occupant
		local character = humanoid and humanoid.Parent
		if not character then
			return
		end
		sitting = character
		ZoneService.setRiding(character, true)
		if armsInside then
			hideArms(character, true, seat.Name == "RearSeat")
		end
		if not roofAbove then
			return
		end
		local root = character:FindFirstChild("HumanoidRootPart")
		local seatWeld = seat:WaitForChild("SeatWeld", 2)
		if not root or not seatWeld or seatWeld.Part1 ~= root or seat.Occupant ~= humanoid then
			return
		end
		-- cantos de todas as peças do boneco (com acessórios), em relação ao HumanoidRootPart
		local points = {}
		for _, p in ipairs(character:GetDescendants()) do
			if p:IsA("BasePart") and p ~= root then
				local s = p.Size / 2
				for _, x in ipairs({ -s.X, s.X }) do
					for _, y in ipairs({ -s.Y, s.Y }) do
						for _, z in ipairs({ -s.Z, s.Z }) do
							table.insert(points, root.CFrame:PointToObjectSpace(p.CFrame:PointToWorldSpace(Vector3.new(x, y, z))))
						end
					end
				end
			end
		end
		local limit = roofAbove - 0.15
		local c0, c1inv = seatWeld.C0, seatWeld.C1:Inverse()
		if highestY(points, c0, c1inv) <= limit then
			return -- cabe sentado normal
		end
		-- inclina em volta do quadril (o ponto da solda, em cima do banco)
		local pivot = c0.Position
		local best
		-- banco de trás: inclina pouco (a cabeça ia para trás, onde o teto do sedã desce)
		local maxDeg = seat.Name == "RearSeat" and 13 or math.deg(RECLINE_MAX)
		for deg = 4, maxDeg, 3 do
			local tilt = CFrame.new(pivot) * CFrame.Angles(math.rad(deg), 0, 0) * CFrame.new(-pivot) * c0
			best = tilt
			if highestY(points, tilt, c1inv) <= limit then
				break
			end
		end
		local over = highestY(points, best, c1inv) - limit
		if over > 0 then
			best = CFrame.new(0, -math.min(over, SINK_MAX), 0) * best
		end
		seatWeld.C0 = best
		-- banco de trás: o que ainda passa do teto (cabelo grande) some enquanto está sentado
		-- (na frente o Luís achou bom como está)
		for _, acc in ipairs(seat.Name == "RearSeat" and character:GetChildren() or {}) do
			local handle = acc:IsA("Accessory") and acc:FindFirstChild("Handle")
			if handle and handle:IsA("BasePart") then
				local s = handle.Size / 2
				local corners = {}
				for _, x in ipairs({ -s.X, s.X }) do
					for _, y in ipairs({ -s.Y, s.Y }) do
						for _, z in ipairs({ -s.Z, s.Z }) do
							table.insert(corners, root.CFrame:PointToObjectSpace(handle.CFrame:PointToWorldSpace(Vector3.new(x, y, z))))
						end
					end
				end
				if highestY(corners, best, c1inv) > limit + 0.35 then
					setOverRoof(handle, true)
				end
			end
		end
	end)
end

local function buildFromMesh(spec, cf, tpl)
	local model = tpl:Clone()
	local parts, marker, hubMarks, lampMarks = {}, nil, {}, {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			local hubName = d.Name:match("^Hub(%a+)") or (d.Parent and d.Parent.Name:match("^Hub(%a+)"))
			local lampName = d.Name:match("^Lamp(%a+)") or (d.Parent and d.Parent.Name:match("^Lamp(%a+)"))
			if d.Name:find("FrontMarker") or (d.Parent and d.Parent.Name:find("FrontMarker")) then
				marker = d
			elseif lampName then
				table.insert(lampMarks, d) -- onde fica a luz de cada farol (Marco 7.5)
			elseif hubName then
				hubMarks[hubName] = d -- centro do eixo da roda (Marco 7.4): a roda gira em volta dele
			else
				table.insert(parts, d)
			end
		end
	end
	if #parts == 0 then
		return nil
	end
	-- 1. Onde é a frente (pela pecinha FrontMarker) e tamanho
	local mn, mx = bounds(parts)
	local center = (mn + mx) / 2
	local front = Vector3.new(0, 0, -1)
	if marker then
		local d = marker.Position - center
		if math.abs(d.X) > math.abs(d.Z) then
			front = Vector3.new(d.X > 0 and 1 or -1, 0, 0)
		else
			front = Vector3.new(0, 0, d.Z > 0 and 1 or -1)
		end
	end
	local length = front.X ~= 0 and (mx.X - mn.X) or (mx.Z - mn.Z)
	-- 2. Escala para o comprimento do spec
	local k = spec.Length / math.max(length, 0.01)
	if math.abs(k - 1) > 0.01 then
		model:ScaleTo(model:GetScale() * k)
		mn, mx = bounds(parts)
		center = (mn + mx) / 2
	end
	-- 3. Referência do carro: centro, no chão, com a frente em -Z
	local groundCenter = Vector3.new(center.X, mn.Y, center.Z)
	local base = CFrame.lookAt(groundCenter, groundCenter + front)

	local car, chassis = newChassis(spec, cf)
	local g = -spec.Hover
	local ground = cf * CFrame.new(0, g, 0)

	-- 4. Rodas: um eixo (hub) no centro de cada roda, girado pelo cliente
	local wheelParts = {}
	for _, p in ipairs(parts) do
		local wheel = partInfo(p)
		if wheel then
			wheelParts[wheel] = wheelParts[wheel] or {}
			table.insert(wheelParts[wheel], p)
		end
	end
	local hubs = {}
	local wheelSize = {} -- tamanho de cada roda no espaço do carro (X = largura do pneu, Y = diâmetro)
	for _, w in ipairs(WHEELS) do
		local list = wheelParts[w]
		if list then
			local a, b = bounds(list)
			local s = base:VectorToObjectSpace(b - a)
			wheelSize[w] = Vector3.new(math.abs(s.X), math.abs(s.Y), math.abs(s.Z))
			local axle = hubMarks[w] and hubMarks[w].Position or (a + b) / 2
			local localCenter = base:PointToObjectSpace(axle) + Vector3.new(0, g, 0)
			local hub = part(car, { Name = w, Size = Vector3.new(0.4, 0.4, 0.4), CFrame = cf * CFrame.new(localCenter), Transparency = 1 })
			local motor = Instance.new("Motor6D")
			motor.Name = "WheelMotor"
			motor.Part0 = chassis
			motor.Part1 = hub
			motor.C0 = CFrame.new(localCenter)
			motor.Parent = hub
			hubs[w] = hub
		end
	end

	-- 5. Peças: posição no carro, cor e solda
	for _, p in ipairs(parts) do
		local wheel, role, hex = partInfo(p)
		local rel = base:ToObjectSpace(p.CFrame)
		p.CFrame = ground * rel
		styleMeshPart(spec, p, role, hex)
		p.Anchored = false
		p.CanCollide = false
		p.CanTouch = false
		p.CanQuery = false
		p.Massless = true
		p.CastShadow = role ~= "Glass"
		p.Parent = car
		weld(wheel and hubs[wheel] or chassis, p)
	end
	-- Faróis (Marco 7.5): uma luz para a frente em cada farol (de dia quase não aparece; o que
	-- se vê é a lente acesa)
	for i, lamp in ipairs(lampMarks) do
		local a = Instance.new("Attachment")
		a.Name = "Farol" .. i
		a.Position = base:PointToObjectSpace(lamp.Position) + Vector3.new(0, g, -0.3)
		a.Parent = chassis
		local spot = Instance.new("SpotLight")
		spot.Face = Enum.NormalId.Front
		spot.Angle = 60
		spot.Range = 34
		spot.Brightness = spec.HeadlightColor and 4 or 3
		spot.Color = spec.HeadlightColor or Color3.fromRGB(255, 246, 225)
		spot.Shadows = false
		spot.Parent = a
	end
	-- Assoalho (Marco 7.6): alguns modelos vêm sem o fundo e, olhando por baixo, dava para ver o
	-- boneco sentado. Marco 8.1: a chapa ficava baixa e aparecia por baixo de alguns carros (Táxi).
	-- Agora ela fica alta, logo embaixo dos bancos e só entre os eixos (escondida pela lataria),
	-- e duas "paredes" escuras atrás do eixo de trás e na frente do eixo da frente fecham a vista
	-- de quem olha por baixo do para-choque.
	if not spec.Moto and not spec.NoFloor then
		local body = {}
		for _, p in ipairs(parts) do
			if not partInfo(p) then
				table.insert(body, p)
			end
		end
		local bmn = bounds(body)
		local bottom = bmn.Y - (cf.Position.Y + g) -- altura do ponto mais baixo da lataria
		local lowestSeat = math.huge
		local seatsSpec = spec.Seats or {}
		for _, pos in ipairs({ seatsSpec.Driver, seatsSpec.Passenger, unpack(seatsSpec.Rear or {}) }) do
			lowestSeat = math.min(lowestSeat, pos.Y)
		end
		local innerX = math.huge
		for _, hub in pairs(hubs) do
			innerX = math.min(innerX, math.abs(chassis.CFrame:PointToObjectSpace(hub.Position).X))
		end
		if innerX == math.huge then
			innerX = spec.Width / 2
		end
		local zFront, zRear = -spec.Length / 2 + 2, spec.Length / 2 - 2
		local hubZ = {}
		for _, hub in pairs(hubs) do
			table.insert(hubZ, chassis.CFrame:PointToObjectSpace(hub.Position).Z)
		end
		if #hubZ >= 2 then
			zFront, zRear = math.min(unpack(hubZ)), math.max(unpack(hubZ))
		end
		local width = math.max(innerX * 2 - 1.6, 2)
		local y = math.max(bottom + 0.3, lowestSeat - 0.55)
		local DARK = Color3.fromRGB(22, 22, 25)
		local floor = part(car, {
			Name = "Assoalho",
			Size = Vector3.new(width, 0.2, zRear - zFront),
			CFrame = cf * CFrame.new(0, g + y, (zFront + zRear) / 2),
			Color = DARK,
		})
		floor.CastShadow = false
		weld(chassis, floor)
		local wallH = y - (bottom + 0.25)
		if wallH > 0.3 then
			for _, z in ipairs({ zFront, zRear }) do
				local wall = part(car, {
					Name = "Assoalho",
					Size = Vector3.new(width, wallH, 0.2),
					CFrame = cf * CFrame.new(0, g + y - wallH / 2, z),
					Color = DARK,
				})
				wall.CastShadow = false
				weld(chassis, wall)
			end
		end
		-- Marco 8.1: parede escura logo atrás do último banco, do chão até a altura do encosto.
		-- Na M5 (L5) dava para ver o boneco sentado pelos buracos do para-choque de trás.
		local backZ = -math.huge
		for _, pos in ipairs({ seatsSpec.Driver, seatsSpec.Passenger, unpack(seatsSpec.Rear or {}) }) do
			backZ = math.max(backZ, pos.Z)
		end
		if backZ > -math.huge and lowestSeat < math.huge then
			local zBack = math.min(backZ + 1.3, zRear)
			local yLow, yHigh = g + bottom + 0.25, g + lowestSeat + 1.4
			local back = part(car, {
				Name = "Assoalho",
				Size = Vector3.new(width, yHigh - yLow, 0.2),
				CFrame = cf * CFrame.new(0, (yLow + yHigh) / 2, zBack),
				Color = DARK,
			})
			back.CastShadow = false
			weld(chassis, back)
		end
		-- Marco 8.1: caixa de roda escura (atrás de cada pneu e em cima dele). Sem ela, na
		-- camionete e na viatura (mais altas) dava para ver o vazio através do arco da roda.
		-- Só nos carros com spec.ArchLiner (folga em studs acima do pneu; o arco da lataria
		-- precisa ficar mais alto que isso, senão a chapa aparece por fora).
		for w, hub in pairs(spec.ArchLiner and hubs or {}) do
			local size = wheelSize[w]
			if size then
				local hp = chassis.CFrame:PointToObjectSpace(hub.Position)
				local r, tw = size.Y / 2, size.X
				local side = hp.X > 0 and 1 or -1
				local steer = w:find("Front") and r * 0.45 or 0 -- a roda da frente vira: mais folga
				local inner = math.abs(hp.X) - tw / 2 - 0.15 - steer
				local yLow, yTop = g + bottom + 0.2, hp.Y + r + spec.ArchLiner
				local len = 2 * r + 0.8
				if inner > 0.5 and yTop - yLow > 0.4 then
					local liner = part(car, {
						Name = "CaixaRoda",
						Size = Vector3.new(0.2, yTop - yLow, len),
						CFrame = cf * CFrame.new(side * inner, (yLow + yTop) / 2, hp.Z),
						Color = DARK,
					})
					liner.CastShadow = false
					weld(chassis, liner)
					local outer = math.abs(hp.X) + tw / 2 - 0.05
					local top = part(car, {
						Name = "CaixaRoda",
						Size = Vector3.new(outer - inner, 0.2, len),
						CFrame = cf * CFrame.new(side * (inner + outer) / 2, yTop, hp.Z),
						Color = DARK,
					})
					top.CastShadow = false
					weld(chassis, top)
				end
			end
		end
	end
	model:Destroy() -- sobra só a "casca" vazia e o FrontMarker

	-- 6. Peças extras do spec (ex.: fundo preto da entrada de ar do capô do L5, que no modelo
	--    original mostrava o motor). Posição em relação ao chão, no centro do carro; frente = -Z.
	for _, f in ipairs(spec.Fillers or {}) do
		local p = part(car, {
			Name = f.Name or "Filler",
			Size = f.Size,
			CFrame = cf * CFrame.new(f.Pos.X, g + f.Pos.Y, f.Pos.Z) * CFrame.Angles(math.rad(f.Pitch or 0), 0, 0),
			Color = f.Color or Color3.fromRGB(12, 12, 14),
			Material = f.Material,
			Reflectance = f.Reflectance,
			Transparency = f.Transparent and 1 or nil,
		})
		p.CastShadow = false
		if f.Siren then
			p:SetAttribute("Siren", f.Siren) -- Marco 9.11: giroflex feito de peça ("Red"/"Blue": piscam alternados)
		end
		if f.Text then
			-- letreiro (Marco 7.1): texto na face pedida, por exemplo SHERLEX na lateral da van
			local gui = Instance.new("SurfaceGui")
			gui.Face = Enum.NormalId[f.Face or "Right"]
			gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
			gui.PixelsPerStud = 40
			gui.LightInfluence = 1
			gui.Parent = p
			local label = Instance.new("TextLabel")
			label.Size = UDim2.fromScale(1, 1)
			label.BackgroundTransparency = 1
			label.Font = Enum.Font.GothamBlack
			label.TextScaled = true
			label.Text = f.Text
			label.TextColor3 = f.TextColor or Color3.new(1, 1, 1)
			label.Parent = gui
		end
		weld(chassis, p)
	end

	-- 7. Placas (Marco 7.5): frente e traseira, com o texto que o dono escolhe na loja de pintura
	for side, pos in pairs(spec.Plates or {}) do
		local moto = spec.Moto
		local plate = part(car, {
			Name = "Placa" .. side,
			Size = spec.PlateSize or (moto and Vector3.new(0.95, 0.62, 0.06) or Vector3.new(1.6, 0.52, 0.06)),
			CFrame = cf * CFrame.new(pos.X, g + pos.Y, pos.Z),
			Color = Color3.fromRGB(245, 245, 245),
		})
		plate.CastShadow = false
		local gui = Instance.new("SurfaceGui")
		gui.Name = "PlacaGui"
		gui.Face = side == "Front" and Enum.NormalId.Front or Enum.NormalId.Back
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 120
		gui.LightInfluence = 1
		gui.Parent = plate
		-- faixa azul de cima, como a placa do Mercosul
		local band = Instance.new("TextLabel")
		band.Name = "Faixa"
		band.Size = UDim2.fromScale(1, 0.26)
		band.BackgroundColor3 = Color3.fromRGB(20, 60, 160)
		band.BorderSizePixel = 0
		band.Font = Enum.Font.GothamBold
		band.TextScaled = true
		band.TextColor3 = Color3.new(1, 1, 1)
		band.Text = "BRASIL"
		band.Parent = gui
		local text = Instance.new("TextLabel")
		text.Name = "Texto"
		text.Size = UDim2.fromScale(0.94, 0.7)
		text.Position = UDim2.fromScale(0.03, 0.28)
		text.BackgroundTransparency = 1
		text.Font = Enum.Font.GothamBlack
		text.TextScaled = true
		text.TextColor3 = Color3.fromRGB(15, 15, 18)
		text.Text = ""
		text.Parent = gui
		weld(chassis, plate)
	end

	-- 8. Bancos (invisíveis, dentro da cabine)
	local seats = spec.Seats or {}
	local function seatAt(className, name, pos)
		local seat = part(car, { ClassName = className, Name = name, Size = Vector3.new(1.8, 0.4, 1.8), CFrame = cf * CFrame.new(pos.X, g + pos.Y, pos.Z), Transparency = 1 })
		weld(chassis, seat)
		-- Marco 9.8: ShowArms só no motorista; nos outros bancos os braços somem (no ônibus, quem
		-- senta na janela ficava com a mão para fora)
		-- Marco 9.10: no ônibus (ShowArms) ninguém inclina o encosto: nos bancos altos do fundo o
		-- passageiro deitava todo e as pernas saíam pela lateral
		local roofAbove = not spec.ShowArms and spec.Roof and spec.Roof - pos.Y or nil
		setupSeat(seat, roofAbove, not spec.Moto and not (spec.ShowArms and className == "VehicleSeat"))
		return seat
	end
	-- Moto: pontos onde vão as mãos e os pés do piloto (o BikeAnimator do cliente usa)
	for _, pair in ipairs({ { spec.Grips, "Grip" }, { spec.Pegs, "Peg" } }) do
		for side, pos in pairs(pair[1] or {}) do
			local a = Instance.new("Attachment")
			a.Name = pair[2] .. side
			a.Position = Vector3.new(pos.X, g + pos.Y, pos.Z)
			a.Parent = chassis
		end
	end
	local driver = seatAt("VehicleSeat", "DriverSeat", seats.Driver or Vector3.new(-1.4, 1.3, 0))
	driver.CanTouch = false -- só entra pela garagem ou pelo E (dono)
	driver.MaxSpeed = 0 -- o VehicleSeat só lê o controle; quem move o carro é o CarController
	driver.Torque = 0
	driver.HeadsUpDisplay = false
	driver:SetAttribute("CarSeat", true)
	local passenger = seatAt("Seat", "PassengerSeat", seats.Passenger or Vector3.new(1.4, 1.3, 0))
	for _, pos in ipairs(seats.Rear or {}) do
		seatAt("Seat", "RearSeat", pos)
	end
	if spec.DoorSide then
		car:SetAttribute("DoorSide", spec.DoorSide) -- Marco 9.7: lado das portas do ônibus (BusService)
	end

	finish(spec, cf, car, chassis)
	return car, driver, passenger
end

-- Pinta a carroceria (peças marcadas com o atributo "Paint") de outra cor (loja de pintura)
function CarBuilder.paint(car, color)
	for _, p in ipairs(car:GetDescendants()) do
		if p:IsA("BasePart") and p:GetAttribute("Paint") then
			p.Color = color
		end
	end
	car:SetAttribute("PaintColor", color)
end

-- Escreve o texto das placas do carro (Marco 7.5). O texto já vem conferido pelo VehicleService.
function CarBuilder.setPlate(car, text)
	for _, p in ipairs(car:GetChildren()) do
		local label = p.Name:sub(1, 5) == "Placa" and p:FindFirstChild("PlacaGui") and p.PlacaGui:FindFirstChild("Texto")
		if label then
			label.Text = text
		end
	end
	car:SetAttribute("Plate", text)
end

-- Marco 10.5: caçamba lotada de som (Saveira Quadrada). Caixas soldadas no chassi, sem peso e sem
-- colisão; o dono liga com E (luzes neon piscam e toca GameConfig.CarSound.MusicId, se tiver).
local SOUND_COLORS = { Color3.fromRGB(255, 60, 200), Color3.fromRGB(60, 200, 255), Color3.fromRGB(255, 220, 60), Color3.fromRGB(120, 255, 120) }
local function addSoundRig(spec, car)
	local rig = spec.SoundRig
	local chassis = car:FindFirstChild("Chassis")
	if not rig or not chassis then
		return
	end
	local CS = require(game:GetService("ReplicatedStorage").Shared.GameConfig).CarSound
	local base = chassis.CFrame * CFrame.new(0, -spec.Hover + rig.Y, 0)
	local folder = Instance.new("Model")
	folder.Name = "SomCacamba"
	folder.Parent = car
	local lights = {}
	local function box(name, size, x, y, z, color, material)
		local p = part(folder, { Name = name, Size = size, CFrame = base * CFrame.new(x, y + size.Y / 2, z), Color = color, Material = material })
		weld(chassis, p)
		return p
	end
	local depth = rig.Z1 - rig.Z0
	local w = rig.HalfX * 2 - 0.2
	-- paredão virado para trás: 2 colunas de caixas, 2 alto-falantes grandes em cada
	local back = rig.Z0 + 0.9
	local wall = box("Paredao", Vector3.new(w, 2.6, 1.6), 0, 0, back, Color3.fromRGB(22, 22, 26))
	for _, x in ipairs({ -w / 4, w / 4 }) do
		for _, y in ipairs({ 0.65, 1.95 }) do
			local cone = box("AltoFalante", Vector3.new(0.2, 1.05, 1.05), x, y - 0.52, back + 0.82, Color3.fromRGB(45, 45, 50), Enum.Material.Metal)
			cone.Shape = Enum.PartType.Cylinder
			cone.CFrame = base * CFrame.new(x, y, back + 0.82) * CFrame.Angles(0, math.rad(90), 0)
			local ring = box("Luz", Vector3.new(0.12, 1.25, 1.25), x, y - 0.62, back + 0.8, SOUND_COLORS[#lights % #SOUND_COLORS + 1], Enum.Material.Neon)
			ring.Shape = Enum.PartType.Cylinder
			ring.CFrame = base * CFrame.new(x, y, back + 0.8) * CFrame.Angles(0, math.rad(90), 0)
			ring.Transparency = 0.6
			table.insert(lights, ring)
		end
	end
	-- caixas de grave deitadas no meio da caçamba e cornetas em cima
	local subZ = rig.Z0 + 1.7 + depth * 0.3
	for _, x in ipairs({ -w / 4, w / 4 }) do
		box("CaixaGrave", Vector3.new(w / 2 - 0.15, 1.1, 1.8), x, 0, subZ, Color3.fromRGB(28, 28, 32))
		local l = box("Luz", Vector3.new(w / 2 - 0.3, 0.12, 0.12), x, 1.1, subZ + 0.92, Color3.fromRGB(60, 200, 255), Enum.Material.Neon)
		l.Transparency = 0.6
		table.insert(lights, l)
	end
	for _, x in ipairs({ -w / 3, 0, w / 3 }) do
		box("Corneta", Vector3.new(0.6, 0.6, 0.9), x, 2.6, back + 0.2, Color3.fromRGB(200, 200, 205), Enum.Material.Metal)
	end
	local sound
	if (CS.MusicId or 0) > 0 then
		sound = Instance.new("Sound")
		sound.Name = "Musica"
		sound.SoundId = "rbxassetid://" .. CS.MusicId
		sound.Looped = true
		sound.Volume = CS.Volume
		sound.RollOffMaxDistance = CS.MaxDistance
		sound.Parent = wall
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "SomPrompt"
	prompt.ActionText = "Ligar o som"
	prompt.ObjectText = spec.Name
	prompt.KeyboardKeyCode = Enum.KeyCode.F
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = wall
	local on, last = false, 0
	prompt.Triggered:Connect(function(player)
		if os.clock() - last < 1 or car:GetAttribute("Owner") ~= player.UserId then
			return
		end
		last = os.clock()
		on = not on
		prompt.ActionText = on and "Desligar o som" or "Ligar o som"
		car:SetAttribute("SomLigado", on or nil)
		if sound then
			if on then
				sound:Play()
			else
				sound:Stop()
			end
		end
		if on then
			task.spawn(function()
				local i = 0
				while on and car.Parent do
					i += 1
					for k, light in ipairs(lights) do
						light.Transparency = 0
						light.Color = SOUND_COLORS[((i + k) % #SOUND_COLORS) + 1]
					end
					task.wait(0.35)
				end
				for _, light in ipairs(lights) do
					light.Transparency = 0.6
				end
			end)
		end
	end)
end

-- cf = posição e direção do centro do chassi no mundo; color = cor da pintura (nil = a de fábrica)
function CarBuilder.build(spec, cf, color)
	local tpl = templateFor(spec)
	local car, driver, passenger
	if tpl then
		local ok
		ok, car, driver, passenger = pcall(buildFromMesh, spec, cf, tpl)
		if not ok or not car then
			warn(("[CarBuilder] Modelo 3D de %s com problema (%s); usando o carro de peças."):format(spec.Name, tostring(car)))
			car = nil
		end
	end
	if not car then
		if spec.Shape == "Bus" then
			car, driver, passenger = buildBusFromParts(spec, cf)
		else
			car, driver, passenger = buildFromParts(spec, cf)
		end
		for _, seat in ipairs(car:GetChildren()) do
			if seat:IsA("Seat") or seat:IsA("VehicleSeat") then
				setupSeat(seat, nil)
			end
		end
	end
	if spec.SoundRig then
		local ok, err = pcall(addSoundRig, spec, car)
		if not ok then
			warn("[CarBuilder] Som da caçamba: " .. tostring(err))
		end
	end
	if color then
		CarBuilder.paint(car, color)
	end
	return car, driver, passenger
end

return CarBuilder
