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
-- Frente do carro = -Z. Há sedãs de serviço e o esportivo pessoal, com portas que
-- abrem para cima, teto preto "flutuante", detalhes azuis e rodas vermelhas.

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

local function surfaceText(target, value, face, color, size)
	local gui = Instance.new("SurfaceGui")
	gui.Name, gui.Face, gui.LightInfluence = "Identificação", face or Enum.NormalId.Front, 0
	gui.SizingMode, gui.PixelsPerStud = Enum.SurfaceGuiSizingMode.PixelsPerStud, 40
	gui.Parent = target
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency, label.Size = 1, UDim2.fromScale(1, 1)
	label.Text, label.TextScaled, label.TextWrapped = value, true, true
	label.Font, label.TextColor3 = Enum.Font.GothamBold, color or Color3.new(1, 1, 1)
	label.Parent = gui
end

-- Sedã original de quatro portas: cabine alta e vazia, duas vagas utilizáveis,
-- banco traseiro visual e identificação própria da empresa/serviço.
local function buildSedan(spec, cf)
	local car = Instance.new("Model"); car.Name = spec.Name
	local V = Vector3.new
	local L, W, r, g = spec.Length, spec.Width, spec.WheelRadius, -spec.Hover
	local front, back = -L / 2, L / 2
	local dark, metal = spec.TrimColor, spec.RimColor
	local chassis = part(car, { Name = "Chassis", Size = V(W - 0.4, 2.4, L - 0.6), CFrame = cf, Transparency = 1 })
	chassis.CanCollide, chassis.CanQuery, chassis.Massless = true, true, false
	chassis.CustomPhysicalProperties = PhysicalProperties.new(0.7, 0, 0, 100, 1)
	car.PrimaryPart = chassis
	local function at(x, y, z) return cf * CFrame.new(x, y, z) end
	local function body(name, size, x, y, z, color, extra, parent, base)
		extra = extra or {}
		local p = part(parent or car, { Name = name, Size = size, CFrame = at(x, y, z) * (extra.rot or CFrame.new()),
			Color = color, Material = extra.Material, Transparency = extra.Transparency, Shape = extra.Shape,
			ClassName = extra.ClassName, Reflectance = extra.Reflectance })
		weld(base or chassis, p); return p
	end
	local paint = { Reflectance = spec.Reflectance }
	body("Soleira", V(W - 0.6, 0.7, L - 1), 0, g + 1.35, 0, dark)
	body("Carroceria", V(W - 0.7, 1.8, L - 1), 0, g + 2.6, 0, spec.BodyColor, paint)
	body("Capô", V(W - 0.8, 0.55, 4.3), 0, g + 3.65, front + 2.7, spec.BodyColor, paint)
	body("PortaMalas", V(W - 0.8, 0.55, 3.1), 0, g + 3.7, back - 2, spec.BodyColor, paint)
	body("Teto", V(W - 1.1, 0.35, 8.6), 0, g + 7.1, 0.55, spec.BodyColor, paint)
	body("ParaBrisa", V(W - 1.3, 2.7, 0.16), 0, g + 5.5, -3.9, spec.GlassColor,
		{ Material = Enum.Material.Glass, Transparency = 0.42, rot = CFrame.Angles(math.rad(-17), 0, 0) })
	body("VidroTraseiro", V(W - 1.3, 2.5, 0.16), 0, g + 5.4, 4.85, spec.GlassColor,
		{ Material = Enum.Material.Glass, Transparency = 0.42, rot = CFrame.Angles(math.rad(18), 0, 0) })
	for _, side in ipairs({ -1, 1 }) do
		for _, z in ipairs({ -3.9, 0.55, 4.85 }) do
			body("Coluna", V(0.35, 3.15, 0.35), side * (W / 2 - 0.6), g + 5.4, z, dark)
		end
		body("Retrovisor", V(0.8, 0.5, 0.8), side * (W / 2 + 0.05), g + 4.7, -3.2, dark)
		for index, z in ipairs({ -1.7, 2.6 }) do
			local isFront = index == 1
			local name = (isFront and "Door" or "RearDoor") .. (side < 0 and "Left" or "Right")
			local color = spec.Role == "Policial" and Color3.fromRGB(238, 240, 243) or spec.BodyColor
			local leaf = part(car, { Name = name, Size = V(0.2, 2.0, 3.85), CFrame = at(side * (W / 2 - 0.2), g + 3.2, z), Color = color })
			body("VidroPorta", V(0.12, 2.0, 3.55), side * (W / 2 - 0.55), g + 5.3, z, spec.GlassColor,
				{ Material = Enum.Material.Glass, Transparency = 0.42 }, leaf, leaf)
			body("Maçaneta", V(0.1, 0.15, 0.8), side * (W / 2 - 0.05), g + 3.9, z + 1.1, metal, nil, leaf, leaf)
			local hinge = hinged(chassis, leaf, V(side * (W / 2 - 0.25), g + 3.2, z - 1.8), "DoorMotor")
			hinge:SetAttribute("Side", side)
			if isFront then
				surfaceText(leaf, spec.Role == "Taxista" and "LXR TÁXIS" or "POLÍCIA", side < 0 and Enum.NormalId.Left or Enum.NormalId.Right,
					spec.Role == "Taxista" and Color3.fromRGB(26, 70, 139) or Color3.fromRGB(24, 66, 115))
			end
		end
		if spec.Role == "Taxista" then
			for i = 1, 16 do
				for row = 0, 1 do
					if (i + row) % 2 == 0 then body("XadrezLXR", V(0.08, 0.35, 0.65), side * (W / 2 - 0.04), g + 2.5 + row * 0.35, -5.5 + i * 0.65, dark) end
				end
			end
		else
			body("FaixaPolicial", V(0.1, 0.4, L - 3), side * (W / 2 - 0.05), g + 2.5, 0.4, Color3.fromRGB(37, 105, 175))
		end
		body("Farol", V(2.1, 0.8, 0.25), side * 2.1, g + 3.1, front + 0.4, Color3.fromRGB(235, 247, 255), { Material = Enum.Material.Neon })
		body("Lanterna", V(2.1, 0.7, 0.2), side * 2.1, g + 3.2, back - 0.4, Color3.fromRGB(211, 40, 44), { Material = Enum.Material.Neon })
	end
	body("Grade", V(2.7, 0.9, 0.25), 0, g + 2.9, front + 0.25, dark)
	for _, z in ipairs({ front + 0.2, back - 0.2 }) do body("ParaChoque", V(W - 0.3, 0.55, 0.5), 0, g + 1.9, z, dark) end
	local plate = body("Placa", V(2, 0.6, 0.1), 0, g + 2.5, back - 0.08, Color3.fromRGB(240, 241, 234))
	surfaceText(plate, spec.Role == "Taxista" and "LXR • CIDADE" or "KINDER • 01", Enum.NormalId.Back, Color3.fromRGB(32, 42, 52))
	body("Painel", V(W - 1.6, 0.65, 1), 0, g + 3.3, -3.1, dark)
	body("Volante", V(0.2, 1.0, 1.0), -1.6, g + 3.3, -2.55, dark, { Shape = Enum.PartType.Cylinder, rot = CFrame.Angles(0, math.pi / 2, 0) })
	local seatY = g + 1.2
	local driver = part(car, { ClassName = "VehicleSeat", Name = "DriverSeat", Size = V(1.9, 0.4, 1.8), CFrame = at(-1.65, seatY, -0.9), Color = spec.SeatColor })
	driver.CanTouch, driver.MaxSpeed, driver.Torque, driver.HeadsUpDisplay = false, 0, 0, false
	driver:SetAttribute("CarSeat", true); weld(chassis, driver)
	local passenger = part(car, { ClassName = "Seat", Name = "PassengerSeat", Size = V(1.9, 0.4, 1.8), CFrame = at(1.65, seatY, -0.9), Color = spec.SeatColor })
	weld(chassis, passenger)
	for _, x in ipairs({ -1.65, 1.65 }) do body("Encosto", V(1.9, 2.4, 0.45), x, seatY + 1.3, 0.15, spec.SeatColor) end
	body("BancoTraseiro", V(W - 2, 0.55, 2.1), 0, seatY + 0.05, 2.55, spec.SeatColor)
	body("EncostoTraseiro", V(W - 2, 2.5, 0.5), 0, seatY + 1.25, 3.65, spec.SeatColor)
	if spec.Role == "Taxista" then
		local sign = body("LetreiroTaxi", V(3.3, 0.9, 1.4), 0, g + 7.8, 0.2, Color3.fromRGB(255, 221, 88))
		surfaceText(sign, "TÁXI", Enum.NormalId.Front, Color3.fromRGB(25, 62, 104))
		surfaceText(sign, "TÁXI", Enum.NormalId.Back, Color3.fromRGB(25, 62, 104))
	else
		body("BaseGiroflex", V(4.8, 0.25, 1.3), 0, g + 7.5, 0.2, dark)
		for _, side in ipairs({ -1, 1 }) do
			local light = body(side < 0 and "PoliceRed" or "PoliceBlue", V(2.1, 0.65, 1.1), side * 1.15, g + 7.9, 0.2,
				side < 0 and Color3.fromRGB(224, 42, 54) or Color3.fromRGB(43, 123, 246), { Material = Enum.Material.Neon })
			local glow = Instance.new("PointLight"); glow.Name, glow.Range, glow.Brightness, glow.Shadows = "Flasher", 14, 0.6, false
			glow.Color, glow.Parent = light.Color, light
		end
		local badge = body("EmblemaPolicial", V(1.2, 0.1, 1.3), 0, g + 3.98, front + 2.8, Color3.fromRGB(235, 190, 68))
		surfaceText(badge, "★", Enum.NormalId.Top, Color3.fromRGB(32, 70, 120))
	end
	for _, wz in ipairs({ front + 3.3, back - 3.3 }) do
		for _, side in ipairs({ -1, 1 }) do
			local name = (wz < 0 and "Front" or "Rear") .. (side < 0 and "Left" or "Right")
			local center = V(side * (W / 2 - 0.3), g + r, wz)
			local hub = part(car, { Name = name, Size = V(0.4, 0.4, 0.4), CFrame = at(center.X, center.Y, center.Z), Transparency = 1 })
			local motor = Instance.new("Motor6D"); motor.Name, motor.Part0, motor.Part1, motor.C0, motor.Parent = "WheelMotor", chassis, hub, CFrame.new(center), hub
			local function rim(name2, size, offset, color)
				local p = part(car, { Name = name2, Size = size, CFrame = hub.CFrame * offset, Color = color, Shape = Enum.PartType.Cylinder })
				weld(hub, p); return p
			end
			rim("Pneu", V(1.1, r * 2, r * 2), CFrame.new(), Color3.fromRGB(21, 23, 27))
			rim("Roda", V(1.15, r * 1.5, r * 1.5), CFrame.new(), metal)
			rim("CentroRoda", V(1.22, r * 0.6, r * 0.6), CFrame.new(), dark)
			for k = 0, 5 do
				local spoke = part(car, { Name = "Raio", Size = V(1.21, r * 0.75, 0.18), CFrame = hub.CFrame * CFrame.Angles(k * math.pi / 3, 0, 0) * CFrame.new(0, r * 0.3, 0), Color = dark })
				weld(hub, spoke)
			end
		end
	end
	local attachment = Instance.new("Attachment"); attachment.Name, attachment.Parent = "DriveAttachment", chassis
	local lv = Instance.new("LinearVelocity"); lv.Name, lv.Attachment0, lv.RelativeTo = "Drive", attachment, Enum.ActuatorRelativeTo.World
	lv.VelocityConstraintMode, lv.MaxForce, lv.VectorVelocity, lv.Parent = Enum.VelocityConstraintMode.Vector, 1e6, V(0, 0, 0), chassis
	local ao = Instance.new("AlignOrientation"); ao.Name, ao.Mode, ao.Attachment0 = "Upright", Enum.OrientationAlignmentMode.OneAttachment, attachment
	ao.MaxTorque, ao.Responsiveness, ao.CFrame, ao.Parent = 1e6, 30, cf.Rotation, chassis
	for _, p in ipairs(car:GetDescendants()) do if p:IsA("BasePart") then p.CollisionGroup = "Veiculos" end end
	car:SetAttribute("Spec", spec.Name); car:SetAttribute("DoorStyle", "Sedan")
	return car, driver, passenger
end

-- cf = posição e direção do centro do chassi no mundo
function CarBuilder.build(spec, cf)
	if spec.Style == "Sedan" then return buildSedan(spec, cf) end
	local car = Instance.new("Model")
	car.Name = spec.Name
	local L, W = spec.Length, spec.Width
	local r = spec.WheelRadius
	local g = -spec.Hover -- altura do chão, em coordenadas do chassi

	local chassis = part(car, { Name = "Chassis", Size = Vector3.new(W - 0.4, 2.4, L - 0.6), CFrame = cf, Transparency = 1 })
	chassis.CanCollide = true
	chassis.CanQuery = true
	chassis.Massless = false
	chassis.CustomPhysicalProperties = PhysicalProperties.new(0.7, 0, 0, 100, 1) -- sem atrito: desliza sobre a calçada
	car.PrimaryPart = chassis

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
		return p
	end
	local paint = { Reflectance = spec.Reflectance or 0.08 }
	local neon = { Material = Enum.Material.Neon }
	local BODY, TRIM, ACCENT, GLASS = spec.BodyColor, spec.TrimColor, spec.AccentColor, spec.GlassColor
	local front, back = -L / 2, L / 2
	local cabinZ = 0.6

	-- Base e laterais (bem baixas)
	body("Sill", Vector3.new(W - 0.5, 0.7, L - 1.2), 0, g + 1.25, 0, TRIM)
	body("Body", Vector3.new(W - 0.6, 1.4, L - 0.8), 0, g + 2.3, 0, BODY, paint)
	-- Capô em cunha: alto perto do para-brisa, fino no bico
	body("Nose", Vector3.new(W - 0.8, 1.0, 5.4), 0, g + 3.5, front + 3.1, BODY, { ClassName = "WedgePart", Reflectance = paint.Reflectance })
	body("NoseTip", Vector3.new(W - 1.0, 0.5, 1.2), 0, g + 2.85, front + 0.55, BODY, paint)
	body("HoodStripe", Vector3.new(1.2, 0.08, 4.4), 0, g + 3.55, front + 3.3, TRIM, { rot = CFrame.Angles(math.rad(-10.5), 0, 0) })
	-- Traseira: tampa curta e aerofólio fino
	body("RearDeck", Vector3.new(W - 0.8, 0.5, 2.4), 0, g + 3.25, back - 1.4, BODY, paint)
	body("Spoiler", Vector3.new(W - 1.2, 0.12, 0.8), 0, g + 3.62, back - 0.55, TRIM)

	-- Cabine baixa: vidros escuros, teto preto "flutuante" e colunas pretas que descem até a traseira
	body("Cabin", Vector3.new(W - 2.0, 1.4, 3.6), 0, g + 3.9, cabinZ, GLASS, { Material = Enum.Material.Glass, Transparency = 0.3 })
	body("Roof", Vector3.new(W - 1.9, 0.25, 4.0), 0, g + 4.72, cabinZ, TRIM, { Reflectance = 0.15 })
	body("Windshield", Vector3.new(W - 2.0, 1.4, 3.6), 0, g + 3.9, cabinZ - 1.8 - 1.8, GLASS, { ClassName = "WedgePart", Material = Enum.Material.Glass, Transparency = 0.3 })
	body("RearGlass", Vector3.new(W - 2.0, 1.4, 4.2), 0, g + 3.9, cabinZ + 1.8 + 2.1, GLASS, {
		ClassName = "WedgePart",
		Material = Enum.Material.Glass,
		Transparency = 0.3,
		rot = CFrame.Angles(0, math.pi, 0),
	})
	for _, s in ipairs({ -1, 1 }) do
		-- "asa" preta que sai do teto e desce até a traseira
		body("Buttress", Vector3.new(0.4, 0.35, 5.2), s * (W / 2 - 1.05), g + 4.1, cabinZ + 4.1, TRIM, { rot = CFrame.Angles(math.rad(14), 0, 0) })
		-- faixa azul na lateral e entrada de ar atrás da porta
		body("SideAccent", Vector3.new(0.08, 0.22, L - 4.5), s * (W / 2 - 0.27), g + 1.85, 0.4, ACCENT, neon)
		body("SideIntake", Vector3.new(0.1, 0.9, 2.2), s * (W / 2 - 0.28), g + 2.45, cabinZ + 3.6, Color3.fromRGB(12, 12, 14))
		body("IntakeTrim", Vector3.new(0.11, 0.12, 2.2), s * (W / 2 - 0.27), g + 2.95, cabinZ + 3.6, ACCENT)
		body("Mirror", Vector3.new(0.7, 0.35, 0.55), s * (W / 2 - 0.05), g + 3.7, cabinZ - 2.2, TRIM)
	end

	-- Portas que abrem para cima (presas na dobradiça da frente, em cima)
	for _, s in ipairs({ -1, 1 }) do
		local door = part(car, { Name = s < 0 and "DoorLeft" or "DoorRight", Size = Vector3.new(0.18, 1.3, 3.6), CFrame = at(s * (W / 2 - 0.22), g + 2.4, cabinZ - 0.3), Color = BODY, Reflectance = paint.Reflectance })
		local doorGlass = part(car, { Name = "DoorGlass", Size = Vector3.new(0.12, 1.2, 3.2), CFrame = at(s * (W / 2 - 0.95), g + 3.75, cabinZ - 0.2), Color = GLASS, Material = Enum.Material.Glass, Transparency = 0.3 })
		local handle = part(car, { Name = "Handle", Size = Vector3.new(0.06, 0.12, 0.6), CFrame = at(s * (W / 2 - 0.12), g + 2.75, cabinZ + 0.9), Color = Color3.fromRGB(190, 190, 195) })
		weld(door, doorGlass)
		weld(door, handle)
		local motor = hinged(chassis, door, Vector3.new(s * (W / 2 - 0.5), g + 4.4, cabinZ - 2.1), "DoorMotor")
		motor:SetAttribute("Side", s)
	end

	-- Frente: faróis finos e angulados, entradas de ar com moldura azul, grade fina no centro
	for _, s in ipairs({ -1, 1 }) do
		body("Headlight", Vector3.new(1.9, 0.22, 0.25), s * 2.3, g + 3.0, front + 0.75, Color3.fromRGB(230, 245, 255), {
			Material = Enum.Material.Neon,
			rot = CFrame.Angles(0, s * math.rad(-14), s * math.rad(6)),
		})
		body("HeadlightAccent", Vector3.new(1.6, 0.1, 0.25), s * 2.3, g + 2.8, front + 0.7, ACCENT, {
			Material = Enum.Material.Neon,
			rot = CFrame.Angles(0, s * math.rad(-14), 0),
		})
		body("Intake", Vector3.new(1.8, 0.75, 0.2), s * 2.4, g + 1.95, front + 0.42, Color3.fromRGB(12, 12, 14))
		body("IntakeFrame", Vector3.new(1.9, 0.12, 0.22), s * 2.4, g + 2.38, front + 0.42, ACCENT)
	end
	body("Grille", Vector3.new(2.4, 0.3, 0.2), 0, g + 2.6, front + 0.15, Color3.fromRGB(12, 12, 14))
	body("GrilleLine", Vector3.new(2.4, 0.06, 0.22), 0, g + 2.6, front + 0.14, Color3.fromRGB(170, 175, 185))
	body("Splitter", Vector3.new(W - 0.6, 0.15, 0.9), 0, g + 1.0, front + 0.6, TRIM)

	-- Traseira: lanternas em "U", difusor e 2 escapamentos
	for _, s in ipairs({ -1, 1 }) do
		body("Taillight", Vector3.new(2.1, 0.2, 0.15), s * 2.3, g + 3.05, back - 0.32, Color3.fromRGB(230, 30, 30), neon)
		body("TaillightSide", Vector3.new(0.2, 0.7, 0.15), s * 3.25, g + 2.8, back - 0.32, Color3.fromRGB(230, 30, 30), neon)
		body("Exhaust", Vector3.new(0.4, 0.5, 0.5), s * 1.2, g + 1.3, back - 0.15, Color3.fromRGB(150, 150, 155), {
			Shape = Enum.PartType.Cylinder,
			Material = Enum.Material.Metal,
			rot = CFrame.Angles(0, math.rad(90), 0),
		})
	end
	body("Diffuser", Vector3.new(W - 1, 0.6, 0.4), 0, g + 1.35, back - 0.3, TRIM)
	body("DiffuserAccent", Vector3.new(W - 1.2, 0.1, 0.42), 0, g + 1.7, back - 0.3, ACCENT)
	body("Plate", Vector3.new(1.9, 0.55, 0.1), 0, g + 2.3, back - 0.35, Color3.new(1, 1, 1))

	-- Interior: painel, volante, bancos
	body("Dashboard", Vector3.new(W - 2.0, 0.6, 1), 0, g + 3.15, cabinZ - 1.9, Color3.fromRGB(30, 30, 34))
	body("SteeringWheel", Vector3.new(0.12, 1.1, 1.1), -1.4, g + 3.0, cabinZ - 1.3, Color3.fromRGB(20, 20, 22), {
		Shape = Enum.PartType.Cylinder,
		rot = CFrame.Angles(0, math.rad(90), 0) * CFrame.Angles(0, 0, math.rad(25)),
	})
	local seatY = g + 0.95 -- baixo, para a cabeça não passar do teto
	local seatColor = spec.SeatColor or Color3.fromRGB(40, 40, 44)
	local driver = part(car, { ClassName = "VehicleSeat", Name = "DriverSeat", Size = Vector3.new(1.8, 0.4, 1.8), CFrame = at(-1.4, seatY, cabinZ + 0.3), Color = seatColor })
	driver.CanTouch = false -- só entra pelo botão "Carro" ou pelo E (dono)
	driver.MaxSpeed = 0 -- o VehicleSeat só lê o controle; quem move o carro é o CarController
	driver.Torque = 0
	driver.HeadsUpDisplay = false
	driver:SetAttribute("CarSeat", true)
	weld(chassis, driver)
	local passenger = part(car, { ClassName = "Seat", Name = "PassengerSeat", Size = Vector3.new(1.8, 0.4, 1.8), CFrame = at(1.4, seatY, cabinZ + 0.3), Color = seatColor })
	weld(chassis, passenger)
	for _, x in ipairs({ -1.4, 1.4 }) do
		body("SeatBack", Vector3.new(1.8, 2.2, 0.4), x, seatY + 1.2, cabinZ + 1.3, seatColor, { rot = CFrame.Angles(math.rad(-12), 0, 0) })
	end

	-- Rodas grandes: pneu, roda vermelha com raios duplos, pinça azul. Hub preso por Motor6D.
	local wheelY = g + r
	for _, wz in ipairs({ front + 3.3, back - 3.1 }) do
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
	ao.CFrame = cf.Rotation
	ao.Parent = chassis

	for _, p in ipairs(car:GetDescendants()) do
		if p:IsA("BasePart") then
			p.CollisionGroup = "Veiculos"
		end
	end
	car:SetAttribute("Spec", spec.Name)
	return car, driver, passenger
end

return CarBuilder
