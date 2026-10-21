-- MapBuilder (ModuleScript)
-- Caminho: ServerScriptService > Services > MapBuilder
-- Monta a cidade de Little Little Kinder com peças simples:
--   * praça com rotatória no centro e 8 ruas saindo dela;
--   * dois anéis de rua (meio e borda) ligando as ruas, formando quarteirões;
--   * 4 estabelecimentos com interior (La Paulistana, Minas Market, Sherlex, Duto Pet Shop);
--   * casas de 3 modelos (térrea com varanda, sobrado, com garagem);
--   * cada rua tem nome e placas; casas e prédios são numerados POR RUA, em ordem:
--     ímpares de um lado, pares do outro, crescendo a partir da praça (como numa cidade de verdade);
--   * prédios com comércio no térreo nas ruas comerciais; árvores, postes e faixas de pedestre.
-- Cada lote é conferido antes de construir: nada fica em cima de rua ou de outra construção.
--
-- Se já existir uma pasta "Map" no Workspace (por exemplo, se você construir
-- o mapa à mão no futuro), este módulo não faz nada.

local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))

local CivicConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CivicConfig"))
local CivicBuilder = require(script.Parent:WaitForChild("CivicBuilder"))

local MapBuilder = {}

local M = GameConfig.Map
local C = GameConfig.Colors

local ROAD_TOP = 0.5 -- altura da superfície das ruas
local SIDEWALK_TOP = 0.8
local RADIAL_START = 50 -- as ruas começam dentro da rotatória
local RADIAL_END = RADIAL_START + M.RoadLength -- onde fica o anel externo
local CROSSING_GAP = M.RoadWidth / 2 + M.SidewalkWidth + 8 -- espaço livre em volta dos cruzamentos

local rng = Random.new(M.TreeSeed)
-- A forma das árvores usa outro gerador: detalhes não redistribuem os lotes.
local treeRng = Random.new(M.TreeSeed + 9417)

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

local function buildGround(parent)
	-- BasePart tem limite de 2048 studs por eixo. Mosaico sem lacunas mantém
	-- a estrada e a prisão apoiadas mesmo quando o mapa ultrapassa esse limite.
	local tiles = math.max(1, math.ceil(M.GroundSize / 1200))
	local tileSize = M.GroundSize / tiles
	for x = 1, tiles do
		for z = 1, tiles do
			makePart(parent, {
				Name = ("Ground_%d_%d"):format(x, z),
				Size = Vector3.new(tileSize, 1, tileSize),
				CFrame = CFrame.new(-M.GroundSize / 2 + (x - 0.5) * tileSize, -0.5, -M.GroundSize / 2 + (z - 0.5) * tileSize),
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

-- Tronco em segmentos inclinados, raízes expostas e copa assimétrica.
-- 16 peças por árvore; raízes/copa não atrapalham os caminhos nem criam degraus.
local function buildTree(parent, position, scale)
	scale = scale or 1
	local tree = model("Tree", parent)
	local leafColor = C.Leaves[rng:NextInteger(1, #C.Leaves)]
	local yaw = treeRng:NextNumber(0, math.pi * 2)
	local base = CFrame.new(position) * CFrame.Angles(0, yaw, 0)
	local function world(p) return (base * CFrame.new(p * scale)).Position end
	local function limb(name, a, b, width, collide)
		local pa, pb = world(a), world(b)
		return makePart(tree, {
			Name = name,
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new((pb - pa).Magnitude + 0.15 * scale, width * scale, width * scale),
			CFrame = CFrame.lookAt((pa + pb) / 2, pb) * CFrame.Angles(0, math.pi / 2, 0),
			Color = C.Trunk,
			Material = Enum.Material.Wood,
			CanCollide = collide == true,
		})
	end
	local bend = treeRng:NextNumber(0.7, 1.6)
	local low = Vector3.new(0, 0.3, 0)
	local knee = Vector3.new(bend * 0.35, 2.6, -0.25)
	local shoulder = Vector3.new(bend, 4.7, 0.3)
	local top = Vector3.new(bend - 0.45, 6.9, -0.4)
	limb("TroncoBase", low, knee, 1.55, true)
	limb("TroncoCurvo", knee, shoulder, 1.2, true)
	limb("TroncoAlto", shoulder, top, 0.85, true)
	limb("GalhoAberto", shoulder, Vector3.new(-1.8, 6.3, 0.7), 0.65, false)
	limb("GalhoInclinado", top, Vector3.new(2.8, 7.6, 1.3), 0.5, false)
	for i = 1, 4 do
		local angle = i * math.pi / 2 + treeRng:NextNumber(-0.35, 0.35)
		local length = treeRng:NextNumber(2.8, 3.8)
		local dir = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local elbow = dir * (length * 0.5) + Vector3.new(0, 0.35, 0)
		limb("RaizAparente", Vector3.new(0, 0.65, 0), elbow, 0.8, false)
		limb("PontaDeRaiz", elbow, dir * length + Vector3.new(0, 0.08, 0), 0.38, false)
	end
	local crowns = {
		{ pos = Vector3.new(bend + 0.2, 7.5, 0.8), size = Vector3.new(6.7, 4.7, 5.5) },
		{ pos = Vector3.new(-1.6, 7.1, 0.4), size = Vector3.new(4.3, 3.8, 4.8) },
		{ pos = Vector3.new(2.2, 8.9, -0.5), size = Vector3.new(4.8, 3.7, 4.2) },
	}
	for i, crown in ipairs(crowns) do
		local variation = treeRng:NextNumber(0.9, 1.08)
		makePart(tree, {
			Name = "CopaIrregular" .. i,
			Shape = Enum.PartType.Ball,
			Size = crown.size * (scale * variation),
			CFrame = CFrame.new(world(crown.pos)) * CFrame.Angles(0.12 * i, yaw + 0.3 * i, 0.15 * (i - 2)),
			Color = leafColor:Lerp(C.Leaves[(i % #C.Leaves) + 1], 0.18),
			Material = Enum.Material.Grass,
			CanCollide = false,
		})
	end
	tree:SetAttribute("OrganicRoots", true)
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
		local water = flatCylinder(f, name .. "Water", Vector3.new(0, y + depth / 2 - 0.05, 0), radius - 0.6, 0.15, C.Water, Enum.Material.Glass)
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

	-- Bancos de madeira com pés de ferro, virados para o chafariz (sentar com E)
	for _, a in ipairs({ 22.5, 157.5, 202.5, 247.5, 292.5, 337.5 }) do
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
			for _, side in ipairs({ -1, 1 }) do
				sidewalkStrip(ring, a + along * CROSSING_GAP, b - along * CROSSING_GAP, side)
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
	makePart(parent, { Name = "Window", Size = Vector3.new(w, h, 0.3), CFrame = cf * CFrame.new(0, 0, -0.05), Color = C.Window, Material = Enum.Material.Glass, Transparency = 0.15 })
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
	local functional = id <= 6
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
		makePart(house, { Name = "BalconyGlass", Size = Vector3.new(8, 2.4, 0.2), CFrame = cf * CFrame.new(0, 1 + 12.6, front - 2.9), Color = Color3.fromRGB(200, 230, 245), Material = Enum.Material.Glass, Transparency = 0.5 })
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
	if functional then
		house:SetAttribute("Functional", true) -- interior será adicionado no Marco 6
	end
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
	makePart(b, { Name = "Shopfront", Size = Vector3.new(w - 4, 7.2, 0.3), CFrame = cf * CFrame.new(0, 0.7 + 4, front - 0.1), Color = Color3.fromRGB(180, 215, 235), Material = Enum.Material.Glass, Transparency = 0.25 })
	makePart(b, { Name = "Door", Size = Vector3.new(4, 7, 0.4), CFrame = cf * CFrame.new(0, 0.7 + 3.5, front - 0.2), Color = Color3.fromRGB(60, 60, 65) })
	makePart(b, { Name = "Awning", Size = Vector3.new(w - 1, 0.4, 3.4), CFrame = cf * CFrame.new(0, 0.7 + 8.3, front - 1.6) * CFrame.Angles(math.rad(-14), 0, 0), Color = awning, CanCollide = false })
	local sign = makePart(b, { Name = "Sign", Size = Vector3.new(math.min(w - 6, 22), 1.8, 0.3), CFrame = cf * CFrame.new(0, 0.7 + 9.8, front - 0.2), Color = Color3.new(1, 1, 1), CanCollide = false })
	addSurfaceText(sign, BUSINESS[rng:NextInteger(1, #BUSINESS)], awning, Color3.new(1, 1, 1))
	local plate = makePart(b, { Name = "NumberPlate", Size = Vector3.new(1.8, 1, 0.1), CFrame = cf * CFrame.new(3, 0.7 + 7.6, front - 0.25), Color = Color3.fromRGB(30, 60, 110), CanCollide = false })
	addSurfaceText(plate, tostring(address.number), Color3.new(1, 1, 1), Color3.fromRGB(30, 60, 110))
	-- Andares: janelas separadas por colunas, na frente e nas laterais + friso
	for f = 1, floors - 1 do
		local y = 0.7 + groundH + (f - 1) * floorH + floorH / 2
		local panes = math.max(2, math.floor((w - 2) / 7))
		local paneW = (w - 2) / panes
		for k = 0, panes - 1 do
			makePart(b, { Name = "Windows", Size = Vector3.new(paneW - 1, 3.6, 0.3), CFrame = cf * CFrame.new(-(w - 2) / 2 + paneW * (k + 0.5), y, front - 0.1), Color = C.Window, Material = Enum.Material.Glass, Transparency = 0.1, CanCollide = false })
		end
		for _, side in ipairs({ -1, 1 }) do
			makePart(b, { Name = "Windows", Size = Vector3.new(0.3, 3.6, d - 4), CFrame = cf * CFrame.new(side * (w / 2 + 0.1), y, 0), Color = C.Window, Material = Enum.Material.Glass, Transparency = 0.1, CanCollide = false })
		end
		makePart(b, { Name = "Ledge", Size = Vector3.new(w + 0.6, 0.4, 0.8), CFrame = cf * CFrame.new(0, y - floorH / 2, front - 0.3), Color = trim, CanCollide = false })
	end
	b:SetAttribute("Address", ("%s, %d"):format(address.street, address.number))
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
		wall("Storefront", Vector3.new(sideW - 1, DOOR_H - 1.5, 0.3), Vector3.new(x, 1.5 + (DOOR_H - 1.5) / 2, zFront), Color3.fromRGB(190, 225, 245), Enum.Material.Glass, 0.55)
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
-- Árvores soltas e parques nos espaços livres
---------------------------------------------------------------------------

local function buildRandomTrees(parent)
	local half = M.GroundSize / 2 - 10
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
	Lighting.Brightness = 2
	Lighting.GlobalShadows = true
	Lighting.OutdoorAmbient = Color3.fromRGB(140, 140, 150)
	Lighting.Ambient = Color3.fromRGB(105, 105, 110) -- deixa o interior das lojas claro
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

function MapBuilder.build()
	if Workspace:FindFirstChild("Map") then
		print("[MapBuilder] Pasta Map já existe; usando o mapa existente.")
		CivicBuilder.build(Workspace:FindFirstChild("Map"))
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

	-- Estabelecimentos primeiro (lugar garantido), perto da praça
	local SHOP_LOT_D = SHOP_D + SHOP_YARD
	local function placeShop(i, side, name, mainColor, accentColor)
		local lot = lotBeside(dirs[i] * RADIAL_START, dirs[i] * RADIAL_END, 150, side, SHOP_LOT_D)
		local area = rect(lot, SHOP_W + 8, SHOP_LOT_D)
		if not isFree(area) then
			warn("[MapBuilder] Sem espaço livre para " .. name)
		end
		occupy(area)
		buildShop(shops, lot * CFrame.new(0, 0, SHOP_YARD / 2), name, mainColor, accentColor)
	end
	placeShop(1, 1, GameConfig.Places.Pizzaria, Color3.fromRGB(245, 225, 190), Color3.fromRGB(200, 50, 45))
	placeShop(1, -1, GameConfig.Places.Mercearia, Color3.fromRGB(235, 240, 220), Color3.fromRGB(40, 140, 70))
	placeShop(3, 1, GameConfig.Places.Entregas, Color3.fromRGB(230, 230, 235), Color3.fromRGB(240, 140, 30))
	placeShop(3, -1, GameConfig.Places.PetShop, Color3.fromRGB(240, 230, 245), Color3.fromRGB(130, 80, 200))

	-- Equipamentos públicos têm lote garantido antes das casas e das árvores.
	-- A delegacia cabe entre a pizzaria e o anel; a prisão fica além do bairro.
	local stationArea = rect(CivicConfig.Station.CFrame, CivicConfig.Station.LotSize.X, CivicConfig.Station.LotSize.Z)
	assert(isFree(stationArea), "Lote da delegacia conflita com o mapa: reveja CivicConfig")
	occupy(stationArea)
	occupy(rect(CivicConfig.Prison.CFrame, CivicConfig.Prison.LotSize.X, CivicConfig.Prison.LotSize.Z))
	for _, road in ipairs(CivicConfig.Roads) do
		local cf = CFrame.lookAt((road.a + road.b) / 2, road.b)
		occupy(rect(cf, road.width + 8, (road.b - road.a).Magnitude + 4))
	end
	CivicBuilder.build(map)

	-- Placas das áreas futuras
	for _, entry in ipairs({ { 5, "Centro e Banco: em breve" }, { 7, "Bombeiros: em breve" } }) do
		local lot = lotBeside(dirs[entry[1]] * RADIAL_START, dirs[entry[1]] * RADIAL_END, 60, 1, 6)
		occupy(rect(lot, 16, 6))
		buildComingSoon(props, lot, entry[2])
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

	buildStreetLamps(props, dirs)
	buildRandomTrees(nature)
	setupLighting()

	map.Parent = Workspace
	print(("[MapBuilder] Cidade montada: %d casas, %d prédios, 4 estabelecimentos."):format(houseCount, #groups.buildings:GetChildren()))
end

return MapBuilder
