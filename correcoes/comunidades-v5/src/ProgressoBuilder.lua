-- ProgressoBuilder (ModuleScript)
-- Caminho: ServerScriptService > Services > ProgressoBuilder
-- Marco 10.4: Jardim Progresso, o bairro residencial dos dois lados da Avenida do Progresso
-- (entre a cidade e a Rotatória do Progresso). As ruas vêm do CityRoads (GameConfig.Progresso
-- .District) e o asfalto é do ExpansionBuilder; aqui ficam as construções, em duas etapas
-- (chamadas pelo MapBuilder), como no Bairro Horizonte:
--   1. plan(): DEPOIS das casas da cidade e ANTES do campo. Só reserva os lotes, com sorteio
--      próprio (District.Seed): não mexe em nenhuma casa que já existia.
--   2. build(): no fim (depois das favelas). Monta tudo nos lotes reservados. As casas novas
--      ganham números depois de todas as antigas, então nenhum endereço salvo muda.
--
-- O que tem:
--   * Hospital Progresso: dá para entrar. Recepção, sala de espera com TV, farmácia,
--     consultórios e 6 quartos com cama (E = deitar), pronto-socorro com 2 ambulâncias e
--     heliponto no teto;
--   * Praça do Progresso: chafariz, parquinho (balanço e escorregador), coreto, quiosque;
--   * Escola Municipal Progresso: prédio, pátio com bandeira e quadra coberta;
--   * lojinhas na avenida, 2 prédios de apartamentos, 4 casas modernas e muitas casas comuns
--     (os 3 modelos da cidade: térrea, sobrado e com garagem).
-- Coordenadas de cada lote: (0, 0, 0) = centro; -Z = frente (virada para a rua).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local CityRoads = require(Shared:WaitForChild("CityRoads"))
local HorizonteBuilder = require(script.Parent:WaitForChild("HorizonteBuilder"))

local ProgressoBuilder = {}

local PG = GameConfig.Progresso
local D = PG.District
local M = GameConfig.Map
local K -- ferramentas do MapBuilder
local rng = Random.new(D.Seed)

local G = 0.7 -- piso dos lotes
local STREET_HALF = M.RoadWidth / 2 + M.SidewalkWidth
local HOUSE_LOT_D = 38 -- igual ao MapBuilder
local SHOP_LOT_D = 34 -- prédio com lojinha (MapBuilder.buildBuilding)
local HOSPITAL_W, HOSPITAL_D = 170, 150
local PLAZA_W, PLAZA_D = 178, 168
local SCHOOL_W, SCHOOL_D = 170, 130

local WHITE = Color3.fromRGB(246, 245, 241)
local DARK = Color3.fromRGB(45, 48, 54)
local STONE = Color3.fromRGB(150, 146, 140)
local PAVING = Color3.fromRGB(214, 208, 198)
local LAWN = Color3.fromRGB(112, 178, 82)
local ASPHALT = Color3.fromRGB(70, 72, 78)
local GLASS = Color3.fromRGB(165, 205, 225)
local RED = Color3.fromRGB(205, 40, 45)
local HOSP_BLUE = Color3.fromRGB(40, 110, 170)
local WATER = Color3.fromRGB(70, 175, 230)
local WOOD = Color3.fromRGB(150, 105, 65)
local LEAVES = { Color3.fromRGB(70, 150, 60), Color3.fromRGB(85, 165, 70), Color3.fromRGB(60, 135, 55) }
local NEON_WARM = Color3.fromRGB(255, 240, 215)
local BALL = Enum.PartType.Ball
local MAT = Enum.Material

---------------------------------------------------------------------------
-- Peças
---------------------------------------------------------------------------

-- extra: shape, transparency, reflectance, collide, class, shadow
local function P(parent, name, size, cf, color, material, extra)
	extra = extra or {}
	return K.makePart(parent, {
		ClassName = extra.class,
		Name = name,
		Size = size,
		CFrame = cf,
		Color = color,
		Material = material,
		Shape = extra.shape,
		Transparency = extra.transparency,
		Reflectance = extra.reflectance,
		CanCollide = extra.collide,
		CastShadow = extra.shadow,
	})
end

-- Caixa pelos limites (x0..x1, y0..y1, z0..z1) no espaço do lote
local function box(parent, name, lot, x0, x1, y0, y1, z0, z1, color, material, extra)
	local sx, sy, sz = math.abs(x1 - x0), math.abs(y1 - y0), math.abs(z1 - z0)
	return P(parent, name, Vector3.new(sx, sy, sz), lot * CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), color, material, extra)
end

local function glow(part, range, brightness, color)
	local light = Instance.new("PointLight")
	light.Range = range
	light.Brightness = brightness
	light.Color = color or Color3.fromRGB(255, 240, 220)
	light.Parent = part
end

-- Assento com o "Sentar"/"Deitar" do SeatService (PropService.scan liga no mapa)
local function seat(parent, cf, size, color, text, material)
	local s = P(parent, "Assento", size, cf, color, material or MAT.Fabric, { class = "Seat" })
	s:SetAttribute("SeatText", text)
	return s
end

local function tree(parent, pos, scale)
	local t = K.model("Arvore", parent)
	local h = 7 * scale
	P(t, "Tronco", Vector3.new(1.3 * scale, h, 1.3 * scale), CFrame.new(pos + Vector3.new(0, h / 2, 0)), GameConfig.Colors.Trunk, MAT.Wood)
	P(t, "Copa", Vector3.new(8, 8, 8) * scale, CFrame.new(pos + Vector3.new(0, h + 2.5 * scale, 0)), LEAVES[rng:NextInteger(1, #LEAVES)], MAT.Grass, { shape = BALL, collide = false })
end

-- Banco de praça (assento de verdade)
local function bench(parent, cf)
	seat(parent, cf * CFrame.new(0, 1.6, 0), Vector3.new(5, 0.4, 1.6), WOOD, "Banco", MAT.WoodPlanks)
	P(parent, "Encosto", Vector3.new(5, 1.4, 0.3), cf * CFrame.new(0, 2.5, 0.7), WOOD, MAT.WoodPlanks)
	for _, x in ipairs({ -2, 2 }) do
		P(parent, "Pe", Vector3.new(0.4, 1.4, 1.4), cf * CFrame.new(x, 0.8, 0), DARK, MAT.Metal)
	end
end

local function stoneSign(parent, cf, text, width)
	local sign = P(parent, "Letreiro", Vector3.new(width, 2.6, 1.2), cf * CFrame.new(0, 1.3, 0), STONE, MAT.Slate)
	local label = P(parent, "LetreiroNome", Vector3.new(width - 1, 1.8, 0.1), sign.CFrame * CFrame.new(0, 0.2, -0.65), STONE, MAT.Slate, { collide = false })
	K.addSurfaceText(label, text, Color3.fromRGB(35, 35, 40), STONE)
end

---------------------------------------------------------------------------
-- Hospital Progresso
---------------------------------------------------------------------------

-- Ambulância de peças (parada, só enfeite). cf = centro no chão, frente = -Z
local function ambulance(parent, cf)
	local m = K.model("Ambulancia", parent)
	P(m, "Bau", Vector3.new(7.4, 7.6, 11), cf * CFrame.new(0, 5.2, 2.4), WHITE)
	P(m, "Cabine", Vector3.new(7.2, 5.4, 5), cf * CFrame.new(0, 4.1, -5.6), WHITE)
	P(m, "Capo", Vector3.new(7.2, 2.6, 2.6), cf * CFrame.new(0, 2.7, -9.3), WHITE)
	P(m, "Parabrisa", Vector3.new(6.6, 2.6, 0.2), cf * CFrame.new(0, 5.4, -8.15) * CFrame.Angles(math.rad(-15), 0, 0), Color3.fromRGB(40, 50, 60), nil, { reflectance = 0.2 })
	for _, s in ipairs({ -1, 1 }) do
		P(m, "Faixa", Vector3.new(0.1, 1, 15.5), cf * CFrame.new(s * 3.72, 4, -0.2), RED, nil, { collide = false })
		P(m, "Cruz", Vector3.new(0.1, 2.6, 0.8), cf * CFrame.new(s * 3.72, 6.6, 3), RED, nil, { collide = false })
		P(m, "Cruz", Vector3.new(0.1, 0.8, 2.6), cf * CFrame.new(s * 3.72, 6.6, 3), RED, nil, { collide = false })
		P(m, "JanelaCabine", Vector3.new(0.1, 2, 2.8), cf * CFrame.new(s * 3.62, 5.6, -5.6), Color3.fromRGB(40, 50, 60), nil, { collide = false })
		for _, z in ipairs({ -8, 5 }) do
			K.flatCylinder(m, "Roda", (cf * CFrame.new(s * 3.3, 1.4, z)).Position, 1.4, 1, Color3.fromRGB(25, 25, 28), MAT.SmoothPlastic)
		end
	end
	-- giroflex (vermelho e azul), parado
	P(m, "GiroflexE", Vector3.new(2.4, 0.5, 0.8), cf * CFrame.new(-1.6, 7.05, -5.6), Color3.fromRGB(255, 40, 40), MAT.Neon, { collide = false })
	P(m, "GiroflexD", Vector3.new(2.4, 0.5, 0.8), cf * CFrame.new(1.6, 7.05, -5.6), Color3.fromRGB(50, 110, 255), MAT.Neon, { collide = false })
	local label = P(m, "Escrita", Vector3.new(5.6, 1, 0.1), cf * CFrame.new(0, 3.4, -10.65), WHITE, nil, { collide = false })
	K.addSurfaceText(label, "AMBULÂNCIA", RED, WHITE)
end

-- Ponto no lote em CFrame virado para dir ("-x", "+x", "-z", "+z")
local function facing(lot, x, y, z, dir)
	local look = ({ ["-x"] = Vector3.new(-1, 0, 0), ["+x"] = Vector3.new(1, 0, 0), ["-z"] = Vector3.new(0, 0, -1), ["+z"] = Vector3.new(0, 0, 1) })[dir]
	return lot * CFrame.lookAt(Vector3.new(x, y, z), Vector3.new(x, y, z) + look)
end

-- Cadeira de espera (assento + encosto), virada para dir
local function waitChair(f, lot, x, z, dir, color)
	local cf = facing(lot, x, G, z, dir)
	seat(f, cf * CFrame.new(0, 1.7, 0), Vector3.new(2.2, 0.4, 2.2), color, "Cadeira")
	P(f, "Encosto", Vector3.new(2.2, 2.2, 0.3), cf * CFrame.new(0, 3, 1.05), color, MAT.Fabric)
	P(f, "Pe", Vector3.new(0.3, 1.5, 0.3), cf * CFrame.new(0, 0.75, 0), DARK, MAT.Metal)
end

-- Cama de hospital (E = deitar), monitor e cadeira. cf = pé da cama no chão, cama ao longo de +Z
local function hospitalBed(f, cf)
	P(f, "Estrado", Vector3.new(4, 1.8, 8.4), cf * CFrame.new(0, 0.9, 4.2), Color3.fromRGB(200, 204, 210), MAT.Metal)
	seat(f, cf * CFrame.new(0, 2.05, 4.2), Vector3.new(3.8, 0.5, 8), Color3.fromRGB(235, 240, 245), "Cama")
	P(f, "Travesseiro", Vector3.new(3, 0.6, 1.6), cf * CFrame.new(0, 2.6, 7.4), WHITE, MAT.Fabric, { collide = false })
	P(f, "Cabeceira", Vector3.new(4.2, 3.4, 0.4), cf * CFrame.new(0, 2.6, 8.6), Color3.fromRGB(160, 170, 180), MAT.Metal)
	P(f, "Suporte", Vector3.new(0.3, 7, 0.3), cf * CFrame.new(3.2, 3.5, 7.6), Color3.fromRGB(180, 184, 190), MAT.Metal)
	local screen = P(f, "Monitor", Vector3.new(2.2, 1.6, 0.4), cf * CFrame.new(3.2, 6.6, 7.6), Color3.fromRGB(30, 34, 40))
	P(f, "MonitorTela", Vector3.new(1.9, 1.3, 0.05), screen.CFrame * CFrame.new(0, 0, -0.22), Color3.fromRGB(60, 230, 120), MAT.Neon, { collide = false })
	P(f, "Soro", Vector3.new(0.8, 1.2, 0.4), cf * CFrame.new(-2.8, 6.2, 7.2), Color3.fromRGB(220, 235, 245), nil, { transparency = 0.3, collide = false })
	P(f, "SoroPoste", Vector3.new(0.2, 7, 0.2), cf * CFrame.new(-2.8, 3.5, 7.4), Color3.fromRGB(180, 184, 190), MAT.Metal)
end

local function buildHospital(parent, item)
	local lot = item.lot
	local f = K.model(D.HospitalName, parent)
	local function B(name, x0, x1, y0, y1, z0, z1, color, material, extra)
		return box(f, name, lot, x0, x1, y0, y1, z0, z1, color, material, extra)
	end
	local hw, hd = HOSPITAL_W / 2, HOSPITAL_D / 2
	-- Medidas do prédio principal
	local X0, X1, Z0, Z1 = -72, 48, -30, 46
	local H0 = 12 -- térreo (dá para entrar)
	local FLOORS, FH = 3, 10 -- andares de cima (só fachada)
	local TOP = G + H0 + FLOORS * FH
	local WALL = Color3.fromRGB(240, 242, 244)
	local FLOOR = Color3.fromRGB(226, 232, 236)
	local T = 1 -- espessura das paredes

	-- Terreno: piso, estacionamento com vagas, gramado, árvores e mastros
	B("Piso", -hw, hw, 0.4, G, -hd, hd, PAVING, MAT.Concrete)
	B("Estacionamento", -82, 30, G, G + 0.05, -hd + 2, -40, ASPHALT, MAT.Asphalt, { collide = false })
	for row = 0, 1 do
		local z = row == 0 and -hd + 4 or -55
		for x = -80, 28, 9 do
			B("Vaga", x - 0.2, x + 0.2, G + 0.05, G + 0.08, z, z + 12, WHITE, nil, { collide = false })
		end
	end
	B("Gramado", 34, hw - 2, G, G + 0.1, -hd + 2, -50, LAWN, MAT.Grass)
	for _, p in ipairs({ { 44, -66 }, { 64, -66 }, { 76, -50 }, { -hw + 5, -10 }, { -hw + 5, 20 }, { -hw + 5, 50 }, { 60, 60 }, { 20, 64 } }) do
		tree(f, (lot * CFrame.new(p[1], G, p[2])).Position, rng:NextNumber(0.9, 1.2))
	end
	for i, x in ipairs({ 36, 40, 44 }) do
		B("Mastro", x - 0.2, x + 0.2, G, G + 18, -44, -43.6, Color3.fromRGB(200, 200, 205), MAT.Metal)
		B("Bandeira", x + 0.2, x + 4.6, G + 15, G + 17.8, -43.85, -43.75, ({ Color3.fromRGB(0, 150, 60), WHITE, HOSP_BLUE })[i], MAT.Fabric, { collide = false })
	end
	stoneSign(f, lot * CFrame.new(-60, G, -hd + 4), D.HospitalName, 20)

	-- Prédio: piso de dentro, laje do térreo, andares de cima e telhado
	B("PisoInterno", X0 + T, X1 - T, G, G + 0.2, Z0 + T, Z1 - T, FLOOR, MAT.Marble)
	B("Laje", X0, X1, G + H0, G + H0 + 0.8, Z0, Z1, WHITE)
	B("Andares", X0, X1, G + H0 + 0.8, TOP, Z0 + 1, Z1 - 1, WALL)
	for k = 0, FLOORS - 1 do
		local y = G + H0 + 0.8 + k * FH + 3.4
		B("Janelas", X0 + 3, X1 - 3, y, y + 4.6, Z0 + 0.7, Z0 + 1, Color3.fromRGB(110, 160, 195), nil, { reflectance = 0.2, collide = false })
		B("Janelas", X0 + 3, X1 - 3, y, y + 4.6, Z1 - 1, Z1 - 0.7, Color3.fromRGB(110, 160, 195), nil, { reflectance = 0.2, collide = false })
		B("Janelas", X0 + 0.7, X0 + 1, y, y + 4.6, Z0 + 4, Z1 - 4, Color3.fromRGB(110, 160, 195), nil, { reflectance = 0.2, collide = false })
		B("Janelas", X1 - 1, X1 - 0.7, y, y + 4.6, Z0 + 4, Z1 - 4, Color3.fromRGB(110, 160, 195), nil, { reflectance = 0.2, collide = false })
		B("Friso", X0, X1, y - 2.6, y - 2, Z0, Z0 + 1, HOSP_BLUE, nil, { collide = false })
	end
	B("Platibanda", X0, X1, TOP, TOP + 2, Z0, Z0 + 1, WHITE)
	B("Platibanda", X0, X1, TOP, TOP + 2, Z1 - 1, Z1, WHITE)
	B("Platibanda", X0, X0 + 1, TOP, TOP + 2, Z0, Z1, WHITE)
	B("Platibanda", X1 - 1, X1, TOP, TOP + 2, Z0, Z1, WHITE)
	-- letreiro grande e cruz vermelha acesa
	local sign = B("Letreiro", -40, 20, TOP - 6.4, TOP - 1.6, Z0 - 0.6, Z0, WHITE, nil, { collide = false })
	K.addSurfaceText(sign, D.HospitalName:upper(), HOSP_BLUE, WHITE)
	local crossC = lot * CFrame.new(32, TOP + 4.5, Z0 + 1)
	local c1 = P(f, "CruzLuz", Vector3.new(2.6, 8, 1), crossC, RED, MAT.Neon, { collide = false })
	P(f, "CruzLuz", Vector3.new(8, 2.6, 1), crossC, RED, MAT.Neon, { collide = false })
	glow(c1, 20, 0.6, Color3.fromRGB(255, 80, 80))
	-- heliponto no telhado
	local pad = (lot * CFrame.new(-28, TOP, 12)).Position
	K.flatCylinder(f, "Heliponto", pad + Vector3.new(0, 0.15, 0), 14, 0.3, Color3.fromRGB(70, 72, 78), MAT.Concrete)
	K.flatCylinder(f, "HelipontoAnel", pad + Vector3.new(0, 0.32, 0), 13, 0.05, Color3.fromRGB(240, 200, 40), MAT.SmoothPlastic)
	K.flatCylinder(f, "HelipontoMeio", pad + Vector3.new(0, 0.36, 0), 12.2, 0.05, Color3.fromRGB(70, 72, 78), MAT.Concrete)
	B("LetraH", -32.2, -31.2, TOP + 0.39, TOP + 0.42, 6, 18, WHITE, nil, { collide = false })
	B("LetraH", -24.8, -23.8, TOP + 0.39, TOP + 0.42, 6, 18, WHITE, nil, { collide = false })
	B("LetraH", -31.2, -24.8, TOP + 0.39, TOP + 0.42, 11.5, 12.5, WHITE, nil, { collide = false })
	B("CasaMaquinas", 10, 26, TOP, TOP + 6, 18, 34, Color3.fromRGB(220, 222, 226))

	-- Térreo: paredes de fora (vidro na frente da recepção, vão da entrada no meio)
	local yT = G + H0
	B("Parede", X0, -30, G, yT, Z0, Z0 + T, WALL)
	B("Parede", 30, X1, G, yT, Z0, Z0 + T, WALL)
	for _, s in ipairs({ { -30, -6 }, { 6, 30 } }) do
		B("Vidro", s[1], s[2], G, G + 9, Z0 + 0.3, Z0 + 0.7, GLASS, nil, { transparency = 0.5, reflectance = 0.1 })
		B("VidroTopo", s[1], s[2], G + 9, yT, Z0, Z0 + T, HOSP_BLUE)
	end
	B("VidroTopo", -6, 6, G + 9, yT, Z0, Z0 + T, HOSP_BLUE)
	for _, x in ipairs({ -30, -18, -6, 6, 18, 30 }) do
		B("Montante", x - 0.3, x + 0.3, G, G + 9, Z0 - 0.1, Z0 + 0.8, DARK, MAT.Metal)
	end
	B("Parede", X0, X1, G, yT, Z1 - T, Z1, WALL)
	B("Parede", X0, X0 + T, G, yT, Z0, Z1, WALL)
	for _, z in ipairs({ -16, 22, 36 }) do -- janelas do térreo nas laterais
		B("Janela", X0 - 0.1, X0 + 0.2, G + 3.5, G + 8.5, z - 4, z + 4, GLASS, nil, { transparency = 0.4, collide = false })
	end
	-- marquise da entrada com o nome
	B("Marquise", -14, 14, G + 10, G + 10.6, Z0 - 10, Z0, WHITE, nil, { collide = false })
	for _, x in ipairs({ -13, 13 }) do
		B("PilarMarquise", x - 0.4, x + 0.4, G, G + 10, Z0 - 9.6, Z0 - 8.8, WHITE)
	end
	local entry = B("PlacaEntrada", -9, 9, G + 10.6, G + 12.2, Z0 - 10.1, Z0 - 9.9, HOSP_BLUE, nil, { collide = false })
	K.addSurfaceText(entry, "ENTRADA", WHITE, HOSP_BLUE)

	-- Recepção (balcão), sala de espera com TV e farmácia
	B("Balcao", -9, 9, G, G + 3.6, -8, -6.6, Color3.fromRGB(240, 240, 244))
	B("BalcaoFaixa", -9.05, 9.05, G + 2.4, G + 2.9, -8.05, -7.95, HOSP_BLUE, nil, { collide = false })
	B("BalcaoLado", -9, -7.6, G, G + 3.6, -6.6, -1, Color3.fromRGB(240, 240, 244))
	B("BalcaoLado", 7.6, 9, G, G + 3.6, -6.6, -1, Color3.fromRGB(240, 240, 244))
	B("BalcaoTampo", -9.3, 9.3, G + 3.6, G + 3.85, -8.3, -6.3, Color3.fromRGB(70, 75, 85), MAT.Marble)
	for _, x in ipairs({ -4, 4 }) do
		B("Computador", x - 1, x + 1, G + 3.85, G + 5.3, -7.4, -7.1, Color3.fromRGB(30, 32, 36), nil, { collide = false })
	end
	local rec = B("PlacaRecepcao", -6, 6, G + 9.2, G + 10.8, -7.5, -7.3, HOSP_BLUE, nil, { collide = false })
	K.addSurfaceText(rec, "RECEPÇÃO", WHITE, HOSP_BLUE)
	for _, x in ipairs({ -23, -18, -13 }) do -- 3 fileiras de cadeiras, viradas para a TV
		for z = -25, -11, 2.8 do
			waitChair(f, lot, x, z, "-x", HOSP_BLUE)
		end
	end
	local tv = B("TV", -29.6, -29.3, G + 5, G + 9, -21.5, -13.5, Color3.fromRGB(20, 20, 24))
	tv:SetAttribute("Toggle", "TV")
	tv:SetAttribute("Label", "TV")
	tv:SetAttribute("On", true)
	B("Parede", -30, -29.6, G, yT, Z0 + T, 5, WALL) -- parede da TV (separa a sala de espera do consultório)
	-- farmácia (lado direito)
	B("Farmacia", 14, 28, G, G + 3.6, -2, -0.6, Color3.fromRGB(240, 240, 244))
	B("FarmaciaTampo", 13.8, 28.2, G + 3.6, G + 3.85, -2.2, -0.4, Color3.fromRGB(70, 75, 85), MAT.Marble)
	B("Prateleira", 14, 28, G, G + 8, 3.6, 4.6, Color3.fromRGB(235, 235, 238))
	for k = 0, 3 do
		B("Remedios", 14.5, 27.5, G + 1.8 + k * 1.6, G + 2.6 + k * 1.6, 3.2, 3.6, ({ Color3.fromRGB(240, 120, 110), Color3.fromRGB(120, 190, 240), Color3.fromRGB(130, 210, 140), Color3.fromRGB(250, 220, 110) })[k + 1], nil, { collide = false })
	end
	local farm = B("PlacaFarmacia", 16, 26, G + 9.2, G + 10.8, -1.6, -1.4, Color3.fromRGB(0, 150, 80), nil, { collide = false })
	K.addSurfaceText(farm, "FARMÁCIA", WHITE, Color3.fromRGB(0, 150, 80))
	-- bebedouro e máquina de lanche
	B("Bebedouro", 26, 28, G, G + 4, -26, -24, Color3.fromRGB(220, 224, 230), MAT.Metal)
	B("Galao", 26.3, 27.7, G + 4, G + 6, -25.7, -24.3, Color3.fromRGB(150, 200, 240), nil, { transparency = 0.3 })
	B("MaquinaLanche", 26, 28.6, G, G + 7, -20, -16, RED)
	B("MaquinaVitrine", 25.9, 26, G + 2.5, G + 6.5, -19.6, -16.4, NEON_WARM, MAT.Neon, { collide = false })
	for _, p in ipairs({ { -28, -27.5 }, { 27, -9 }, { -28, 2.5 } }) do
		P(f, "Vaso", Vector3.new(1.6, 1.6, 1.6), lot * CFrame.new(p[1], G + 0.8, p[2]), DARK, MAT.Slate)
		P(f, "Planta", Vector3.new(2.6, 2.6, 2.6), lot * CFrame.new(p[1], G + 2.6, p[2]), Color3.fromRGB(70, 150, 70), MAT.Grass, { shape = BALL, collide = false })
	end

	-- Consultórios na frente, à esquerda (2) e à direita (1)
	-- consultório: parede do corredor com porta, maca na parede de fora, mesa e 2 cadeiras
	local function consult(x0, x1, label)
		local mid = (x0 + x1) / 2
		B("Parede", x0, mid - 2.6, G, yT, 4.6, 5, WALL)
		B("Parede", mid + 2.6, x1, G, yT, 4.6, 5, WALL)
		B("Parede", mid - 2.6, mid + 2.6, G + 8, yT, 4.6, 5, WALL)
		hospitalBed(f, facing(lot, x0 + 4, G, -28, "-z"))
		B("Mesa", mid, mid + 6, G, G + 3, -20, -17, Color3.fromRGB(190, 160, 120), MAT.Wood)
		waitChair(f, lot, mid + 3, -15, "-z", Color3.fromRGB(60, 62, 70))
		waitChair(f, lot, mid + 3, -22.5, "+z", Color3.fromRGB(60, 62, 70))
		local plate = B("PlacaSala", mid - 3, mid + 3, G + 8.4, G + 9.6, 5.05, 5.15, HOSP_BLUE, nil, { collide = false })
		K.addSurfaceText(plate, label, WHITE, HOSP_BLUE)
	end
	B("Parede", -50.2, -49.8, G, yT, Z0 + T, 5, WALL)
	consult(X0 + T, -50.2, "Consultório 1")
	consult(-49.8, -30, "Consultório 2")
	B("Parede", 30, 30.4, G, yT, Z0 + T, 5, WALL)
	consult(30.4, X1 - T, "Consultório 3")

	-- Corredor (z 5..13) e 6 quartos no fundo (z 13..45)
	local roomW = (X1 - X0 - 2 * T) / 6
	for i = 0, 5 do
		local rx0 = X0 + T + i * roomW
		local rx1 = rx0 + roomW
		local mid = (rx0 + rx1) / 2
		-- parede do corredor com vão de porta
		B("Parede", rx0, mid - 2.6, G, yT, 13, 13.4, WALL)
		B("Parede", mid + 2.6, rx1, G, yT, 13, 13.4, WALL)
		B("Parede", mid - 2.6, mid + 2.6, G + 8, yT, 13, 13.4, WALL)
		B("Batente", mid - 2.9, mid + 2.9, G + 8, G + 8.4, 12.9, 13.5, HOSP_BLUE, nil, { collide = false })
		if i > 0 then
			B("Parede", rx0 - 0.2, rx0 + 0.2, G, yT, 13.4, Z1 - T, WALL)
		end
		hospitalBed(f, facing(lot, mid - 2, G, 36, "-z"))
		waitChair(f, lot, mid + 4.5, 39, "-x", Color3.fromRGB(120, 130, 145))
		B("Cortina", mid - 7, mid + 3, G + 0.5, G + 9, 24.6, 24.9, Color3.fromRGB(150, 200, 215), MAT.Fabric, { collide = false, transparency = 0.15 })
		B("JanelaQuarto", mid - 5, mid + 5, G + 3.5, G + 8.5, Z1 - 0.15, Z1 + 0.1, GLASS, nil, { transparency = 0.4, collide = false })
		local plate = B("PlacaQuarto", mid - 2.5, mid + 2.5, G + 8.6, G + 9.8, 12.75, 12.85, HOSP_BLUE, nil, { collide = false })
		K.addSurfaceText(plate, ("Quarto %d"):format(i + 1), WHITE, HOSP_BLUE)
	end
	-- luzes do teto (poucas luzes de verdade, para não pesar)
	local lights = 0
	for _, p in ipairs({ { -18, -18 }, { 0, -18 }, { 18, -18 }, { -45, 9 }, { -15, 9 }, { 15, 9 }, { 40, 9 } }) do
		local lamp = B("Luminaria", p[1] - 3, p[1] + 3, yT - 0.2, yT, p[2] - 1, p[2] + 1, NEON_WARM, MAT.Neon, { collide = false, shadow = false })
		if lights < 5 then
			glow(lamp, 22, 0.6)
			lights += 1
		end
	end
	for i = 0, 5 do
		local mid = X0 + T + (i + 0.5) * roomW
		B("Luminaria", mid - 2, mid + 2, yT - 0.2, yT, 28, 30, NEON_WARM, MAT.Neon, { collide = false, shadow = false })
	end

	-- Pronto-socorro: anexo à direita com cobertura para as ambulâncias
	local PX0, PX1 = X1, 80
	B("PSPiso", PX0, PX1, G, G + 0.2, -24, 26, FLOOR, MAT.Marble)
	B("PSParede", PX0, PX1, G, G + 11, 25, 26, WALL)
	B("PSParede", PX1 - 1, PX1, G, G + 11, -24, 26, WALL)
	B("PSTeto", PX0, PX1, G + 11, G + 11.8, -24, 26, WHITE)
	B("PSFaixa", PX0, PX1, G + 9, G + 11, -24, -23, RED)
	local ps = B("PSPlaca", PX0 + 4, PX1 - 4, G + 9.3, G + 10.7, -24.1, -24.05, RED, nil, { collide = false })
	K.addSurfaceText(ps, "PRONTO-SOCORRO", WHITE, RED)
	-- Marco 10.19: cobertura 1 stud mais alta (a ambulância nova tem 9,8 de altura)
	B("PSCobertura", PX0 + 2, PX1, G + 11, G + 11.6, -48, -24, WHITE, nil, { collide = false })
	for _, x in ipairs({ PX0 + 3, PX1 - 1 }) do
		B("PSPilar", x - 0.4, x + 0.4, G, G + 11, -47.6, -46.8, WHITE)
	end
	-- Marco 10.19: as 2 ambulâncias de enfeite viraram a garagem do SAMU: o Paramédico tira a
	-- ambulância de verdade no balcão (E). Garagem de serviço (ServiceJob) em Map > Garages.
	local map = f:FindFirstAncestor("Map")
	local garages = map and (map:FindFirstChild("Garages") or Instance.new("Folder"))
	if garages then
		garages.Name = "Garages"
		garages.Parent = map
		local gar = K.model("GaragemSAMU", garages)
		gar:SetAttribute("Garage", true)
		gar:SetAttribute("ServiceJob", "Paramedico")
		gar:SetAttribute("PlaceName", "Ambulâncias SAMU")
		for k, x in ipairs({ 57, 71 }) do
			local vaga = P(gar, "Vaga" .. k, Vector3.new(1, 1, 1), lot * CFrame.new(x, G + 0.5, -36), WHITE, nil, { collide = false, transparency = 1 })
			vaga.CanQuery = false
			vaga.CanTouch = false
			B("FaixaVaga", x + 5.2, x + 5.5, G + 0.05, G + 0.08, -47, -25, Color3.fromRGB(240, 190, 20), nil, { collide = false })
		end
		local balcao = P(gar, "Balcao", Vector3.new(4, 3.4, 1.6), lot * CFrame.new(PX0 + 3, G + 1.7, -27), Color3.fromRGB(200, 20, 30))
		local placa = P(gar, "PlacaSAMU", Vector3.new(4, 1, 0.1), lot * CFrame.new(PX0 + 3, G + 3.9, -27.85), WHITE, nil, { collide = false })
		K.addSurfaceText(placa, "SAMU 192", Color3.fromRGB(200, 20, 30), WHITE)
		balcao:SetAttribute("Garagem", true)
	else
		for k, x in ipairs({ 57, 71 }) do
			ambulance(f, lot * CFrame.new(x, G, -34 - k) * CFrame.Angles(0, 0, 0))
		end
	end
	for _, z in ipairs({ -10, 6 }) do -- 2 macas de atendimento lá dentro
		hospitalBed(f, facing(lot, 70, G, z, "-x"))
	end
	B("PSBalcao", 52, 62, G, G + 3.6, 18, 20, Color3.fromRGB(240, 240, 244))
	local psLamp = B("Luminaria", 60, 68, G + 10.8, G + 11, -2, 2, NEON_WARM, MAT.Neon, { collide = false, shadow = false })
	glow(psLamp, 24, 0.6)
	-- porta do pronto-socorro para o corredor do hospital (z 6..12)
	B("Parede", X1 - T, X1, G, yT, Z0, 6, WALL)
	B("Parede", X1 - T, X1, G, yT, 12, Z1, WALL)
	B("Parede", X1 - T, X1, G + 8, yT, 6, 12, WALL)

	-- Bancos e postes
	for _, x in ipairs({ -40, -24, 24 }) do
		bench(f, lot * CFrame.new(x, G - 0.7, -36))
	end
	for _, x in ipairs({ -78, -50, -22, 6 }) do
		K.buildLamp(f, lot * CFrame.new(x, G - 0.8, -42))
	end

	f:SetAttribute("PlaceName", D.HospitalName)
	f:SetAttribute("Address", ("%s, %d"):format(item.street, item.number or 0))
	f:SetAttribute("Curb", K.curbOf(lot, HOSPITAL_D))
	return f
end

---------------------------------------------------------------------------
-- Praça do Progresso
---------------------------------------------------------------------------

local function swingSet(f, cf)
	for _, x in ipairs({ -5, 5 }) do
		for _, z in ipairs({ -1.4, 1.4 }) do
			P(f, "BalancoPoste", Vector3.new(0.4, 9, 0.4), cf * CFrame.new(x, 4.5, z) * CFrame.Angles(z > 0 and -0.15 or 0.15, 0, 0), Color3.fromRGB(230, 70, 60), MAT.Metal)
		end
	end
	P(f, "BalancoTrave", Vector3.new(10.8, 0.5, 0.5), cf * CFrame.new(0, 8.9, 0), Color3.fromRGB(230, 70, 60), MAT.Metal)
	for _, x in ipairs({ -2.2, 2.2 }) do
		for _, dx in ipairs({ -0.9, 0.9 }) do
			P(f, "Corrente", Vector3.new(0.12, 6, 0.12), cf * CFrame.new(x + dx, 5.8, 0), Color3.fromRGB(150, 150, 155), MAT.Metal, { collide = false })
		end
		seat(f, cf * CFrame.new(x, 2.7, 0), Vector3.new(2.2, 0.3, 1.2), Color3.fromRGB(40, 110, 200), "Balanço", MAT.SmoothPlastic)
	end
end

local function slide(f, cf)
	P(f, "EscorregaTorre", Vector3.new(4, 0.5, 4), cf * CFrame.new(0, 6, 0), Color3.fromRGB(250, 200, 50))
	for _, x in ipairs({ -1.8, 1.8 }) do
		for _, z in ipairs({ -1.8, 1.8 }) do
			P(f, "EscorregaPoste", Vector3.new(0.4, 9, 0.4), cf * CFrame.new(x, 4.5, z), Color3.fromRGB(40, 110, 200), MAT.Metal)
		end
	end
	P(f, "EscorregaTeto", Vector3.new(4.6, 0.4, 4.6), cf * CFrame.new(0, 9.2, 0), Color3.fromRGB(230, 70, 60))
	for k = 0, 4 do -- escadinha
		P(f, "Degrau", Vector3.new(2.6, 0.3, 0.8), cf * CFrame.new(0, 1 + k * 1.2, 2.4 + (4 - k) * 0.7), Color3.fromRGB(40, 110, 200), MAT.Metal)
	end
	P(f, "Rampa", Vector3.new(2.6, 0.3, 9.6), cf * CFrame.new(0, 3.1, -6.4) * CFrame.Angles(math.rad(-34), 0, 0), Color3.fromRGB(60, 190, 110))
	for _, x in ipairs({ -1.4, 1.4 }) do
		P(f, "RampaBorda", Vector3.new(0.3, 0.8, 9.6), cf * CFrame.new(x, 3.5, -6.4) * CFrame.Angles(math.rad(-34), 0, 0), Color3.fromRGB(60, 190, 110), nil, { collide = false })
	end
end

local function buildPlaza(parent, item)
	local lot = item.lot
	local f = K.model(D.PlazaName, parent)
	local hw, hd = PLAZA_W / 2, PLAZA_D / 2
	local function B(name, x0, x1, y0, y1, z0, z1, color, material, extra)
		return box(f, name, lot, x0, x1, y0, y1, z0, z1, color, material, extra)
	end
	B("Gramado", -hw, hw, 0.4, G, -hd, hd, LAWN, MAT.Grass)
	-- caminhos em cruz e em volta
	B("Caminho", -4, 4, G, G + 0.1, -hd, hd, PAVING, MAT.Pavement)
	B("Caminho", -hw, hw, G, G + 0.1, -4, 4, PAVING, MAT.Pavement)
	B("Caminho", -hw + 6, hw - 6, G, G + 0.1, -hd + 6, -hd + 12, PAVING, MAT.Pavement)
	B("Caminho", -hw + 6, hw - 6, G, G + 0.1, hd - 12, hd - 6, PAVING, MAT.Pavement)
	B("Caminho", -hw + 6, -hw + 12, G, G + 0.1, -hd + 6, hd - 6, PAVING, MAT.Pavement)
	B("Caminho", hw - 12, hw - 6, G, G + 0.1, -hd + 6, hd - 6, PAVING, MAT.Pavement)
	-- chafariz no meio
	local c = (lot * CFrame.new(0, 0, 0)).Position
	K.flatCylinder(f, "LargoChafariz", c + Vector3.new(0, G + 0.08, 0), 20, 0.15, PAVING, MAT.Pavement)
	K.flatCylinder(f, "Bacia", c + Vector3.new(0, G + 0.8, 0), 11, 1.4, STONE, MAT.Slate)
	local water = K.flatCylinder(f, "Agua", c + Vector3.new(0, G + 1.45, 0), 10.2, 0.2, WATER, MAT.SmoothPlastic)
	water.Transparency = 0.2
	water.CanCollide = false
	K.flatCylinder(f, "Coluna", c + Vector3.new(0, G + 3.2, 0), 1.3, 5, WHITE, MAT.Marble)
	K.flatCylinder(f, "Prato", c + Vector3.new(0, G + 5.8, 0), 3.6, 0.6, WHITE, MAT.Marble)
	local jet = P(f, "Jato", Vector3.new(1, 1, 1), CFrame.new(c + Vector3.new(0, G + 6.5, 0)), WATER, nil, { transparency = 1, collide = false })
	local e = Instance.new("ParticleEmitter")
	e.Name = "Agua"
	e.Color = ColorSequence.new(Color3.fromRGB(190, 225, 255))
	e.Size = NumberSequence.new(0.35)
	e.Transparency = NumberSequence.new(0.3, 1)
	e.Lifetime = NumberRange.new(0.9, 1.2)
	e.Rate = 40
	e.Speed = NumberRange.new(9, 11)
	e.SpreadAngle = Vector2.new(12, 12)
	e.Acceleration = Vector3.new(0, -22, 0)
	e.EmissionDirection = Enum.NormalId.Top
	e.Parent = jet
	for i = 0, 7 do
		local a = i * math.pi / 4 + math.pi / 8
		local p = c + Vector3.new(math.cos(a) * 16, G - 0.7, math.sin(a) * 16)
		bench(f, CFrame.lookAt(p, Vector3.new(c.X, p.Y, c.Z)))
	end
	-- parquinho (quadrante da frente, à esquerda): areia, balanço, escorregador e gangorra
	B("Areia", -hw + 16, -10, G, G + 0.15, -hd + 16, -10, Color3.fromRGB(225, 205, 150), MAT.Sand)
	swingSet(f, lot * CFrame.new(-60, G, -50))
	slide(f, lot * CFrame.new(-30, G, -42))
	P(f, "GangorraBase", Vector3.new(0.8, 1.6, 0.8), lot * CFrame.new(-40, G + 0.8, -22), Color3.fromRGB(230, 70, 60), MAT.Metal)
	P(f, "Gangorra", Vector3.new(0.8, 0.3, 12), lot * CFrame.new(-40, G + 1.8, -22) * CFrame.Angles(math.rad(10), 0, 0), Color3.fromRGB(250, 200, 50))
	for _, z in ipairs({ -27, -17 }) do
		seat(f, lot * CFrame.new(-40, G + (z < -22 and 2.9 or 1.0), z) * CFrame.Angles(math.rad(10), 0, 0), Vector3.new(1.6, 0.3, 1.6), Color3.fromRGB(40, 110, 200), "Gangorra", MAT.SmoothPlastic)
	end
	-- coreto (quadrante de trás, à direita)
	local cc = (lot * CFrame.new(45, 0, 45)).Position
	K.flatCylinder(f, "CoretoBase", cc + Vector3.new(0, G + 0.6, 0), 11, 1.2, WHITE, MAT.Concrete)
	for i = 0, 7 do
		local a = i * math.pi / 4
		P(f, "CoretoColuna", Vector3.new(0.6, 9, 0.6), CFrame.new(cc + Vector3.new(math.cos(a) * 9.5, G + 5.7, math.sin(a) * 9.5)), WHITE)
	end
	K.flatCylinder(f, "CoretoTeto", cc + Vector3.new(0, G + 10.4, 0), 12, 0.6, Color3.fromRGB(190, 70, 60), MAT.SmoothPlastic)
	K.flatCylinder(f, "CoretoTopo", cc + Vector3.new(0, G + 11.6, 0), 7, 1.8, Color3.fromRGB(190, 70, 60), MAT.SmoothPlastic)
	-- quiosque (quadrante de trás, à esquerda)
	B("Quiosque", -52, -40, G, G + 7, 40, 50, WHITE)
	B("QuiosqueToldo", -54, -38, G + 7, G + 7.5, 36, 52, Color3.fromRGB(240, 150, 40), MAT.Fabric, { collide = false })
	local kiosk = B("QuiosquePlaca", -51, -41, G + 4.6, G + 6.2, 39.9, 39.95, Color3.fromRGB(240, 150, 40), nil, { collide = false })
	K.addSurfaceText(kiosk, "Pastelaria", WHITE, Color3.fromRGB(240, 150, 40))
	for _, x in ipairs({ -50, -46, -42 }) do
		local cf = facing(lot, x, G, 36.5, "+z")
		seat(f, cf * CFrame.new(0, 2.6, 0), Vector3.new(1.6, 0.3, 1.6), Color3.fromRGB(240, 150, 40), "Banqueta", MAT.SmoothPlastic)
		P(f, "BanquetaPe", Vector3.new(0.3, 2.4, 0.3), cf * CFrame.new(0, 1.2, 0), DARK, MAT.Metal)
	end
	-- canteiros de flores, árvores e postes
	local flowerColors = { Color3.fromRGB(240, 90, 120), Color3.fromRGB(250, 210, 60), Color3.fromRGB(170, 100, 230), Color3.fromRGB(255, 140, 60) }
	for _, p in ipairs({ { 30, -40 }, { 60, -30 }, { 30, -60 }, { 62, -60 }, { -62, 20 }, { -30, 24 }, { 20, 22 } }) do
		local fl = P(f, "Flores", Vector3.new(7, 1, 7), lot * CFrame.new(p[1], G + 0.5, p[2]), flowerColors[rng:NextInteger(1, #flowerColors)], MAT.Grass, { shape = BALL, collide = false })
		fl.Size = Vector3.new(7, 1.6, 7)
	end
	for _, p in ipairs({ { -80, -78 }, { 80, -78 }, { -80, 78 }, { 80, 78 }, { -80, 0 }, { 80, 0 }, { -20, -70 }, { 20, 70 }, { 72, 40 }, { -20, 70 }, { 40, -20 }, { -70, 40 } }) do
		tree(f, (lot * CFrame.new(p[1], G, p[2])).Position, rng:NextNumber(0.95, 1.3))
	end
	for _, p in ipairs({ { -10, -40 }, { 10, 40 }, { -40, 10 }, { 40, -10 } }) do
		K.buildLamp(f, lot * CFrame.new(p[1], G - 0.8, p[2]))
	end
	stoneSign(f, lot * CFrame.new(16, G, -hd + 3), D.PlazaName, 18)
	f:SetAttribute("PlaceName", D.PlazaName)
	f:SetAttribute("Curb", K.curbOf(lot, PLAZA_D))
	return f
end

---------------------------------------------------------------------------
-- Escola Municipal Progresso
---------------------------------------------------------------------------

local function buildSchool(parent, item)
	local lot = item.lot
	local f = K.model(D.SchoolName, parent)
	local hw, hd = SCHOOL_W / 2, SCHOOL_D / 2
	local function B(name, x0, x1, y0, y1, z0, z1, color, material, extra)
		return box(f, name, lot, x0, x1, y0, y1, z0, z1, color, material, extra)
	end
	local YELLOW = Color3.fromRGB(245, 205, 90)
	local ORANGE = Color3.fromRGB(230, 120, 50)
	B("Piso", -hw, hw, 0.4, G, -hd, hd, PAVING, MAT.Concrete)
	-- muro baixo com grade e portão
	for _, s in ipairs({ { -hw, -8 }, { 8, hw } }) do
		B("Muro", s[1], s[2], G, G + 2.4, -hd, -hd + 0.8, WHITE)
		B("Grade", s[1], s[2], G + 2.4, G + 6, -hd + 0.3, -hd + 0.5, Color3.fromRGB(40, 110, 70), MAT.Metal, { transparency = 0.35 })
	end
	for _, x in ipairs({ -8, 8 }) do
		B("PilarPortao", x - 0.8, x + 0.8, G, G + 7, -hd - 0.2, -hd + 1, ORANGE)
	end
	local gate = B("PlacaPortao", -8, 8, G + 7, G + 9, -hd + 0.2, -hd + 0.4, ORANGE, nil, { collide = false })
	K.addSurfaceText(gate, D.SchoolName, WHITE, ORANGE)
	-- prédio de 2 andares no fundo
	local Z0, Z1 = 22, hd - 2
	B("Predio", -hw + 4, hw - 4, G, G + 20, Z0, Z1, YELLOW)
	B("Friso", -hw + 3.5, hw - 3.5, G + 9.6, G + 10.4, Z0 - 0.5, Z1 + 0.5, ORANGE, nil, { collide = false })
	B("Telhado", -hw + 3, hw - 3, G + 20, G + 21, Z0 - 1, Z1 + 1, Color3.fromRGB(170, 70, 50))
	for _, y in ipairs({ G + 3.5, G + 13.5 }) do
		for x = -hw + 12, hw - 12, 12 do
			if not (y < 10 and math.abs(x) < 8) then
				B("Janela", x - 4, x + 4, y, y + 4.5, Z0 - 0.15, Z0 + 0.1, GLASS, nil, { transparency = 0.3, collide = false })
				B("Peitoril", x - 4.4, x + 4.4, y - 0.4, y, Z0 - 0.5, Z0, WHITE, nil, { collide = false })
			end
		end
	end
	B("Porta", -4, 4, G, G + 8, Z0 - 0.3, Z0, Color3.fromRGB(120, 80, 50), MAT.Wood)
	B("MarquisePorta", -7, 7, G + 9, G + 9.5, Z0 - 6, Z0, ORANGE, nil, { collide = false })
	local name = B("PlacaEscola", -24, 24, G + 15.5, G + 18.5, Z0 - 0.3, Z0 - 0.2, WHITE, nil, { collide = false })
	K.addSurfaceText(name, D.SchoolName:upper(), Color3.fromRGB(40, 90, 160), WHITE)
	-- pátio: mastro com bandeira, bancos, árvores
	B("Mastro", -0.3, 0.3, G, G + 22, 6, 6.6, Color3.fromRGB(200, 200, 205), MAT.Metal)
	B("Bandeira", 0.3, 6.3, G + 18, G + 22, 6.2, 6.4, Color3.fromRGB(0, 150, 60), MAT.Fabric, { collide = false })
	B("BandeiraLosango", 1.8, 4.8, G + 19, G + 21, 6.15, 6.45, Color3.fromRGB(250, 210, 40), MAT.Fabric, { collide = false })
	for _, x in ipairs({ -40, -24, 24, 40 }) do
		bench(f, lot * CFrame.new(x, G - 0.7, 12) * CFrame.Angles(0, math.pi, 0))
	end
	for _, p in ipairs({ { -70, 0 }, { -70, -40 }, { -40, -45 }, { -50, 8 }, { -20, -50 } }) do
		tree(f, (lot * CFrame.new(p[1], G, p[2])).Position, rng:NextNumber(0.9, 1.2))
	end
	-- quadra coberta (lado direito, na frente)
	local QX0, QX1, QZ0, QZ1 = 10, 76, -hd + 6, 2
	B("Quadra", QX0, QX1, G, G + 0.15, QZ0, QZ1, Color3.fromRGB(60, 140, 200), MAT.Concrete)
	B("QuadraMeio", QX0 + 3, QX1 - 3, G + 0.15, G + 0.2, QZ0 + 3, QZ1 - 3, Color3.fromRGB(230, 130, 60), nil, { collide = false })
	B("Linha", (QX0 + QX1) / 2 - 0.2, (QX0 + QX1) / 2 + 0.2, G + 0.2, G + 0.23, QZ0 + 3, QZ1 - 3, WHITE, nil, { collide = false })
	for _, x in ipairs({ QX0 + 2, QX1 - 2 }) do
		local zc = (QZ0 + QZ1) / 2
		B("Trave", x - 0.2, x + 0.2, G, G + 6, zc - 4, zc - 3.6, WHITE, MAT.Metal)
		B("Trave", x - 0.2, x + 0.2, G, G + 6, zc + 3.6, zc + 4, WHITE, MAT.Metal)
		B("Trave", x - 0.2, x + 0.2, G + 6, G + 6.4, zc - 4, zc + 4, WHITE, MAT.Metal)
	end
	for _, x in ipairs({ QX0, QX1 }) do
		for _, z in ipairs({ QZ0, (QZ0 + QZ1) / 2, QZ1 }) do
			B("PilarQuadra", x - 0.5, x + 0.5, G, G + 16, z - 0.5, z + 0.5, Color3.fromRGB(150, 150, 155), MAT.Metal)
		end
	end
	B("TetoQuadra", QX0 - 1, QX1 + 1, G + 16, G + 16.6, QZ0 - 1, QZ1 + 1, Color3.fromRGB(190, 195, 200), MAT.Metal)
	-- arquibancada
	for k = 0, 2 do
		local y = G + 0.8 + k * 1.2
		local z0 = QZ1 + 2 + k * 2
		seat(f, lot * CFrame.new((QX0 + QX1) / 2, y, z0 + 1), Vector3.new(QX1 - QX0 - 6, 0.5, 2), Color3.fromRGB(200, 205, 210), "Arquibancada", MAT.Concrete)
		B("Degrau", QX0 + 3, QX1 - 3, G, y - 0.25, z0, z0 + 2, Color3.fromRGB(170, 172, 176), MAT.Concrete)
	end
	f:SetAttribute("PlaceName", D.SchoolName)
	f:SetAttribute("Curb", K.curbOf(lot, SCHOOL_D))
	return f
end

---------------------------------------------------------------------------
-- Etapa 1: reserva dos lotes
---------------------------------------------------------------------------

local function lotAlong(a, b, t, side, depth)
	local dir = (b - a).Unit
	local perp = Vector3.new(-dir.Z, 0, dir.X)
	local center = a + dir * t + perp * side * (STREET_HALF + 0.6 + depth / 2)
	return CFrame.lookAt(center, center - perp * side)
end

function ProgressoBuilder.plan(map, helpers)
	K = helpers
	local f = K.folder("JardimProgresso", map)
	local plan = { folder = f, items = {} }
	local function reserve(kind, lot, w, d, extra, quiet)
		local area = K.rect(lot, w, d)
		if not K.isFree(area) then
			if not quiet then
				local p = lot.Position
				warn(("[Progresso] Sem espaço livre para %s em (%d, %d)"):format(kind, p.X, p.Z))
			end
			return nil
		end
		K.occupy(area)
		local item = { kind = kind, lot = lot, w = w, d = d }
		for key, v in pairs(extra or {}) do
			item[key] = v
		end
		table.insert(plan.items, item)
		return item
	end

	-- Avenida do Progresso (de norte para sul): lado -1 = leste, +1 = oeste
	local avA = Vector3.new(0, 0, CityRoads.RADIAL_END)
	local avB = Vector3.new(0, 0, PG.EndZ + PG.RoundaboutRadius)
	local function avT(z)
		return z - CityRoads.RADIAL_END
	end
	reserve("hospital", lotAlong(avA, avB, avT(980), -1, HOSPITAL_D), HOSPITAL_W, HOSPITAL_D, { street = PG.Name, t = avT(980), side = -1 })
	reserve("praca", lotAlong(avA, avB, avT(1210), 1, PLAZA_D), PLAZA_W, PLAZA_D, { street = PG.Name, t = avT(1210), side = 1 })
	reserve("escola", lotAlong(avA, avB, avT(1210), -1, SCHOOL_D), SCHOOL_W, SCHOOL_D, { street = PG.Name, t = avT(1210), side = -1 })
	local TW, TD = HorizonteBuilder.TOWER_W, HorizonteBuilder.TOWER_D
	reserve("torre", lotAlong(avA, avB, avT(960), 1, TD), TW, TD, { cfg = D.Towers[1], street = PG.Name, t = avT(960), side = 1 })
	local streets = {}
	for _, st in ipairs(D.Streets) do
		streets[st.Name] = st
	end
	local pain = streets["Rua das Paineiras"]
	reserve("torre", lotAlong(pain.From, pain.To, 900 + 200, 1, TD), TW, TD, { cfg = D.Towers[2], street = pain.Name, t = 1100, side = 1 })
	-- 4 casas modernas (poucas, como o Luís pediu) na Paineiras, lado sul, perto da Rua da Saúde
	local MW, MD = HorizonteBuilder.MODERN_W, HorizonteBuilder.MODERN_D
	for k, x in ipairs({ 530, 596, 662, 728 }) do
		local t = x + 900
		reserve("moderna", lotAlong(pain.From, pain.To, t, 1, MD), MW, MD, { street = pain.Name, t = t, side = 1, mirror = k % 2 == 0 })
	end

	-- Lojinhas (prédios com comércio no térreo) no resto da avenida
	for _, side in ipairs({ -1, 1 }) do
		local t = 40
		while t < avT(1500) do
			local w = rng:NextInteger(32, 40)
			local floors = rng:NextInteger(2, 4)
			local item = reserve("loja", lotAlong(avA, avB, t, side, SHOP_LOT_D), w + 2, SHOP_LOT_D, { street = PG.Name, t = t, side = side, lotW = w, floors = floors }, true)
			t += (item and (w / 2 + 26) or 6)
		end
	end

	-- Casas: todas as ruas do bairro, dos dois lados (os 3 modelos da cidade, sorteados)
	for _, st in ipairs(D.Streets) do
		local len = (st.To - st.From).Magnitude
		for _, side in ipairs({ -1, 1 }) do
			local t = 30
			while t < len - 30 do
				local variant = rng:NextInteger(1, 3)
				local w = variant == 3 and 46 or rng:NextInteger(34, 38)
				local item = reserve("casa", lotAlong(st.From, st.To, t, side, HOUSE_LOT_D), w + 2, HOUSE_LOT_D, { street = st.Name, t = t, side = side, lotW = w, variant = variant }, true)
				-- de vez em quando sobra um terreno vazio com árvores (a rua não fica um paredão)
				t += (item and (w / 2 + 26 + (rng:NextNumber() < 0.15 and 30 or 0)) or 6)
			end
		end
	end
	return plan
end

---------------------------------------------------------------------------
-- Etapa 2: construções (depois de tudo, para os números das casas antigas não mudarem)
---------------------------------------------------------------------------

function ProgressoBuilder.build(plan, groups, props)
	local streets = {}
	local function streetOf(name)
		streets[name] = streets[name] or K.newStreet(name)
		return streets[name]
	end
	local numbered = {}
	for _, item in ipairs(plan.items) do
		if item.street then
			table.insert(numbered, item)
		end
	end
	table.sort(numbered, function(x, y)
		if x.street ~= y.street then
			return x.street < y.street
		end
		return x.t < y.t
	end)
	for _, item in ipairs(numbered) do
		item.number = K.takeNumber(streetOf(item.street), item.side)
	end

	local counts = { casa = 0, moderna = 0, torre = 0, loja = 0 }
	local builders = {
		hospital = function(item)
			buildHospital(plan.folder, item)
		end,
		praca = function(item)
			buildPlaza(plan.folder, item)
		end,
		escola = function(item)
			buildSchool(plan.folder, item)
		end,
		torre = function(item)
			HorizonteBuilder.buildTower(groups, item, item.street)
		end,
		moderna = function(item)
			HorizonteBuilder.buildModernHouse(groups, item, item.street)
		end,
		loja = function(item)
			K.withRng(rng, K.buildBuilding, groups.buildings, item.lot, item.lotW, item.floors, { street = item.street, number = item.number })
		end,
		casa = function(item)
			K.withRng(rng, K.buildHouse, groups.houses, item.lot, item.lotW, item.variant, { street = item.street, number = item.number })
		end,
	}
	for _, item in ipairs(plan.items) do
		local ok, err = pcall(builders[item.kind], item)
		if ok then
			if counts[item.kind] then
				counts[item.kind] += 1
			end
		else
			warn(("[Progresso] Erro ao montar %s: %s"):format(item.kind, tostring(err)))
		end
	end

	-- Árvores nos miolos dos quarteirões e nos terrenos que sobraram
	local placed = 0
	for _ = 1, 800 do
		if placed >= 110 then
			break
		end
		local p = Vector3.new(rng:NextNumber(-880, 880), 0, rng:NextNumber(890, 1515))
		local spot = K.rect(CFrame.new(p), 8, 8)
		if K.isFree(spot) then
			K.occupy(spot)
			tree(plan.folder, p, rng:NextNumber(0.9, 1.35))
			placed += 1
		end
	end

	-- Placas com o nome das ruas (nas duas pontas) e o portal de pedra na entrada do bairro
	for _, st in ipairs(D.Streets) do
		local dir = (st.To - st.From).Unit
		local perp = Vector3.new(-dir.Z, 0, dir.X)
		local len = (st.To - st.From).Magnitude
		for _, t in ipairs({ 34, len - 34 }) do
			local p = st.From + dir * t + perp * (STREET_HALF - 1)
			K.buildStreetSign(props, CFrame.lookAt(p, p - perp), st.Name)
		end
	end
	local gate = Vector3.new(-(M.RoadWidth / 2 + M.SidewalkWidth + 8), 0, CityRoads.RADIAL_END + 120)
	local sign = CFrame.lookAt(gate, gate + Vector3.new(0, 0, -1))
	stoneSign(plan.folder, sign + Vector3.new(0, G - 0.2, 0), "Bem-vindo ao " .. D.Name, 22)
	return counts
end

return ProgressoBuilder
