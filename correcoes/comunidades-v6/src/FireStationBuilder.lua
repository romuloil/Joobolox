-- FireStationBuilder (ModuleScript)
-- Caminho: ServerScriptService > Services > FireStationBuilder
-- Marco 9.9: quartel do Corpo de Bombeiros, montado por script (chamado pelo MapBuilder), no fim
-- da sua própria avenida, fora da cidade. Inspirado nas fotos que o Luís mandou:
--   * à direita, o pátio das viaturas: 3 baias com pé-direito bem alto (a câmera não bate), pórtico
--     vermelho com "CORPO DE BOMBEIROS" e o brasão, balcão "Abrir garagem" (garagem de serviço);
--   * à esquerda, o prédio de 2 andares: cinza com faixa de vidro escuro e marquise vermelha
--     ("UNIDADE ..."), com recepção e vitrine de capacetes (museu), central 193, vestiário com
--     armários; em cima, alojamento com beliches, refeitório com cozinha e academia;
--   * mezanino com guarda-corpo amarelo dentro do pátio e o CANO de descida (aviso "Descer pelo
--     cano": o FireService escorrega o jogador até o chão);
--   * torre de treinamento, mastro com bandeira, canteiro de pinheirinhos e postes.
-- Coordenadas locais: (0, 0, 0) = centro do lote, no chão; -Z = frente (virada para a avenida).
-- Nada aqui sorteia números (o rng do mapa é compartilhado: mudaria as casas da cidade).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))

local FireStationBuilder = {}

FireStationBuilder.W, FireStationBuilder.D = 150, 124

local RED = Color3.fromRGB(200, 22, 30)
local DARK_RED = Color3.fromRGB(150, 15, 22)
local GREY = Color3.fromRGB(184, 184, 182) -- Marco 9.14: menos claro
local LIGHT = Color3.fromRGB(236, 236, 232)
local CONCRETE = Color3.fromRGB(175, 172, 165)
local PAVER = Color3.fromRGB(150, 90, 85)
local STEEL = Color3.fromRGB(110, 112, 118)
local BLACK = Color3.fromRGB(28, 28, 32)
local GLASS = Color3.fromRGB(60, 80, 95)
local YELLOW = Color3.fromRGB(242, 183, 5)
local WOOD = Color3.fromRGB(140, 100, 65)
local WHITE = Color3.new(1, 1, 1)
local BALL, CYL = Enum.PartType.Ball, Enum.PartType.Cylinder

local K, lot, G, folder

local function at(x, y, z)
	return lot * CFrame.new(x, G + y, z)
end

local function box(name, size, cf, color, material, extra)
	local props = { Name = name, Size = size, CFrame = cf, Color = color, Material = material }
	for k, v in pairs(extra or {}) do
		props[k] = v
	end
	local p = K.makePart(folder, props)
	if extra and extra.CanQuery == false then
		p.CanQuery = false
	end
	return p
end

-- caixa pelos cantos (x0..x1, y0..y1, z0..z1) em coordenadas locais
local function block(name, x0, x1, y0, y1, z0, z1, color, material, extra)
	return box(name, Vector3.new(math.abs(x1 - x0), math.abs(y1 - y0), math.abs(z1 - z0)),
		at((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), color, material, extra)
end

local function light(p, range, brightness, color)
	local l = Instance.new("PointLight")
	l.Range = range or 24
	l.Brightness = brightness or 1
	l.Color = color or Color3.fromRGB(255, 245, 225)
	l.Parent = p
	return l
end

-- texto numa face de uma peça (SurfaceGui)
local function sign(p, text, color, face, font)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face or Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 30
	gui.LightInfluence = 0
	gui.Parent = p
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextColor3 = color or WHITE
	label.Font = font or Enum.Font.GothamBlack
	label.TextScaled = true
	label.Text = text
	label.Parent = gui
	return label
end

-- brasão redondo (cruz de bombeiro estilizada) numa face
local function emblem(cf, radius)
	local disc = box("Brasao", Vector3.new(0.3, radius * 2, radius * 2), cf * CFrame.Angles(0, math.rad(90), 0), WHITE, nil, { Shape = CYL, CanCollide = false })
	local inner = box("BrasaoMeio", Vector3.new(0.32, radius * 1.6, radius * 1.6), cf * CFrame.Angles(0, math.rad(90), 0), RED, nil, { Shape = CYL, CanCollide = false })
	local face = box("BrasaoTexto", Vector3.new(radius * 1.3, radius * 1.3, 0.05), cf * CFrame.new(0, 0, -0.2), WHITE, nil, { Transparency = 1, CanCollide = false })
	sign(face, "193", YELLOW)
	return disc, inner
end

-- parede com vãos de porta ao longo de X (em z), de x0 a x1; doors = { {centroX, largura}, ... }
local function wallX(name, x0, x1, z, y0, y1, color, doors, thick)
	thick = thick or 1
	local cuts = {}
	for _, d in ipairs(doors or {}) do
		table.insert(cuts, { d[1] - d[2] / 2, d[1] + d[2] / 2, d[3] or 9 })
	end
	table.sort(cuts, function(a, b)
		return a[1] < b[1]
	end)
	local x = x0
	for _, c in ipairs(cuts) do
		if c[1] > x then
			block(name, x, c[1], y0, y1, z - thick / 2, z + thick / 2, color)
		end
		if y0 + c[3] < y1 then
			block(name, c[1], c[2], y0 + c[3], y1, z - thick / 2, z + thick / 2, color) -- verga em cima da porta
		end
		x = c[2]
	end
	if x < x1 then
		block(name, x, x1, y0, y1, z - thick / 2, z + thick / 2, color)
	end
end

-- parede ao longo de Z (em x), de z0 a z1
local function wallZ(name, z0, z1, x, y0, y1, color, doors, thick)
	thick = thick or 1
	local cuts = {}
	for _, d in ipairs(doors or {}) do
		table.insert(cuts, { d[1] - d[2] / 2, d[1] + d[2] / 2, d[3] or 9 })
	end
	table.sort(cuts, function(a, b)
		return a[1] < b[1]
	end)
	local z = z0
	for _, c in ipairs(cuts) do
		if c[1] > z then
			block(name, x - thick / 2, x + thick / 2, y0, y1, z, c[1], color)
		end
		if y0 + c[3] < y1 then
			block(name, x - thick / 2, x + thick / 2, y0 + c[3], y1, c[1], c[2], color)
		end
		z = c[2]
	end
	if z < z1 then
		block(name, x - thick / 2, x + thick / 2, y0, y1, z, z1, color)
	end
end

-- pinheirinho (cone de bolas, sem sorteio)
local function pine(x, z, h)
	block("Tronco", x - 0.3, x + 0.3, 0, 1.2, z - 0.3, z + 0.3, WOOD, Enum.Material.Wood)
	for i = 0, 3 do
		local r = (1 - i / 4) * h * 0.32
		box("Pinheiro", Vector3.new(r * 2, r * 1.6, r * 2), at(x, 1.2 + i * h * 0.2 + r * 0.6, z), Color3.fromRGB(40, 110, 55), Enum.Material.Grass, { Shape = BALL, CanCollide = false })
	end
end

local function lamp(x, y, z, sx, sz)
	local p = block("Luminaria", x - sx / 2, x + sx / 2, y - 0.2, y, z - sz / 2, z + sz / 2, Color3.fromRGB(255, 250, 235), Enum.Material.Neon, { CanCollide = false })
	light(p, 24, 0.7)
	return p
end

---------------------------------------------------------------------------
-- Pátio das viaturas (garagem de serviço "Bombeiro")
---------------------------------------------------------------------------
-- x de 0 a 72, z de -24 a 44; 3 baias; pé-direito 30
local BAY_X0, BAY_X1, BAY_Z0, BAY_Z1, BAY_H = 0, 72, -24, 44, 30

local function buildBays(g)
	-- piso de epóxi e faixas amarelas
	block("PisoPatio", BAY_X0, BAY_X1, -0.6, 0, BAY_Z0, BAY_Z1, Color3.fromRGB(120, 122, 128), Enum.Material.SmoothPlastic)
	for k = 1, 3 do
		local x = BAY_X0 + 12 + (k - 1) * 24
		local vaga = box("Vaga" .. k, Vector3.new(1, 1, 1), at(x, 0.5, 12), WHITE, nil, { Transparency = 1, CanCollide = false })
		vaga.CanQuery = false
		vaga.CanTouch = false
		vaga.Parent = g
		for _, dx in ipairs({ -7, 7 }) do
			block("FaixaVaga", x + dx - 0.25, x + dx + 0.25, 0, 0.04, -14, 36, YELLOW, nil, { CanCollide = false })
		end
		local num = block("NumeroVaga", x - 2.5, x + 2.5, 0, 0.04, -18, -13, RED, nil, { CanCollide = false })
		sign(num, "ABT-" .. k, WHITE, Enum.NormalId.Top)
		-- porta de enrolar aberta (enrolada em cima do vão)
		block("PortaEnrolada", x - 11, x + 11, BAY_H - 9, BAY_H - 6, BAY_Z0 - 0.5, BAY_Z0 + 2.5, Color3.fromRGB(205, 208, 212), Enum.Material.Metal)
		-- luminárias
		lamp(x, BAY_H - 0.5, 0, 2, 20)
		lamp(x, BAY_H - 0.5, 26, 2, 20)
	end
	-- colunas cinza entre as baias (frente) e paredes
	for _, x in ipairs({ BAY_X0 + 24, BAY_X0 + 48 }) do
		block("Coluna", x - 1, x + 1, 0, BAY_H, BAY_Z0, BAY_Z0 + 2, STEEL, Enum.Material.Metal)
	end
	wallZ("ParedePatio", BAY_Z0, BAY_Z1, BAY_X1, 0, BAY_H, GREY, nil, 2)
	wallX("FundoPatio", BAY_X0, BAY_X1, BAY_Z1, 0, BAY_H, GREY, { { 60, 10, 12 } }, 2) -- portão dos fundos
	-- teto do pátio com treliças pretas
	block("TetoPatio", BAY_X0 - 1, BAY_X1 + 1, BAY_H, BAY_H + 1, BAY_Z0, BAY_Z1 + 1, Color3.fromRGB(90, 92, 98), Enum.Material.Metal)
	for z = BAY_Z0 + 6, BAY_Z1 - 4, 10 do
		block("Trelica", BAY_X0, BAY_X1, BAY_H - 1.6, BAY_H, z - 0.4, z + 0.4, BLACK, Enum.Material.Metal)
	end
	-- pórtico vermelho na frente (como a foto): coluna, viga alta com o nome e o brasão
	block("Portico", BAY_X1 - 1, BAY_X1 + 2, 0, BAY_H + 10, BAY_Z0 - 6, BAY_Z0 + 2, RED)
	block("Portico", BAY_X0 - 2, BAY_X1 + 2, BAY_H + 1, BAY_H + 10, BAY_Z0 - 6, BAY_Z0 + 2, RED)
	local nome = block("NomeQuartel", BAY_X0 + 2, BAY_X1 - 10, BAY_H + 3.5, BAY_H + 8, BAY_Z0 - 6.05, BAY_Z0 - 6, RED, nil, { CanCollide = false, Transparency = 1 })
	sign(nome, "CORPO DE BOMBEIROS MILITAR", WHITE)
	emblem(at(BAY_X1 - 4.5, BAY_H + 5.5, BAY_Z0 - 6.2), 3.2)
	-- balcão da garagem: armário vermelho "Controle das viaturas" na entrada do pátio
	local balcao = block("Balcao", BAY_X1 - 6, BAY_X1 - 2, 0, 4, BAY_Z0 + 4, BAY_Z0 + 6, RED)
	balcao.Parent = g
	local placa = block("PlacaBalcao", BAY_X1 - 6, BAY_X1 - 2, 4.6, 6.2, BAY_Z0 + 4, BAY_Z0 + 4.1, BLACK, nil, { CanCollide = false })
	sign(placa, "VIATURAS", YELLOW)
	-- mangueiras enroladas e extintores na parede do fundo
	for i = 0, 5 do
		box("Mangueira", Vector3.new(0.8, 3, 3), at(8 + i * 5, 6, BAY_Z1 - 1.6) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(230, 220, 200), nil, { Shape = CYL })
		box("Extintor", Vector3.new(2.4, 0.9, 0.9), at(9.5 + i * 5, 1.2, BAY_Z1 - 1.8) * CFrame.Angles(0, 0, math.rad(90)), RED, nil, { Shape = CYL })
	end
end

---------------------------------------------------------------------------
-- Prédio (2 andares): x de -74 a 0, z de -24 a 44. Térreo 0..14, andar de cima 14..28.
-- Marco 9.14: planta refeita (o Luís achou as salas soltas e não achou a escada).
--   TÉRREO                                   ANDAR DE CIMA
--   frente: recepção/museu (com a escada     frente: alojamento | hall da escada (porta da
--           em U no canto) | comando                 varanda) | refeitório e cozinha
--   meio:   corredor (porta para o pátio)    meio:   corredor
--   fundo:  central 193 | vestiário (farda)  fundo:  academia | sala de instrução | descanso
--           | almoxarifado                           (porta do mezanino e do cano)
-- Cada porta tem placa com o nome da sala. Luz mais fraca e paredes menos brancas.
---------------------------------------------------------------------------
local B_X0, B_X1, B_Z0, B_Z1 = -74, 0, -24, 44
local F2, TOP = 14, 28
local DOOR_X0, DOOR_X1 = -54, -44 -- porta de vidro da frente
-- escada em U: lance 1 sobe para o fundo (x -29..-24), patamar, lance 2 volta para a frente (x -34..-29)
local ST_X0, ST_XM, ST_X1, ST_Z0, ST_Z1 = -34, -29, -24, -14, 4
local LANDING_Z = -3.5
local C_Z0, C_Z1 = 4, 10 -- corredor do térreo
local UC_Z0, UC_Z1 = 10, 16 -- corredor de cima
local WALL = Color3.fromRGB(192, 188, 180) -- Marco 9.14: menos branco (estourava com a luz)
local FLOOR = Color3.fromRGB(176, 170, 160)
local SLAB = Color3.fromRGB(190, 186, 178)

-- luz de teto mais suave que a do pátio
local function roomLamp(x, y, z)
	local p = block("Luminaria", x - 2, x + 2, y - 0.2, y, z - 2, z + 2, Color3.fromRGB(200, 196, 182), Enum.Material.Neon, { CanCollide = false })
	light(p, 20, 0.35)
	return p
end

-- placa com o nome da sala em cima de uma porta; face = lado da parede que fica no corredor
local function doorSign(x, y, z, alongX, text, face)
	local p
	if alongX then
		p = block("PlacaSala", x - 3, x + 3, y, y + 1.2, z - 0.65, z + 0.65, Color3.fromRGB(30, 32, 38))
	else
		p = block("PlacaSala", x - 0.65, x + 0.65, y, y + 1.2, z - 3, z + 3, Color3.fromRGB(30, 32, 38))
	end
	sign(p, text, YELLOW, face)
	-- os dois lados da parede
	local back = ({ [Enum.NormalId.Front] = Enum.NormalId.Back, [Enum.NormalId.Back] = Enum.NormalId.Front, [Enum.NormalId.Left] = Enum.NormalId.Right, [Enum.NormalId.Right] = Enum.NormalId.Left })[face]
	sign(p, text, YELLOW, back)
	return p
end

local function buildStairs()
	local steps = 7
	local run = (LANDING_Z - ST_Z0) / steps
	-- lance 1: sobe para +Z de 0 a 7
	for i = 0, steps - 1 do
		block("Degrau", ST_XM, ST_X1, 0, i + 1, ST_Z0 + i * run, ST_Z0 + (i + 1) * run, CONCRETE, Enum.Material.Concrete)
		block("Faixa", ST_XM, ST_X1, i + 1, i + 1.05, ST_Z0 + (i + 1) * run - 0.4, ST_Z0 + (i + 1) * run, YELLOW, nil, { CanCollide = false })
	end
	-- patamar
	block("Patamar", ST_X0, ST_X1, 0, 7, LANDING_Z, ST_Z1, CONCRETE, Enum.Material.Concrete)
	-- lance 2: volta para -Z de 7 a 14
	for i = 0, steps - 1 do
		local z1 = LANDING_Z - i * run
		block("Degrau", ST_X0, ST_XM, 0, 7 + i + 1, z1 - run, z1, CONCRETE, Enum.Material.Concrete)
		block("Faixa", ST_X0, ST_XM, 7 + i + 1, 7 + i + 1.05, z1 - run, z1 - run + 0.4, YELLOW, nil, { CanCollide = false })
	end
	-- mureta no meio dos lances e corrimão de fora (lance 1 fica de frente para a recepção)
	block("MuretaEscada", ST_XM - 0.2, ST_XM + 0.2, 0, F2 + 3.5, ST_Z0, LANDING_Z, WALL)
	local a = at(ST_X1 - 0.2, 3, ST_Z0)
	local b = at(ST_X1 - 0.2, 10, LANDING_Z)
	box("Corrimao", Vector3.new(0.3, 0.3, (b.Position - a.Position).Magnitude), CFrame.lookAt((a.Position + b.Position) / 2, b.Position), YELLOW, Enum.Material.Metal)
	for k = 0, 3 do
		local z = ST_Z0 + 0.3 + k * (LANDING_Z - ST_Z0 - 0.6) / 3
		local top = 3 + (z - ST_Z0) / (LANDING_Z - ST_Z0) * 7
		block("PosteCorrimao", ST_X1 - 0.35, ST_X1 - 0.05, 0, top, z - 0.15, z + 0.15, YELLOW, Enum.Material.Metal)
	end
	-- placa na frente da escada
	local placa = block("PlacaEscada", ST_XM + 0.5, ST_X1 - 0.5, 10.5, 12.5, ST_Z0 - 0.15, ST_Z0, Color3.fromRGB(30, 32, 38), nil, { CanCollide = false })
	sign(placa, "ESCADA: 2º ANDAR\nalojamento, refeitório, academia", YELLOW)
end

local function bunk(x, z)
	for _, y in ipairs({ 1.6, 5.2 }) do
		block("Colchao", x - 2.2, x + 2.2, F2 + y, F2 + y + 0.8, z - 4.5, z + 4.5, Color3.fromRGB(235, 235, 240))
		block("Coberta", x - 2.25, x + 2.25, F2 + y + 0.5, F2 + y + 0.85, z - 1.5, z + 4.5, DARK_RED)
		block("Travesseiro", x - 1.6, x + 1.6, F2 + y + 0.8, F2 + y + 1.3, z - 4.3, z - 3, WHITE)
	end
	for _, dx in ipairs({ -2.3, 2.3 }) do
		for _, dz in ipairs({ -4.6, 4.6 }) do
			block("PeBeliche", x + dx - 0.2, x + dx + 0.2, F2, F2 + 7, z + dz - 0.2, z + dz + 0.2, STEEL, Enum.Material.Metal)
		end
	end
	block("Escadinha", x + 2.3, x + 2.5, F2, F2 + 6, z + 2, z + 3, STEEL, Enum.Material.Metal, { CanCollide = false })
end

local function desk(x0, x1, y, z0, z1)
	block("Mesa", x0, x1, y + 2.8, y + 3.1, z0, z1, WOOD, Enum.Material.Wood)
	for _, x in ipairs({ x0 + 0.3, x1 - 0.3 }) do
		block("PeMesa", x - 0.2, x + 0.2, y, y + 2.8, z0 + 0.2, z1 - 0.2, BLACK, Enum.Material.Metal)
	end
end

local function chair(x, y, z, faceZ)
	block("Assento", x - 0.9, x + 0.9, y + 1.6, y + 1.9, z - 0.9, z + 0.9, BLACK)
	block("Encosto", x - 0.9, x + 0.9, y + 1.9, y + 4, z + faceZ * 0.9 - 0.15, z + faceZ * 0.9 + 0.15, BLACK)
	block("PeCadeira", x - 0.15, x + 0.15, y, y + 1.6, z - 0.15, z + 0.15, STEEL, Enum.Material.Metal)
end

local function buildBuilding(g)
	-- zona "dentro" para a luz (LightingController baixa o céu aqui dentro)
	local zone = block("ZonaInterna", B_X0, B_X1, 0, TOP, B_Z0, B_Z1, WHITE, nil, { Transparency = 1, CanCollide = false, CanQuery = false })
	zone.CanTouch = false
	zone:SetAttribute("Indoor", true)

	-- pisos e lajes (vão da escada aberto)
	block("PisoTerreo", B_X0, B_X1, -0.6, 0, B_Z0, B_Z1, FLOOR, Enum.Material.Slate)
	block("Laje", B_X0, B_X1, F2 - 0.8, F2, B_Z0, ST_Z0, SLAB)
	block("Laje", B_X0, B_X1, F2 - 0.8, F2, ST_Z1, B_Z1, SLAB)
	block("Laje", B_X0, ST_X0, F2 - 0.8, F2, ST_Z0, ST_Z1, SLAB)
	block("Laje", ST_X1, B_X1, F2 - 0.8, F2, ST_Z0, ST_Z1, SLAB)
	block("PisoCima", B_X0, B_X1, F2, F2 + 0.05, B_Z0, ST_Z0, Color3.fromRGB(150, 120, 95), Enum.Material.WoodPlanks, { CanCollide = false })
	block("Telhado", B_X0 - 1, B_X1 + 1, TOP, TOP + 1, B_Z0 - 1, B_Z1 + 1, Color3.fromRGB(90, 90, 95))
	-- guarda-corpo em volta do vão da escada (aberto onde o lance 2 chega, x -34..-29 na frente)
	block("GuardaCorpo", ST_XM, ST_X1, F2 + 3.4, F2 + 3.8, ST_Z0 - 0.2, ST_Z0 + 0.2, YELLOW, Enum.Material.Metal)
	block("GuardaCorpo", ST_X1 - 0.2, ST_X1 + 0.2, F2 + 3.4, F2 + 3.8, ST_Z0, ST_Z1, YELLOW, Enum.Material.Metal)
	block("GuardaCorpo", ST_X0 - 0.2, ST_X0 + 0.2, F2 + 3.4, F2 + 3.8, ST_Z0, ST_Z1, YELLOW, Enum.Material.Metal)
	block("GuardaCorpo", ST_X0, ST_X1, F2 + 3.4, F2 + 3.8, ST_Z1 - 0.2, ST_Z1 + 0.2, YELLOW, Enum.Material.Metal)
	for _, x in ipairs({ ST_X0, ST_X1 }) do
		for z = ST_Z0, ST_Z1, 3 do
			block("GuardaCorpo", x - 0.12, x + 0.12, F2, F2 + 3.4, z - 0.12, z + 0.12, YELLOW, Enum.Material.Metal)
		end
	end
	buildStairs()

	-- FACHADA --------------------------------------------------------------
	-- base escura, faixa de janelas de vidro escuro com caixilho preto e a porta de vidro (sem
	-- caixilho no meio: a barra atrapalhava a passagem)
	wallX("Fachada", B_X0, B_X1, B_Z0, 0, 3.5, BLACK, { { (DOOR_X0 + DOOR_X1) / 2, DOOR_X1 - DOOR_X0, 3.5 } }, 1.2)
	for x = B_X0, B_X1 - 5, 5 do
		local inDoor = x >= DOOR_X0 and x < DOOR_X1
		if not inDoor then
			block("Janela", x, x + 5, 3.5, 10, B_Z0 - 0.3, B_Z0 + 0.3, GLASS, nil, { Transparency = 0.35, Reflectance = 0.15 })
		end
		if not (x > DOOR_X0 and x < DOOR_X1) then
			block("Caixilho", x - 0.15, x + 0.15, 3.5, 10, B_Z0 - 0.5, B_Z0 + 0.5, BLACK)
		end
	end
	block("Caixilho", B_X1 - 4, B_X1, 0, 10, B_Z0 - 0.5, B_Z0 + 0.5, BLACK)
	block("Vergamestra", B_X0, B_X1, 10, F2, B_Z0 - 0.6, B_Z0 + 0.6, BLACK)
	block("PortaVidro", DOOR_X0, DOOR_X1, 0, 10, B_Z0 - 0.1, B_Z0 + 0.1, GLASS, nil, { Transparency = 0.7, CanCollide = false, CanQuery = false })
	local entrada = block("PlacaEntrada", DOOR_X0, DOOR_X1, 10.4, 12.6, B_Z0 - 0.75, B_Z0 - 0.6, BLACK, nil, { CanCollide = false })
	sign(entrada, "RECEPÇÃO", WHITE)
	-- marquise vermelha com "UNIDADE ..." e brasão; também é o piso da varanda de cima
	block("Marquise", B_X0 - 1, B_X1 + 1, F2 - 3, F2, B_Z0 - 8, B_Z0, RED)
	for x = B_X0 + 6, B_X1 - 4, 12 do
		lamp(x, F2 - 3.05, B_Z0 - 4, 4, 0.6)
	end
	local unidade = block("Unidade", -40, -6, F2 - 2.7, F2 - 0.3, B_Z0 - 8.06, B_Z0 - 8, RED, nil, { Transparency = 1, CanCollide = false })
	sign(unidade, "UNIDADE " .. string.upper(GameConfig.FireStation.UnitName), YELLOW)
	emblem(at(-49, F2 - 1.5, B_Z0 - 8.2), 1.3)
	-- andar de cima: parede vermelha com janelas e porta para a varanda (no hall da escada)
	wallX("FachadaCima", B_X0, B_X1, B_Z0 + 2, F2, TOP, RED, { { -38, 5, 9 } })
	for _, x in ipairs({ -66, -56, -48, -28, -16, -6 }) do
		block("Janela", x - 2.5, x + 2.5, F2 + 5, F2 + 9.5, B_Z0 + 1.3, B_Z0 + 1.5, GLASS, nil, { Transparency = 0.2, Reflectance = 0.15 })
		block("Moldura", x - 2.8, x + 2.8, F2 + 4.7, F2 + 9.8, B_Z0 + 1.45, B_Z0 + 1.5, WHITE)
	end
	block("GuardaCorpo", B_X0, B_X1, F2 + 3.4, F2 + 3.8, B_Z0 - 7.8, B_Z0 - 7.4, YELLOW, Enum.Material.Metal)
	for x = B_X0, B_X1, 4 do
		block("GuardaCorpo", x - 0.12, x + 0.12, F2, F2 + 3.4, B_Z0 - 7.75, B_Z0 - 7.45, YELLOW, Enum.Material.Metal)
	end
	for _, x in ipairs({ B_X0, B_X1 }) do
		block("GuardaCorpo", x - 0.2, x + 0.2, F2 + 3.4, F2 + 3.8, B_Z0 - 7.8, B_Z0, YELLOW, Enum.Material.Metal)
	end

	-- paredes externas
	wallZ("ParedeLado", B_Z0, B_Z1, B_X0, 0, TOP, GREY, nil, 1.2)
	wallX("ParedeFundo", B_X0, B_X1, B_Z1, 0, TOP, GREY, nil, 1.2)
	-- parede entre o prédio e o pátio: porta do corredor embaixo, porta do mezanino em cima
	wallZ("ParedePatioPredio", B_Z0, B_Z1, B_X1, 0, F2, GREY, { { (C_Z0 + C_Z1) / 2, 6, 10 } }, 1)
	wallZ("ParedePatioPredio", B_Z0, B_Z1, B_X1, F2, TOP, GREY, { { 24, 6, 9 } }, 1)

	-- TÉRREO --------------------------------------------------------------
	local H = F2 - 0.8
	-- recepção x -74..-24 (escada no canto de trás à direita) | comando x -24..0
	wallZ("Divisoria", B_Z0, C_Z0, -24, 0, H, WALL, nil)
	-- corredor: parede da frente (recepção aberta num vão largo; porta do comando)
	wallX("Divisoria", B_X0, B_X1, C_Z0, 0, H, WALL, { { -56, 14, 10 }, { -12, 5, 9 } })
	-- corredor: parede do fundo com as portas das 3 salas
	wallX("Divisoria", B_X0, B_X1, C_Z1, 0, H, WALL, { { -60, 5, 9 }, { -32, 5, 9 }, { -10, 5, 9 } })
	wallZ("Divisoria", C_Z1, B_Z1, -44, 0, H, WALL, nil)
	wallZ("Divisoria", C_Z1, B_Z1, -20, 0, H, WALL, nil)
	doorSign(-60, 9.4, C_Z1, true, "CENTRAL 193", Enum.NormalId.Front)
	doorSign(-32, 9.4, C_Z1, true, "VESTIÁRIO", Enum.NormalId.Front)
	doorSign(-10, 9.4, C_Z1, true, "ALMOXARIFADO", Enum.NormalId.Front)
	doorSign(-12, 9.4, C_Z0, true, "COMANDO", Enum.NormalId.Back)
	block("FaixaCorredor", B_X0 + 1, B_X1 - 1, 0, 0.03, C_Z0 + 2.6, C_Z0 + 3.4, RED, nil, { CanCollide = false })
	for _, x in ipairs({ -64, -40, -16 }) do
		roomLamp(x, H, (C_Z0 + C_Z1) / 2)
	end

	-- recepção / museu: balcão em L, cadeiras de espera, vitrine de capacetes, painel e plantas
	block("Recepcao", -46, -34, 0, 3.6, -10, -7.5, RED)
	block("Recepcao", -46, -43.5, 0, 3.6, -7.5, -2, RED)
	block("RecepcaoTampo", -46.3, -33.7, 3.6, 3.9, -10.3, -7.2, BLACK)
	block("RecepcaoTampo", -46.3, -43.2, 3.6, 3.9, -7.2, -1.7, BLACK)
	chair(-40, 0, -5, 1)
	block("Computador", -41, -38.5, 3.9, 5.6, -9.4, -9.1, BLACK)
	local tela = block("TelaPC", -40.9, -38.6, 4, 5.5, -9.1, -9.05, Color3.fromRGB(40, 110, 190), Enum.Material.Neon, { CanCollide = false })
	tela.Color = Color3.fromRGB(35, 90, 150)
	for k = 0, 3 do
		chair(-70 + k * 2.6, 0, -2, 1)
	end
	local vitrineX, vitrineZ = -64, -16
	block("VitrineBase", vitrineX - 5, vitrineX + 5, 0, 3, vitrineZ - 3, vitrineZ + 3, Color3.fromRGB(220, 205, 180))
	block("Vitrine", vitrineX - 5, vitrineX + 5, 3, 8, vitrineZ - 3, vitrineZ + 3, Color3.fromRGB(190, 215, 230), nil, { Transparency = 0.7, Reflectance = 0.1 })
	block("VitrineTampo", vitrineX - 5.2, vitrineX + 5.2, 8, 8.4, vitrineZ - 3.2, vitrineZ + 3.2, DARK_RED)
	local helmetColors = { YELLOW, RED, WHITE, BLACK, Color3.fromRGB(230, 140, 30), RED }
	for i, col in ipairs(helmetColors) do
		local hx = vitrineX - 3.5 + ((i - 1) % 3) * 3.5
		local hz = vitrineZ + (i <= 3 and -1.2 or 1.2)
		box("Capacete", Vector3.new(1.6, 1.6, 1.6), at(hx, 3.8, hz), col, nil, { Shape = BALL, CanCollide = false })
		block("Aba", hx - 1, hx + 1, 3.2, 3.4, hz - 1, hz + 1, col, nil, { CanCollide = false })
	end
	local museu = block("PlacaMuseu", vitrineX - 4, vitrineX + 4, 8.6, 9.8, vitrineZ - 0.1, vitrineZ + 0.1, BLACK, nil, { CanCollide = false })
	sign(museu, "MEMÓRIA DOS BOMBEIROS", YELLOW, Enum.NormalId.Front)
	local painel = block("Painel", B_X0 + 0.7, B_X0 + 0.9, 3, 11, -14, 0, BLACK)
	sign(painel, "VIDA ALHEIA E RIQUEZAS SALVAR", Color3.fromRGB(255, 150, 60), Enum.NormalId.Right)
	for _, x in ipairs({ -72, -26 }) do
		block("Vaso", x - 0.8, x + 0.8, 0, 1.6, -22, -20.4, Color3.fromRGB(70, 60, 55))
		box("Planta", Vector3.new(2.6, 3, 2.6), at(x, 3, -21.2), Color3.fromRGB(50, 120, 60), Enum.Material.Grass, { Shape = BALL, CanCollide = false })
	end
	block("Tapete", DOOR_X0, DOOR_X1, 0, 0.05, B_Z0 + 0.6, B_Z0 + 5, DARK_RED, Enum.Material.Fabric, { CanCollide = false })
	roomLamp(-62, H, -12)
	roomLamp(-46, H, -14)
	roomLamp(-40, H, -2)

	-- comando: mesa do comandante, bandeiras, estante e mesa de reunião
	desk(-14, -4, 0, -20, -16)
	chair(-9, 0, -14, 1)
	chair(-9, 0, -22, -1)
	block("Estante", -23.4, -22.4, 0, 9, -20, -8, WOOD, Enum.Material.Wood)
	for y = 2, 8, 2 do
		block("Livros", -23.5, -22.4, y, y + 1.4, -19.5, -8.5, Color3.fromRGB(120, 40, 40))
	end
	for k, col in ipairs({ Color3.fromRGB(0, 150, 60), RED }) do
		block("Mastro", -3 - k * 2, -2.8 - k * 2, 0, 9, -22.5, -22.3, STEEL, Enum.Material.Metal)
		block("Bandeira", -2.8 - k * 2, -0.4 - k * 2, 6, 8.5, -22.45, -22.35, col, Enum.Material.Fabric, { CanCollide = false })
	end
	desk(-18, -6, 0, -4, 1)
	for _, x in ipairs({ -16, -12, -8 }) do
		chair(x, 0, -5.5, -1)
		chair(x, 0, 2.5, 1)
	end
	roomLamp(-12, H, -14)
	roomLamp(-12, H, -2)

	-- central 193 (x -74..-44, z 10..44): mesas com 3 monitores, telão e mapa da cidade
	for i = 0, 2 do
		local z = 18 + i * 8
		desk(-70, -50, 0, z - 1.5, z + 1.5)
		for j = 0, 3 do
			local x = -68 + j * 4.5
			block("Monitor", x, x + 3, 3.1, 5.4, z + 0.6, z + 0.9, BLACK)
			block("Tela", x + 0.1, x + 2.9, 3.2, 5.3, z + 0.55, z + 0.6, Color3.fromRGB(35, 90, 150), Enum.Material.Neon, { CanCollide = false })
			chair(x + 1.5, 0, z - 2.6, -1)
		end
	end
	local telao = block("Telao", -70, -48, 4, 12, B_Z1 - 1.2, B_Z1 - 0.8, BLACK)
	local tl = sign(telao, "CENTRAL 193\nOCORRÊNCIAS AO VIVO", Color3.fromRGB(255, 80, 60), Enum.NormalId.Front)
	tl.BackgroundTransparency = 0
	tl.BackgroundColor3 = Color3.fromRGB(15, 20, 30)
	local mapa = block("MapaCidade", -44.9, -44.7, 3, 10, 16, 30, Color3.fromRGB(60, 120, 80))
	sign(mapa, "MAPA DE " .. string.upper(GameConfig.CityName), WHITE, Enum.NormalId.Left)
	roomLamp(-60, H, 20)
	roomLamp(-60, H, 34)

	-- vestiário (x -44..-20): armários da farda, bancos e chuveiros
	-- Marco 9.11: dois armários têm a farda (UniformService acha pelo atributo UniformLocker)
	for i = 0, 6 do
		local x = -43 + i * 3.1
		local armario = block("Armario", x, x + 3, 0, 8, B_Z1 - 3.5, B_Z1 - 0.7, RED, Enum.Material.Metal)
		if i == 2 or i == 4 then
			armario.Name = "ArmarioFarda"
			armario:SetAttribute("UniformLocker", "Bombeiro")
			sign(block("PlacaFarda", x + 0.3, x + 2.7, 6, 7, B_Z1 - 3.62, B_Z1 - 3.5, BLACK), "FARDA", YELLOW)
		end
		block("Puxador", x + 2.3, x + 2.5, 3.5, 5, B_Z1 - 3.6, B_Z1 - 3.5, STEEL, Enum.Material.Metal)
	end
	block("BancoVestiario", -40, -24, 0, 1.8, 30, 32, WOOD, Enum.Material.Wood)
	for k = 0, 2 do
		local z = 13 + k * 5
		block("Box", -43.5, -38, 0, 8, z + 4.4, z + 4.6, Color3.fromRGB(200, 220, 230))
		block("Chuveiro", -43.4, -42.6, 6.5, 7.2, z + 1.8, z + 2.6, STEEL, Enum.Material.Metal)
		block("PisoBox", -43.5, -38, 0, 0.05, z, z + 4.4, Color3.fromRGB(120, 150, 170), Enum.Material.Slate, { CanCollide = false })
	end
	for _, x in ipairs({ -30, -26 }) do
		box("Bota", Vector3.new(0.9, 1.6, 1.6), at(x, 0.8, 34), BLACK)
		box("Jaqueta", Vector3.new(2, 3, 0.6), at(x, 6, 11), Color3.fromRGB(210, 150, 40))
	end
	roomLamp(-32, H, 20)
	roomLamp(-32, H, 36)

	-- almoxarifado (x -20..0): prateleiras com capacetes, cilindros de ar e mangueiras
	for _, x in ipairs({ -18, -10 }) do
		block("Prateleira", x, x + 6, 0, 9, 38, 42, STEEL, Enum.Material.Metal)
		for y = 2.5, 7.5, 2.5 do
			block("Tabua", x - 0.1, x + 6.1, y, y + 0.2, 37.8, 42, Color3.fromRGB(80, 82, 88), Enum.Material.Metal)
			box("Capacete", Vector3.new(1.4, 1.4, 1.4), at(x + 1.5, y + 0.9, 39), YELLOW, nil, { Shape = BALL, CanCollide = false })
			box("Capacete", Vector3.new(1.4, 1.4, 1.4), at(x + 4.5, y + 0.9, 39), RED, nil, { Shape = BALL, CanCollide = false })
		end
	end
	for k = 0, 4 do
		box("CilindroAr", Vector3.new(3, 1, 1), at(-3, 1.5, 14 + k * 1.4) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(240, 200, 40), Enum.Material.Metal, { Shape = CYL })
	end
	for k = 0, 2 do
		box("Mangueira", Vector3.new(0.8, 3, 3), at(-16 + k * 4, 1.5, 20), Color3.fromRGB(230, 220, 200), nil, { Shape = CYL })
	end
	roomLamp(-10, H, 20)
	roomLamp(-10, H, 36)

	-- ANDAR DE CIMA -------------------------------------------------------
	local UH = TOP - 0.2
	-- frente: alojamento x -74..-44 | hall da escada x -44..-20 | refeitório x -20..0
	wallZ("DivisoriaCima", B_Z0 + 2, UC_Z0, -44, F2, UH, WALL, { { -4, 5, 9 } })
	wallZ("DivisoriaCima", B_Z0 + 2, UC_Z0, -20, F2, UH, WALL, { { -4, 5, 9 } })
	-- corredor de cima (z 10..16): o hall da escada abre direto nele
	wallX("DivisoriaCima", B_X0, -44, UC_Z0, F2, UH, WALL, nil)
	wallX("DivisoriaCima", -20, B_X1, UC_Z0, F2, UH, WALL, nil)
	wallX("DivisoriaCima", B_X0, B_X1, UC_Z1, F2, UH, WALL, { { -58, 5, 9 }, { -30, 5, 9 }, { -10, 5, 9 } })
	wallZ("DivisoriaCima", UC_Z1, B_Z1, -40, F2, UH, WALL, nil)
	wallZ("DivisoriaCima", UC_Z1, B_Z1, -20, F2, UH, WALL, nil)
	doorSign(-44, F2 + 9.4, -4, false, "ALOJAMENTO", Enum.NormalId.Right)
	doorSign(-20, F2 + 9.4, -4, false, "REFEITÓRIO", Enum.NormalId.Left)
	doorSign(-58, F2 + 9.4, UC_Z1, true, "ACADEMIA", Enum.NormalId.Front)
	doorSign(-30, F2 + 9.4, UC_Z1, true, "INSTRUÇÃO", Enum.NormalId.Front)
	doorSign(-10, F2 + 9.4, UC_Z1, true, "DESCANSO · MEZANINO", Enum.NormalId.Front)
	for _, x in ipairs({ -64, -10 }) do
		roomLamp(x, UH, (UC_Z0 + UC_Z1) / 2)
	end
	roomLamp(-38, UH, -16)
	roomLamp(-26, UH, 8)

	-- alojamento: 2 fileiras de beliches com armarinhos
	for _, x in ipairs({ -70, -61, -52 }) do
		bunk(x, -14)
		bunk(x, 2)
		block("Armarinho", x - 2, x + 2, F2, F2 + 6, -21.5, -20, Color3.fromRGB(120, 125, 135), Enum.Material.Metal)
	end
	block("TapeteAlojamento", -72, -46, F2, F2 + 0.05, -8, -4, Color3.fromRGB(40, 60, 120), Enum.Material.Fabric, { CanCollide = false })
	roomLamp(-60, UH, -16)
	roomLamp(-60, UH, 4)

	-- refeitório e cozinha
	desk(-17, -7, F2, -12, -6)
	for _, x in ipairs({ -15, -12, -9 }) do
		chair(x, F2, -13.4, -1)
		chair(x, F2, -4.6, 1)
	end
	block("Bancada", -19, -1.5, F2, F2 + 3.4, 6, 9.4, GREY)
	block("Fogao", -16, -11, F2 + 3.4, F2 + 3.6, 6.5, 9, BLACK)
	block("Pia", -9, -5, F2 + 3.4, F2 + 3.5, 6.5, 9, STEEL, Enum.Material.Metal)
	block("Geladeira", -4, -1, F2, F2 + 9, -21, -17, Color3.fromRGB(230, 230, 232), Enum.Material.Metal)
	block("Cafeteira", -3, -1.8, F2 + 3.4, F2 + 5, 7, 8.2, RED)
	roomLamp(-10, UH, -14)
	roomLamp(-10, UH, 2)

	-- academia (x -74..-40): esteiras, supino, halteres e saco de pancada
	block("Tatame", -73, -41, F2, F2 + 0.15, UC_Z1 + 1, B_Z1 - 1, Color3.fromRGB(40, 60, 120))
	for k = 0, 1 do
		local x = -70 + k * 6
		block("Esteira", x, x + 4, F2, F2 + 1.2, 34, 42, BLACK)
		block("EsteiraPainel", x, x + 4, F2 + 4, F2 + 5, 33.5, 34.2, BLACK)
		block("EsteiraBraco", x + 0.2, x + 0.6, F2, F2 + 4.5, 33.6, 34.2, STEEL)
		block("EsteiraBraco", x + 3.4, x + 3.8, F2, F2 + 4.5, 33.6, 34.2, STEEL)
	end
	block("BancoSupino", -56, -54, F2, F2 + 2, 22, 28, BLACK)
	box("Barra", Vector3.new(7, 0.3, 0.3), at(-55, 4.2 + F2, 23), STEEL, Enum.Material.Metal)
	for _, dx in ipairs({ -3.5, 3.5 }) do
		box("Anilha", Vector3.new(0.4, 2.2, 2.2), at(-55 + dx, 4.2 + F2, 23), BLACK, nil, { Shape = CYL })
	end
	local saco = box("SacoPancada", Vector3.new(5, 2, 2), at(-46, F2 + 7, 36), RED, nil, { Shape = CYL })
	saco.CFrame = at(-46, F2 + 7, 36) * CFrame.Angles(0, 0, math.rad(90))
	block("Corrente", -46.1, -45.9, F2 + 9.5, TOP, 35.9, 36.1, STEEL, nil, { CanCollide = false })
	block("Espelho", -73.3, -73.1, F2 + 2, F2 + 10, 20, 40, Color3.fromRGB(200, 215, 225), nil, { Reflectance = 0.4 })
	roomLamp(-58, UH, 24)
	roomLamp(-58, UH, 38)

	-- sala de instrução (x -40..-20): carteiras viradas para o quadro
	local quadro = block("Quadro", -38, -22, F2 + 3, F2 + 10, B_Z1 - 1.2, B_Z1 - 0.8, Color3.fromRGB(30, 70, 50))
	sign(quadro, "INSTRUÇÃO: COMBATE A INCÊNDIO\n1. Avalie  2. Isole  3. Combata", WHITE, Enum.NormalId.Front)
	for row = 0, 2 do
		for col = 0, 2 do
			local x, z = -35 + col * 6, 22 + row * 6
			desk(x - 1.6, x + 1.6, F2, z - 1, z + 1)
			chair(x, F2, z - 2.2, -1)
		end
	end
	roomLamp(-30, UH, 24)
	roomLamp(-30, UH, 38)

	-- descanso (x -20..0): sofás, TV e a porta do mezanino (cano de descida)
	block("Sofa", -19, -11, F2, F2 + 2, 36, 40, Color3.fromRGB(60, 65, 80), Enum.Material.Fabric)
	block("SofaEncosto", -19, -11, F2 + 2, F2 + 4.5, 39, 40, Color3.fromRGB(60, 65, 80), Enum.Material.Fabric)
	block("MesaCentro", -18, -12, F2, F2 + 1.4, 29, 33, WOOD, Enum.Material.Wood)
	local tv = block("TV", -19.5, -13.5, F2 + 4, F2 + 8.5, UC_Z1 + 0.6, UC_Z1 + 0.9, BLACK)
	local tvTela = sign(tv, "BOMBEIROS 193", WHITE, Enum.NormalId.Back)
	tvTela.BackgroundTransparency = 0
	tvTela.BackgroundColor3 = Color3.fromRGB(25, 60, 110)
	roomLamp(-10, UH, 26)
	roomLamp(-10, UH, 38)
end

---------------------------------------------------------------------------
-- Mezanino dentro do pátio e o cano de descida
---------------------------------------------------------------------------
local function buildMezzanine(g)
	-- passarela de 7 de largura encostada na parede do prédio (x de 0 a 7), z de 14 a 40
	block("Mezanino", BAY_X0, BAY_X0 + 7, F2 - 0.8, F2, 14, 40, CONCRETE, Enum.Material.Concrete)
	block("GuardaCorpo", BAY_X0 + 6.8, BAY_X0 + 7.2, F2 + 3.4, F2 + 3.8, 14, 40, YELLOW, Enum.Material.Metal)
	block("GuardaCorpo", BAY_X0, BAY_X0 + 7.2, F2 + 3.4, F2 + 3.8, 13.8, 14.2, YELLOW, Enum.Material.Metal)
	for z = 14, 40, 3.25 do
		if math.abs(z - 34) > 2 then
			block("GuardaCorpo", BAY_X0 + 6.85, BAY_X0 + 7.15, F2, F2 + 3.4, z - 0.15, z + 0.15, YELLOW, Enum.Material.Metal)
		end
	end
	for _, z in ipairs({ 16, 38 }) do
		block("PilarMezanino", BAY_X0 + 5.5, BAY_X0 + 6.5, 0, F2 - 0.8, z - 0.5, z + 0.5, STEEL, Enum.Material.Metal)
	end
	-- cano (latão), saindo do mezanino até o chão, com um buraco no guarda-corpo
	local poleX, poleZ = BAY_X0 + 8.5, 34
	local pole = box("Cano", Vector3.new(F2 + 6, 0.6, 0.6), at(poleX, (F2 + 6) / 2, poleZ) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(215, 175, 60), Enum.Material.Metal, { Shape = CYL })
	pole.Parent = g
	box("ColchaoCano", Vector3.new(0.6, 4, 4), at(poleX, 0.3, poleZ), Color3.fromRGB(30, 30, 120), nil, { Shape = CYL }).CFrame = at(poleX, 0.3, poleZ) * CFrame.Angles(0, 0, math.rad(90))
	-- onde o jogador fica em cima (aviso) e onde ele chega embaixo
	local top = box("CanoTopo", Vector3.new(2, 2, 2), at(poleX - 2, F2 + 2, poleZ), WHITE, nil, { Transparency = 1, CanCollide = false })
	top.CanQuery = false
	top.Parent = g
	local bottom = box("CanoBase", Vector3.new(2, 2, 2), at(poleX + 2, 2, poleZ), WHITE, nil, { Transparency = 1, CanCollide = false })
	bottom.CanQuery = false
	bottom.CanTouch = false
	bottom.Parent = g
	local placa = block("PlacaCano", BAY_X0 + 0.6, BAY_X0 + 0.7, F2 + 4, F2 + 6, 31, 37, BLACK, nil, { CanCollide = false })
	sign(placa, "CANO: DESCER EM CASO DE CHAMADO", YELLOW, Enum.NormalId.Right)
end

---------------------------------------------------------------------------
-- Área externa: pátio de pavers, canteiro de pinheirinhos, mastro, torre de treinamento, muro
---------------------------------------------------------------------------
local function buildOutside(g)
	local W, D = FireStationBuilder.W, FireStationBuilder.D
	block("Base", -W / 2, W / 2, -0.7, -0.05, -D / 2, D / 2, CONCRETE, Enum.Material.Concrete)
	block("Patio", -W / 2, W / 2, -0.6, 0.02, -D / 2, B_Z0 - 8, PAVER, Enum.Material.Brick)
	-- canteiro com pinheirinhos na frente do prédio (fotos 3 e 4)
	-- (Marco 9.14: aberto na frente da porta da recepção)
	for _, span in ipairs({ { B_X0 + 2, -58 }, { -40, -26 } }) do
		block("Canteiro", span[1], span[2], 0, 0.8, B_Z0 - 13, B_Z0 - 10, Color3.fromRGB(70, 140, 60), Enum.Material.Grass)
		block("MeioFio", span[1] - 0.4, span[2] + 0.4, 0, 1, B_Z0 - 13.4, B_Z0 - 13, CONCRETE)
		for x = span[1] + 3, span[2] - 2, 6 do
			pine(x, B_Z0 - 11.5, 7)
		end
	end
	-- mastro com bandeira
	local mx, mz = -10, -48
	box("Mastro", Vector3.new(0.5, 30, 0.5), at(mx, 15, mz), STEEL, Enum.Material.Metal, { Shape = Enum.PartType.Block })
	box("BaseMastro", Vector3.new(0.6, 4, 4), at(mx, 0.3, mz), RED, nil, { Shape = CYL }).CFrame = at(mx, 0.3, mz) * CFrame.Angles(0, 0, math.rad(90))
	local flag = block("Bandeira", mx + 0.3, mx + 8.3, 24, 29, mz - 0.05, mz + 0.05, RED, Enum.Material.Fabric, { CanCollide = false })
	sign(flag, "193", WHITE)
	-- torre de treinamento atrás do prédio (5 andares com janelas abertas)
	local tx0, tx1, tz0, tz1 = -70, -54, B_Z1 + 4, B_Z1 + 18
	for f = 0, 4 do
		local y0 = f * 9
		wallX("Torre", tx0, tx1, tz0, y0, y0 + 9, RED, { { (tx0 + tx1) / 2, 5, 6 } }, 1)
		wallX("Torre", tx0, tx1, tz1, y0, y0 + 9, RED, nil, 1)
		wallZ("Torre", tz0, tz1, tx0, y0, y0 + 9, RED, { { (tz0 + tz1) / 2, 5, 6 } }, 1)
		wallZ("Torre", tz0, tz1, tx1, y0, y0 + 9, RED, nil, 1)
		block("PisoTorre", tx0, tx1, y0 + 8.6, y0 + 9, tz0, tz1, CONCRETE)
	end
	local torre = block("PlacaTorre", tx0, tx1, 41, 44, tz0 - 0.6, tz0 - 0.5, BLACK, nil, { CanCollide = false })
	sign(torre, "TORRE DE TREINAMENTO", YELLOW)
	-- muro nos lados e no fundo (a frente fica aberta para a avenida)
	block("Muro", -W / 2, -W / 2 + 1, 0, 5, -D / 2, D / 2, GREY, Enum.Material.Concrete)
	block("Muro", W / 2 - 1, W / 2, 0, 5, -D / 2, D / 2, GREY, Enum.Material.Concrete)
	block("Muro", -W / 2, W / 2, 0, 5, D / 2 - 1, D / 2, GREY, Enum.Material.Concrete)
	-- postes na frente
	for _, x in ipairs({ -W / 2 + 4, -2, W / 2 - 4 }) do
		K.buildLamp(folder, at(x, -0.8 + 0.02, -D / 2 + 3))
	end
end

-- cf = CFrame do centro do lote, no chão, com a frente (-Z) virada para a avenida
-- groundY = altura do piso (o caminhão entra direto da avenida)
function FireStationBuilder.build(parent, cf, groundY, kit)
	K, lot, G = kit, cf, groundY
	local g = K.model("QuartelBombeiros", parent)
	g:SetAttribute("Garage", true)
	g:SetAttribute("ServiceJob", "Bombeiro")
	g:SetAttribute("PlaceName", GameConfig.Places.Bombeiros)
	folder = K.model("Predio", g)
	buildBays(g)
	buildBuilding(g)
	buildMezzanine(g)
	buildOutside(g)
	return g
end

return FireStationBuilder
