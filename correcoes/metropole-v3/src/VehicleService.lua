-- VehicleService (ModuleScript)
-- Caminho: ServerScriptService > Services > VehicleService
-- Bicicleta e carros. Marco 6.3: bike e carro saem das garagens (guaritas do mapa);
-- os botões só servem para descer da bike e sair do carro.
-- Dentro dos locais de trabalho (ZoneService) não dá para usar bike nem carro.
-- O jogador "monta" a bicicleta: um modelo é preso ao personagem e a velocidade
-- de caminhada aumenta. Funciona igual no PC e no celular, porque usa o próprio
-- controle de movimento do Roblox. A bike é montada do tamanho do boneco
-- (RigMeasure) e o BikeAnimator, no cliente, faz a pedalada e gira rodas e pedais.
-- O servidor decide tudo: quem pode montar, a velocidade e o cooldown.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local ServerStorage = game:GetService("ServerStorage")
local TextService = game:GetService("TextService")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))
local JobConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("JobConfig"))
local RigMeasure = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("RigMeasure"))
local SecurityService = require(script.Parent:WaitForChild("SecurityService"))
local ZoneService = require(script.Parent:WaitForChild("ZoneService"))
local CarBuilder = require(script.Parent:WaitForChild("CarBuilder"))
local SeatService = require(script.Parent:WaitForChild("SeatService"))
local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))
local EconomyService = require(script.Parent:WaitForChild("EconomyService"))

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

local function buildPartsBike(character, humanoid, root)
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

-- Marco 9.6: BMX do Luís (modelos/BMX.glb, preparada por tools/bmxprep.py), importada em
-- ServerStorage > CarModels com o nome de BIKE.Model. Peças "Frame_...", "WheelFront_...",
-- "WheelRear_..." e "Crank_..." (Papel_cor no nome, igual aos carros) e caixinhas marcadoras:
-- FrontMarker, MarkSeat (topo do selim), MarkGripLeft/Right (manoplas), MarkPedal (pedal direito).
-- A BMX é escalada para o selim ficar embaixo do quadril do boneco. Sem o modelo, usa a bike de peças.
local BIKE_GROUPS = { Frame = true, WheelFront = true, WheelRear = true, Crank = true }

local function bikeTemplate()
	local folder = ServerStorage:FindFirstChild("CarModels")
	return folder and BIKE.Model and folder:FindFirstChild(BIKE.Model)
end

local function partsBounds(parts, base)
	local mn = Vector3.new(math.huge, math.huge, math.huge)
	local mx = -mn
	for _, p in ipairs(parts) do
		local half = p.Size / 2
		for _, sx in ipairs({ -1, 1 }) do
			for _, sy in ipairs({ -1, 1 }) do
				for _, sz in ipairs({ -1, 1 }) do
					local c = p.CFrame * Vector3.new(half.X * sx, half.Y * sy, half.Z * sz)
					if base then
						c = base:PointToObjectSpace(c)
					end
					mn = mn:Min(c)
					mx = mx:Max(c)
				end
			end
		end
	end
	return mn, mx
end

local function buildMeshBike(character, humanoid, root, tpl)
	local bike = tpl:Clone()
	bike.Name = "StarterBike"
	local marks, groups, all = {}, {}, {}
	for _, d in ipairs(bike:GetDescendants()) do
		if d:IsA("BasePart") then
			local names = { d.Name, d.Parent and d.Parent.Name or "" }
			local mark, group
			for _, n in ipairs(names) do
				mark = mark or (n:find("^FrontMarker") and "Front") or n:match("^Mark(%a+)")
				local g = n:match("^(%a+)_")
				group = group or (BIKE_GROUPS[g] and g)
			end
			if mark then
				marks[mark] = d
			elseif group then
				groups[group] = groups[group] or {}
				table.insert(groups[group], d)
				table.insert(all, d)
			end
		end
	end
	if not (marks.Seat and marks.GripLeft and marks.GripRight and marks.Pedal and groups.Frame and groups.Crank and groups.WheelFront and groups.WheelRear) then
		bike:Destroy()
		warn("[VehicleService] Modelo da BMX incompleto em CarModels; usando a bike de peças.")
		return nil
	end

	-- 1. Referência do modelo: chão, centro e frente (pela FrontMarker), escala pelo selim
	local function frameOf()
		local mn, mx = partsBounds(all)
		local center = (mn + mx) / 2
		local front = Vector3.new(0, 0, -1)
		if marks.Front then
			local d = marks.Front.Position - center
			if math.abs(d.X) > math.abs(d.Z) then
				front = Vector3.new(d.X > 0 and 1 or -1, 0, 0)
			else
				front = Vector3.new(0, 0, d.Z > 0 and 1 or -1)
			end
		end
		local g = Vector3.new(center.X, mn.Y, center.Z)
		return CFrame.lookAt(g, g + front)
	end
	local m = RigMeasure.measure(character)
	local hip = m and (m.hip.Left + m.hip.Right) / 2 or Vector3.new(0, -1, 0)
	local ground = -rootHeightAboveGround(humanoid, root)
	local base = frameOf()
	local seatH = base:PointToObjectSpace(marks.Seat.Position).Y
	-- Marco 9.8: a BMX ficava pequena (o boneco do Roblox tem perna curta). Agora ela tem
	-- BIKE.MeshLength studs de comprimento e o boneco sobe junto com o selim (HipHeight + lift).
	local mn0, mx0 = partsBounds(all, base)
	local length = math.max(mx0.Z - mn0.Z, 0.01)
	local k = math.clamp((BIKE.MeshLength or 6) / length, 1.6, 8)
	bike:ScaleTo(bike:GetScale() * k)
	base = frameOf()
	local seat = base:PointToObjectSpace(marks.Seat.Position)
	local hipAbove = hip.Y - 0.15 + BIKE.SeatOffsetY - ground -- quadril acima do chão, a pé
	local lift = math.max(0, seat.Y - (BIKE.SeatSink or 0.3) - hipAbove)
	ground -= lift -- o root vai subir "lift": as rodas ficam no chão depois disso

	-- 2. Tudo no espaço do HumanoidRootPart: selim embaixo do quadril, rodas no chão
	local offset = CFrame.new(-seat.X, ground, hip.Z + 0.3 - seat.Z)
	local place = root.CFrame * offset
	local function toLocal(pos) -- posição do modelo -> espaço do root
		return (offset * base:ToObjectSpace(CFrame.new(pos))).Position
	end
	local function settle(p)
		for _, child in ipairs(p:GetChildren()) do
			if child:IsA("SurfaceAppearance") then
				child:Destroy() -- a cor vem do nome da peça
			end
		end
		local role, hex = p.Name:match("^%a+_(%a+)_(%x%x%x%x%x%x)")
		if not role and p.Parent then
			role, hex = p.Parent.Name:match("^%a+_(%a+)_(%x%x%x%x%x%x)")
		end
		if hex then
			p.Color = Color3.fromRGB(tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16))
		end
		p.Material = role == "Metal" and Enum.Material.Metal or Enum.Material.SmoothPlastic
		p.Reflectance = 0
		p.CanCollide = false
		p.CanTouch = false
		p.CanQuery = false
		p.Massless = true
		p.Anchored = false
		p.CFrame = place * base:ToObjectSpace(p.CFrame)
	end

	-- 3. Rodas e pedivela: eixo invisível no centro, girado pelo BikeAnimator (Motor6D)
	local function spinner(name, list)
		local mn, mx = partsBounds(list, base)
		local center = toLocal(base:PointToWorldSpace((mn + mx) / 2))
		local hub = newBikePart(bike, name, Vector3.new(0.2, 0.2, 0.2), BIKE.MetalColor)
		hub.Transparency = 1
		hub.CFrame = root.CFrame * CFrame.new(center)
		local motor = Instance.new("Motor6D")
		motor.Name = name .. "Motor"
		motor.Part0 = root
		motor.Part1 = hub
		motor.C0 = CFrame.new(center)
		motor.Parent = hub
		for _, p in ipairs(list) do
			settle(p)
			weldTo(hub, p)
		end
		return (mx.Y - mn.Y) / 2, center
	end
	local wheelR = spinner("FrontWheel", groups.WheelFront)
	spinner("RearWheel", groups.WheelRear)
	local pedal = base:PointToObjectSpace(marks.Pedal.Position)
	local _, bb = spinner("Crank", groups.Crank)
	local pedalLocal = toLocal(base:PointToWorldSpace(pedal))
	local crankR = Vector2.new(pedalLocal.Y - bb.Y, pedalLocal.Z - bb.Z).Magnitude
	for _, p in ipairs(groups.Frame) do
		settle(p)
		weldTo(root, p)
	end

	-- 4. Manoplas (as mãos vão nelas) e marcadores que não servem mais
	for _, side in ipairs({ "Left", "Right" }) do
		local grip = newBikePart(bike, "Grip" .. side, Vector3.new(0.2, 0.2, 0.2), BIKE.AccentColor)
		grip.Transparency = 1
		grip.CFrame = root.CFrame * CFrame.new(toLocal(marks["Grip" .. side].Position))
		weldTo(root, grip)
	end
	for _, mark in pairs(marks) do
		local holder = mark.Parent
		mark:Destroy()
		if holder and holder ~= bike and holder:IsA("Model") and #holder:GetChildren() == 0 then
			holder:Destroy()
		end
	end

	bike:SetAttribute("WheelRadius", wheelR)
	bike:SetAttribute("CrankRadius", crankR)
	bike:SetAttribute("Lift", lift)
	bike.Parent = character
	humanoid.HipHeight += lift
	return bike
end

local function buildBike(character, humanoid, root)
	local tpl = bikeTemplate()
	if tpl then
		local ok, bike = pcall(buildMeshBike, character, humanoid, root, tpl)
		if ok and bike then
			return bike
		elseif not ok then
			warn("[VehicleService] Erro ao montar a BMX: " .. tostring(bike))
		end
	end
	return buildPartsBike(character, humanoid, root)
end

local function sendState(player, mounted)
	uiUpdate:FireClient(player, "BikeState", { mounted = mounted })
end

local function dismount(player)
	local bike = bikes[player]
	bikes[player] = nil
	local lift = bike and bike:GetAttribute("Lift") or 0
	if bike then
		bike:Destroy()
	end
	local _, humanoid = SecurityService.getLivingCharacter(player)
	if humanoid then
		humanoid.WalkSpeed = GameConfig.WalkSpeed
		if bike and bike.Parent == nil and lift > 0 then
			humanoid.HipHeight = math.max(0, humanoid.HipHeight - lift) -- desce do selim
		end
	end
	sendState(player, false)
end

local function mount(player)
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

-- Lugar de uma vaga da garagem: no chão, livre de paredes e de outros carros
local function spotFree(spec, cf)
	local ray = RaycastParams.new()
	ray.FilterType = Enum.RaycastFilterType.Exclude
	ray.FilterDescendantsInstances = charactersList()
	local hit = Workspace:Raycast(cf.Position + Vector3.new(0, 6, 0), Vector3.new(0, -30, 0), ray)
	if not hit then
		return nil
	end
	local center = Vector3.new(cf.X, hit.Position.Y + spec.Hover, cf.Z)
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = charactersList()
	overlap.RespectCanCollide = true
	-- caixa do carro, começando um pouco acima do chão (calçada e meio-fio não contam)
	local box = CFrame.new(center + Vector3.new(0, 0.6, 0)) * cf.Rotation
	local parts = Workspace:GetPartBoundsInBox(box, Vector3.new(spec.Width + 0.6, 3, spec.Length + 0.6), overlap)
	if #parts > 0 then
		return nil
	end
	return CFrame.new(center) * cf.Rotation
end

local function sitInCar(player, humanoid)
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

-- Cor salva do carro (loja de pintura); nil = cor de fábrica
local function savedColor(player, carId)
	local data = PlayerDataService.get(player)
	local c = data and type(data.carColors) == "table" and data.carColors[carId]
	if type(c) == "table" and type(c[1]) == "number" and type(c[2]) == "number" and type(c[3]) == "number" then
		return Color3.fromRGB(math.clamp(c[1], 0, 255), math.clamp(c[2], 0, 255), math.clamp(c[3], 0, 255))
	end
	return nil
end

-- Placas (Marco 7.5) ----------------------------------------------------
local PLATE_MAX = 7

-- Só letras sem acento, números e espaço, em maiúsculas, até 7. nil = não sobrou nada.
local function cleanPlate(text)
	if type(text) ~= "string" then
		return nil
	end
	local s = text:sub(1, 40):upper():gsub("[^A-Z0-9 ]", "")
	s = s:gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")
	s = s:sub(1, PLATE_MAX)
	return #s > 0 and s or nil
end

-- Placa padrão de quem ainda não escolheu: 3 letras e 4 números, sempre a mesma para a pessoa
local function defaultPlate(player, carId)
	local n = (player.UserId * 7919 + #tostring(carId or "")) % 10000
	local letters = ""
	local k = player.UserId
	for _ = 1, 3 do
		letters ..= string.char(65 + k % 26)
		k = math.floor(k / 26)
	end
	return ("%s%04d"):format(letters, n)
end

local function savedPlate(player, carId)
	local data = PlayerDataService.get(player)
	local p = data and type(data.carPlates) == "table" and data.carPlates[carId]
	return cleanPlate(p) or defaultPlate(player, carId)
end

-- Todo texto que outras pessoas veem passa pelo filtro do Roblox (obrigatório)
local function filterPlate(player, text)
	local ok, result = pcall(function()
		local filtered = TextService:FilterStringAsync(text, player.UserId, Enum.TextFilterContext.PublicChat)
		return filtered:GetNonChatStringForBroadcastAsync()
	end)
	if not ok or type(result) ~= "string" then
		return nil
	end
	if result ~= text or result:find("#") then
		return nil -- o filtro trocou alguma coisa: placa recusada
	end
	return result
end

-- Carro sem motorista desliza até parar (Marco 7.1). Freia com COAST_DECEL studs/s²: a 80 studs/s
-- anda uns 30 studs. Para antes de bater numa parede e acompanha a altura do chão.
local COAST_DECEL = 34
local coastRay = RaycastParams.new()
coastRay.FilterType = Enum.RaycastFilterType.Exclude
coastRay.RespectCanCollide = true

local function coast(model, chassis, drive, driver, spec, velocity)
	local speed = velocity.Magnitude
	if speed < 3 then
		drive.VectorVelocity = Vector3.zero
		return
	end
	local dir = velocity.Unit
	task.spawn(function()
		while speed > 0 and model.Parent and not driver.Occupant do
			local dt = RunService.Heartbeat:Wait()
			speed = math.max(0, speed - COAST_DECEL * dt)
			local ignore = charactersList()
			table.insert(ignore, model)
			coastRay.FilterDescendantsInstances = ignore
			-- parede logo à frente: para
			local size = Vector3.new(spec.Width - 1, 1.6, spec.Length - 1)
			local box = chassis.CFrame * CFrame.new(0, 0.5, 0)
			local hit = Workspace:Blockcast(box, size, dir * (speed * dt + 1), coastRay)
			if hit and math.abs(hit.Normal.Y) < 0.6 then
				speed = 0
			end
			-- altura do chão (igual ao CarController)
			local vy = 0
			local ground = Workspace:Raycast(chassis.Position + Vector3.new(0, 4, 0), Vector3.new(0, -30, 0), coastRay)
			if ground then
				vy = math.clamp((ground.Position.Y + spec.Hover - chassis.Position.Y) * 10, -40, 40)
			end
			if not driver.Occupant then
				drive.VectorVelocity = dir * speed + Vector3.new(0, vy, 0)
			end
		end
		if model.Parent and not driver.Occupant then
			drive.VectorVelocity = Vector3.zero
		end
	end)
end

local function spawnCar(player, humanoid, spec, spot, carId)
	destroyCar(player)
	local model, driver, passenger = CarBuilder.build(spec, spot, carId and savedColor(player, carId))
	model.Name = player.Name .. "_" .. spec.Name
	model:SetAttribute("Owner", player.UserId)
	model:SetAttribute("Service", spec.Service) -- Marco 10.16: caminhão de bombeiros perto (mangueira)
	CarBuilder.setPlate(model, spec.Service and defaultPlate(player, carId) or savedPlate(player, carId))
	model.Parent = vehiclesFolder()
	SeatService.setup(passenger, "Carona")
	for _, seat in ipairs(model:GetChildren()) do
		if seat.Name == "RearSeat" then
			SeatService.setup(seat, "Banco de trás")
		end
	end
	cars[player] = { model = model, driver = driver, spec = spec, id = carId }

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
		if occupant and who ~= player then
			occupant.Sit = false -- só o dono dirige
			return
		end
		if who then
			pcall(function()
				chassis:SetNetworkOwner(who)
			end)
			-- Marco 7.5: confirma de novo logo depois (carro recém-saído da garagem: o Roblox ainda
			-- podia estar ajeitando o boneco soldado no banco e o carro não andava)
			task.delay(0.4, function()
				if driver.Occupant == occupant and chassis.Parent then
					pcall(function()
						chassis:SetNetworkOwner(who)
					end)
				end
			end)
			uiUpdate:FireClient(player, "CarState", { driving = true })
		else
			-- saiu: o carro segue um pouquinho, perdendo velocidade, e para (Marco 7.1; antes
			-- parava na hora), virado para o mesmo lado
			local drive = chassis:FindFirstChildOfClass("LinearVelocity")
			local upright = chassis:FindFirstChildOfClass("AlignOrientation")
			local v = chassis.AssemblyLinearVelocity
			local flat = Vector3.new(v.X, 0, v.Z)
			if upright then
				local look = chassis.CFrame.LookVector
				upright.CFrame = CFrame.Angles(0, math.atan2(-look.X, -look.Z), 0)
			end
			pcall(function()
				chassis:SetNetworkOwner(nil)
			end)
			if drive then
				coast(model, chassis, drive, driver, spec, flat)
			end
			uiUpdate:FireClient(player, "CarState", { driving = false })
		end
	end)

	-- Entrar de novo: E perto da porta do motorista (só o dono)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "DrivePrompt"
	prompt.ActionText = "Dirigir"
	prompt.ObjectText = spec.Name
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

	-- Marco 7.5: espera o carro novo chegar no aparelho do jogador antes de sentar. Sentando no
	-- mesmo instante, o controle do Roblox podia não achar o banco (ainda não tinha chegado) e o
	-- carro não andava até sair e entrar de novo.
	task.spawn(function()
		pcall(function()
			player:RequestStreamAroundAsync(chassis.Position, 2)
		end)
		task.wait(0.35)
		local _, hum = SecurityService.getLivingCharacter(player)
		if hum and hum == humanoid and not hum.SeatPart and cars[player] and cars[player].model == model then
			sitInCar(player, hum)
		end
	end)
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
		character:PivotTo(chassis.CFrame * CFrame.new(-(c.spec.Width / 2 + 2.5), 1, 0))
	end
end

-- Tecla V / botão "Sair do carro": sai dirigindo, ou entra no seu carro se ele estiver perto.
-- Carro novo só na garagem (Marco 6.3).
local function toggleCar(player)
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
	local chassis = c and c.model.PrimaryPart
	if chassis and (chassis.Position - root.Position).Magnitude < 40 and not ZoneService.isInside(player) then
		sitInCar(player, humanoid)
		return
	end
	notice(player, "Pegue um carro na Garagem (a guarita azul; veja no Mapa).")
end

---------------------------------------------------------------------------
-- Garagens (Marco 6.3): guaritas do mapa (MapBuilder) com vagas "Vaga1", "Vaga2"
---------------------------------------------------------------------------

local function garageByName(name)
	local map = Workspace:FindFirstChild("Map")
	local folder = map and map:FindFirstChild("Garages")
	return folder and type(name) == "string" and folder:FindFirstChild(name)
end

-- Marco 7: carros comprados ficam em data.ownedCars (ex.: { L5 = true }).
-- No Studio, com GameConfig.Garage.FreeInStudio, todos ficam liberados para testar.
-- Marco 7.1: no Studio (Garage.ServiceInStudio) os veículos de serviço também saem da garagem,
-- para testar viatura, táxi e caminhão antes dos empregos existirem
local function serviceTest()
	return GameConfig.Garage.ServiceInStudio == true and RunService:IsStudio()
end

-- Marco 8.1: garagem de serviço (ex.: garagem da PM na Penitenciária). O atributo ServiceJob
-- diz de qual profissão ela é; só quem está nessa profissão tira os veículos dela.
local function serviceJobOf(garage)
	return garage and garage:GetAttribute("ServiceJob")
end

-- Marco 9.16: carros só dos admins (spec.AdminOnly, aba "Admin" da garagem). Admin = dono do
-- jogo (ou dono do grupo, rank 255), quem está em GameConfig.Admins.UserIds e, no Studio, todo mundo.
local adminCache = {}
local function isAdmin(player)
	if adminCache[player] ~= nil then
		return adminCache[player]
	end
	local cfg = GameConfig.Admins or {}
	local ok = false
	if cfg.InStudio ~= false and RunService:IsStudio() then
		ok = true
	elseif table.find(cfg.UserIds or {}, player.UserId) then
		ok = true
	elseif game.CreatorType == Enum.CreatorType.User then
		ok = player.UserId == game.CreatorId
	elseif game.CreatorType == Enum.CreatorType.Group then
		local got, rank = pcall(player.GetRankInGroup, player, game.CreatorId)
		ok = got and rank >= (cfg.GroupRank or 255)
	end
	adminCache[player] = ok
	player:SetAttribute("Admin", ok or nil)
	return ok
end
Players.PlayerRemoving:Connect(function(player)
	adminCache[player] = nil
end)

local function ownsCar(player, carId, garage)
	local spec = GameConfig.Cars[carId]
	if not spec then
		return false
	end
	if spec.AdminOnly then
		return isAdmin(player) and not serviceJobOf(garage)
	end
	if spec.Service then
		if serviceJobOf(garage) == spec.Service and player:GetAttribute("Job") == spec.Service then
			return true
		end
		return serviceTest() -- veículo de serviço não é da garagem (só no teste do Studio)
	end
	if GameConfig.Garage.FreeInStudio and RunService:IsStudio() then
		return true
	end
	local data = PlayerDataService.get(player)
	return data ~= nil and type(data.ownedCars) == "table" and data.ownedCars[carId] == true
end

local function isDealership(garage)
	return garage and garage:GetAttribute("Dealership") == true
end

local function carList(player, garage)
	local list = {}
	local serviceJob = serviceJobOf(garage)
	for id, spec in pairs(GameConfig.Cars) do
		local show
		if isDealership(garage) then
			show = not spec.Service and not spec.AdminOnly
		elseif serviceJob then
			show = spec.Service == serviceJob -- garagem de serviço: só os veículos da profissão
		elseif spec.AdminOnly then
			show = isAdmin(player) -- Marco 9.16: aba "Admin" só para os admins
		else
			show = not spec.Service or serviceTest()
		end
		if not isDealership(garage) and not ownsCar(player, id, garage) then show = false end
		if show then
			table.insert(list, {
				id = id,
				name = spec.Name,
				order = spec.Order or 99,
				speed = spec.MaxSpeed,
				accel = spec.Acceleration,
				turn = spec.TurnRate,
				drift = spec.DriftTurnBoost,
				owned = ownsCar(player, id, garage),
				price = spec.Price or 0,
				rarity = spec.Rarity,
				category = spec.Category or "Carros",
				service = spec.Service ~= nil,
				admin = spec.AdminOnly == true,
			})
		end
	end
	table.sort(list, function(a, b)
		return a.order < b.order
	end)
	return list
end

local function nearGarage(player, garage)
	local _, humanoid, root = SecurityService.getLivingCharacter(player)
	local booth = garage and garage:FindFirstChild("Balcao")
	if not root or not booth then
		return nil
	end
	if (booth.Position - root.Position).Magnitude > GameConfig.Garage.UseDistance then
		return nil
	end
	return humanoid
end

-- Pode usar essa garagem? (preso não usa nenhuma; garagem de serviço só para a profissão dela)
local function garageRefusal(player, garage)
	if player:GetAttribute("Preso") then
		return "Você está preso. Faça tarefas para diminuir a pena!"
	end
	-- Marco 10.6: garagem da mansão, só para quem mora nela
	if garage:GetAttribute("Private") and garage:GetAttribute("OwnerId") ~= player.UserId then
		return "Essa garagem é só do dono da mansão."
	end
	local serviceJob = serviceJobOf(garage)
	if serviceJob and player:GetAttribute("Job") ~= serviceJob then
		local job = JobConfig.Jobs[serviceJob]
		return ("Só quem é %s pode tirar veículos aqui."):format(job and job.Name or serviceJob)
	end
	return nil
end

local function openGarage(player, garage)
	if not nearGarage(player, garage) then return end
	local why = garageRefusal(player, garage)
	if why then
		return notice(player, why)
	end
	local c = cars[player]
	uiUpdate:FireClient(player, "GarageOpen", {
		garage = garage.Name,
		dealership = isDealership(garage),
		testMode = GameConfig.Garage.FreeInStudio == true and RunService:IsStudio(),
		cars = carList(player, garage),
		hasCar = c ~= nil,
		current = c and c.id,
		onBike = bikes[player] ~= nil,
		money = EconomyService.getMoney(player) or 0,
	})
end

local function garageAction(player, data)
	if type(data) ~= "table" then
		return
	end
	local garage = garageByName(data.garage)
	local humanoid = nearGarage(player, garage)
	if not humanoid then
		return notice(player, "Chegue mais perto da guarita da garagem.")
	end
	if humanoid.SeatPart then
		return notice(player, "Desça do veículo primeiro.")
	end
	local why = garageRefusal(player, garage)
	if why then
		return notice(player, why)
	end
	if data.op == "Buy" then
		if not isDealership(garage) then
			return notice(player, "Compre veículos na Concessionária do Vale. A garagem guarda seus veículos.")
		end
		-- comprar um carro: preço do GameConfig (o cliente nunca manda o preço)
		local spec = type(data.car) == "string" and GameConfig.Cars[data.car]
		if not spec or spec.Service or spec.AdminOnly or serviceJobOf(garage) or ownsCar(player, data.car) then
			return
		end
		local saved = PlayerDataService.get(player)
		if not saved then
			return notice(player, "Seus dados ainda estão carregando. Tente de novo.")
		end
		if not RunService:IsStudio() and not PlayerDataService.canPersist(player) then
			return notice(player, "Não foi possível carregar seu progresso com segurança. Reconecte antes de comprar.")
		end
		local price = spec.Price or 0
		if type(price) ~= "number" or price ~= price or price < 0 or price > GameConfig.Economy.MaxMoney or price % 1 ~= 0 then return end
		if price > 0 and not EconomyService.spend(player, price, "Carro " .. spec.Name) then
			return notice(player, ("Falta dinheiro: o %s custa %s%d."):format(spec.Name, GameConfig.Economy.CurrencySymbol, price))
		end
		local owned = type(saved.ownedCars) == "table" and table.clone(saved.ownedCars) or {}
		owned[data.car] = true
		PlayerDataService.set(player, "ownedCars", owned)
		task.spawn(function()
			local savedOk = PlayerDataService.save(player)
			if not savedOk and player.Parent and not RunService:IsStudio() then
				notice(player, "Compra disponível nesta sessão. Salvamento pendente; o jogo tentará novamente.")
			end
		end)
		notice(player, ("Parabéns! O %s agora é seu. Toque em Retirar."):format(spec.Name))
		openGarage(player, garage)
	elseif data.op == "Bike" then
		if not bikes[player] then
			mount(player)
		end
	elseif data.op == "Store" then
		local had = cars[player] ~= nil or bikes[player] ~= nil
		destroyCar(player)
		if bikes[player] then
			dismount(player)
		end
		notice(player, had and "Veículo guardado na garagem." or "Você não tem veículo na rua.")
	elseif data.op == "Car" then
		local spec = type(data.car) == "string" and GameConfig.Cars[data.car]
		if not spec or not ownsCar(player, data.car, garage) then
			return
		end
		local spot
		local k = 1
		local vaga = garage:FindFirstChild("Vaga1")
		while vaga and not spot do -- 2 vagas (3 na LXR Táxis)
			spot = spotFree(spec, vaga.CFrame)
			k += 1
			vaga = garage:FindFirstChild("Vaga" .. k)
		end
		if not spot then
			return notice(player, "As vagas da garagem estão ocupadas. Espere liberar.")
		end
		if bikes[player] then
			dismount(player)
		end
		destroyCar(player) -- só troca após encontrar uma vaga livre
		spawnCar(player, humanoid, spec, spot, data.car)
	end
end

-- Miniaturas da garagem (Marco 7.1): uma cópia parada de cada veículo, com as cores de fábrica,
-- em ReplicatedStorage > CarPreviews. O painel da garagem mostra elas girando (ViewportFrame).
local function buildPreviews()
	local folder = Instance.new("Folder")
	folder.Name = "CarPreviews"
	for id, spec in pairs(GameConfig.Cars) do
		local ok, car = pcall(CarBuilder.build, spec, CFrame.new(0, -1000, 0))
		if ok and car then
			for _, d in ipairs(car:GetDescendants()) do
				if d:IsA("Constraint") or d:IsA("Attachment") or d:IsA("ProximityPrompt") or d:IsA("JointInstance") or d:IsA("WeldConstraint") then
					d:Destroy()
				end
			end
			for _, d in ipairs(car:GetDescendants()) do
				if d:IsA("BasePart") then
					d.Anchored = true
					d.CanCollide = false
					d.CanQuery = false
					d.CanTouch = false
					if d:IsA("Seat") or d:IsA("VehicleSeat") then
						d.Transparency = 1
					end
				end
			end
			car.Name = id
			car.Parent = folder
		else
			warn("[VehicleService] Miniatura de " .. tostring(spec.Name) .. " falhou: " .. tostring(car))
		end
	end
	folder.Parent = ReplicatedStorage
end

local function setupGarages()
	local map = Workspace:FindFirstChild("Map")
	local folder = map and map:FindFirstChild("Garages")
	for _, garage in ipairs(folder and folder:GetChildren() or {}) do
		local booth = garage:FindFirstChild("Balcao")
		if booth then
			local prompt = Instance.new("ProximityPrompt")
			prompt.Name = "GaragePrompt"
			prompt.ActionText = isDealership(garage) and "Ver catálogo / comprar" or "Abrir garagem"
			prompt.ObjectText = isDealership(garage) and "Concessionária do Vale" or (garage:GetAttribute("Private") and "Garagem da mansão" or "Garagem")
			prompt.KeyboardKeyCode = Enum.KeyCode.E
			prompt.MaxActivationDistance = 10
			prompt.RequiresLineOfSight = false
			prompt.Parent = booth
			prompt.Triggered:Connect(function(player)
				if SecurityService.checkRate(player, "GarageOpen", 1) then
					openGarage(player, garage)
				end
			end)
		end
	end
end

---------------------------------------------------------------------------
-- Loja de pintura (Marco 6.4): o jogador para o carro na cabine e escolhe a cor.
-- PROVISÓRIO: de graça para testar (GameConfig.PaintShop.Price).
---------------------------------------------------------------------------

local PAINT = GameConfig.PaintShop

local function paintShop()
	local map = Workspace:FindFirstChild("Map")
	return map and map:FindFirstChild("PaintShop")
end

-- O carro do jogador, se ele estiver dirigindo e parado dentro da cabine
local function carInBooth(player)
	local shop = paintShop()
	local pad = shop and shop:FindFirstChild("PaintPad")
	local c = cars[player]
	local chassis = c and c.model and c.model.PrimaryPart
	if not pad or not chassis then
		return nil, "Traga o seu carro até a cabine de pintura."
	end
	local flat = (chassis.Position - pad.Position) * Vector3.new(1, 0, 1)
	if flat.Magnitude > PAINT.UseDistance then
		return nil, "Pare o carro dentro da cabine de pintura (o quadrado colorido)."
	end
	return c
end

local function openPaint(player)
	local c, why = carInBooth(player)
	if not c then
		return notice(player, why)
	end
	local current = c.model:GetAttribute("PaintColor") or c.spec.BodyColor
	uiUpdate:FireClient(player, "PaintOpen", {
		car = c.spec.Name,
		plate = c.model:GetAttribute("Plate"),
		plateMax = PLATE_MAX,
		canPlate = c.id ~= nil and not c.spec.Service and c.spec.Plates ~= nil,
		price = PAINT.Price,
		palette = PAINT.Palette,
		current = { math.floor(current.R * 255 + 0.5), math.floor(current.G * 255 + 0.5), math.floor(current.B * 255 + 0.5) },
	})
end

local function plateAction(player, text)
	local c, why = carInBooth(player)
	if not c then
		return notice(player, why)
	end
	if c.spec.Service or not c.id then
		return notice(player, ("A placa da %s é da empresa e não pode ser trocada."):format(c.spec.Name))
	end
	local plate = cleanPlate(text)
	if not plate then
		return notice(player, "Escreva a placa com letras e números (até 7).")
	end
	plate = filterPlate(player, plate)
	if not plate then
		return notice(player, "Essa placa não pode ser usada. Tente outra.")
	end
	CarBuilder.setPlate(c.model, plate)
	local saved = PlayerDataService.get(player)
	if saved then
		local plates = type(saved.carPlates) == "table" and saved.carPlates or {}
		plates[c.id] = plate
		PlayerDataService.set(player, "carPlates", plates)
	end
	notice(player, ("Placa %s colocada! Todo mundo vê."):format(plate))
end

local function paintAction(player, data)
	if type(data) == "table" and data.plate ~= nil then
		return plateAction(player, data.plate)
	end
	-- cor = 3 números inteiros de 0 a 255 (nada de texto ou tabela estranha)
	local rgb = type(data) == "table" and data.color
	if type(rgb) ~= "table" or #rgb ~= 3 then
		return
	end
	for i = 1, 3 do
		local v = rgb[i]
		if type(v) ~= "number" or v ~= v or v < 0 or v > 255 or v % 1 ~= 0 then
			return
		end
	end
	local c, why = carInBooth(player)
	if not c then
		return notice(player, why)
	end
	if c.spec.Service then
		return notice(player, ("A %s tem as cores da empresa e não pode ser pintada."):format(c.spec.Name))
	end
	if PAINT.Price > 0 then
		return notice(player, "Pintura paga ainda não está pronta.") -- PROVISÓRIO: preço a decidir
	end
	CarBuilder.paint(c.model, Color3.fromRGB(rgb[1], rgb[2], rgb[3]))
	if c.id then
		local saved = PlayerDataService.get(player)
		if saved then
			local colors = type(saved.carColors) == "table" and saved.carColors or {}
			colors[c.id] = { rgb[1], rgb[2], rgb[3] }
			PlayerDataService.set(player, "carColors", colors)
		end
	end
	notice(player, "Carro pintado! A cor fica salva para a próxima vez.")
end

local function setupPaintShop()
	local shop = paintShop()
	local post = shop and shop:FindFirstChild("PaintPost")
	if not post then
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "PaintPrompt"
	prompt.ActionText = "Pintar carro"
	prompt.ObjectText = PAINT.Name
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.MaxActivationDistance = 16
	prompt.RequiresLineOfSight = false
	prompt.Parent = post
	prompt.Triggered:Connect(function(player)
		if SecurityService.checkRate(player, "PaintOpen", 1) then
			openPaint(player)
		end
	end)
end

---------------------------------------------------------------------------
-- Van da Sherlex (Marco 7): veículo de serviço de quem trabalha de Entregador.
-- Placa "Pegar van" na frente da Sherlex; a van some quando a pessoa larga o emprego.
---------------------------------------------------------------------------

local function serviceVehicleFor(job)
	for id, spec in pairs(GameConfig.Cars) do
		if spec.Service and spec.Service == job then
			return id, spec
		end
	end
	return nil
end

local function takeVan(player, shop)
	local _, humanoid, root = SecurityService.getLivingCharacter(player)
	local post = shop:FindFirstChild("VanPost")
	local vaga = shop:FindFirstChild("VanSpot")
	if not root or not post or not vaga or (post.Position - root.Position).Magnitude > 16 then
		return
	end
	local id, spec = serviceVehicleFor(player:GetAttribute("Job"))
	if not id or spec.Model ~= "SherlexVan" then
		return notice(player, "A van é só para quem trabalha de Entregador Sherlex (quadro de empregos na praça).")
	end
	if humanoid.SeatPart then
		return notice(player, "Desça do veículo primeiro.")
	end
	destroyCar(player) -- o carro pessoal volta para a garagem
	local spot = spotFree(spec, vaga.CFrame)
	if not spot then
		return notice(player, "Tem alguma coisa na vaga da van. Espere liberar.")
	end
	if bikes[player] then
		dismount(player)
	end
	spawnCar(player, humanoid, spec, spot, id)
end

local function setupServiceVehicles()
	local map = Workspace:FindFirstChild("Map")
	local shops = map and map:FindFirstChild("JobLocations")
	local shop = shops and shops:FindFirstChild(GameConfig.Places.Entregas)
	local post = shop and shop:FindFirstChild("VanPost")
	if post then
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "VanPrompt"
		prompt.ActionText = "Pegar van"
		prompt.ObjectText = "Van Sherlex"
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.MaxActivationDistance = 12
		prompt.RequiresLineOfSight = false
		prompt.Parent = post
		prompt.Triggered:Connect(function(player)
			if SecurityService.checkRate(player, "Car", GameConfig.CarCooldown) then
				takeVan(player, shop)
			end
		end)
	end
end

-- Largou (ou trocou) o emprego: o veículo de serviço volta para a empresa
local function watchJob(player)
	player:GetAttributeChangedSignal("Job"):Connect(function()
		local c = cars[player]
		if c and c.spec.Service and player:GetAttribute("Job") ~= c.spec.Service then
			destroyCar(player)
			notice(player, ("A %s voltou para a empresa."):format(c.spec.Name))
		end
	end)
end

-- Anti-trapaça do carro: velocidade bem acima do máximo por 2 checagens seguidas = carro parado.
-- Só a velocidade no chão conta (batidas dão "picos" rápidos que não são trapaça e não tiram
-- ninguém do carro; antes isso fazia o carro "morrer" ao encostar em algo).
local strikes = {}
local function watchCarSpeed()
	while true do
		task.wait(1)
		for player, c in pairs(cars) do
			local chassis = c.model and c.model.PrimaryPart
			if chassis then
				local v = chassis.AssemblyLinearVelocity
				local flat = Vector3.new(v.X, 0, v.Z).Magnitude
				if flat > c.spec.MaxSpeed * 1.6 then
					strikes[player] = (strikes[player] or 0) + 1
					if strikes[player] >= 2 then
						warn(("[VehicleService] Velocidade estranha no carro de %s; carro parado."):format(player.Name))
						chassis.AssemblyLinearVelocity = Vector3.zero
						strikes[player] = 0
					end
				else
					strikes[player] = nil
				end
			end
		end
	end
end

local function onVehicleRequest(player, action, data)
	-- 1. limite de frequência antes de qualquer coisa
	if not SecurityService.checkRate(player, "VehicleRequest", BIKE.ToggleCooldown) then
		return
	end
	-- 2. tipo do argumento
	if not SecurityService.isShortString(action, 16) then
		return
	end
	-- 3. preso não pega bike, carro nem garagem (Marco 8.1)
	if player:GetAttribute("Preso") and action ~= "ToggleBike" then
		return notice(player, "Você está preso. Faça tarefas para diminuir a pena!")
	end
	-- 4. ação conhecida
	if action == "ToggleBike" then
		-- o botão só desce da bike; pegar a bike é na garagem
		if bikes[player] and bikes[player].Parent then
			dismount(player)
		else
			notice(player, "Pegue a bike na Garagem (a guarita azul; veja no Mapa).")
		end
	elseif action == "ToggleCar" then
		if SecurityService.checkRate(player, "Car", GameConfig.CarCooldown) then
			toggleCar(player)
		end
	elseif action == "Garage" then
		if SecurityService.checkRate(player, "Car", GameConfig.CarCooldown) then
			garageAction(player, data)
		end
	elseif action == "Paint" then
		if SecurityService.checkRate(player, "Paint", PAINT.Cooldown) then
			paintAction(player, data)
		end
	elseif action == "Siren" then
		-- Marco 9.9: liga/desliga a sirene (som e giroflex) de quem está dirigindo viatura ou bombeiros
		local c = cars[player]
		local _, humanoid = SecurityService.getLivingCharacter(player)
		if c and c.spec.Siren and humanoid and humanoid.SeatPart == c.driver and c.model.Parent then
			c.model:SetAttribute("SirenOn", not c.model:GetAttribute("SirenOn"))
		end
	end
end

-- Usado pelo SeatService: desce da bike antes de sentar num banco
-- Marco 9: carro que o jogador tem na rua agora ({ model, driver, spec, id }) ou nil
function VehicleService.getCar(player)
	return cars[player]
end

function VehicleService.dismount(player)
	if bikes[player] then
		dismount(player)
	end
end

-- Marco 8.1: tira a bike e o carro do jogador (ex.: quando ele é preso)
function VehicleService.removeVehicles(player)
	if bikes[player] then
		dismount(player)
	end
	destroyCar(player)
end

function VehicleService.init(remotes)
	uiUpdate = remotes[GameConfig.Remotes.UIUpdate]
	remotes[GameConfig.Remotes.VehicleRequest].OnServerEvent:Connect(onVehicleRequest)

	local function onPlayerAdded(player)
		watchJob(player)
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
		strikes[player] = nil
		destroyCar(player)
	end)

	-- Entrou num local de trabalho de bike: desce na hora
	ZoneService.onChange(function(player, inside)
		if inside and bikes[player] then
			dismount(player)
			notice(player, "Bike guardada: aqui é local de trabalho.")
		end
	end)
	setupGarages()
	setupPaintShop()
	setupServiceVehicles()
	task.spawn(buildPreviews)
	task.spawn(watchCarSpeed)
end

return VehicleService
