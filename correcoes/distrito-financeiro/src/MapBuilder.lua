-- MapBuilder (ModuleScript)
-- Caminho: ServerScriptService > Services > MapBuilder
-- Monta a cidade de Little Little Kinder com peças simples:
--   * praça com rotatória no centro e 8 ruas saindo dela;
--   * dois anéis de rua (meio e borda) ligando as ruas, formando quarteirões;
--   * 4 estabelecimentos com interior (La Paulistana, Minas Market, Sherlex, Duto Pet Shop);
--   * casas de 3 modelos (térrea com varanda, sobrado, com garagem);
--   * cada rua tem nome e placas; casas e prédios são numerados POR RUA, em ordem:
--     ímpares de um lado, pares do outro, crescendo a partir da praça (como numa cidade de verdade);
--   * prédios com comércio no térreo nas ruas comerciais; árvores, postes e faixas de pedestre;
--   * Vila Esperança (Marco 6.1): bairro humilde no fim de uma rua, com as casinhas iniciais.
--   * Parque MigueLândia (Marco 7.2): no fim de uma avenida depois do anel externo (ParkBuilder).
--   * Penitenciária (Marco 8): no fim de uma estrada depois do anel externo (PrisonBuilder).
--   * LXR Táxis (Marco 9): garagem dos táxis na rua 5. Casas, prédios e lugares guardam o
--     atributo "Curb" (ponto na calçada da frente) para o passageiro do táxi.
--   * Marco 10: a cidade cresce para fora. ExpansionBuilder monta as estradas do CityRoads
--     (Rodovia LK-101 de pista dupla saindo da rua 1, Rodoanel, saídas "em breve", Avenida do
--     Progresso saindo da rua 5) e o campo; HorizonteBuilder monta o Bairro Horizonte (bairro de
--     luxo depois do Trevo Norte: prédios, casas modernas e o condomínio de mansões).
-- Cada lote é conferido antes de construir: nada fica em cima de rua ou de outra construção.
--
-- Se já existir uma pasta "Map" no Workspace (por exemplo, se você construir
-- o mapa à mão no futuro), este módulo não faz nada.

local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))
local ParkBuilder = require(script.Parent:WaitForChild("ParkBuilder"))
local PrisonBuilder = require(script.Parent:WaitForChild("PrisonBuilder"))
local FireStationBuilder = require(script.Parent:WaitForChild("FireStationBuilder"))
local HorizonteBuilder = require(script.Parent:WaitForChild("HorizonteBuilder"))
local ExpansionBuilder = require(script.Parent:WaitForChild("ExpansionBuilder"))
local FavelaBuilder = require(script.Parent:WaitForChild("FavelaBuilder")) -- Marco 10.1
local ProgressoBuilder = require(script.Parent:WaitForChild("ProgressoBuilder")) -- Marco 10.4
local CrimeBuilder = require(script.Parent:WaitForChild("CrimeBuilder")) -- Marco 10.5: lojas e caixas eletrônicos
local BankBuilder = require(script.Parent:WaitForChild("BankBuilder")) -- Marco 10.20: Banco Central (Estrada do Vale)
local CityRoads = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CityRoads")) -- Marco 10.6: garagens no mapa novo

local MapBuilder = {}

local M = GameConfig.Map
local C = GameConfig.Colors

local ROAD_TOP = 0.5 -- altura da superfície das ruas
local SIDEWALK_TOP = 0.8
local RADIAL_START = 50 -- as ruas começam dentro da rotatória
local RADIAL_END = RADIAL_START + M.RoadLength -- onde fica o anel externo
local CROSSING_GAP = M.RoadWidth / 2 + M.SidewalkWidth + 8 -- espaço livre em volta dos cruzamentos

local rng = Random.new(M.TreeSeed)

-- Nomes das ruas (índice = rua radial; ímpares são comerciais, pares residenciais)
local STREET_NAMES = M.StreetNames
local INNER_RING_NAME = M.InnerRingName
local OUTER_RING_NAME = M.OuterRingName

-- Rua com contador de números: lado -1 = ímpares (1, 3, 5...), lado +1 = pares (2, 4, 6...)
local function newStreet(name)
	return { name = name, next = { [-1] = 1, [1] = 2 } }
end

local function takeNumber(street, side)
	local n = street.next[side]
	street.next[side] = n + 2
	return n
end

---------------------------------------------------------------------------
-- Funções auxiliares
---------------------------------------------------------------------------

local function makePart(parent, props)
	local p = Instance.new(props.ClassName or "Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = props.Material or Enum.Material.SmoothPlastic
	p.Color = props.Color or Color3.new(1, 1, 1)
	p.Size = props.Size
	p.CFrame = props.CFrame
	if props.Shape then
		p.Shape = props.Shape
	end
	if props.Transparency then
		p.Transparency = props.Transparency
	end
	if props.Reflectance then
		p.Reflectance = props.Reflectance
	end
	if props.CanCollide ~= nil then
		p.CanCollide = props.CanCollide
	end
	if props.CastShadow ~= nil then
		p.CastShadow = props.CastShadow
	end
	p.Name = props.Name or "Part"
	p.Parent = parent
	return p
end

local function folder(name, parent)
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

local function model(name, parent)
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end

-- Cilindro "deitado" no chão (eixo vertical). height = espessura, radius = raio.
local function flatCylinder(parent, name, center, radius, height, color, material)
	return makePart(parent, {
		Name = name,
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(height, radius * 2, radius * 2),
		CFrame = CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90)),
		Color = color,
		Material = material,
	})
end

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

-- Texto pintado na frente (face -Z) de uma peça
local function addSurfaceText(part, text, textColor, bgColor)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	gui.Parent = part

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = bgColor or Color3.new(1, 1, 1)
	label.BackgroundTransparency = bgColor and 0 or 1
	label.TextColor3 = textColor
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextWrapped = true -- Marco 9.14: nome comprido quebra a linha em vez de sair da placa
	label.Text = text
	label.Parent = gui
end

---------------------------------------------------------------------------
-- Partes do mapa
---------------------------------------------------------------------------

-- Placa de nome de rua (verde, como as de verdade), legível dos dois lados.
-- cf: frente virada para a rua; a placa fica paralela à rua.
local function buildStreetSign(parent, cf, name)
	local sign = model("PlacaDeRua", parent)
	makePart(sign, { Name = "Post", Size = Vector3.new(0.35, 9, 0.35), CFrame = cf * CFrame.new(0, 4.5, 0), Color = Color3.fromRGB(70, 75, 80), Material = Enum.Material.Metal })
	local board = makePart(sign, { Name = "Board", Size = Vector3.new(10, 1.5, 0.2), CFrame = cf * CFrame.new(0, 8.6, 0), Color = Color3.fromRGB(30, 110, 60), CanCollide = false })
	for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 40
		gui.LightInfluence = 0
		gui.Parent = board
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.TextColor3 = Color3.new(1, 1, 1)
		label.Font = Enum.Font.GothamBold
		label.TextScaled = true
		label.Text = name
		label.Parent = gui
		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.new(1, 1, 1)
		stroke.Thickness = 3
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = label
	end
end

-- Marco 8.2: uma peça do Roblox tem no máximo 2048 studs de lado. Com o chão de 3600 numa peça só,
-- o Roblox cortava para 2048 e a prisão ficava na borda. Agora o chão é feito de vários pedaços.
local function buildGround(parent)
	local tiles = math.ceil(M.GroundSize / 2000)
	local tile = M.GroundSize / tiles
	for i = 0, tiles - 1 do
		for j = 0, tiles - 1 do
			makePart(parent, {
				Name = "Ground",
				Size = Vector3.new(tile, 1, tile),
				CFrame = CFrame.new(-M.GroundSize / 2 + (i + 0.5) * tile, -0.5, -M.GroundSize / 2 + (j + 0.5) * tile),
				Color = C.Grass,
				Material = Enum.Material.Grass,
			})
		end
	end
end

local function buildSpawn(parent)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "StartSpawn"
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0 -- sem campo de força
	spawn.Size = Vector3.new(8, 1, 8)
	spawn.CFrame = CFrame.new(0, 0.6, 20)
	spawn.Color = C.Sidewalk
	spawn.Material = Enum.Material.Concrete
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Parent = parent
end

local function buildTree(parent, position, scale)
	scale = scale or 1
	local tree = model("Tree", parent)
	local trunkHeight = 6 * scale
	makePart(tree, {
		Name = "Trunk",
		Size = Vector3.new(1.4 * scale, trunkHeight, 1.4 * scale),
		CFrame = CFrame.new(position + Vector3.new(0, trunkHeight / 2, 0)),
		Color = C.Trunk,
		Material = Enum.Material.Wood,
	})
	local leafColor = C.Leaves[rng:NextInteger(1, #C.Leaves)]
	local leafSize = 7 * scale
	makePart(tree, {
		Name = "Leaves",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(leafSize, leafSize, leafSize),
		CFrame = CFrame.new(position + Vector3.new(0, trunkHeight + leafSize * 0.3, 0)),
		Color = leafColor,
		Material = Enum.Material.Grass,
	})
	makePart(tree, {
		Name = "Leaves2",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(leafSize * 0.7, leafSize * 0.7, leafSize * 0.7),
		CFrame = CFrame.new(position + Vector3.new(leafSize * 0.25, trunkHeight + leafSize * 0.65, 0)),
		Color = leafColor,
		Material = Enum.Material.Grass,
	})
	return tree
end

-- Praça central: é o primeiro lugar que o jogador vê, então é a parte mais caprichada.
-- Chafariz de 3 andares com água caindo, piso de pedra com desenho, letreiro da cidade,
-- coreto, gramados com árvores e flores, palmeiras, bancos, postes antigos e carrinho de sorvete.
-- Ângulo 90° = lado do ponto de nascimento (+Z), onde ficam o Seu Bento e o quadro de empregos.
local function buildRoundabout(parent)
	local f = folder("Roundabout", parent)
	local R = M.RoundaboutIslandRadius
	local STONE = Color3.fromRGB(214, 196, 170)
	local STONE_DARK = Color3.fromRGB(176, 150, 125)
	local MARBLE = Color3.fromRGB(240, 238, 232)
	local IRON = Color3.fromRGB(40, 44, 48)
	local function polar(angleDeg, radius, y)
		local a = math.rad(angleDeg)
		return Vector3.new(math.cos(a) * radius, y or 0, math.sin(a) * radius)
	end

	-- Asfalto da rotatória, meio-fio e piso de pedra
	flatCylinder(f, "RoundaboutRoad", Vector3.new(0, ROAD_TOP + 0.05 - 0.5, 0), M.RoundaboutOuterRadius, 1, C.Asphalt, Enum.Material.Asphalt)
	flatCylinder(f, "Curb", Vector3.new(0, 0.4, 0), R + 1, 1, C.Sidewalk, Enum.Material.Concrete)
	flatCylinder(f, "Plaza", Vector3.new(0, 0.45, 0), R, 1, STONE, Enum.Material.Pavement)
	-- desenho no piso: anéis e raios de pedra mais escura
	for _, ring in ipairs({ { 15, 2 }, { 34, 1.6 } }) do
		local n = 28
		for i = 1, n do
			local a1, a2 = (i - 1) / n * 360, i / n * 360
			local p1, p2 = polar(a1, ring[1], 0.97), polar(a2, ring[1], 0.97)
			makePart(f, { Name = "FloorRing", Size = Vector3.new(ring[2], 0.06, (p2 - p1).Magnitude + 0.3), CFrame = CFrame.lookAt((p1 + p2) / 2, p2), Color = STONE_DARK, Material = Enum.Material.Pavement, CanCollide = false, CastShadow = false })
		end
	end
	for i = 0, 7 do
		local p1, p2 = polar(i * 45, 16, 0.97), polar(i * 45, R - 1, 0.97)
		makePart(f, { Name = "FloorRay", Size = Vector3.new(1.6, 0.06, (p2 - p1).Magnitude), CFrame = CFrame.lookAt((p1 + p2) / 2, p2), Color = STONE_DARK, Material = Enum.Material.Pavement, CanCollide = false, CastShadow = false })
	end

	-- Chafariz de 3 andares
	local function bowl(name, y, radius, depth)
		flatCylinder(f, name .. "Rim", Vector3.new(0, y, 0), radius, depth, MARBLE, Enum.Material.Marble)
		local water = flatCylinder(f, name .. "Water", Vector3.new(0, y + depth / 2 - 0.05, 0), radius - 0.6, 0.15, C.Water, Enum.Material.SmoothPlastic)
		water.Transparency = 0.2
		water.CanCollide = false
	end
	bowl("Basin", 1.5, 11, 2)
	flatCylinder(f, "BasinStep", Vector3.new(0, 0.8, 0), 12, 0.6, STONE_DARK, Enum.Material.Pavement)
	makePart(f, { Name = "Column", Shape = Enum.PartType.Cylinder, Size = Vector3.new(6, 2.2, 2.2), CFrame = CFrame.new(0, 5, 0) * CFrame.Angles(0, 0, math.rad(90)), Color = MARBLE, Material = Enum.Material.Marble })
	bowl("Middle", 7.6, 5.5, 1)
	makePart(f, { Name = "Column2", Shape = Enum.PartType.Cylinder, Size = Vector3.new(3, 1.4, 1.4), CFrame = CFrame.new(0, 9.6, 0) * CFrame.Angles(0, 0, math.rad(90)), Color = MARBLE, Material = Enum.Material.Marble })
	bowl("Top", 11.3, 2.6, 0.8)
	makePart(f, { Name = "Finial", Shape = Enum.PartType.Ball, Size = Vector3.new(1.4, 1.4, 1.4), CFrame = CFrame.new(0, 12.6, 0), Color = Color3.fromRGB(220, 180, 70), Material = Enum.Material.Metal })
	-- água caindo (partículas) no topo e nos jatinhos em volta
	local function spray(pos, speed, rate, size)
		local emitterPart = makePart(f, { Name = "Spray", Size = Vector3.new(0.4, 0.4, 0.4), CFrame = CFrame.new(pos), Transparency = 1, CanCollide = false })
		emitterPart.CanQuery = false
		local e = Instance.new("ParticleEmitter")
		e.Color = ColorSequence.new(Color3.fromRGB(200, 235, 255))
		e.LightEmission = 0.3
		e.Size = NumberSequence.new(size)
		e.Transparency = NumberSequence.new(0.2, 0.8)
		e.Lifetime = NumberRange.new(0.9, 1.3)
		e.Rate = rate
		e.Speed = NumberRange.new(speed)
		e.SpreadAngle = Vector2.new(25, 25)
		e.Acceleration = Vector3.new(0, -30, 0)
		e.EmissionDirection = Enum.NormalId.Top
		e.Parent = emitterPart
	end
	spray(Vector3.new(0, 13.2, 0), 12, 40, 0.6)
	for i = 0, 7 do
		spray(polar(i * 45 + 22.5, 9.5, 2.3), 10, 12, 0.4)
	end
	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(150, 210, 255)
	glow.Range = 16
	glow.Brightness = 0.8
	glow.Parent = f:FindFirstChild("BasinWater")

	-- Anel de flores em volta do chafariz
	for i = 1, 32 do
		local p = polar(i / 32 * 360, 13.6, 1.2)
		makePart(f, { Name = "Flower", Shape = Enum.PartType.Ball, Size = Vector3.new(1.5, 1.2, 1.5), CFrame = CFrame.new(p), Color = C.Flowers[(i % #C.Flowers) + 1], Material = Enum.Material.Grass, CanCollide = false })
	end

	-- 4 gramados com árvore/coreto e flores (nas diagonais, entre os caminhos)
	local function lawn(angleDeg)
		local center = polar(angleDeg, 30, 0)
		flatCylinder(f, "Lawn", center + Vector3.new(0, 1.0, 0), 9, 0.3, C.GrassDark, Enum.Material.Grass)
		flatCylinder(f, "LawnBorder", center + Vector3.new(0, 0.95, 0), 9.6, 0.25, MARBLE, Enum.Material.Marble)
		for k = 1, 10 do
			local p = center + polar(k * 36, 7.6, 1.6)
			makePart(f, { Name = "Flower", Shape = Enum.PartType.Ball, Size = Vector3.new(1.4, 1.1, 1.4), CFrame = CFrame.new(p), Color = C.Flowers[((k + angleDeg) % #C.Flowers) + 1], Material = Enum.Material.Grass, CanCollide = false })
		end
		return center
	end
	local lawns = {}
	for _, a in ipairs({ 45, 135, 225, 315 }) do
		lawns[a] = lawn(a)
	end
	buildTree(f, lawns[45] + Vector3.new(0, 1, 0), 1.3)
	buildTree(f, lawns[135] + Vector3.new(0, 1, 0), 1.3)
	buildTree(f, lawns[315] + Vector3.new(0, 1, 0), 1.2)

	-- Coreto (clássico de praça) no gramado de 225°
	local gz = model("Coreto", f)
	local gc = lawns[225]
	flatCylinder(gz, "Floor", gc + Vector3.new(0, 1.6, 0), 6.5, 1.2, MARBLE, Enum.Material.Marble)
	for k = 0, 7 do
		local p = gc + polar(k * 45, 5.8, 0)
		makePart(gz, { Name = "Column", Size = Vector3.new(0.5, 8, 0.5), CFrame = CFrame.new(p + Vector3.new(0, 6.2, 0)), Color = Color3.new(1, 1, 1) })
		local q = gc + polar(k * 45 + 45, 5.8, 0)
		if k ~= 2 then -- uma abertura para entrar
			makePart(gz, { Name = "Rail", Size = Vector3.new(0.25, 1.2, (q - p).Magnitude), CFrame = CFrame.lookAt((p + q) / 2 + Vector3.new(0, 3, 0), q + Vector3.new(0, 3, 0)), Color = Color3.new(1, 1, 1) })
		end
	end
	for k = 0, 7 do
		local p = gc + polar(k * 45 + 22.5, 3.4, 0)
		makePart(gz, {
			ClassName = "WedgePart",
			Name = "Roof",
			Size = Vector3.new(4.8, 2.6, 3.8),
			CFrame = CFrame.lookAt(p + Vector3.new(0, 11.4, 0), gc + Vector3.new(0, 11.4, 0)) * CFrame.Angles(0, math.pi, 0),
			Color = Color3.fromRGB(190, 70, 60),
		})
	end
	makePart(gz, { Name = "RoofTop", Shape = Enum.PartType.Ball, Size = Vector3.new(1.2, 1.2, 1.2), CFrame = CFrame.new(gc + Vector3.new(0, 13.1, 0)), Color = Color3.fromRGB(220, 180, 70), Material = Enum.Material.Metal })

	-- Letreiro da cidade atrás do chafariz, de frente para quem nasce
	local sign = model("LetreiroCidade", f)
	local signCf = CFrame.lookAt(Vector3.new(0, 0, -21), Vector3.new(0, 0, 20))
	makePart(sign, { Name = "Base", Size = Vector3.new(26, 1.6, 3), CFrame = signCf * CFrame.new(0, 1.7, 0), Color = MARBLE, Material = Enum.Material.Marble })
	local board = makePart(sign, { Name = "Board", Size = Vector3.new(24, 4, 0.6), CFrame = signCf * CFrame.new(0, 4.6, 0), Color = Color3.fromRGB(30, 80, 150) })
	for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 30
		gui.LightInfluence = 0
		gui.Parent = board
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.RichText = true
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		-- cada letra de uma cor (bem colorido)
		local colors = { "#FF6B6B", "#FFD93D", "#6BCB77", "#4D96FF", "#FF9F45", "#C77DFF" }
		local text, k = "", 0
		for _, ch in utf8.codes(GameConfig.CityName) do
			local c = utf8.char(ch)
			if c ~= " " then
				k += 1
			end
			text ..= ('<font color="%s">%s</font>'):format(colors[(k % #colors) + 1], c)
		end
		label.Text = text
		label.Parent = gui
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 3
		stroke.Color = Color3.new(1, 1, 1)
		stroke.Parent = label
	end
	for _, x in ipairs({ -12.5, 12.5 }) do
		makePart(sign, { Name = "Post", Size = Vector3.new(1, 6.6, 1), CFrame = signCf * CFrame.new(x, 3.3, 0), Color = MARBLE, Material = Enum.Material.Marble })
	end
	for _, x in ipairs({ -9, -3, 3, 9 }) do
		makePart(sign, { Name = "Flower", Shape = Enum.PartType.Ball, Size = Vector3.new(2, 1.6, 2), CFrame = signCf * CFrame.new(x, 2.8, -1.4), Color = C.Flowers[(x % #C.Flowers) + 1], Material = Enum.Material.Grass, CanCollide = false })
	end

	-- Bancos de madeira com pés de ferro, virados para o chafariz (sentar com E).
	-- Marco 9.4: sem os de 247,5° e 292,5°, que ficavam dentro do letreiro da cidade.
	for _, a in ipairs({ 22.5, 157.5, 202.5, 337.5 }) do
		local pos = polar(a, 21, 0.95)
		local cf = CFrame.lookAt(pos, Vector3.new(0, 0.95, 0))
		local bench = model("Bench", f)
		makePart(bench, { ClassName = "Seat", Name = "Seat", Size = Vector3.new(6, 0.4, 2), CFrame = cf * CFrame.new(0, 1.6, 0), Color = Color3.fromRGB(150, 95, 55), Material = Enum.Material.Wood })
		makePart(bench, { Name = "Back", Size = Vector3.new(6, 1.6, 0.3), CFrame = cf * CFrame.new(0, 2.8, 0.9) * CFrame.Angles(math.rad(-10), 0, 0), Color = Color3.fromRGB(150, 95, 55), Material = Enum.Material.Wood })
		for _, x in ipairs({ -2.6, 2.6 }) do
			makePart(bench, { Name = "Leg", Size = Vector3.new(0.3, 1.6, 2), CFrame = cf * CFrame.new(x, 0.8, 0.1), Color = IRON, Material = Enum.Material.Metal })
		end
	end

	-- Postes antigos (dois globos) e palmeiras no anel de fora
	local function oldLamp(pos)
		local lamp = model("PosteAntigo", f)
		makePart(lamp, { Name = "Pole", Size = Vector3.new(0.5, 9, 0.5), CFrame = CFrame.new(pos + Vector3.new(0, 5.4, 0)), Color = IRON, Material = Enum.Material.Metal })
		makePart(lamp, { Name = "Arm", Size = Vector3.new(3.2, 0.25, 0.25), CFrame = CFrame.new(pos + Vector3.new(0, 9.4, 0)), Color = IRON, Material = Enum.Material.Metal })
		for _, x in ipairs({ -1.6, 1.6 }) do
			local globe = makePart(lamp, { Name = "Globe", Shape = Enum.PartType.Ball, Size = Vector3.new(1.2, 1.2, 1.2), CFrame = CFrame.new(pos + Vector3.new(x, 10.1, 0)), Color = Color3.fromRGB(255, 245, 210), Material = Enum.Material.Neon })
			local l = Instance.new("PointLight")
			l.Range = 14
			l.Brightness = 0.8
			l.Color = Color3.fromRGB(255, 230, 180)
			l.Parent = globe
		end
	end
	for _, a in ipairs({ 0, 90 - 40, 90 + 40, 180, 270 }) do
		oldLamp(polar(a, 40, 0.95))
	end
	local function palm(pos)
		local p = model("Palmeira", f)
		local h = 14
		for k = 0, 6 do
			local y = 1 + k * (h / 7)
			makePart(p, { Name = "Trunk", Size = Vector3.new(1.1 - k * 0.06, h / 7 + 0.1, 1.1 - k * 0.06), CFrame = CFrame.new(pos + Vector3.new(k * 0.18, y + h / 14, 0)), Color = Color3.fromRGB(140, 110, 75), Material = Enum.Material.Wood })
		end
		local top = pos + Vector3.new(1.3, h + 1, 0)
		for k = 0, 6 do
			local a = math.rad(k * 360 / 7)
			local dir = Vector3.new(math.cos(a), 0, math.sin(a))
			makePart(p, { Name = "Leaf", Size = Vector3.new(1.4, 0.2, 6), CFrame = CFrame.lookAt(top + dir * 2.6, top + dir * 6) * CFrame.Angles(math.rad(-20), 0, 0), Color = Color3.fromRGB(60, 150, 60), Material = Enum.Material.Grass, CanCollide = false })
		end
	end
	for _, a in ipairs({ 22.5 + 45, 157.5 - 45, 202.5, 337.5 }) do
		palm(polar(a, 45, 0.95))
	end

	-- Cerca viva baixa na borda, com aberturas nas faixas de pedestre (a cada 45°)
	for i = 0, 7 do
		for _, half in ipairs({ -1, 1 }) do
			local a1 = i * 45 + half * 9
			local a2 = i * 45 + half * 36
			local p1, p2 = polar(a1, R - 2, 1.6), polar(a2, R - 2, 1.6)
			makePart(f, { Name = "Hedge", Size = Vector3.new(1.4, 1.4, (p2 - p1).Magnitude), CFrame = CFrame.lookAt((p1 + p2) / 2, p2), Color = C.Leaves[1], Material = Enum.Material.Grass })
		end
	end

	-- Carrinho de sorvete
	local cart = model("CarrinhoSorvete", f)
	local cartCf = CFrame.lookAt(polar(200, 33, 0.95), Vector3.new(0, 0.95, 0))
	makePart(cart, { Name = "Box", Size = Vector3.new(4, 2.6, 2.4), CFrame = cartCf * CFrame.new(0, 2.2, 0), Color = Color3.fromRGB(250, 245, 235) })
	makePart(cart, { Name = "Stripe", Size = Vector3.new(4.05, 0.5, 2.45), CFrame = cartCf * CFrame.new(0, 2.6, 0), Color = Color3.fromRGB(240, 120, 160) })
	makePart(cart, { Name = "Umbrella", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 6, 6), CFrame = cartCf * CFrame.new(0, 7, 0) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(240, 120, 160), CanCollide = false })
	makePart(cart, { Name = "UmbrellaPole", Size = Vector3.new(0.2, 3.6, 0.2), CFrame = cartCf * CFrame.new(0, 5.2, 0), Color = IRON })
	for _, x in ipairs({ -1.6, 1.6 }) do
		makePart(cart, { Name = "Wheel", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 1.4, 1.4), CFrame = cartCf * CFrame.new(x, 1.3, 1.3), Color = IRON })
	end
	for k = 0, 2 do
		makePart(cart, { Name = "Scoop", Shape = Enum.PartType.Ball, Size = Vector3.new(0.7, 0.7, 0.7), CFrame = cartCf * CFrame.new(-1 + k, 3.7, 0), Color = ({ Color3.fromRGB(250, 200, 220), Color3.fromRGB(140, 90, 60), Color3.fromRGB(250, 240, 200) })[k + 1] })
	end
end


local function buildLamp(parent, cf)
	local lamp = model("StreetLamp", parent)
	makePart(lamp, {
		Name = "Pole",
		Size = Vector3.new(0.6, 12, 0.6),
		CFrame = cf * CFrame.new(0, 6 + SIDEWALK_TOP, 0),
		Color = Color3.fromRGB(50, 55, 60),
		Material = Enum.Material.Metal,
	})
	local head = makePart(lamp, {
		Name = "Light",
		Size = Vector3.new(1.6, 0.8, 1.6),
		CFrame = cf * CFrame.new(0, 12.3 + SIDEWALK_TOP, 0),
		Color = Color3.fromRGB(255, 240, 200),
		Material = Enum.Material.Neon,
	})
	local light = Instance.new("PointLight")
	light.Range = 18
	light.Brightness = 1
	light.Color = Color3.fromRGB(255, 230, 180)
	light.Parent = head
end

---------------------------------------------------------------------------
-- Espaço ocupado: cada lote, rua e árvore vira um retângulo (visto de cima).
-- Nada é construído onde já existe algo: assim casas, lojas e ruas nunca se sobrepõem.
---------------------------------------------------------------------------

local blocks = {}

local function rect(cf, sizeX, sizeZ)
	local r, l = cf.RightVector, cf.LookVector
	return {
		c = Vector2.new(cf.X, cf.Z),
		ax = Vector2.new(r.X, r.Z).Unit,
		az = Vector2.new(l.X, l.Z).Unit,
		hx = sizeX / 2,
		hz = sizeZ / 2,
	}
end

local function reach(o, axis)
	return o.hx * math.abs(o.ax:Dot(axis)) + o.hz * math.abs(o.az:Dot(axis))
end

local function overlaps(a, b)
	for _, axis in ipairs({ a.ax, a.az, b.ax, b.az }) do
		if math.abs((b.c - a.c):Dot(axis)) > reach(a, axis) + reach(b, axis) then
			return false
		end
	end
	return true
end

local function isFree(o)
	local radius = math.sqrt(o.hx * o.hx + o.hz * o.hz)
	if o.c.Magnitude - radius < M.RoundaboutOuterRadius + M.SidewalkWidth + 3 then
		return false -- praça e rotatória
	end
	local edge = M.GroundSize / 2 - 4
	if math.abs(o.c.X) + radius > edge or math.abs(o.c.Y) + radius > edge then
		return false
	end
	for _, b in ipairs(blocks) do
		if overlaps(o, b) then
			return false
		end
	end
	return true
end

local function occupy(o)
	table.insert(blocks, o)
end

-- Trecho de rua: guarda para as construções não invadirem (asfalto + calçadas)
local roads = {} -- { a, b } em Vector3
local function addRoadArea(a, b)
	table.insert(roads, { a = a, b = b })
	local mid = (a + b) / 2
	local cf = CFrame.lookAt(mid, b)
	occupy(rect(cf, M.RoadWidth + 2 * M.SidewalkWidth + 1, (b - a).Magnitude + M.RoadWidth))
end

-- Lote ao lado de uma rua. t = distância desde o início do trecho; side = +1 direita, -1 esquerda.
-- Devolve o CFrame do centro do lote, com a frente (-Z) virada para a rua.
local function lotBeside(a, b, t, side, depth)
	local dir = (b - a).Unit
	local perp = Vector3.new(-dir.Z, 0, dir.X)
	local offset = M.RoadWidth / 2 + M.SidewalkWidth + 0.6 + depth / 2
	local center = a + dir * t + perp * side * offset
	return CFrame.lookAt(center, center - perp * side)
end

-- Marco 9: ponto na calçada em frente a um lote (onde o passageiro do táxi espera),
-- olhando para a rua. lot = CFrame do lote (frente -Z virada para a rua), depth = fundo do lote.
local function curbOf(lot, depth)
	return lot * CFrame.new(0, SIDEWALK_TOP, -(depth / 2 + 0.6 + M.SidewalkWidth * 0.55))
end

---------------------------------------------------------------------------
-- Ruas
---------------------------------------------------------------------------

local function sidewalkStrip(parent, a, b, side)
	local dir = (b - a).Unit
	local perp = Vector3.new(-dir.Z, 0, dir.X)
	local len = (b - a).Magnitude
	if len < 2 then
		return
	end
	local mid = (a + b) / 2 + perp * side * (M.RoadWidth / 2 + M.SidewalkWidth / 2)
	makePart(parent, {
		Name = "Sidewalk",
		Size = Vector3.new(M.SidewalkWidth, 1, len),
		CFrame = CFrame.lookAt(mid, mid + dir) + Vector3.new(0, SIDEWALK_TOP - 0.5, 0),
		Color = C.Sidewalk,
		Material = Enum.Material.Concrete,
	})
end

local function dashes(parent, a, b, skip)
	local dir = (b - a).Unit
	local len = (b - a).Magnitude
	for d = 10, len - 10, 14 do
		local p = a + dir * d
		local blocked = false
		for _, s in ipairs(skip or {}) do
			if (p - s).Magnitude < CROSSING_GAP then
				blocked = true
			end
		end
		if not blocked then
			makePart(parent, {
				Name = "Line",
				Size = Vector3.new(0.6, 0.1, 6),
				CFrame = CFrame.lookAt(p, p + dir) + Vector3.new(0, ROAD_TOP + 0.08, 0),
				Color = C.RoadLine,
				CanCollide = false,
				CastShadow = false,
			})
		end
	end
end

local function asphalt(parent, a, b, extra, lift)
	local mid = (a + b) / 2
	makePart(parent, {
		Name = "Asphalt",
		Size = Vector3.new(M.RoadWidth, 1, (b - a).Magnitude + extra),
		CFrame = CFrame.lookAt(mid, b) + Vector3.new(0, ROAD_TOP - 0.5 + lift, 0),
		Color = C.Asphalt,
		Material = Enum.Material.Asphalt,
	})
end

-- Faixa de pedestres atravessando a rua no ponto p
local function crosswalk(parent, p, dir)
	local perp = Vector3.new(-dir.Z, 0, dir.X)
	for i = -4, 4 do
		local s = p + perp * i * 2.4
		makePart(parent, {
			Name = "Crosswalk",
			Size = Vector3.new(1.4, 0.1, 5),
			CFrame = CFrame.lookAt(s, s + dir) + Vector3.new(0, ROAD_TOP + 0.08, 0),
			Color = C.RoadLine,
			CanCollide = false,
			CastShadow = false,
		})
	end
end

-- Marco 9.8: baia de ônibus no meio de cada trecho do anel do meio, do lado direito (onde ficam
-- as paradas): a calçada recua e o ônibus para fora da faixa, sem atrapalhar o trânsito.
local BAY_L, BAY_D = 46, 5
local BAY_TAPER = 12 -- rampa nas duas pontas da baia (o meio-fio vai em diagonal, não em degrau)

local function busBay(parent, a, b)
	local along = (b - a).Unit
	local perp = Vector3.new(-along.Z, 0, along.X)
	local mid = (a + b) / 2
	local function strip(name, lateral, width, len, y, h, color, material)
		local p = mid + perp * lateral
		makePart(parent, {
			Name = name,
			Size = Vector3.new(width, h, len),
			CFrame = CFrame.lookAt(p, p + along) + Vector3.new(0, y, 0),
			Color = color,
			Material = material,
		})
	end
	-- asfalto da baia (com as rampas) e o meio-fio que sobra da calçada atrás dela
	local full = BAY_L + 2 * BAY_TAPER
	strip("Baia", M.RoadWidth / 2 + BAY_D / 2, BAY_D, full, ROAD_TOP - 0.5 + 0.06, 1, C.Asphalt, Enum.Material.Asphalt)
	strip("Sidewalk", M.RoadWidth / 2 + BAY_D + (M.SidewalkWidth - BAY_D) / 2, M.SidewalkWidth - BAY_D, full, SIDEWALK_TOP - 0.5, 1, C.Sidewalk, Enum.Material.Concrete)
	-- Marco 9.8: rampas: triângulos de calçada nas pontas, o meio-fio entra em diagonal
	local lat = M.RoadWidth / 2 + BAY_D / 2
	for _, dirSign in ipairs({ -1, 1 }) do
		local zAxis = along * dirSign
		local yAxis = -perp
		local xAxis = yAxis:Cross(zAxis)
		local p = mid + perp * lat + along * dirSign * (BAY_L / 2 + BAY_TAPER / 2) + Vector3.new(0, SIDEWALK_TOP - 0.5, 0)
		makePart(parent, {
			ClassName = "WedgePart",
			Name = "Sidewalk",
			Size = Vector3.new(1, BAY_D, BAY_TAPER),
			CFrame = CFrame.fromMatrix(p, xAxis, yAxis, zAxis),
			Color = C.Sidewalk,
			Material = Enum.Material.Concrete,
		})
	end
end

local function buildRoads(parent, dirs)
	local f = folder("Roads", parent)
	local inner, outer = M.InnerRingRadius, RADIAL_END
	-- 8 ruas radiais; calçadas interrompidas onde cruzam os anéis
	for _, dir in ipairs(dirs) do
		local road = folder("Road", f)
		local a, b = dir * RADIAL_START, dir * RADIAL_END
		asphalt(road, a, b, 0, 0)
		addRoadArea(dir * (M.RoundaboutOuterRadius - 4), b)
		local cuts = {
			{ M.RoundaboutOuterRadius, inner - CROSSING_GAP },
			{ inner + CROSSING_GAP, outer - CROSSING_GAP },
		}
		for _, cut in ipairs(cuts) do
			for _, side in ipairs({ -1, 1 }) do
				sidewalkStrip(road, dir * cut[1], dir * cut[2], side)
			end
		end
		dashes(road, dir * (M.RoundaboutOuterRadius + 4), b, { dir * inner })
		crosswalk(road, dir * (M.RoundaboutOuterRadius + 10), dir)
	end
	-- Anel do meio e anel externo (octógonos ligando as radiais)
	for _, radius in ipairs({ inner, outer }) do
		local ring = folder(radius == inner and "InnerRing" or "OuterRing", f)
		for i, dir in ipairs(dirs) do
			local nextDir = dirs[(i % #dirs) + 1]
			local a, b = dir * radius, nextDir * radius
			asphalt(ring, a, b, M.RoadWidth, 0.06)
			addRoadArea(a, b)
			local along = (b - a).Unit
			local mid = (a + b) / 2
			for _, side in ipairs({ -1, 1 }) do
				if side == 1 then -- Marco 9.10: baias também no anel externo (Linha Contorno), do lado de fora
					sidewalkStrip(ring, a + along * CROSSING_GAP, mid - along * (BAY_L / 2 + BAY_TAPER), side)
					busBay(ring, a, b)
					sidewalkStrip(ring, mid + along * (BAY_L / 2 + BAY_TAPER), b - along * CROSSING_GAP, side)
				else
					sidewalkStrip(ring, a + along * CROSSING_GAP, b - along * CROSSING_GAP, side)
				end
			end
			dashes(ring, a, b, { a, b })
		end
	end
end

local function buildStreetLamps(parent, dirs)
	local lateral = M.RoadWidth / 2 + M.SidewalkWidth / 2 + 1
	for _, dir in ipairs(dirs) do
		local perp = Vector3.new(-dir.Z, 0, dir.X)
		local n = 0
		for d = M.RoundaboutOuterRadius + 30, RADIAL_END - 30, 60 do
			if math.abs(d - M.InnerRingRadius) > CROSSING_GAP + 4 then
				n += 1
				local side = (n % 2 == 0) and 1 or -1
				local p = dir * d + perp * side * lateral
				buildLamp(parent, CFrame.lookAt(p, p - perp * side))
			end
		end
	end
end

---------------------------------------------------------------------------
-- Casas (3 modelos: térrea com varanda, sobrado com sacada, casa com garagem)
---------------------------------------------------------------------------

local HOUSE_LOT_D = 38
local houseCount = 0

local function gableRoof(parent, cf, w, d, wallTop, color, wallColor)
	local angle = math.rad(28)
	local rise = (d / 2) * math.tan(angle)
	local slope = (d / 2) / math.cos(angle) + 1.6
	for _, side in ipairs({ -1, 1 }) do
		makePart(parent, {
			Name = "Roof",
			Size = Vector3.new(w + 2.4, 0.8, slope),
			CFrame = cf * CFrame.new(0, wallTop + rise / 2 + 0.3, side * d / 4) * CFrame.Angles(side * angle, 0, 0),
			Color = color,
		})
	end
	for _, x in ipairs({ -w / 2 + 0.5, w / 2 - 0.5 }) do
		for _, back in ipairs({ false, true }) do
			makePart(parent, {
				ClassName = "WedgePart",
				Name = "Gable",
				Size = Vector3.new(1, rise, d / 2),
				CFrame = cf * CFrame.new(x, wallTop + rise / 2, (back and 1 or -1) * d / 4) * (back and CFrame.Angles(0, math.pi, 0) or CFrame.new()),
				Color = wallColor,
			})
		end
	end
	return rise
end

-- Janela com moldura branca e peitoril
local function window(parent, cf, w, h)
	makePart(parent, { Name = "WindowFrame", Size = Vector3.new(w + 0.6, h + 0.6, 0.25), CFrame = cf, Color = Color3.fromRGB(250, 250, 248) })
	makePart(parent, { Name = "Window", Size = Vector3.new(w, h, 0.3), CFrame = cf * CFrame.new(0, 0, -0.05), Color = C.Window, Material = Enum.Material.SmoothPlastic, Transparency = 0.15 })
	makePart(parent, { Name = "Sill", Size = Vector3.new(w + 1, 0.3, 0.6), CFrame = cf * CFrame.new(0, -h / 2 - 0.4, -0.2), Color = Color3.fromRGB(250, 250, 248) })
end

local function bush(parent, pos, size)
	makePart(parent, {
		Name = "Bush",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(size, size * 0.8, size),
		CFrame = CFrame.new(pos + Vector3.new(0, size * 0.3, 0)),
		Color = C.Leaves[rng:NextInteger(1, #C.Leaves)],
		Material = Enum.Material.Grass,
		CanCollide = false,
	})
end

-- lotCf = centro do lote, frente (-Z) virada para a rua
-- address = { street = nome da rua, number = número na rua }
local function buildHouse(parent, lotCf, lotW, variant, address)
	houseCount += 1
	local id = houseCount -- número único (nome do modelo e do ponto de entrega)
	local number = address.number
	local house = model("Casa " .. id, parent)
	local wallColor = C.Walls[rng:NextInteger(1, #C.Walls)]
	local roofColor = C.Roofs[rng:NextInteger(1, #C.Roofs)]
	local garage = variant == 3
	local twoFloors = variant == 2
	local w = garage and (lotW - 22) or (lotW - 12)
	local d = 18
	local h = twoFloors and 20 or 11
	local frontZ = -HOUSE_LOT_D / 2 + 11 -- frente da casa (depois do jardim)
	local bodyX = garage and -5 or 0
	local cf = lotCf * CFrame.new(bodyX, 0, frontZ + d / 2)
	local front = -d / 2

	makePart(house, { Name = "Foundation", Size = Vector3.new(w + 2, 1, d + 2), CFrame = cf * CFrame.new(0, 0.5, 0), Color = C.Sidewalk, Material = Enum.Material.Concrete })
	makePart(house, { Name = "Walls", Size = Vector3.new(w, h, d), CFrame = cf * CFrame.new(0, 1 + h / 2, 0), Color = wallColor })
	makePart(house, { Name = "BaseBand", Size = Vector3.new(w + 0.2, 1.2, d + 0.2), CFrame = cf * CFrame.new(0, 1.6, 0), Color = Color3.fromRGB(150, 140, 130), Material = Enum.Material.Slate })
	gableRoof(house, cf, w, d, 1 + h, roofColor, wallColor)

	-- Porta com moldura e plaquinha do número
	makePart(house, { Name = "DoorFrame", Size = Vector3.new(5, 8, 0.3), CFrame = cf * CFrame.new(0, 1 + 4, front - 0.1), Color = Color3.fromRGB(250, 250, 248) })
	makePart(house, { Name = "Door", Size = Vector3.new(4, 7, 0.4), CFrame = cf * CFrame.new(0, 1 + 3.5, front - 0.2), Color = C.Door, Material = Enum.Material.Wood })
	local plate = makePart(house, { Name = "NumberPlate", Size = Vector3.new(1.6, 1, 0.1), CFrame = cf * CFrame.new(3.4, 1 + 6, front - 0.1), Color = Color3.fromRGB(30, 60, 110) })
	addSurfaceText(plate, tostring(number), Color3.new(1, 1, 1), Color3.fromRGB(30, 60, 110))

	-- Janelas do térreo (e do andar de cima no sobrado)
	local wx = math.min(w / 2 - 3.5, 7)
	for _, x in ipairs({ -wx, wx }) do
		window(house, cf * CFrame.new(x, 1 + 5.5, front - 0.15), 4, 4)
	end
	if twoFloors then
		for _, x in ipairs({ -wx, 0, wx }) do
			window(house, cf * CFrame.new(x, 1 + 15, front - 0.15), 3.6, 4)
		end
		-- Sacada com vidro
		makePart(house, { Name = "Balcony", Size = Vector3.new(8, 0.5, 3), CFrame = cf * CFrame.new(0, 1 + 11.2, front - 1.5), Color = Color3.fromRGB(240, 240, 238) })
		makePart(house, { Name = "BalconyGlass", Size = Vector3.new(8, 2.4, 0.2), CFrame = cf * CFrame.new(0, 1 + 12.6, front - 2.9), Color = Color3.fromRGB(200, 230, 245), Material = Enum.Material.SmoothPlastic, Transparency = 0.5 })
	else
		-- Varanda com colunas
		makePart(house, { Name = "Porch", Size = Vector3.new(math.min(w - 2, 14), 0.6, 5), CFrame = cf * CFrame.new(0, 1.3, front - 2.5), Color = Color3.fromRGB(170, 130, 95), Material = Enum.Material.WoodPlanks })
		local pw = math.min(w - 2, 14)
		for _, x in ipairs({ -pw / 2 + 0.5, pw / 2 - 0.5 }) do
			makePart(house, { Name = "Column", Size = Vector3.new(0.7, 7.5, 0.7), CFrame = cf * CFrame.new(x, 1.6 + 3.75, front - 4.5), Color = Color3.fromRGB(250, 250, 248) })
		end
		makePart(house, { Name = "PorchRoof", Size = Vector3.new(pw + 1, 0.5, 5.6), CFrame = cf * CFrame.new(0, 9.6, front - 2.6) * CFrame.Angles(math.rad(-10), 0, 0), Color = roofColor })
	end
	if rng:NextNumber() < 0.6 then
		makePart(house, { Name = "Chimney", Size = Vector3.new(2, 7, 2), CFrame = cf * CFrame.new(w / 2 - 4, 1 + h + 3, 3), Color = Color3.fromRGB(150, 80, 60), Material = Enum.Material.Brick })
	end

	-- Garagem ao lado
	if garage then
		local gcf = lotCf * CFrame.new(bodyX + w / 2 + 6, 0, frontZ + 7)
		makePart(house, { Name = "Garage", Size = Vector3.new(12, 9, 14), CFrame = gcf * CFrame.new(0, 1 + 4.5, 0), Color = wallColor })
		makePart(house, { Name = "GarageRoof", Size = Vector3.new(13, 0.6, 15), CFrame = gcf * CFrame.new(0, 10.3, 0), Color = roofColor })
		makePart(house, { Name = "GarageDoor", Size = Vector3.new(9, 7, 0.3), CFrame = gcf * CFrame.new(0, 1 + 3.5, -7.1), Color = Color3.fromRGB(235, 235, 235), Material = Enum.Material.DiamondPlate })
		makePart(house, { Name = "Driveway", Size = Vector3.new(9, 0.2, 12), CFrame = lotCf * CFrame.new(bodyX + w / 2 + 6, 0.6, -HOUSE_LOT_D / 2 + 6), Color = Color3.fromRGB(170, 170, 170), Material = Enum.Material.Concrete, CanCollide = false })
	end

	-- Caminho, cerca viva, caixa de correio e jardim
	local pathLen = 11 - (twoFloors and 0 or 5)
	makePart(house, { Name = "Path", Size = Vector3.new(3, 0.2, pathLen), CFrame = cf * CFrame.new(0, 0.6, front - (twoFloors and 0 or 5) - pathLen / 2), Color = C.Sidewalk, Material = Enum.Material.Concrete, CanCollide = false })
	local hedgeZ = -HOUSE_LOT_D / 2 + 0.8
	local hedgeLen = (lotW - 4) / 2 - 2.5
	for _, dir in ipairs({ -1, 1 }) do
		local x = dir * (2.5 + hedgeLen / 2)
		if not (garage and dir == 1) then
			makePart(house, { Name = "Hedge", Size = Vector3.new(hedgeLen, 1.8, 1.2), CFrame = lotCf * CFrame.new(x + (garage and 0 or 0), 0.9, hedgeZ), Color = C.Leaves[1], Material = Enum.Material.Grass })
		end
	end
	makePart(house, { Name = "MailPost", Size = Vector3.new(0.3, 3.4, 0.3), CFrame = lotCf * CFrame.new(-3.4, 1.7, hedgeZ - 0.3), Color = Color3.fromRGB(60, 60, 65) })
	local mailbox = makePart(house, { Name = "Mailbox", Size = Vector3.new(1, 0.9, 1.6), CFrame = lotCf * CFrame.new(-3.4, 3.6, hedgeZ - 0.3), Color = Color3.fromRGB(200, 60, 50), CanCollide = false })
	-- número também na caixa de correio (dá para ler da rua)
	local mailPlate = makePart(house, { Name = "MailNumber", Size = Vector3.new(0.9, 0.6, 0.05), CFrame = mailbox.CFrame * CFrame.new(0, 0, -0.83), Color = Color3.new(1, 1, 1), CanCollide = false })
	addSurfaceText(mailPlate, tostring(number), Color3.fromRGB(30, 60, 110), Color3.new(1, 1, 1))
	bush(house, (cf * CFrame.new(-w / 2 + 1.5, 0, front - 1.5)).Position, 2.6)
	bush(house, (cf * CFrame.new(w / 2 - 1.5, 0, front - 1.5)).Position, 2.6)
	if rng:NextNumber() < 0.5 then
		buildTree(house, (lotCf * CFrame.new(rng:NextNumber(-lotW / 2 + 4, lotW / 2 - 4), 0, HOUSE_LOT_D / 2 - 3)).Position, 0.9)
	end

	house:SetAttribute("HouseNumber", id)
	house:SetAttribute("Street", address.street)
	house:SetAttribute("StreetNumber", number)
	house:SetAttribute("Address", ("%s, %d"):format(address.street, number))
	house:SetAttribute("Curb", curbOf(lotCf, HOUSE_LOT_D))
	-- Nível da casa à venda (Marco 6.1): sobrado ou perto da praça = "sobrado"; o resto = "media"
	local nearPlaza = Vector3.new(cf.X, 0, cf.Z).Magnitude < M.NobreRadius
	house:SetAttribute("Tier", (twoFloors or nearPlaza) and "sobrado" or "media")
	return house
end

---------------------------------------------------------------------------
-- Prédios (comércio no térreo, apartamentos em cima). Só fachada por enquanto.
---------------------------------------------------------------------------

local BUSINESS = {
	"Padaria Pão Quente", "Farmácia Vida", "Café da Esquina", "Livraria Letra", "Sorveteria Gelato",
	"Barbearia do Zé", "Floricultura Flora", "Ótica Visão", "Lanchonete Sabor", "Academia Força",
	"Papelaria Arco-Íris", "Lavanderia Bolha", "Doceria Doce Lar", "Brinquedos Kinder", "Açougue Boi Bom",
}
local BUILDING_COLORS = {
	Color3.fromRGB(220, 200, 170), Color3.fromRGB(190, 120, 90), Color3.fromRGB(170, 190, 200),
	Color3.fromRGB(230, 225, 215), Color3.fromRGB(150, 160, 175), Color3.fromRGB(210, 170, 140),
	Color3.fromRGB(120, 170, 160),
}
local AWNINGS = {
	Color3.fromRGB(200, 60, 50), Color3.fromRGB(40, 120, 180), Color3.fromRGB(60, 150, 80),
	Color3.fromRGB(230, 160, 40), Color3.fromRGB(130, 80, 170),
}
local BUILDING_LOT_D = 34

local function buildBuilding(parent, lotCf, lotW, floors, address)
	local b = model("Predio", parent)
	local w, d = lotW - 4, BUILDING_LOT_D - 8
	local floorH = 7
	local groundH = 11 -- térreo alto (loja)
	local h = groundH + (floors - 1) * floorH
	local cf = lotCf * CFrame.new(0, 0, -BUILDING_LOT_D / 2 + 6 + d / 2)
	local front = -d / 2
	local color = BUILDING_COLORS[rng:NextInteger(1, #BUILDING_COLORS)]
	local trim = Color3.fromRGB(245, 245, 240)
	local awning = AWNINGS[rng:NextInteger(1, #AWNINGS)]

	makePart(b, { Name = "Plaza", Size = Vector3.new(lotW, 0.3, BUILDING_LOT_D), CFrame = lotCf * CFrame.new(0, 0.55, 0), Color = Color3.fromRGB(185, 180, 172), Material = Enum.Material.Concrete })
	makePart(b, { Name = "Body", Size = Vector3.new(w, h, d), CFrame = cf * CFrame.new(0, 0.7 + h / 2, 0), Color = color, Material = Enum.Material.SmoothPlastic })
	-- Térreo alto: vitrine, porta, toldo e letreiro. Toldo, letreiro e frisos não colidem
	-- (assim ninguém usa a fachada como escada para subir no prédio).
	makePart(b, { Name = "Shopfront", Size = Vector3.new(w - 4, 7.2, 0.3), CFrame = cf * CFrame.new(0, 0.7 + 4, front - 0.1), Color = Color3.fromRGB(180, 215, 235), Material = Enum.Material.SmoothPlastic, Transparency = 0.25 })
	makePart(b, { Name = "Door", Size = Vector3.new(4, 7, 0.4), CFrame = cf * CFrame.new(0, 0.7 + 3.5, front - 0.2), Color = Color3.fromRGB(60, 60, 65) })
	makePart(b, { Name = "Awning", Size = Vector3.new(w - 1, 0.4, 3.4), CFrame = cf * CFrame.new(0, 0.7 + 8.3, front - 1.6) * CFrame.Angles(math.rad(-14), 0, 0), Color = awning, CanCollide = false })
	local sign = makePart(b, { Name = "Sign", Size = Vector3.new(math.min(w - 6, 22), 1.8, 0.3), CFrame = cf * CFrame.new(0, 0.7 + 9.8, front - 0.2), Color = Color3.new(1, 1, 1), CanCollide = false })
	local business = BUSINESS[rng:NextInteger(1, #BUSINESS)]
	addSurfaceText(sign, business, awning, Color3.new(1, 1, 1))
	local plate = makePart(b, { Name = "NumberPlate", Size = Vector3.new(1.8, 1, 0.1), CFrame = cf * CFrame.new(3, 0.7 + 7.6, front - 0.25), Color = Color3.fromRGB(30, 60, 110), CanCollide = false })
	addSurfaceText(plate, tostring(address.number), Color3.new(1, 1, 1), Color3.fromRGB(30, 60, 110))
	-- Andares: janelas separadas por colunas, na frente e nas laterais + friso
	for f = 1, floors - 1 do
		local y = 0.7 + groundH + (f - 1) * floorH + floorH / 2
		local panes = math.max(2, math.floor((w - 2) / 7))
		local paneW = (w - 2) / panes
		for k = 0, panes - 1 do
			makePart(b, { Name = "Windows", Size = Vector3.new(paneW - 1, 3.6, 0.3), CFrame = cf * CFrame.new(-(w - 2) / 2 + paneW * (k + 0.5), y, front - 0.1), Color = C.Window, Material = Enum.Material.SmoothPlastic, Transparency = 0.1, CanCollide = false })
		end
		for _, side in ipairs({ -1, 1 }) do
			makePart(b, { Name = "Windows", Size = Vector3.new(0.3, 3.6, d - 4), CFrame = cf * CFrame.new(side * (w / 2 + 0.1), y, 0), Color = C.Window, Material = Enum.Material.SmoothPlastic, Transparency = 0.1, CanCollide = false })
		end
		makePart(b, { Name = "Ledge", Size = Vector3.new(w + 0.6, 0.4, 0.8), CFrame = cf * CFrame.new(0, y - floorH / 2, front - 0.3), Color = trim, CanCollide = false })
	end
	b:SetAttribute("Address", ("%s, %d"):format(address.street, address.number))
	b:SetAttribute("Business", business)
	b:SetAttribute("Curb", curbOf(lotCf, BUILDING_LOT_D))
	-- Topo: platibanda, caixa d'água e ar-condicionado
	makePart(b, { Name = "Parapet", Size = Vector3.new(w + 1, 1.2, d + 1), CFrame = cf * CFrame.new(0, 0.7 + h + 0.6, 0), Color = trim })
	makePart(b, { Name = "WaterTank", Shape = Enum.PartType.Cylinder, Size = Vector3.new(4, 4, 4), CFrame = cf * CFrame.new(w / 4, 0.7 + h + 2.5, d / 4) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(80, 120, 170) })
	makePart(b, { Name = "AC", Size = Vector3.new(3, 2, 3), CFrame = cf * CFrame.new(-w / 4, 0.7 + h + 1.6, -d / 6), Color = Color3.fromRGB(200, 200, 205), Material = Enum.Material.Metal })
	for _, x in ipairs({ -w / 2 + 2, w / 2 - 2 }) do
		local planter = makePart(b, { Name = "Planter", Size = Vector3.new(2.4, 1.2, 2.4), CFrame = lotCf * CFrame.new(x, 1.2, -BUILDING_LOT_D / 2 + 2.5), Color = Color3.fromRGB(120, 115, 110), Material = Enum.Material.Concrete })
		bush(b, planter.Position + Vector3.new(0, 0.4, 0), 2.2)
	end
	return b
end

-- Estabelecimento com interior (dá para entrar). Frente = lado -Z do cframe.
-- Aqui fica só o prédio (paredes, vitrine, porta aberta, teto, luzes, placa).
-- Os móveis e as estações de trabalho de dentro são montados pelo JobSiteBuilder,
-- que encontra o chão de dentro pelo atributo "BaseCFrame" da loja.
local SHOP_W, SHOP_D, SHOP_H = 44, 36, 21
local SHOP_YARD = 10 -- calçadinha entre a loja e a calçada da rua
local function buildShop(parent, cf, name, mainColor, accentColor)
	local W, D, H, T = SHOP_W, SHOP_D, SHOP_H, 1
	local FLOOR = 1 -- altura do chão de dentro
	local DOOR_W, DOOR_H = 6, 9
	local shop = model(name, parent)
	local base = cf * CFrame.new(0, FLOOR, 0)

	makePart(shop, {
		Name = "Yard",
		Size = Vector3.new(W + 6, 0.4, SHOP_YARD),
		CFrame = cf * CFrame.new(0, 0.6, -D / 2 - SHOP_YARD / 2),
		Color = Color3.fromRGB(150, 150, 150),
		Material = Enum.Material.Concrete,
	})
	makePart(shop, {
		Name = "Floor",
		Size = Vector3.new(W, FLOOR - 0.2, D),
		CFrame = cf * CFrame.new(0, 0.2 + (FLOOR - 0.2) / 2, 0),
		Color = Color3.fromRGB(225, 220, 210),
		Material = Enum.Material.SmoothPlastic,
	})

	local function wall(nameW, size, pos, color, material, transparency)
		return makePart(shop, {
			Name = nameW,
			Size = size,
			CFrame = base * CFrame.new(pos),
			Color = color or mainColor,
			Material = material or Enum.Material.SmoothPlastic,
			Transparency = transparency,
		})
	end

	-- Fundo e laterais
	wall("WallBack", Vector3.new(W, H, T), Vector3.new(0, H / 2, D / 2 - T / 2))
	wall("WallLeft", Vector3.new(T, H, D), Vector3.new(-W / 2 + T / 2, H / 2, 0))
	wall("WallRight", Vector3.new(T, H, D), Vector3.new(W / 2 - T / 2, H / 2, 0))

	-- Frente: mureta + vitrine dos dois lados da porta, faixa de cima inteira
	local sideW = (W - DOOR_W) / 2
	local zFront = -D / 2 + T / 2
	for _, dir in ipairs({ -1, 1 }) do
		local x = dir * (DOOR_W / 2 + sideW / 2)
		wall("WallFront", Vector3.new(sideW, 1.5, T), Vector3.new(x, 0.75, zFront))
		wall("Storefront", Vector3.new(sideW - 1, DOOR_H - 1.5, 0.3), Vector3.new(x, 1.5 + (DOOR_H - 1.5) / 2, zFront), Color3.fromRGB(190, 225, 245), Enum.Material.SmoothPlastic, 0.55)
		wall("WindowPost", Vector3.new(0.6, DOOR_H - 1.5, T), Vector3.new(dir * (W / 2 - 0.8), 1.5 + (DOOR_H - 1.5) / 2, zFront), accentColor)
		wall("DoorFrame", Vector3.new(0.6, DOOR_H, T + 0.2), Vector3.new(dir * (DOOR_W / 2 + 0.3), DOOR_H / 2, zFront), accentColor)
	end
	wall("WallFront", Vector3.new(W, H - DOOR_H, T), Vector3.new(0, DOOR_H + (H - DOOR_H) / 2, zFront))

	-- Teto, beiral e luzes de dentro
	wall("Ceiling", Vector3.new(W, 0.6, D), Vector3.new(0, H + 0.3, 0), Color3.fromRGB(245, 245, 240))
	wall("Parapet", Vector3.new(W + 1, 1.5, D + 1), Vector3.new(0, H + 1.35, 0), accentColor)
	for _, x in ipairs({ -W / 4, W / 4 }) do
		for _, z in ipairs({ -D / 4, D / 4 }) do
			local lamp = wall("CeilingLamp", Vector3.new(5, 0.2, 2), Vector3.new(x, H - 0.1, z), Color3.fromRGB(255, 250, 230), Enum.Material.Neon)
			lamp.CanCollide = false
			local light = Instance.new("PointLight")
			light.Range = 22
			light.Brightness = 1.2
			light.Color = Color3.fromRGB(255, 245, 225)
			light.Shadows = false
			light.Parent = lamp
		end
	end

	-- Toldo e placa
	makePart(shop, {
		Name = "Awning",
		Size = Vector3.new(W - 2, 0.5, 5),
		CFrame = base * CFrame.new(0, DOOR_H + 0.9, -D / 2 - 2.3) * CFrame.Angles(math.rad(-15), 0, 0),
		Color = accentColor,
		CanCollide = false, -- não serve de degrau para subir no telhado
	})
	local sign = makePart(shop, {
		Name = "Sign",
		Size = Vector3.new(W - 8, 5, 0.6),
		CFrame = base * CFrame.new(0, DOOR_H + 6, -D / 2 - 0.3),
		Color = Color3.new(1, 1, 1),
		CanCollide = false,
	})
	-- Fachada mais alta que o telhado (platibanda decorada na frente)
	wall("FrontCrown", Vector3.new(W + 1, 3, T + 0.4), Vector3.new(0, H + 1.5, -D / 2 + T / 2 - 0.2), accentColor)
	addSurfaceText(sign, name, accentColor, Color3.new(1, 1, 1))

	shop:SetAttribute("PlaceName", name)
	shop:SetAttribute("BaseCFrame", base) -- chão de dentro, olhando para a rua
	shop:SetAttribute("InteriorSize", Vector3.new(W - 2 * T, H, D - 2 * T))
	return shop
end

-- Placa de "em breve" no fim de uma rua
local function buildComingSoon(parent, cf, text)
	local sign = model("EmBreve", parent)
	for _, x in ipairs({ -5, 5 }) do
		makePart(sign, {
			Name = "Post",
			Size = Vector3.new(0.8, 9, 0.8),
			CFrame = cf * CFrame.new(x, 4.5, 0),
			Color = Color3.fromRGB(70, 70, 75),
			Material = Enum.Material.Metal,
		})
	end
	local board = makePart(sign, {
		Name = "Board",
		Size = Vector3.new(14, 4.5, 0.5),
		CFrame = cf * CFrame.new(0, 8, 0),
		Color = Color3.fromRGB(30, 80, 150),
	})
	addSurfaceText(board, text, Color3.new(1, 1, 1), Color3.fromRGB(30, 80, 150))
end

---------------------------------------------------------------------------
-- Garagem (Marco 6.3): guarita azul "24h" com 2 vagas, onde o jogador retira carro ou bike
-- (o VehicleService põe o aviso "Abrir garagem" no balcão). Frente do lote (-Z) virada para a rua.
---------------------------------------------------------------------------

local GARAGE_W, GARAGE_D = 38, 26
local GARAGE_BLUE = Color3.fromRGB(40, 70, 150)

local function buildGarage(parent, lot, name)
	local g = model(name, parent)
	g:SetAttribute("Garage", true)
	local function at(x, y, z)
		return lot * CFrame.new(x, y, z)
	end
	-- Piso de asfalto na altura da calçada, faixas amarelas das vagas
	makePart(g, { Name = "Floor", Size = Vector3.new(GARAGE_W, 0.4, GARAGE_D), CFrame = at(0, SIDEWALK_TOP - 0.2, 0), Color = C.Asphalt, Material = Enum.Material.Asphalt })
	for _, x in ipairs({ -18, -6.5, 5 }) do
		makePart(g, { Name = "Line", Size = Vector3.new(0.35, 0.05, 20), CFrame = at(x, SIDEWALK_TOP + 0.02, 1.5), Color = Color3.fromRGB(245, 200, 40), CanCollide = false })
	end
	-- Vagas: o carro aparece aqui, de frente para a rua
	for k, x in ipairs({ -12.25, -0.75 }) do
		local vaga = makePart(g, { Name = "Vaga" .. k, Size = Vector3.new(1, 1, 1), CFrame = at(x, SIDEWALK_TOP + 0.5, 1.5), Transparency = 1, CanCollide = false })
		vaga.CanQuery = false
		vaga.CanTouch = false
	end
	-- Guarita
	local bx, bz = 13.5, 4
	local floorY = SIDEWALK_TOP
	makePart(g, { Name = "BoothBase", Size = Vector3.new(8, 1.4, 8), CFrame = at(bx, floorY + 0.7, bz), Color = GARAGE_BLUE })
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			makePart(g, { Name = "Pillar", Size = Vector3.new(0.6, 6, 0.6), CFrame = at(bx + sx * 3.7, floorY + 4.4, bz + sz * 3.7), Color = Color3.fromRGB(235, 235, 235) })
		end
	end
	-- vidros nos lados e atrás; na frente, metade vidro e metade porta aberta
	local glass = { Color = Color3.fromRGB(170, 200, 220), Material = Enum.Material.SmoothPlastic, Transparency = 0.5 }
	local function pane(size, cf)
		makePart(g, { Name = "Window", Size = size, CFrame = cf, Color = glass.Color, Material = glass.Material, Transparency = glass.Transparency })
	end
	pane(Vector3.new(0.2, 4, 6.8), at(bx - 3.7, floorY + 4, bz))
	pane(Vector3.new(0.2, 4, 6.8), at(bx + 3.7, floorY + 4, bz))
	makePart(g, { Name = "BackWall", Size = Vector3.new(6.8, 6, 0.3), CFrame = at(bx, floorY + 4.4, bz + 3.7), Color = Color3.fromRGB(235, 235, 235) })
	pane(Vector3.new(3.4, 4, 0.2), at(bx + 1.7, floorY + 4, bz - 3.7))
	makePart(g, { Name = "WindowSill", Size = Vector3.new(3.4, 0.3, 0.6), CFrame = at(bx + 1.7, floorY + 1.95, bz - 3.6), Color = Color3.fromRGB(235, 235, 235) })
	-- teto azul com letreiro "GARAGEM 24H" virado para a rua
	makePart(g, { Name = "Roof", Size = Vector3.new(9, 0.6, 9), CFrame = at(bx, floorY + 7.7, bz), Color = Color3.fromRGB(235, 235, 235) })
	local sign = makePart(g, { Name = "Sign", Size = Vector3.new(9, 1.6, 0.4), CFrame = at(bx, floorY + 8.8, bz - 4.3), Color = GARAGE_BLUE })
	addSurfaceText(sign, "GARAGEM 24H", Color3.new(1, 1, 1), GARAGE_BLUE)
	makePart(g, { Name = "SignTop", Size = Vector3.new(9, 1.6, 8.6), CFrame = at(bx, floorY + 8.8, bz), Color = GARAGE_BLUE })
	-- balcão (o aviso "Abrir garagem" fica nele), cadeira e luz
	makePart(g, { Name = "Balcao", Size = Vector3.new(3.2, 0.3, 1.2), CFrame = at(bx + 1.7, floorY + 3.3, bz - 3.1), Color = Color3.fromRGB(150, 100, 60) })
	makePart(g, { Name = "Chair", Size = Vector3.new(1.4, 1.6, 1.4), CFrame = at(bx + 1.7, floorY + 2.2, bz - 0.5), Color = Color3.fromRGB(40, 40, 45) })
	local lamp = makePart(g, { Name = "Lamp", Size = Vector3.new(2, 0.2, 2), CFrame = at(bx, floorY + 7.3, bz), Color = Color3.fromRGB(255, 250, 230), Material = Enum.Material.Neon, CanCollide = false })
	local light = Instance.new("PointLight")
	light.Range = 18
	light.Brightness = 1.2
	light.Parent = lamp
	-- placa "P" na entrada e cancela listrada
	makePart(g, { Name = "PPost", Size = Vector3.new(0.4, 7, 0.4), CFrame = at(-18, floorY + 3.5, -11.5), Color = Color3.fromRGB(70, 70, 75), Material = Enum.Material.Metal })
	local p = makePart(g, { Name = "PSign", Size = Vector3.new(2.6, 2.6, 0.25), CFrame = at(-18, floorY + 7.5, -11.6), Color = GARAGE_BLUE })
	addSurfaceText(p, "P", Color3.new(1, 1, 1), GARAGE_BLUE)
	makePart(g, { Name = "BarrierPost", Size = Vector3.new(0.8, 2.6, 0.8), CFrame = at(9, floorY + 1.3, -11.8), Color = Color3.fromRGB(245, 200, 40) })
	for k = 0, 4 do
		makePart(g, {
			Name = "BarrierArm",
			Size = Vector3.new(1.6, 0.35, 0.35),
			CFrame = at(9 + 1.2 + k * 1.6, floorY + 2.3, -11.8),
			Color = k % 2 == 0 and Color3.fromRGB(220, 40, 40) or Color3.new(1, 1, 1),
			CanCollide = false,
		})
	end
	return g
end

---------------------------------------------------------------------------
-- LXR Táxis (Marco 9): garagem dos táxis com escritório amarelo e 3 vagas cobertas.
-- É uma garagem de serviço (ServiceJob = "Taxista"): só o Taxista tira o Táxi LXR aqui.
-- Frente do lote (-Z) virada para a rua.
---------------------------------------------------------------------------

local TAXI_W, TAXI_D = 56, 30
local TAXI_YELLOW = Color3.fromRGB(250, 204, 20)
local TAXI_BLACK = Color3.fromRGB(25, 25, 28)

local function buildTaxiStand(parent, lot)
	local g = model("LXRTaxis", parent)
	g:SetAttribute("Garage", true)
	g:SetAttribute("ServiceJob", "Taxista")
	g:SetAttribute("PlaceName", GameConfig.Places.Taxi)
	local function at(x, y, z)
		return lot * CFrame.new(x, y, z)
	end
	local floorY = SIDEWALK_TOP
	makePart(g, { Name = "Floor", Size = Vector3.new(TAXI_W, 0.4, TAXI_D), CFrame = at(0, floorY - 0.2, 0), Color = C.Asphalt, Material = Enum.Material.Asphalt })
	-- 3 vagas (o táxi aparece de frente para a rua) com faixas amarelas
	for _, x in ipairs({ -26, -15, -4, 7 }) do
		makePart(g, { Name = "Line", Size = Vector3.new(0.35, 0.05, 20), CFrame = at(x, floorY + 0.02, 2), Color = TAXI_YELLOW, CanCollide = false })
	end
	for k, x in ipairs({ -20.5, -9.5, 1.5 }) do
		local vaga = makePart(g, { Name = "Vaga" .. k, Size = Vector3.new(1, 1, 1), CFrame = at(x, floorY + 0.5, 2), Transparency = 1, CanCollide = false })
		vaga.CanQuery = false
		vaga.CanTouch = false
		local mark = makePart(g, { Name = "TaxiMark", Size = Vector3.new(5, 0.05, 2.4), CFrame = at(x, floorY + 0.03, 10), Color = TAXI_YELLOW, CanCollide = false })
		addSurfaceText(mark, "TÁXI", TAXI_BLACK, TAXI_YELLOW)
	end
	-- cobertura alta em cima das vagas, com faixa xadrez na frente
	makePart(g, { Name = "Cobertura", Size = Vector3.new(36, 0.8, 24), CFrame = at(-9.5, floorY + 12, 3), Color = Color3.fromRGB(235, 235, 235), Material = Enum.Material.Metal })
	for i = 0, 17 do
		makePart(g, { Name = "Xadrez", Size = Vector3.new(2, 1, 0.3), CFrame = at(-9.5 - 17 + i * 2, floorY + 11.2, -9.1), Color = i % 2 == 0 and TAXI_BLACK or TAXI_YELLOW, CanCollide = false })
	end
	for _, x in ipairs({ -27, 8 }) do
		for _, z in ipairs({ -8, 14 }) do
			makePart(g, { Name = "Pilar", Size = Vector3.new(0.8, 12, 0.8), CFrame = at(x, floorY + 6, z), Color = TAXI_BLACK, Material = Enum.Material.Metal })
		end
	end
	-- escritório amarelo com vitrine e letreiro
	local ox, oz, ow, od, oh = 19.5, 4, 15, 16, 10
	makePart(g, { Name = "Escritorio", Size = Vector3.new(ow, oh, od), CFrame = at(ox, floorY + oh / 2, oz), Color = TAXI_YELLOW })
	makePart(g, { Name = "Vitrine", Size = Vector3.new(ow - 3, 5, 0.3), CFrame = at(ox, floorY + 4, oz - od / 2 - 0.1), Color = Color3.fromRGB(170, 200, 220), Material = Enum.Material.SmoothPlastic, Transparency = 0.3 })
	for i = 0, 7 do
		makePart(g, { Name = "Xadrez", Size = Vector3.new(ow / 8, 0.8, 0.3), CFrame = at(ox - ow / 2 + ow / 16 + i * ow / 8, floorY + 7.2, oz - od / 2 - 0.1), Color = i % 2 == 0 and TAXI_BLACK or Color3.new(1, 1, 1), CanCollide = false })
	end
	makePart(g, { Name = "Telhado", Size = Vector3.new(ow + 1, 0.6, od + 1), CFrame = at(ox, floorY + oh + 0.3, oz), Color = TAXI_BLACK })
	local sign = makePart(g, { Name = "Sign", Size = Vector3.new(ow, 2.4, 0.4), CFrame = at(ox, floorY + oh + 1.8, oz - od / 2), Color = TAXI_BLACK, CanCollide = false })
	addSurfaceText(sign, GameConfig.Places.Taxi, TAXI_YELLOW, TAXI_BLACK)
	-- balcão na frente do escritório (o aviso "Abrir garagem" fica nele) e toldo
	makePart(g, { Name = "Balcao", Size = Vector3.new(4, 3.4, 1.6), CFrame = at(ox, floorY + 1.7, oz - od / 2 - 2), Color = TAXI_BLACK })
	makePart(g, { Name = "Toldo", Size = Vector3.new(ow, 0.3, 4), CFrame = at(ox, floorY + 8.6, oz - od / 2 - 2) * CFrame.Angles(math.rad(-12), 0, 0), Color = TAXI_YELLOW, CanCollide = false })
	-- placa de ponto de táxi na calçada
	makePart(g, { Name = "PostePonto", Size = Vector3.new(0.4, 8, 0.4), CFrame = at(ox, floorY + 4, -TAXI_D / 2 + 1.5), Color = Color3.fromRGB(70, 70, 75), Material = Enum.Material.Metal })
	local ponto = makePart(g, { Name = "PlacaPonto", Size = Vector3.new(4.4, 2.2, 0.3), CFrame = at(ox, floorY + 8.6, -TAXI_D / 2 + 1.5), Color = TAXI_YELLOW, CanCollide = false })
	addSurfaceText(ponto, "PONTO DE TÁXI", TAXI_BLACK, TAXI_YELLOW)
	local lamp = makePart(g, { Name = "Lamp", Size = Vector3.new(6, 0.2, 2), CFrame = at(-9.5, floorY + 11.5, 3), Color = Color3.fromRGB(255, 250, 230), Material = Enum.Material.Neon, CanCollide = false })
	local light = Instance.new("PointLight")
	light.Range = 24
	light.Brightness = 1
	light.Parent = lamp
	return g
end

---------------------------------------------------------------------------
-- Marco 9: Um Tijo (empresa de ônibus). Garagem só para o Motorista de ônibus (ServiceJob),
-- com 2 baias cobertas, escritório e balcão. Frente do lote (-Z) virada para a rua.
---------------------------------------------------------------------------

local BUS_W, BUS_D = 156, 120
local BUS_GREEN = Color3.fromRGB(30, 130, 80)

local function buildBusTerminal(parent, lot)
	local g = model("UmTijo", parent)
	g:SetAttribute("Garage", true)
	g:SetAttribute("ServiceJob", "Motorista")
	g:SetAttribute("PlaceName", GameConfig.Places.Onibus)
	local function at(x, y, z)
		return lot * CFrame.new(x, y, z)
	end
	-- Marco 9.8: terminal bem maior, longe da cidade. Frente (-Z) para a avenida; à esquerda as
	-- 6 plataformas cobertas (teto bem alto: a câmera de 3ª pessoa não bate nele), à direita o
	-- prédio do terminal com o balcão (o aviso "Abrir garagem") e uma pracinha na frente.
	local floorY = ROAD_TOP + 0.1 -- quase na altura da avenida: o ônibus sai direto
	local WHITE = Color3.fromRGB(240, 240, 236)
	local GREY = Color3.fromRGB(70, 72, 78)
	local CONCRETE = Color3.fromRGB(200, 198, 190)
	local ROOF_Y = floorY + 30
	makePart(g, { Name = "Floor", Size = Vector3.new(BUS_W, 0.6, BUS_D), CFrame = at(0, floorY - 0.3, 0), Color = C.Asphalt, Material = Enum.Material.Asphalt })

	-- plataformas: 6 baias (o ônibus aparece de frente para a avenida) com ilhas de embarque
	local bays = {}
	for k = 1, 6 do
		bays[k] = -66 + (k - 1) * 17
	end
	for k, x in ipairs(bays) do
		local vaga = makePart(g, { Name = "Vaga" .. k, Size = Vector3.new(1, 1, 1), CFrame = at(x, floorY + 0.5, 8), Transparency = 1, CanCollide = false })
		vaga.CanQuery = false
		vaga.CanTouch = false
		local mark = makePart(g, { Name = "Numero", Size = Vector3.new(5, 0.05, 5), CFrame = at(x, floorY + 0.03, -14), Color = BUS_GREEN, CanCollide = false })
		addSurfaceText(mark, tostring(k), Color3.new(1, 1, 1), BUS_GREEN)
		-- placa pendurada com o número da plataforma
		local placa = makePart(g, { Name = "PlacaPlataforma", Size = Vector3.new(6, 3, 0.4), CFrame = at(x, floorY + 18, -11), Color = BUS_GREEN, CanCollide = false })
		addSurfaceText(placa, "PLATAFORMA " .. k, Color3.new(1, 1, 1), BUS_GREEN)
		for _, dx in ipairs({ -2.2, 2.2 }) do
			makePart(g, { Name = "Cabo", Size = Vector3.new(0.15, ROOF_Y - floorY - 19.5, 0.15), CFrame = at(x + dx, (ROOF_Y + floorY + 19.5) / 2, -11), Color = GREY, CanCollide = false })
		end
	end
	-- ilhas de embarque entre as baias (calçada baixa com bancos e lixeira)
	for k = 0, 6 do
		local x = bays[1] - 8.5 + k * 17
		makePart(g, { Name = "Ilha", Size = Vector3.new(4.5, 0.6, 34), CFrame = at(x, floorY + 0.3, 9), Color = CONCRETE, Material = Enum.Material.Concrete })
		makePart(g, { Name = "FaixaAmarela", Size = Vector3.new(4.6, 0.05, 0.6), CFrame = at(x, floorY + 0.62, -7.7), Color = Color3.fromRGB(250, 200, 30), CanCollide = false })
		if k > 0 and k < 6 then
			for _, z in ipairs({ 4, 16 }) do
				makePart(g, { Name = "Banco", Size = Vector3.new(1.4, 0.4, 5), CFrame = at(x, floorY + 1.9, z), Color = Color3.fromRGB(120, 85, 55), Material = Enum.Material.Wood })
				makePart(g, { Name = "PeBanco", Size = Vector3.new(1, 1.4, 0.4), CFrame = at(x, floorY + 1.1, z), Color = GREY })
			end
		end
	end
	-- cobertura alta: laje, beirais verdes, faixas de claraboia e luminárias
	local roofW, roofZ0, roofZ1 = 17 * 6 + 6, -16, 32
	local roofX = (bays[1] + bays[6]) / 2
	local roofD = roofZ1 - roofZ0
	makePart(g, { Name = "Cobertura", Size = Vector3.new(roofW, 0.8, roofD), CFrame = at(roofX, ROOF_Y, (roofZ0 + roofZ1) / 2), Color = WHITE, Material = Enum.Material.Metal })
	for _, z in ipairs({ roofZ0, roofZ1 }) do
		makePart(g, { Name = "Beiral", Size = Vector3.new(roofW + 0.4, 2.4, 0.6), CFrame = at(roofX, ROOF_Y - 0.4, z), Color = BUS_GREEN })
	end
	for _, x in ipairs({ roofX - roofW / 2, roofX + roofW / 2 }) do
		makePart(g, { Name = "Beiral", Size = Vector3.new(0.6, 2.4, roofD), CFrame = at(x, ROOF_Y - 0.4, (roofZ0 + roofZ1) / 2), Color = BUS_GREEN })
	end
	for k = 0, 6 do
		local x = bays[1] - 8.5 + k * 17
		for _, z in ipairs({ roofZ0 + 2, roofZ1 - 2 }) do
			makePart(g, { Name = "Pilar", Size = Vector3.new(1.4, ROOF_Y - floorY, 1.4), CFrame = at(x, (ROOF_Y + floorY) / 2, z), Color = WHITE, Material = Enum.Material.Metal })
		end
		makePart(g, { Name = "Viga", Size = Vector3.new(1, 1.6, roofD), CFrame = at(x, ROOF_Y - 1.2, (roofZ0 + roofZ1) / 2), Color = GREY, Material = Enum.Material.Metal })
	end
	for k = 1, 6 do
		makePart(g, { Name = "Claraboia", Size = Vector3.new(8, 0.3, roofD - 8), CFrame = at(bays[k], ROOF_Y + 0.5, (roofZ0 + roofZ1) / 2), Color = Color3.fromRGB(200, 230, 245), Transparency = 0.4, CanCollide = false })
		local lamp = makePart(g, { Name = "Lamp", Size = Vector3.new(1.2, 0.3, roofD - 10), CFrame = at(bays[k], ROOF_Y - 0.6, (roofZ0 + roofZ1) / 2), Color = Color3.fromRGB(255, 250, 230), Material = Enum.Material.Neon, CanCollide = false })
		local light = Instance.new("PointLight")
		light.Range = 40
		light.Brightness = 1.2
		light.Parent = lamp
	end
	-- letreiro grande na frente da cobertura
	local front = makePart(g, { Name = "Letreiro", Size = Vector3.new(60, 5, 0.6), CFrame = at(roofX, ROOF_Y + 3.2, roofZ0), Color = BUS_GREEN, CanCollide = false })
	addSurfaceText(front, "TERMINAL " .. string.upper(GameConfig.Places.Onibus) .. " 🚌", Color3.new(1, 1, 1), BUS_GREEN)

	-- prédio do terminal (2 andares) com vitrine, faixa verde, letreiro e balcão
	local ox, oz, ow, od, oh = 54, 8, 36, 52, 22
	local zf = oz - od / 2 -- fachada
	makePart(g, { Name = "Escritorio", Size = Vector3.new(ow, oh, od), CFrame = at(ox, floorY + oh / 2, oz), Color = WHITE })
	makePart(g, { Name = "Faixa", Size = Vector3.new(ow + 0.2, 1.6, od + 0.2), CFrame = at(ox, floorY + 10.4, oz), Color = BUS_GREEN, CanCollide = false })
	makePart(g, { Name = "Vitrine", Size = Vector3.new(ow - 6, 7, 0.3), CFrame = at(ox, floorY + 4.6, zf - 0.1), Color = Color3.fromRGB(150, 190, 215), Material = Enum.Material.SmoothPlastic, Transparency = 0.3, Reflectance = 0.15 })
	for k = 0, 4 do
		makePart(g, { Name = "Janela", Size = Vector3.new(5, 5, 0.3), CFrame = at(ox - 14 + k * 7, floorY + 16, zf - 0.1), Color = Color3.fromRGB(110, 150, 180), Material = Enum.Material.SmoothPlastic, Reflectance = 0.15 })
	end
	makePart(g, { Name = "Telhado", Size = Vector3.new(ow + 1.4, 0.8, od + 1.4), CFrame = at(ox, floorY + oh + 0.4, oz), Color = GREY })
	local sign = makePart(g, { Name = "Sign", Size = Vector3.new(ow, 4, 0.4), CFrame = at(ox, floorY + oh + 2.8, zf), Color = BUS_GREEN, CanCollide = false })
	addSurfaceText(sign, GameConfig.Places.Onibus .. " 🚌", Color3.new(1, 1, 1), BUS_GREEN)
	makePart(g, { Name = "Balcao", Size = Vector3.new(4, 3.4, 1.6), CFrame = at(ox, floorY + 1.7, zf - 2), Color = BUS_GREEN })
	makePart(g, { Name = "Toldo", Size = Vector3.new(ow, 0.3, 5), CFrame = at(ox, floorY + 9.4, zf - 2.4) * CFrame.Angles(math.rad(-10), 0, 0), Color = BUS_GREEN, CanCollide = false })

	-- pracinha na frente do prédio: piso, árvores, bancos e postes
	local plazaD = BUS_D / 2 + zf
	makePart(g, { Name = "Praca", Size = Vector3.new(ow + 8, 0.7, plazaD - 4), CFrame = at(ox, floorY + 0.05, -BUS_D / 2 + 2 + (plazaD - 4) / 2), Color = CONCRETE, Material = Enum.Material.Concrete })
	for _, x in ipairs({ ox - 15, ox + 15 }) do
		-- árvore de peças sem sortear nada (buildTree usa o rng do mapa: mudaria as casas da cidade)
		makePart(g, { Name = "Tronco", Size = Vector3.new(1.3, 6, 1.3), CFrame = at(x, floorY + 3.4, -BUS_D / 2 + 10), Color = C.Trunk, Material = Enum.Material.Wood })
		makePart(g, { Name = "Copa", Shape = Enum.PartType.Ball, Size = Vector3.new(8, 8, 8), CFrame = at(x, floorY + 9.5, -BUS_D / 2 + 10), Color = C.Leaves[1], Material = Enum.Material.Grass })
		makePart(g, { Name = "Banco", Size = Vector3.new(5, 0.4, 1.4), CFrame = at(x, floorY + 1.9, -BUS_D / 2 + 16), Color = Color3.fromRGB(120, 85, 55), Material = Enum.Material.Wood })
	end
	for _, x in ipairs({ -BUS_W / 2 + 3, 30, BUS_W / 2 - 3 }) do
		buildLamp(g, at(x, floorY - SIDEWALK_TOP + 0.4, -BUS_D / 2 + 3))
	end
	-- muro baixo no fundo e nos lados (a frente fica aberta para a avenida), com canteiros
	for _, w in ipairs({ { 0, BUS_D / 2 - 0.5, BUS_W, 1 }, { -BUS_W / 2 + 0.5, 0, 1, BUS_D }, { BUS_W / 2 - 0.5, 0, 1, BUS_D } }) do
		makePart(g, { Name = "Muro", Size = Vector3.new(w[3], 3, w[4]), CFrame = at(w[1], floorY + 1.5, w[2]), Color = WHITE })
	end
	makePart(g, { Name = "Canteiro", Size = Vector3.new(4, 1, BUS_D - 30), CFrame = at(BUS_W / 2 - 3, floorY + 0.5, 12), Color = Color3.fromRGB(80, 150, 60), Material = Enum.Material.Grass })
	return g
end

-- Marco 9.7: abrigo 3D (modelos do Luís, tools/paradaprep.py) em ServerStorage > CarModels
-- ("ParadaA", "ParadaB"). Fica com SHELTER_H de altura, de costas para "cf" (frente -Z para a rua),
-- com o fundo encostado em "cf". Devolve nil se o modelo não existir (aí o abrigo é de peças).
local SHELTER_H = 8
local function placeShelter(parent, name, cf)
	local holder = ServerStorage:FindFirstChild("CarModels")
	local tpl = holder and holder:FindFirstChild(name)
	if not tpl then
		return nil
	end
	local m = tpl:Clone()
	local front, ground
	local parts = {}
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			local names = d.Name .. " " .. (d.Parent and d.Parent.Name or "")
			if names:find("FrontMarker") then
				front = d
			elseif names:find("GroundMarker") then
				ground = d
			else
				table.insert(parts, d)
			end
		end
	end
	local function box()
		local mn, mx = Vector3.new(math.huge, math.huge, math.huge), Vector3.new(-math.huge, -math.huge, -math.huge)
		for _, p in ipairs(parts) do
			local h = p.Size / 2
			for _, sx in ipairs({ -1, 1 }) do
				for _, sy in ipairs({ -1, 1 }) do
					for _, sz in ipairs({ -1, 1 }) do
						local c = p.CFrame * Vector3.new(h.X * sx, h.Y * sy, h.Z * sz)
						mn, mx = mn:Min(c), mx:Max(c)
					end
				end
			end
		end
		return mn, mx
	end
	if #parts == 0 then
		m:Destroy()
		return nil
	end
	local mn, mx = box()
	m:ScaleTo(m:GetScale() * SHELTER_H / math.max(mx.Y - mn.Y, 0.01))
	mn, mx = box()
	local center = (mn + mx) / 2
	local dir = Vector3.new(0, 0, -1)
	if front then
		local d = front.Position - center
		dir = math.abs(d.X) > math.abs(d.Z) and Vector3.new(math.sign(d.X), 0, 0) or Vector3.new(0, 0, math.sign(d.Z))
	end
	local depth = math.abs(dir.X) > 0 and (mx.X - mn.X) or (mx.Z - mn.Z)
	local floor = Vector3.new(center.X, ground and ground.Position.Y or mn.Y, center.Z)
	local base = CFrame.lookAt(floor, floor + dir)
	local place = cf * CFrame.new(0, 0, -depth / 2)
	for _, p in ipairs(parts) do
		p.CFrame = place * base:ToObjectSpace(p.CFrame)
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
	end
	if front then
		front:Destroy()
	end
	if ground then
		ground:Destroy()
	end
	m.Name = "Abrigo"
	m.Parent = parent
	return m
end

-- Marco 9: paradas de ônibus no anel do meio (a linha circular do Motorista de ônibus).
-- Uma no meio de cada trecho, do lado direito de quem anda de dirs[k] para dirs[k+1]: abrigo
-- com banco e placa na calçada e faixa amarela no asfalto. Cada parada é uma peça "Parada" em
-- Map > PontosOnibus com os atributos Curb (onde os passageiros esperam, olhando a rua),
-- Order (posição na linha, começando perto da Um Tijo) e Label.
-- Marco 9.10: paradas 1 a 8 no anel do meio e 9 a 16 no anel externo (Linha Contorno). As
-- linhas (JobConfig.Bus.Lines) usam essas paradas em ordens diferentes.
local function buildBusStops(parent, dirs, firstDir)
	local stops = folder("PontosOnibus", parent)
	local yellow = Color3.fromRGB(250, 200, 30)
	for idx = 1, 2 * #dirs do
		local outerRing = idx > #dirs
		local k = (idx - 1) % #dirs + 1
		local dir = dirs[k]
		local radius = outerRing and RADIAL_END or M.InnerRingRadius
		local a, b = dir * radius, dirs[(k % #dirs) + 1] * radius
		local along = (b - a).Unit
		local perp = Vector3.new(-along.Z, 0, along.X) -- lado direito de quem anda de a para b
		local mid = (a + b) / 2
		local order = ((k - firstDir) % #dirs) + 1 + (outerRing and #dirs or 0)
		local function on(lateral, y, fwd)
			local p = mid + perp * lateral + along * (fwd or 0)
			return CFrame.lookAt(Vector3.new(p.X, y, p.Z), Vector3.new(p.X, y, p.Z) - perp) -- frente (-Z) para a rua
		end
		local m = model("Parada" .. order, stops)
		-- abrigo: fundo de vidro, teto, 2 colunas e banco (só enfeite)
		-- Marco 9.8: o ônibus para na baia (BAY_L); abrigo e passageiros logo depois dela, na
		-- calçada inteira, perto da porta da frente
		local ahead = BAY_L / 2 + BAY_TAPER + 5
		local back = M.RoadWidth / 2 + M.SidewalkWidth - 0.6
		local shelter = on(back, SIDEWALK_TOP, ahead)
		-- Marco 9.7: abrigo 3D do Luís (alternando os 2 modelos); sem ele, o de peças
		local model3d = placeShelter(m, order % 2 == 1 and "ParadaA" or "ParadaB", on(M.RoadWidth / 2 + M.SidewalkWidth + 0.3, SIDEWALK_TOP, ahead))
		if not model3d then
			makePart(m, { Name = "Fundo", Size = Vector3.new(9, 4.5, 0.25), CFrame = shelter * CFrame.new(0, 2.6, 0), Color = Color3.fromRGB(180, 215, 230), Material = Enum.Material.SmoothPlastic, Transparency = 0.4 })
			makePart(m, { Name = "Teto", Size = Vector3.new(10, 0.35, 3.4), CFrame = shelter * CFrame.new(0, 5.1, -1.3), Color = BUS_GREEN })
			for _, x in ipairs({ -4.5, 4.5 }) do
				makePart(m, { Name = "Coluna", Size = Vector3.new(0.3, 5, 0.3), CFrame = shelter * CFrame.new(x, 2.5, 0), Color = Color3.fromRGB(60, 60, 64), Material = Enum.Material.Metal })
			end
			makePart(m, { Name = "Banco", Size = Vector3.new(6, 0.35, 1.2), CFrame = shelter * CFrame.new(0, 1.5, -0.9), Color = Color3.fromRGB(120, 85, 55), Material = Enum.Material.Wood })
		end
		local placa = makePart(m, { Name = "Placa", Size = Vector3.new(3.2, 1.6, 0.2), CFrame = shelter * CFrame.new(9, 6.2, -0.6), Color = BUS_GREEN, CanCollide = false })
		addSurfaceText(placa, "🚌 " .. (outerRing and ("C" .. (order - #dirs)) or tostring(order)), Color3.new(1, 1, 1), BUS_GREEN)
		makePart(m, { Name = "Poste", Size = Vector3.new(0.3, 7, 0.3), CFrame = shelter * CFrame.new(9, 3.5, -0.6), Color = Color3.fromRGB(60, 60, 64), Material = Enum.Material.Metal })
		-- faixa amarela no asfalto (onde o ônibus para)
		local lane = makePart(m, { Name = "Faixa", Size = Vector3.new(BAY_L - 8, 0.05, 8), CFrame = on(M.RoadWidth / 2 + BAY_D - 4.6, ROAD_TOP + 0.09, 0), Color = yellow, Transparency = 0.35, CanCollide = false })
		-- Marco 9.8: "ÔNIBUS" escrito como faixa de rua de verdade: atravessado na pista e de pé
		-- para quem chega dirigindo (lido de trás para frente da baia)
		local textCf = lane.CFrame * CFrame.new(BAY_L / 2 - 14, 0.01, 0)
		local textPart = makePart(m, { Name = "FaixaTexto", Size = Vector3.new(7, 0.05, 5), CFrame = CFrame.lookAt(textCf.Position, textCf.Position + along), Transparency = 1, CanCollide = false })
		textPart.CanQuery = false
		textPart.CanTouch = false
		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Top
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 30
		gui.Parent = textPart
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBlack
		label.TextScaled = true
		label.TextColor3 = Color3.fromRGB(60, 50, 10)
		label.Text = "ÔNIBUS"
		label.Parent = gui
		local point = makePart(m, { Name = "Parada", Size = Vector3.new(2, 2, 2), CFrame = on(M.RoadWidth / 2 + BAY_D - 4.6, ROAD_TOP + 1, 0), Transparency = 1, CanCollide = false })
		point.CanQuery = false
		point.CanTouch = false
		point:SetAttribute("Curb", on(M.RoadWidth / 2 + M.SidewalkWidth * 0.45, SIDEWALK_TOP, BAY_L / 2 + BAY_TAPER + 1))
		point:SetAttribute("Order", order)
		point:SetAttribute("Label", outerRing and ("Parada Contorno %d"):format(order - #dirs) or ("Parada %d"):format(order))
	end
	return stops
end

---------------------------------------------------------------------------
-- Loja de pintura (Marco 6.4): galpão com cabine de pintura, longe da cidade, no fim de uma
-- estradinha que sai do anel externo. O carro entra de frente pela abertura, para no quadrado
-- colorido ("PaintPad") e o jogador usa o aviso "Pintar carro" no totem ("PaintPost").
-- Frente do lote (-Z) virada para a estradinha.
---------------------------------------------------------------------------

local PAINT_W, PAINT_D, PAINT_H = 46, 42, 17
local RAINBOW = {
	Color3.fromRGB(230, 50, 50), Color3.fromRGB(245, 140, 30), Color3.fromRGB(250, 210, 40),
	Color3.fromRGB(60, 180, 80), Color3.fromRGB(40, 120, 220), Color3.fromRGB(140, 70, 200),
}

local function buildPaintRoad(parent, dir)
	local P = GameConfig.PaintShop
	local a, b = dir * RADIAL_END, dir * (RADIAL_END + P.RoadLength)
	local f = folder("PaintRoad", parent)
	asphalt(f, a, b, 0, 0.02)
	dashes(f, a, b, { a })
	return a, b
end

local function buildPaintShop(parent, lot)
	local s = model("PaintShop", parent)
	local function at(x, y, z)
		return lot * CFrame.new(x, y, z)
	end
	local W, D, H = PAINT_W, PAINT_D, PAINT_H
	local top = ROAD_TOP + 0.1 -- piso quase na altura da rua: o carro entra direto
	local WALL = Color3.fromRGB(240, 240, 236)
	local DARK = Color3.fromRGB(45, 48, 55)
	-- Piso de concreto e "garagem" coberta no fundo (z de -6 até o fundo)
	makePart(s, { Name = "Floor", Size = Vector3.new(W, 0.6, D), CFrame = at(0, top - 0.3, 0), Color = Color3.fromRGB(175, 178, 182), Material = Enum.Material.Concrete })
	local backZ, frontZ = D / 2, -6
	local roofLen = backZ - frontZ
	makePart(s, { Name = "BackWall", Size = Vector3.new(W, H, 1), CFrame = at(0, top + H / 2, backZ - 0.5), Color = WALL, Material = Enum.Material.Concrete })
	for _, sx in ipairs({ -1, 1 }) do
		makePart(s, { Name = "SideWall", Size = Vector3.new(1, H, roofLen), CFrame = at(sx * (W / 2 - 0.5), top + H / 2, (backZ + frontZ) / 2), Color = WALL, Material = Enum.Material.Concrete })
		-- faixas arco-íris na lateral, por fora
		for k, color in ipairs(RAINBOW) do
			makePart(s, { Name = "Stripe", Size = Vector3.new(0.2, 0.7, roofLen - 2), CFrame = at(sx * (W / 2 + 0.05), top + 3 + k * 0.7, (backZ + frontZ) / 2), Color = color, CanCollide = false })
		end
	end
	makePart(s, { Name = "Roof", Size = Vector3.new(W + 2, 1, roofLen + 2), CFrame = at(0, top + H + 0.5, (backZ + frontZ) / 2), Color = DARK })
	-- frente: viga com o letreiro e faixa arco-íris
	makePart(s, { Name = "FrontBeam", Size = Vector3.new(W + 2, 3, 1), CFrame = at(0, top + H - 1.5, frontZ), Color = WALL })
	local sign = makePart(s, { Name = "Sign", Size = Vector3.new(30, 4.2, 0.6), CFrame = at(0, top + H + 3, frontZ - 0.2), Color = DARK })
	addSurfaceText(sign, string.upper(GameConfig.PaintShop.Name), Color3.new(1, 1, 1), DARK)
	for k, color in ipairs(RAINBOW) do
		local w = (W + 2) / #RAINBOW
		makePart(s, { Name = "FrontStripe", Size = Vector3.new(w, 0.6, 1.1), CFrame = at(-(W + 2) / 2 + w * (k - 0.5), top + H - 3.3, frontZ), Color = color, CanCollide = false })
	end
	-- Cabine: quadrado colorido no chão onde o carro para
	local padZ = 7
	local pad = makePart(s, { Name = "PaintPad", Size = Vector3.new(16, 0.1, 24), CFrame = at(0, top + 0.05, padZ), Color = Color3.fromRGB(60, 64, 72), CanCollide = false, CastShadow = false })
	pad.CanQuery = false
	for k, color in ipairs(RAINBOW) do
		local z = padZ - 12 + (k - 0.5) * (24 / #RAINBOW)
		for _, sx in ipairs({ -1, 1 }) do
			makePart(s, { Name = "PadEdge", Size = Vector3.new(0.6, 0.12, 24 / #RAINBOW), CFrame = at(sx * 8, top + 0.06, z), Color = color, CanCollide = false, CastShadow = false })
		end
	end
	-- luzes fortes no teto (neon) em cima da cabine
	for _, x in ipairs({ -6, 0, 6 }) do
		local lamp = makePart(s, { Name = "BoothLight", Size = Vector3.new(1.2, 0.3, 20), CFrame = at(x, top + H - 0.2, padZ), Color = Color3.fromRGB(255, 252, 240), Material = Enum.Material.Neon, CanCollide = false })
		if x == 0 then
			local light = Instance.new("PointLight")
			light.Range = 28
			light.Brightness = 1.2
			light.Parent = lamp
		end
	end
	-- 2 braços de pistola de pintura (um de cada lado da cabine)
	for _, sx in ipairs({ -1, 1 }) do
		local x = sx * 13
		makePart(s, { Name = "SprayStand", Size = Vector3.new(1, 9, 1), CFrame = at(x, top + 4.5, padZ), Color = Color3.fromRGB(90, 95, 105), Material = Enum.Material.Metal })
		makePart(s, { Name = "SprayArm", Size = Vector3.new(3.5, 0.6, 0.6), CFrame = at(x - sx * 1.75, top + 8.5, padZ), Color = Color3.fromRGB(90, 95, 105), Material = Enum.Material.Metal })
		makePart(s, { Name = "SprayGun", Size = Vector3.new(1.2, 0.9, 0.9), CFrame = at(x - sx * 3.6, top + 8.1, padZ), Color = RAINBOW[sx < 0 and 1 or 5] })
	end
	-- Totem "Pintar carro" (o aviso fica nele) ao lado da entrada da cabine
	local post = makePart(s, { Name = "PaintPost", Size = Vector3.new(2.4, 6, 1.2), CFrame = at(-11, top + 3, -3), Color = DARK })
	addSurfaceText(post, "PINTAR", Color3.new(1, 1, 1), RAINBOW[5])
	-- latas de tinta coloridas no fundo
	for k, color in ipairs(RAINBOW) do
		for j = 0, 1 do
			local can = makePart(s, { Name = "PaintCan", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.4, 1.3, 1.3), CFrame = at(-16 + k * 2, top + 0.7 + j * 1.4, backZ - 2) * CFrame.Angles(0, 0, math.rad(90)), Color = color })
			can.CanCollide = false
		end
	end
	makePart(s, { Name = "Shelf", Size = Vector3.new(14, 0.3, 2), CFrame = at(-9, top + 3.3, backZ - 2), Color = Color3.fromRGB(150, 100, 60) })
	return s
end

---------------------------------------------------------------------------
-- Árvores soltas e parques nos espaços livres
---------------------------------------------------------------------------

local function buildRandomTrees(parent)
	local half = M.TreeArea / 2 - 10 -- Marco 10: o chão cresceu; as árvores soltas ficam perto da cidade
	local placed, attempts = 0, 0
	while placed < M.RandomTrees and attempts < 6000 do
		attempts += 1
		local p = Vector3.new(rng:NextNumber(-half, half), 0, rng:NextNumber(-half, half))
		local spot = rect(CFrame.new(p), 7, 7)
		if isFree(spot) then
			occupy(spot)
			buildTree(parent, p, rng:NextNumber(0.85, 1.4))
			placed += 1
		end
	end
end

local function setupLighting()
	Lighting.ClockTime = 14
	-- Marco 9.14: sol um pouco mais fraco e exposição menor: as paredes brancas "estouravam"
	Lighting.Brightness = 1.6
	Lighting.GlobalShadows = true
	-- Marco 7.4: luz ambiente mais baixa e menos reflexo do céu: com os valores antigos as cores
	-- ficavam "lavadas" (brancão), principalmente nos lugares claros. PROVISÓRIO até o Luís testar.
	Lighting.OutdoorAmbient = Color3.fromRGB(105, 105, 115)
	Lighting.Ambient = Color3.fromRGB(85, 85, 92) -- interior das lojas claro, sem estourar
	Lighting.EnvironmentDiffuseScale = 0.35
	Lighting.EnvironmentSpecularScale = 0.35
	Lighting.ExposureCompensation = -0.2
	-- Marco 10.20: o Luís pediu para tirar o céu que foi posto à mão no Studio ("Simple Sunset Sky"):
	-- ele mudava o reflexo de alguns modelos. Fica o céu padrão do Roblox.
	for _, sky in ipairs(Lighting:GetChildren()) do
		if sky:IsA("Sky") then
			sky:Destroy()
		end
	end
	local bloom = Lighting:FindFirstChildOfClass("BloomEffect") or Instance.new("BloomEffect")
	bloom.Intensity = 0.2
	bloom.Size = 18
	bloom.Threshold = 2.2
	bloom.Parent = Lighting
	local grade = Lighting:FindFirstChild("CoresDaCidade") or Instance.new("ColorCorrectionEffect")
	grade.Name = "CoresDaCidade"
	grade.Saturation = 0.12
	grade.Contrast = 0.08
	grade.Brightness = -0.03
	grade.Parent = Lighting
	if not Lighting:FindFirstChildOfClass("Atmosphere") then
		local atm = Instance.new("Atmosphere")
		atm.Density = 0.25
		atm.Color = Color3.fromRGB(200, 220, 240)
		atm.Decay = Color3.fromRGB(110, 140, 170)
		atm.Parent = Lighting
	end
end


---------------------------------------------------------------------------
-- Montagem completa
---------------------------------------------------------------------------

-- Preenche um lado de um trecho de rua com lotes (casas ou prédios) onde couber
local function fillSide(parent, a, b, tStart, tEnd, side, kind, gap, street)
	local t = tStart
	while t <= tEnd do
		local isHouse = kind == "house" or (kind == "mix" and rng:NextNumber() < 0.65)
		local variant = isHouse and rng:NextInteger(1, 3) or nil
		local lotW = isHouse and (variant == 3 and 46 or rng:NextInteger(34, 38)) or rng:NextInteger(32, 40)
		local lotD = isHouse and HOUSE_LOT_D or BUILDING_LOT_D
		local lot = lotBeside(a, b, t, side, lotD)
		local area = rect(lot, lotW + 2, lotD)
		if isFree(area) then
			occupy(area)
			local address = { street = street.name, number = takeNumber(street, side) }
			if isHouse then
				buildHouse(parent.houses, lot, lotW, variant, address)
			else
				local floors = math.clamp(3 + math.floor(t / 110) + rng:NextInteger(0, 2), 3, 10)
				buildBuilding(parent.buildings, lot, lotW, floors, address)
			end
			t += lotW / 2 + (gap or 6) + 20
		else
			t += 6
		end
	end
end

---------------------------------------------------------------------------
-- Vila Esperança (Marco 6.1): bairro humilde, casinhas coloridas, onde todo jogador começa
---------------------------------------------------------------------------

local VILA_COLORS = {
	Color3.fromRGB(255, 170, 90),
	Color3.fromRGB(120, 200, 230),
	Color3.fromRGB(240, 120, 130),
	Color3.fromRGB(250, 215, 90),
	Color3.fromRGB(150, 210, 120),
	Color3.fromRGB(190, 150, 230),
}
local VILA_LOT_W, VILA_LOT_D = 18, 24

local function buildVilaHouse(parent, lot, address, k)
	houseCount += 1
	local id = houseCount
	local house = model("Casa " .. id, parent)
	local w, d, h = 12, 10, 8
	local cf = lot * CFrame.new(0, 0, -VILA_LOT_D / 2 + 6 + d / 2)
	local front = -d / 2
	local wallColor = VILA_COLORS[(k % #VILA_COLORS) + 1]
	makePart(house, { Name = "Foundation", Size = Vector3.new(w + 1, 0.6, d + 1), CFrame = cf * CFrame.new(0, 0.3, 0), Color = Color3.fromRGB(170, 165, 155), Material = Enum.Material.Concrete })
	makePart(house, { Name = "Walls", Size = Vector3.new(w, h, d), CFrame = cf * CFrame.new(0, 0.6 + h / 2, 0), Color = wallColor, Material = Enum.Material.Plaster })
	-- telhado de telha ondulada, um pouco inclinado para trás
	makePart(house, { Name = "Roof", Size = Vector3.new(w + 1.4, 0.3, d + 1.6), CFrame = cf * CFrame.new(0, 0.6 + h + 0.35, 0) * CFrame.Angles(math.rad(6), 0, 0), Color = ({ Color3.fromRGB(150, 150, 155), Color3.fromRGB(185, 95, 65) })[(k % 2) + 1], Material = Enum.Material.CorrodedMetal })
	-- caixa d'água azul
	makePart(house, { Name = "WaterTank", Shape = Enum.PartType.Cylinder, Size = Vector3.new(2.2, 3, 3), CFrame = cf * CFrame.new(w / 2 - 2.2, 0.6 + h + 1.6, d / 2 - 2.2) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(40, 110, 200) })
	-- porta, janela com grade, número pintado
	makePart(house, { Name = "DoorFrame", Size = Vector3.new(4, 7, 0.3), CFrame = cf * CFrame.new(-2.5, 0.6 + 3.5, front - 0.1), Color = Color3.fromRGB(250, 250, 245) })
	makePart(house, { Name = "Door", Size = Vector3.new(3.4, 6.4, 0.4), CFrame = cf * CFrame.new(-2.5, 0.6 + 3.2, front - 0.2), Color = ({ Color3.fromRGB(60, 120, 180), Color3.fromRGB(170, 70, 60), Color3.fromRGB(70, 140, 80) })[(k % 3) + 1], Material = Enum.Material.Wood })
	makePart(house, { Name = "WindowFrame", Size = Vector3.new(3.4, 3, 0.3), CFrame = cf * CFrame.new(3, 0.6 + 4.4, front - 0.1), Color = Color3.new(1, 1, 1) })
	makePart(house, { Name = "WindowGlass", Size = Vector3.new(2.8, 2.4, 0.32), CFrame = cf * CFrame.new(3, 0.6 + 4.4, front - 0.1), Color = Color3.fromRGB(150, 200, 230), Material = Enum.Material.SmoothPlastic, Transparency = 0.2 })
	for i = -1, 1 do
		makePart(house, { Name = "WindowBar", Size = Vector3.new(0.12, 2.4, 0.36), CFrame = cf * CFrame.new(3 + i * 0.7, 0.6 + 4.4, front - 0.12), Color = Color3.fromRGB(50, 50, 55), CanCollide = false })
	end
	local plate = makePart(house, { Name = "NumberPlate", Size = Vector3.new(1.4, 1, 0.1), CFrame = cf * CFrame.new(-0.2, 0.6 + 6.3, front - 0.1), Color = Color3.new(1, 1, 1) })
	addSurfaceText(plate, tostring(address.number), Color3.fromRGB(40, 40, 50), Color3.new(1, 1, 1))
	-- varal com roupas coloridas no quintal da frente
	local lineA = cf * CFrame.new(-w / 2 + 0.5, 0, front - 3.5)
	local lineB = cf * CFrame.new(w / 2 - 0.5, 0, front - 3.5)
	for _, p in ipairs({ lineA, lineB }) do
		makePart(house, { Name = "VaralPost", Size = Vector3.new(0.25, 5, 0.25), CFrame = p * CFrame.new(0, 2.5, 0), Color = Color3.fromRGB(120, 90, 60), Material = Enum.Material.Wood })
	end
	makePart(house, { Name = "Varal", Size = Vector3.new(w - 1, 0.06, 0.06), CFrame = cf * CFrame.new(0, 4.8, front - 3.5), Color = Color3.fromRGB(230, 230, 230), CanCollide = false })
	for i = 0, 2 do
		makePart(house, { Name = "Roupa", Size = Vector3.new(1.3, 1.5, 0.08), CFrame = cf * CFrame.new(-3 + i * 2.6 + (k % 2), 4.0, front - 3.5), Color = VILA_COLORS[((k + i + 2) % #VILA_COLORS) + 1], Material = Enum.Material.Fabric, CanCollide = false })
	end
	-- vaso de planta na porta
	makePart(house, { Name = "Vaso", Size = Vector3.new(1, 1, 1), CFrame = cf * CFrame.new(-5, 1.1, front - 0.9), Color = Color3.fromRGB(190, 100, 60), Material = Enum.Material.Slate })
	makePart(house, { Name = "Folhas", Shape = Enum.PartType.Ball, Size = Vector3.new(1.4, 1.4, 1.4), CFrame = cf * CFrame.new(-5, 2.1, front - 0.9), Color = Color3.fromRGB(80, 160, 70), Material = Enum.Material.Grass, CanCollide = false })

	house:SetAttribute("HouseNumber", id)
	house:SetAttribute("Street", address.street)
	house:SetAttribute("StreetNumber", address.number)
	house:SetAttribute("Address", ("%s, %d"):format(address.street, address.number))
	house:SetAttribute("Tier", "basica")
	house:SetAttribute("Curb", curbOf(lot, VILA_LOT_D) - Vector3.new(0, SIDEWALK_TOP - 0.35, 0)) -- calçada de terra é mais baixa
	return house
end

-- Rua da vila: continua a rua "Dir" depois do anel externo. Chamar ANTES de encher o anel
-- externo, para nenhuma casa do anel ficar em cima dela.
local function buildVilaRoad(parent, dir)
	local V = M.Vila
	local a, b = dir * RADIAL_END, dir * (RADIAL_END + V.Length)
	local f = folder("Vila", parent)
	asphalt(f, a, b, 0, 0.02)
	addRoadArea(a, b)
	-- "calçada" de terra batida dos dois lados
	local perp = Vector3.new(-dir.Z, 0, dir.X)
	for _, side in ipairs({ -1, 1 }) do
		local mid = (a + b) / 2 + perp * side * (M.RoadWidth / 2 + M.SidewalkWidth / 2)
		makePart(f, { Name = "Terra", Size = Vector3.new(M.SidewalkWidth, 1, V.Length - 10), CFrame = CFrame.lookAt(mid, mid + dir) + Vector3.new(0, 0.05 - 0.5 + 0.3, 0), Color = Color3.fromRGB(170, 130, 90), Material = Enum.Material.Ground })
	end
	return a, b, f
end

local function buildVila(groups, props, a, b, f)
	local V = M.Vila
	local dir = (b - a).Unit
	local perp = Vector3.new(-dir.Z, 0, dir.X)
	local street = newStreet(V.StreetName)
	local k = 0
	for t = 40, V.Length - 16, VILA_LOT_W + 4 do
		for _, side in ipairs({ -1, 1 }) do
			local lot = lotBeside(a, b, t, side, VILA_LOT_D)
			local area = rect(lot, VILA_LOT_W, VILA_LOT_D)
			if isFree(area) then
				occupy(area)
				k += 1
				buildVilaHouse(groups.houses, lot, { street = street.name, number = takeNumber(street, side) }, k)
			end
		end
	end
	-- Portal de entrada colorido
	local gate = model("PortalVila", props)
	local gp = a + dir * 16
	for _, side in ipairs({ -1, 1 }) do
		local p = gp + perp * side * (M.RoadWidth / 2 + 2)
		makePart(gate, { Name = "Post", Size = Vector3.new(1.2, 13, 1.2), CFrame = CFrame.new(p + Vector3.new(0, 6.5, 0)), Color = Color3.fromRGB(240, 150, 60), Material = Enum.Material.Wood })
	end
	local board = makePart(gate, { Name = "Board", Size = Vector3.new(M.RoadWidth + 6, 3, 0.5), CFrame = CFrame.lookAt(gp + Vector3.new(0, 12, 0), gp + Vector3.new(0, 12, 0) - dir), Color = Color3.fromRGB(250, 215, 90), Material = Enum.Material.Wood, CanCollide = false })
	addSurfaceText(board, V.Name, Color3.fromRGB(150, 60, 40), Color3.fromRGB(250, 215, 90))
	occupy(rect(CFrame.lookAt(gp, gp + dir), M.RoadWidth + 8, 4))
	-- Campinho de futebol no fim da rua
	local fieldCf = CFrame.lookAt(b + dir * 22, b + dir * 40)
	local area = rect(fieldCf, 30, 44)
	if isFree(area) then
		occupy(area)
		makePart(f, { Name = "Campinho", Size = Vector3.new(30, 0.2, 44), CFrame = fieldCf * CFrame.new(0, 0.1, 0), Color = Color3.fromRGB(175, 140, 95), Material = Enum.Material.Ground })
		makePart(f, { Name = "LinhaMeio", Size = Vector3.new(30, 0.22, 0.4), CFrame = fieldCf * CFrame.new(0, 0.11, 0), Color = Color3.new(1, 1, 1), CanCollide = false })
		for _, z in ipairs({ -21, 21 }) do
			for _, x in ipairs({ -4, 4 }) do
				makePart(f, { Name = "Trave", Size = Vector3.new(0.4, 5, 0.4), CFrame = fieldCf * CFrame.new(x, 2.5, z), Color = Color3.new(1, 1, 1) })
			end
			makePart(f, { Name = "Travessao", Size = Vector3.new(8.4, 0.4, 0.4), CFrame = fieldCf * CFrame.new(0, 5, z), Color = Color3.new(1, 1, 1) })
		end
	end
	-- Postes simples de madeira
	for t = 30, V.Length - 10, 60 do
		local p = a + dir * t + perp * (M.RoadWidth / 2 + 1.5)
		makePart(props, { Name = "PosteMadeira", Size = Vector3.new(0.6, 12, 0.6), CFrame = CFrame.new(p + Vector3.new(0, 6, 0)), Color = Color3.fromRGB(110, 80, 55), Material = Enum.Material.Wood })
		local bulb = makePart(props, { Name = "Lampada", Shape = Enum.PartType.Ball, Size = Vector3.new(1, 1, 1), CFrame = CFrame.new(p + Vector3.new(0, 11.5, 0) - perp * 1.2), Color = Color3.fromRGB(255, 230, 170), Material = Enum.Material.Neon, CanCollide = false })
		local light = Instance.new("PointLight")
		light.Range = 22
		light.Brightness = 1
		light.Color = Color3.fromRGB(255, 220, 160)
		light.Parent = bulb
	end
	-- Placa de rua na entrada
	local sp = a + dir * 26 + perp * (M.RoadWidth / 2 + M.SidewalkWidth - 1)
	buildStreetSign(props, CFrame.lookAt(sp, sp - perp), V.StreetName)
	return k
end

-- Marco 10.22 (streaming): com o Workspace.StreamingEnabled ligado, o aparelho só recebe as peças
-- perto do jogador. Os Models e as pastas chegam todos, mas sem as peças. Então o minimapa e os
-- outros sistemas do cliente não conseguem medir uma casa longe. Aqui o servidor anota em cada Model
-- importante o pivô (MapaPivot) e a caixa (MapaBox + MapaTam). As peças soltas que o mapa desenha
-- (área e morro das favelas, casinhas de enfeite) viram CFrameValues em Map.MapaInfo.
local function stampModel(m)
	local ok, cf, size = pcall(m.GetBoundingBox, m)
	if ok and cf then
		m:SetAttribute("MapaBox", cf)
		m:SetAttribute("MapaTam", size)
	end
	local okp, pivot = pcall(m.GetPivot, m)
	if okp and pivot then
		m:SetAttribute("MapaPivot", pivot)
	end
end

function MapBuilder.stampMapInfo()
	local map = Workspace:FindFirstChild("Map")
	if not map then
		return
	end
	local n = 0
	local function stamp(m)
		if m and m:IsA("Model") then
			stampModel(m)
			n += 1
			if n % 400 == 0 then
				task.wait()
			end
		end
	end
	local function children(container)
		for _, c in ipairs(container and container:GetChildren() or {}) do
			stamp(c)
		end
	end
	for _, name in ipairs({ "Houses", "Buildings", "JobLocations", "Garages", "JardimProgresso", "Nature" }) do
		children(map:FindFirstChild(name))
	end
	for _, name in ipairs({ "MigueLandia", "Penitenciaria" }) do
		local m = map:FindFirstChild(name)
		if m then
			stamp(m)
			for _, d in ipairs(m:GetDescendants()) do
				stamp(d)
			end
		end
	end
	stamp(map:FindFirstChild("PaintShop"))
	stamp(map:FindFirstChild("PostoEstrela", true))
	local horizonte = map:FindFirstChild("Horizonte")
	stamp(horizonte and horizonte:FindFirstChild("Joalheria"))
	for _, b in ipairs(CollectionService:GetTagged("Banco")) do
		stamp(b)
	end
	-- placa de cada loja (o tour do tutorial mira nela)
	local shops = map:FindFirstChild("JobLocations")
	for _, shop in ipairs(shops and shops:GetChildren() or {}) do
		local sign = shop:FindFirstChild("Sign")
		if sign and sign:IsA("BasePart") then
			shop:SetAttribute("SignCF", sign.CFrame)
		end
	end
	-- peças soltas das favelas
	local old = map:FindFirstChild("MapaInfo")
	if old then
		old:Destroy()
	end
	local info = Instance.new("Folder")
	info.Name = "MapaInfo"
	local function value(kind, cf, size)
		local v = Instance.new("CFrameValue")
		v.Name = kind
		v.Value = cf
		v:SetAttribute("Tam", size)
		v.Parent = info
	end
	local favelas = map:FindFirstChild("Favelas")
	for _, fav in ipairs(favelas and favelas:GetChildren() or {}) do
		local area = fav:FindFirstChild("Area")
		if area and area:IsA("BasePart") then
			value("FavelaArea", area.CFrame, area.Size)
		end
		local chao = fav:FindFirstChild("Chao")
		for _, p in ipairs(chao and chao:GetChildren() or {}) do
			if p.Name == "Morro" and p:IsA("BasePart") then
				value("Morro", p.CFrame, p.Size)
			end
		end
		local casas = fav:FindFirstChild("Casas")
		for _, c in ipairs(casas and casas:GetChildren() or {}) do
			if c:IsA("Model") then
				local ok, cf, size = pcall(c.GetBoundingBox, c)
				if ok and cf then
					value("FavelaCasaModel", cf, size)
				end
			elseif c:IsA("BasePart") then
				value("FavelaCasa", c.CFrame, c.Size)
			end
		end
	end
	info.Parent = map
	map:SetAttribute("MapaPronto", true)
	print(("[MapBuilder] Mapa anotado para o streaming: %d models."):format(n))
end

function MapBuilder.build()
	if Workspace:FindFirstChild("Map") then
		print("[MapBuilder] Pasta Map já existe; usando o mapa existente.")
		return
	end

	-- Remove a Baseplate padrão do Studio, se houver
	local baseplate = Workspace:FindFirstChild("Baseplate")
	if baseplate then
		baseplate:Destroy()
	end

	local map = folder("Map", nil) -- monta fora do Workspace e coloca no fim (mais rápido)
	local groups = {
		houses = folder("Houses", map),
		buildings = folder("Buildings", map),
	}
	local shops = folder("JobLocations", map)
	local nature = folder("Nature", map)
	local props = folder("Props", map)

	buildGround(map)
	buildRoundabout(map)
	buildSpawn(map)

	-- 8 ruas saindo da rotatória. Índices ímpares = ruas comerciais, pares = residenciais.
	local dirs = {}
	for i = 0, 7 do
		table.insert(dirs, CFrame.Angles(0, i * math.pi / 4, 0).LookVector)
	end
	buildRoads(map, dirs)
	local vilaA, vilaB, vilaFolder = buildVilaRoad(map, dirs[M.Vila.Dir])

	-- Estabelecimentos primeiro (lugar garantido), perto da praça
	local SHOP_LOT_D = SHOP_D + SHOP_YARD
	local function placeShop(i, side, name, mainColor, accentColor)
		local lot = lotBeside(dirs[i] * RADIAL_START, dirs[i] * RADIAL_END, 150, side, SHOP_LOT_D)
		local area = rect(lot, SHOP_W + 8, SHOP_LOT_D)
		if not isFree(area) then
			warn("[MapBuilder] Sem espaço livre para " .. name)
		end
		occupy(area)
		local shop = buildShop(shops, lot * CFrame.new(0, 0, SHOP_YARD / 2), name, mainColor, accentColor)
		shop:SetAttribute("Curb", curbOf(lot, SHOP_LOT_D))
		if name == GameConfig.Places.Entregas then
			-- Marco 7: van de serviço. Placa "Pegar van" na calçadinha e vaga na faixa da rua
			local toRoad = M.RoadWidth / 2 + M.SidewalkWidth + 0.6 + SHOP_LOT_D / 2
			local spot = makePart(shop, { Name = "VanSpot", Size = Vector3.new(1, 1, 1), CFrame = lot * CFrame.new(0, ROAD_TOP + 0.5, -(toRoad - M.RoadWidth / 4)) * CFrame.Angles(0, math.pi / 2, 0), Transparency = 1, CanCollide = false })
			spot.CanQuery = false
			spot.CanTouch = false
			local postCf = lot * CFrame.new(-16, SIDEWALK_TOP, -SHOP_LOT_D / 2 + 3)
			makePart(shop, { Name = "VanPole", Size = Vector3.new(0.4, 6, 0.4), CFrame = postCf * CFrame.new(0, 3, 0), Color = Color3.fromRGB(70, 70, 75), Material = Enum.Material.Metal })
			local sign = makePart(shop, { Name = "VanPost", Size = Vector3.new(4, 2, 0.3), CFrame = postCf * CFrame.new(0, 6.6, 0), Color = accentColor })
			addSurfaceText(sign, "VAN SHERLEX", Color3.new(1, 1, 1), accentColor)
		end
	end
	placeShop(1, 1, GameConfig.Places.Pizzaria, Color3.fromRGB(245, 225, 190), Color3.fromRGB(200, 50, 45))
	placeShop(1, -1, GameConfig.Places.Mercearia, Color3.fromRGB(235, 240, 220), Color3.fromRGB(40, 140, 70))
	placeShop(3, 1, GameConfig.Places.Entregas, Color3.fromRGB(230, 230, 235), Color3.fromRGB(240, 140, 30))
	placeShop(3, -1, GameConfig.Places.PetShop, Color3.fromRGB(240, 230, 245), Color3.fromRGB(130, 80, 200))

	-- Marco 9: LXR Táxis (garagem dos táxis, só para o Taxista), na rua 5 perto da praça
	do
		local garagesFolder = map:FindFirstChild("Garages") or folder("Garages", map)
		local lot = lotBeside(dirs[5] * RADIAL_START, dirs[5] * RADIAL_END, 140, -1, TAXI_D) -- 140: o poste da rua fica fora da saída dos táxis
		local area = rect(lot, TAXI_W + 4, TAXI_D)
		if not isFree(area) then
			warn("[MapBuilder] Sem espaço livre para a " .. GameConfig.Places.Taxi)
		end
		occupy(area)
		buildTaxiStand(garagesFolder, lot)
	end

	-- Placas das áreas futuras
	for _, entry in ipairs({ { 5, "Centro e Banco: em breve" }, { 7, "Delegacia: em breve" } }) do
		local lot = lotBeside(dirs[entry[1]] * RADIAL_START, dirs[entry[1]] * RADIAL_END, 60, 1, 6)
		occupy(rect(lot, 16, 6))
		buildComingSoon(props, lot, entry[2])
	end

	-- Garagens (Marco 6.3): perto da praça, no meio da cidade e na entrada da Vila Esperança
	local garages = map:FindFirstChild("Garages") or folder("Garages", map)
	local function placeGarage(a, b, t, side, name)
		local lot = lotBeside(a, b, t, side, GARAGE_D)
		local area = rect(lot, GARAGE_W, GARAGE_D)
		if not isFree(area) then
			warn("[MapBuilder] Sem espaço livre para " .. name)
		end
		occupy(area)
		buildGarage(garages, lot, name)
	end
	placeGarage(dirs[2] * RADIAL_START, dirs[2] * RADIAL_END, 70, 1, "Garagem1")
	placeGarage(dirs[4] * RADIAL_START, dirs[4] * RADIAL_END, 400, -1, "Garagem2")
	placeGarage(vilaA, vilaB, 40, -1, "Garagem3")

	-- Loja de pintura (Marco 6.4): longe da cidade, no fim de uma estradinha depois do anel externo
	do
		local dir = dirs[GameConfig.PaintShop.Dir]
		local roadStart, roadEnd = buildPaintRoad(map, dir)
		local center = roadEnd + dir * (PAINT_D / 2 - 2)
		local lot = CFrame.lookAt(center, roadEnd)
		local area = rect(lot, PAINT_W, PAINT_D)
		if not isFree(area) then
			warn("[MapBuilder] Sem espaço livre para a loja de pintura")
		end
		occupy(area)
		addRoadArea(roadStart, roadEnd) -- depois do teste acima (a área da rua encosta na loja)
		buildPaintShop(map, lot)
	end

	-- Marco 9.7: Um Tijo (ônibus) numa área nova, no fim de uma avenida que sai do anel externo,
	-- e as paradas da Linha Circular no anel do meio (começando no trecho da mesma rua)
	do
		local T = GameConfig.BusTerminal
		local dir = dirs[T.Dir]
		local a, b = dir * RADIAL_END, dir * (RADIAL_END + T.RoadLength)
		local road = folder("AvenidaTerminal", map)
		asphalt(road, a, b, 0, 0.02)
		dashes(road, a, b, { a })
		-- Marco 9.8: calçadas, postes e placa (a avenida ficou bem mais comprida)
		local perp = Vector3.new(-dir.Z, 0, dir.X)
		for _, side in ipairs({ -1, 1 }) do
			sidewalkStrip(road, a + dir * CROSSING_GAP, b, side)
		end
		local lateral = M.RoadWidth / 2 + M.SidewalkWidth / 2 + 1
		local n = 0
		for d = 80, T.RoadLength - 20, 70 do
			n += 1
			local side = (n % 2 == 0) and 1 or -1
			local p = a + dir * d + perp * side * lateral
			buildLamp(props, CFrame.lookAt(p, p - perp * side))
		end
		local sp = a + dir * 30 + perp * (M.RoadWidth / 2 + M.SidewalkWidth - 1)
		buildStreetSign(props, CFrame.lookAt(sp, sp - perp), T.RoadName)
		local center = b + dir * (BUS_D / 2 - 2)
		local lot = CFrame.lookAt(center, b) -- frente (-Z) virada para a avenida
		local area = rect(lot, BUS_W, BUS_D)
		if not isFree(area) then
			warn("[MapBuilder] Sem espaço livre para a " .. GameConfig.Places.Onibus)
		end
		occupy(area)
		addRoadArea(a, b) -- depois do teste acima (a área da rua encosta no terminal)
		local garagesFolder = map:FindFirstChild("Garages") or folder("Garages", map)
		buildBusTerminal(garagesFolder, lot)
		buildBusStops(map, dirs, T.Dir)
	end

	-- Marco 9.9: quartel do Corpo de Bombeiros, no fim da sua avenida (área nova, fora da cidade)
	do
		local FS = GameConfig.FireStation
		local dir = dirs[FS.Dir]
		local a, b = dir * RADIAL_END, dir * (RADIAL_END + FS.RoadLength)
		local road = folder("AvenidaBombeiros", map)
		asphalt(road, a, b, 0, 0.02)
		dashes(road, a, b, { a })
		local perp = Vector3.new(-dir.Z, 0, dir.X)
		for _, side in ipairs({ -1, 1 }) do
			sidewalkStrip(road, a + dir * CROSSING_GAP, b, side)
		end
		local lateral = M.RoadWidth / 2 + M.SidewalkWidth / 2 + 1
		local n = 0
		for d = 80, FS.RoadLength - 20, 70 do
			n += 1
			local side = (n % 2 == 0) and 1 or -1
			local p = a + dir * d + perp * side * lateral
			buildLamp(props, CFrame.lookAt(p, p - perp * side))
		end
		local sp = a + dir * 30 + perp * (M.RoadWidth / 2 + M.SidewalkWidth - 1)
		buildStreetSign(props, CFrame.lookAt(sp, sp - perp), FS.RoadName)
		local W, D = FireStationBuilder.W, FireStationBuilder.D
		local center = b + dir * (D / 2 - 2)
		local lot = CFrame.lookAt(center, b) -- frente (-Z) virada para a avenida
		local area = rect(lot, W, D)
		if not isFree(area) then
			warn("[MapBuilder] Sem espaço livre para o " .. GameConfig.Places.Bombeiros)
		end
		occupy(area)
		addRoadArea(a, b)
		local garagesFolder = map:FindFirstChild("Garages") or folder("Garages", map)
		task.wait() -- Marco 10.21: pausa (evita "Script timeout" montando a cidade)

		local ok, err = pcall(FireStationBuilder.build, garagesFolder, lot, ROAD_TOP + 0.1, {
			makePart = makePart,
			model = model,
			buildLamp = buildLamp,
		})
		if not ok then
			warn("[MapBuilder] Erro ao montar o quartel dos bombeiros: " .. tostring(err))
		end
		local station = garagesFolder:FindFirstChild("QuartelBombeiros")
		if station then
			local p = b - dir * 14 + perp * (M.RoadWidth / 2 + 3)
			station:SetAttribute("Curb", CFrame.lookAt(p, p - perp))
		end
	end

	-- Parque MigueLândia (Marco 7.2): avenida saindo do anel externo e o parque no fim dela
	local park
	do
		local PK = GameConfig.Park
		local dir = dirs[PK.Dir]
		local a, b = dir * RADIAL_END, dir * (RADIAL_END + PK.RoadLength)
		local road = folder("AvenidaParque", map)
		asphalt(road, a, b + dir * 6, 0, 0.02)
		dashes(road, a, b, { a })
		local perp = Vector3.new(-dir.Z, 0, dir.X)
		local sp = a + dir * 30 + perp * (M.RoadWidth / 2 + M.SidewalkWidth - 1)
		buildStreetSign(props, CFrame.lookAt(sp, sp - perp), PK.RoadName)
		local center = b + dir * (PK.Size / 2)
		local lot = CFrame.lookAt(center, b)
		local area = rect(lot, PK.Size, PK.Size)
		if not isFree(area) then
			warn("[MapBuilder] Sem espaço livre para o parque")
		end
		occupy(area)
		addRoadArea(a, b) -- depois do teste acima (a área da rua encosta no parque)
		-- Protegido: se o parque der erro, o resto da cidade monta mesmo assim
		task.wait() -- Marco 10.21: pausa (evita "Script timeout" montando a cidade)

		local ok, result = pcall(ParkBuilder.build, map, lot, {
			makePart = makePart,
			model = model,
			addSurfaceText = addSurfaceText,
			buildTree = buildTree,
			buildLamp = buildLamp,
		})
		if ok then
			park = result
			local parkModel = map:FindFirstChild("MigueLandia")
			if parkModel then
				-- Marco 9: ponto do táxi na beira da avenida, perto da entrada
				local p = b - dir * 14 + perp * (M.RoadWidth / 2 + 3)
				parkModel:SetAttribute("Curb", CFrame.lookAt(p, p - perp))
			end
		else
			warn("[MapBuilder] Erro ao montar o parque: " .. tostring(result))
			local broken = map:FindFirstChild("MigueLandia")
			if broken then
				broken:Destroy()
			end
		end
	end

	-- Penitenciária (Marco 8): estrada saindo do anel externo e a prisão no fim dela
	do
		local PR = GameConfig.Prison
		local dir = dirs[PR.Dir]
		local a, b = dir * RADIAL_END, dir * (RADIAL_END + PR.RoadLength)
		local road = folder("EstradaPenitenciaria", map)
		asphalt(road, a, b + dir * 6, 0, 0.02)
		dashes(road, a, b, { a })
		local perp = Vector3.new(-dir.Z, 0, dir.X)
		local sp = a + dir * 30 + perp * (M.RoadWidth / 2 + M.SidewalkWidth - 1)
		buildStreetSign(props, CFrame.lookAt(sp, sp - perp), PR.RoadName)
		local center = b + dir * (PR.Depth / 2)
		local lot = CFrame.lookAt(center, b)
		local area = rect(lot, PR.Width, PR.Depth)
		if not isFree(area) then
			warn("[MapBuilder] Sem espaço livre para a penitenciária")
		end
		occupy(area)
		addRoadArea(a, b)
		-- Protegido: se a prisão der erro, o resto da cidade monta mesmo assim
		task.wait() -- Marco 10.21: pausa (evita "Script timeout" montando a cidade)

		local ok, err = pcall(PrisonBuilder.build, map, lot, {
			makePart = makePart,
			model = model,
			addSurfaceText = addSurfaceText,
			buildTree = buildTree,
			buildLamp = buildLamp,
			gableRoof = gableRoof,
		})
		local prisonModel = map:FindFirstChild("Penitenciaria")
		if ok and prisonModel then
			local p = b - dir * 14 + perp * (M.RoadWidth / 2 + 3)
			prisonModel:SetAttribute("Curb", CFrame.lookAt(p, p - perp))
		end
		if not ok then
			warn("[MapBuilder] Erro ao montar a penitenciária: " .. tostring(err))
			local broken = map:FindFirstChild("Penitenciaria")
			if broken then
				broken:Destroy()
			end
			local policeGarage = garages:FindFirstChild("GaragemPolicia")
			if policeGarage then
				policeGarage:Destroy()
			end
		end
	end

	-- Marco 10: estradas da expansão e Bairro Horizonte. Etapa 1 (asfalto e lotes reservados) ANTES
	-- das casas da cidade; a etapa 2 (construções) fica depois da Vila, para o número das casas
	-- antigas não mudar.
	local expansion, horizonte, favelas
	local helpers
	do
		helpers = {
			makePart = makePart,
			model = model,
			folder = folder,
			addSurfaceText = addSurfaceText,
			buildLamp = buildLamp,
			buildStreetSign = buildStreetSign,
			buildComingSoon = buildComingSoon,
			flatCylinder = flatCylinder,
			asphalt = asphalt,
			dashes = dashes,
			sidewalkStrip = sidewalkStrip,
			crosswalk = crosswalk,
			addRoadArea = addRoadArea,
			lotBeside = lotBeside,
			rect = rect,
			isFree = isFree,
			occupy = occupy,
			curbOf = curbOf,
			newStreet = newStreet,
			takeNumber = takeNumber,
			nextHouseId = function()
				houseCount += 1
				return houseCount
			end,
			-- Marco 10.4: casas e prédios da cidade no Jardim Progresso, com o sorteio do bairro
			-- (rng trocado só durante a chamada: o resto da cidade não muda)
			buildHouse = buildHouse,
			buildShop = buildShop,
			financialTower = HorizonteBuilder.buildTower,
			buildTree = buildTree,
			buildBuilding = buildBuilding,
			withRng = function(r, fn, ...)
				local saved = rng
				rng = r
				local ok, result = pcall(fn, ...)
				rng = saved
				if not ok then
					error(result, 0)
				end
				return result
			end,
			RADIAL_END = RADIAL_END,
			CROSSING_GAP = CROSSING_GAP,
			ROAD_TOP = ROAD_TOP,
			SIDEWALK_TOP = SIDEWALK_TOP,
		}
		HorizonteBuilder.init(helpers)
		helpers.palm = HorizonteBuilder.palm
		task.wait() -- Marco 10.21: pausa (evita "Script timeout" montando a cidade)

		local ok, result = pcall(ExpansionBuilder.plan, map, props, helpers)
		if ok then
			expansion = result
		else
			warn("[MapBuilder] Erro ao montar as estradas novas: " .. tostring(result))
		end
		ok, result = pcall(HorizonteBuilder.plan, map, helpers)
		if ok then
			horizonte = result
		else
			warn("[MapBuilder] Erro ao reservar os lotes do Bairro Horizonte: " .. tostring(result))
		end
		-- Marco 10.1: área das 3 favelas (comunidades das gangues)
		ok, result = pcall(FavelaBuilder.plan, map, helpers)
		if ok then
			favelas = result
		else
			warn("[MapBuilder] Erro ao reservar as favelas: " .. tostring(result))
		end
	end

	-- Ruas residenciais: casas dos dois lados (as 6 primeiras são "funcionais", com interior no Marco 6)
	local streets = {}
	for i = 1, 8 do
		streets[i] = newStreet(STREET_NAMES[i])
	end
	for i = 2, 8, 2 do
		for _, side in ipairs({ -1, 1 }) do
			fillSide(groups, dirs[i] * RADIAL_START, dirs[i] * RADIAL_END, 40, M.RoadLength - 20, side, "house", nil, streets[i])
		end
	end
	-- Ruas comerciais: prédios com lojinhas no térreo
	for i = 1, 7, 2 do
		for _, side in ipairs({ -1, 1 }) do
			fillSide(groups, dirs[i] * RADIAL_START, dirs[i] * RADIAL_END, 40, M.RoadLength - 20, side, "building", 8, streets[i])
		end
	end
	-- Anéis: anel do meio misturado; anel externo só casas, do lado de fora.
	-- Cada anel é UMA rua: a numeração continua de um trecho para o outro.
	local innerStreet, outerStreet = newStreet(INNER_RING_NAME), newStreet(OUTER_RING_NAME)
	for k, dir in ipairs(dirs) do
		local nextDir = dirs[(k % #dirs) + 1]
		local a, b = dir * M.InnerRingRadius, nextDir * M.InnerRingRadius
		local len = (b - a).Magnitude
		for _, side in ipairs({ -1, 1 }) do
			fillSide(groups, a, b, 20, len - 20, side, "mix", nil, innerStreet)
		end
		a, b = dir * RADIAL_END, nextDir * RADIAL_END
		local perp = Vector3.new(-(b - a).Unit.Z, 0, (b - a).Unit.X)
		local outward = perp:Dot((a + b) / 2) > 0 and 1 or -1
		fillSide(groups, a, b, 20, (b - a).Magnitude - 20, outward, "house", 14, outerStreet)
	end

	-- Vila Esperança (casinhas iniciais dos jogadores)
	task.wait()
	local vilaHouses = buildVila(groups, props, vilaA, vilaB, vilaFolder)

	-- Marco 10.4: Jardim Progresso, etapa 1 (reserva dos lotes): depois das casas da cidade (não
	-- toma lote de ninguém) e antes do campo (as plantações não caem dentro do bairro)
	local progresso
	do
		task.wait() -- Marco 10.21: pausa (evita "Script timeout" montando a cidade)

		local ok, result = pcall(ProgressoBuilder.plan, map, helpers)
		if ok then
			progresso = result
		else
			warn("[MapBuilder] Erro ao reservar o Jardim Progresso: " .. tostring(result))
		end
	end
	-- Marco 10.20: Banco Central, etapa 1 (reserva o lote na Estrada do Vale, antes do campo)
	local bankPlan
	do
		task.wait() -- Marco 10.21: pausa (evita "Script timeout" montando a cidade)

		local ok, result = pcall(BankBuilder.plan, map, helpers)
		if ok then
			bankPlan = result
		else
			warn("[MapBuilder] Erro ao reservar o banco: " .. tostring(result))
		end
	end

	-- Antes do campo: áreas novas nunca recebem plantações ou árvores aleatórias.
	local financialPlan = BankBuilder.planDistrict(map, helpers)

	-- Marco 10: Bairro Horizonte, etapa 2 (prédios, casas, praça, condomínio) e enfeites das estradas
	local towers, modern, mansions = 0, 0, 0
	if horizonte then
		task.wait() -- Marco 10.21: pausa (evita "Script timeout" montando a cidade)

		local ok, t, c, m = pcall(HorizonteBuilder.build, horizonte, groups, props)
		if ok then
			towers, modern, mansions = t, c, m
		else
			warn("[MapBuilder] Erro ao montar o Bairro Horizonte: " .. tostring(t))
		end
	end
	-- Marco 10.1: favelas (sorteio próprio de cada uma; depois de tudo, antes do campo)
	local shacks = 0
	if favelas then
		task.wait() -- Marco 10.21: pausa (evita "Script timeout" montando a cidade)

		local ok, n = pcall(FavelaBuilder.build, favelas, groups)
		if ok then
			shacks = n
		else
			warn("[MapBuilder] Erro ao montar as favelas: " .. tostring(n))
		end
	end
	-- Marco 10.4: Jardim Progresso, etapa 2 (depois de todas as casas: números antigos não mudam)
	local progressoCounts = { casa = 0, moderna = 0, torre = 0, loja = 0 }
	if progresso then
		task.wait() -- Marco 10.21: pausa (evita "Script timeout" montando a cidade)

		local ok, result = pcall(ProgressoBuilder.build, progresso, groups, props)
		if ok then
			progressoCounts = result
		else
			warn("[MapBuilder] Erro ao montar o Jardim Progresso: " .. tostring(result))
		end
	end
	-- Marco 10.20: Banco Central, etapa 2 (o prédio)
	if bankPlan then
		task.wait() -- Marco 10.21: pausa (evita "Script timeout" montando a cidade)

		local ok, err = pcall(BankBuilder.build, bankPlan)
		if not ok then
			warn("[MapBuilder] Erro ao montar o banco: " .. tostring(err))
		end
	end
	BankBuilder.buildDistrict(financialPlan, helpers, groups)
	-- Marco 10.6 (pedido do Luís): mais garagens, espalhadas pelo mapa novo (Horizonte, condomínio,
	-- Jardim Progresso, saída da rodovia e perto das 3 favelas). Para cada ponto procura o lote
	-- livre mais perto na beira de uma estrada. Antes do campo (as plantações desviam delas).
	do
		local ok, err = pcall(function()
			local at = CityRoads.districtPoint
			local wishes = {
				{ "GaragemHorizonte", at(-260, 820) },
				{ "GaragemPoente", at(-520, 430) },
				{ "GaragemJardins", at(60, 870) },
				{ "GaragemProgresso", Vector3.new(120, 0, 1100) },
				{ "GaragemRodovia", Vector3.new(160, 0, GameConfig.Rodovia.ExitZ) },
				{ "GaragemSerra", Vector3.new(-820, 0, GameConfig.Rodovia.ExitZ) },
				{ "GaragemLuaNegra", Vector3.new(800, 0, 1480) },
				{ "GaragemSol", Vector3.new(1150, 0, -1260) },
			}
			local spots = {}
			for _, r in ipairs(CityRoads.get().roads) do
				if r.Kind ~= "rodovia" then
					local kind = CityRoads.Kinds[r.Kind]
					local half = r.Width / 2 + (kind.Sidewalk and M.SidewalkWidth or (kind.Verge or 3))
					for _, seg in ipairs(CityRoads.segments(r)) do
						local perp = Vector3.new(-seg.dir.Z, 0, seg.dir.X)
						for t = 30, seg.len - 30, 12 do
							for _, side in ipairs({ -1, 1 }) do
								local center = seg.a + seg.dir * t + perp * side * (half + 0.6 + GARAGE_D / 2)
								table.insert(spots, CFrame.lookAt(center, center - perp * side))
							end
						end
					end
				end
			end
			local garagesFolder = map:FindFirstChild("Garages") or folder("Garages", map)
			for _, wish in ipairs(wishes) do
				local target = wish[2]
				table.sort(spots, function(a, b)
					return (a.Position - target).Magnitude < (b.Position - target).Magnitude
				end)
				local placed = false
				for _, lot in ipairs(spots) do
					if (lot.Position - target).Magnitude > 500 then
						break
					end
					local area = rect(lot, GARAGE_W + 4, GARAGE_D)
					if isFree(area) then
						occupy(area)
						buildGarage(garagesFolder, lot, wish[1])
						placed = true
						break
					end
				end
				if not placed then
					warn("[MapBuilder] Sem lugar para a " .. wish[1])
				end
			end
		end)
		if not ok then
			warn("[MapBuilder] Erro ao espalhar as garagens: " .. tostring(err))
		end
	end
	if expansion then
		task.wait() -- Marco 10.21: pausa (evita "Script timeout" montando a cidade)

		local ok, err = pcall(ExpansionBuilder.build, expansion)
		if not ok then
			warn("[MapBuilder] Erro ao montar placas, posto e campo: " .. tostring(err))
		end
	end
	-- Marco 10.5: lojas de conveniência e caixas eletrônicos (depois de tudo: só mexe no térreo de
	-- alguns prédios e põe os caixas na calçadinha deles)
	do
		task.wait() -- Marco 10.21: pausa (evita "Script timeout" montando a cidade)

		local ok, err = pcall(CrimeBuilder.build, map, helpers)
		if not ok then
			warn("[MapBuilder] Erro ao montar as lojas e caixas eletrônicos: " .. tostring(err))
		end
	end

	-- Placas com o nome das ruas: no começo de cada rua (perto da praça), depois do anel do meio
	-- e no começo de cada trecho dos anéis
	local signLateral = M.RoadWidth / 2 + M.SidewalkWidth - 1
	for i, dir in ipairs(dirs) do
		local perp = Vector3.new(-dir.Z, 0, dir.X)
		for _, d in ipairs({ M.RoundaboutOuterRadius + 16, M.InnerRingRadius + CROSSING_GAP + 6 }) do
			local p = dir * d + perp * signLateral
			buildStreetSign(props, CFrame.lookAt(p, p - perp), STREET_NAMES[i])
		end
		local nextDir = dirs[(i % #dirs) + 1]
		for _, ringData in ipairs({ { M.InnerRingRadius, INNER_RING_NAME }, { RADIAL_END, OUTER_RING_NAME } }) do
			local a, b = dir * ringData[1], nextDir * ringData[1]
			local along = (b - a).Unit
			local rp = Vector3.new(-along.Z, 0, along.X)
			local inward = rp:Dot(a) > 0 and -1 or 1 -- placa do lado de dentro do anel
			local p = a + along * (CROSSING_GAP + 6) + rp * inward * signLateral
			buildStreetSign(props, CFrame.lookAt(p, p - rp * inward), ringData[2])
		end
	end

	task.wait()
	buildStreetLamps(props, dirs)
	task.wait()
	buildRandomTrees(nature)
	setupLighting()

	map.Parent = Workspace
	if park then
		local ok, err = pcall(ParkBuilder.start, park)
		if not ok then
			warn("[MapBuilder] Erro ao ligar os brinquedos: " .. tostring(err))
		end
	end
	print(("[MapBuilder] Cidade montada: %d casas (%d na %s), %d prédios, 4 estabelecimentos. %s: %d torres, %d casas modernas e %d mansões. Favelas: %d barracos. %s: %d casas, %d casas modernas, %d prédios, %d lojas."):format(houseCount, vilaHouses, M.Vila.Name, #groups.buildings:GetChildren(), GameConfig.Horizonte.Name, towers, modern, mansions, shacks, GameConfig.Progresso.District.Name, progressoCounts.casa, progressoCounts.moderna, progressoCounts.torre, progressoCounts.loja))
end

return MapBuilder
