-- ObraBuilder (ModuleScript)
-- Caminho: ServerScriptService > Services > ObraBuilder
-- Marco 10.30 (pedido do Luís): OBRA GRANDE na Estrada do Vale, onde aparece a PERFURATRIZ do assalto
-- ao banco (FerramentasAssaltoService sorteia um dos pontos "PontoPerfuratriz").
--   * Prédio de concreto em construção: térreo + 4 lajes + a cobertura pela metade (ferros para cima),
--     12 pilares, paredes de tijolo nos andares de baixo, escada interna até o topo, guarda-corpos.
--   * Andaime na fachada (tubos, tábuas em cada andar, tela verde) com uma escada de treliça.
--   * Grua (guindaste de torre) de 100 studs: a torre é de treliça e dá para SUBIR até a cabine.
--   * Canteiro: tapume com portão, contêineres do escritório (dois andares, com escada), betoneira,
--     pilhas de tijolo e de ferro, areia, banheiros químicos, gerador, refletores (acendem à noite).
-- Sorteio próprio (Random fixo): a obra sai sempre igual e não muda o resto da cidade.
-- Tudo dentro do Model "Obra" (tag "Obra", atributo PlaceName) para o mapa pôr o pino.

local CollectionService = game:GetService("CollectionService")

local ObraBuilder = {}

local K -- ferramentas do MapBuilder
local W, D = 150, 140 -- lote: largura (ao longo da estrada) e fundo
local G = 0.7 -- chão do lote
local FLOOR = 12 -- altura de cada andar
local NAME = "Obra do Residencial Vale Alto"

local CONCRETE = Color3.fromRGB(168, 166, 160)
local CONCRETE_DARK = Color3.fromRGB(130, 128, 124)
local BRICK = Color3.fromRGB(172, 92, 62)
local DIRT = Color3.fromRGB(138, 112, 82)
local SAND = Color3.fromRGB(214, 190, 140)
local STEEL = Color3.fromRGB(120, 124, 132)
local RUST = Color3.fromRGB(120, 70, 44)
local YELLOW = Color3.fromRGB(240, 186, 30)
local BLACK = Color3.fromRGB(30, 30, 32)
local WOOD = Color3.fromRGB(176, 134, 84)
local PLY = Color3.fromRGB(196, 160, 110)
local GREEN_NET = Color3.fromRGB(40, 120, 60)
local BLUE = Color3.fromRGB(40, 90, 170)
local WHITE = Color3.fromRGB(240, 240, 236)
local ORANGE = Color3.fromRGB(240, 110, 30)

local lot, obra, rng

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
		CanCollide = extra.collide,
		CastShadow = extra.shadow,
	})
end

local function at(x, y, z)
	return lot * CFrame.new(x, y, z)
end

local function box(parent, name, x0, y0, z0, x1, y1, z1, color, material, extra)
	local sx, sy, sz = math.abs(x1 - x0), math.abs(y1 - y0), math.abs(z1 - z0)
	if sx < 0.01 or sy < 0.01 or sz < 0.01 then
		return nil
	end
	return P(parent, name, Vector3.new(sx, sy, sz), at((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), color, material, extra)
end

-- barra entre dois pontos do lote (tubo do andaime, cabo, ferro)
local function bar(parent, name, a, b, thick, color, material, extra)
	local pa, pb = lot:PointToWorldSpace(a), lot:PointToWorldSpace(b)
	local len = (pb - pa).Magnitude
	local up = math.abs((pb - pa).Unit.Y) > 0.98 and Vector3.xAxis or Vector3.yAxis -- tubo em pé
	return P(parent, name, Vector3.new(thick, thick, len), CFrame.lookAt((pa + pb) / 2, pb, up), color, material or Enum.Material.Metal, extra)
end

local function truss(parent, name, x, y0, y1, z)
	local h = math.max(2, math.floor((y1 - y0) / 2 + 0.5) * 2)
	return P(parent, name, Vector3.new(2, h, 2), at(x, y0 + h / 2, z), YELLOW, Enum.Material.Metal, { class = "TrussPart" })
end

local function spotLight(part, face, range, angle)
	local l = Instance.new("SpotLight")
	l.Face = face or Enum.NormalId.Front
	l.Range = range or 50
	l.Angle = angle or 70
	l.Brightness = 2
	l.Color = Color3.fromRGB(255, 236, 200)
	l.Shadows = false
	l.Parent = part
	part:SetAttribute("LuzNoturna", true) -- (o LightingController liga e desliga, se usar a tag)
	return l
end

local spots = {} -- pontos onde a perfuratriz pode aparecer
local function spot(name, x, y, z, yaw)
	local p = P(obra, "PontoPerfuratriz", Vector3.new(1, 1, 1), at(x, y, z) * CFrame.Angles(0, math.rad(yaw or 0), 0), WHITE, nil, { transparency = 1, collide = false, shadow = false })
	p.CanQuery = false
	p.CanTouch = false
	p:SetAttribute("Lugar", name)
	table.insert(spots, p)
	return p
end

---------------------------------------------------------------------------
-- Prédio
---------------------------------------------------------------------------
local BX0, BX1, BZ0, BZ1 = -50, 10, -30, 20 -- caixa do prédio
local COLS_X = { -50, -30, -10, 10 }
local COLS_Z = { -30, -5, 20 }
local HOLE = { x0 = -49, x1 = -37, z0 = 4, z1 = 19 } -- vão da escada nas lajes

local function levelY(k)
	return G + 0.6 + k * FLOOR
end

-- laje com o vão da escada
local function slab(parent, k, x0, x1)
	local y = levelY(k)
	local t = 1
	local function s(a0, a1, c0, c1)
		box(parent, "Laje", a0, y - t, c0, a1, y, c1, CONCRETE, Enum.Material.Concrete)
	end
	x0, x1 = x0 or BX0 - 1, x1 or BX1 + 1
	if x0 < HOLE.x1 then
		s(x0, x1, BZ0 - 1, HOLE.z0)
		s(x0, x1, HOLE.z1, BZ1 + 1)
		s(x0, HOLE.x0, HOLE.z0, HOLE.z1)
		s(HOLE.x1, x1, HOLE.z0, HOLE.z1)
	else
		s(x0, x1, BZ0 - 1, BZ1 + 1)
	end
end

-- escada em "U" de um andar para o próximo, dentro do vão
local function stairs(parent, k)
	local y0 = levelY(k)
	local steps = 6
	local rise = FLOOR / (steps * 2)
	local run = 1.8
	-- lance 1: sobe para o fundo (+Z) do lado esquerdo do vão
	for i = 1, steps do
		local z = HOLE.z0 + 0.5 + (i - 1) * run
		box(parent, "Degrau", HOLE.x0 + 0.3, y0, z, HOLE.x0 + 5.6, y0 + i * rise, z + run, CONCRETE_DARK, Enum.Material.Concrete)
	end
	-- patamar no fundo
	local yl = y0 + steps * rise
	local zl = HOLE.z0 + 0.5 + steps * run
	box(parent, "Patamar", HOLE.x0 + 0.3, yl - 0.8, zl, HOLE.x1 - 0.3, yl, HOLE.z1 - 0.2, CONCRETE_DARK, Enum.Material.Concrete)
	-- lance 2: volta para a frente (-Z) do lado direito
	for i = 1, steps do
		local z = zl - i * run
		box(parent, "Degrau", HOLE.x1 - 5.6, yl, z, HOLE.x1 - 0.3, yl + i * rise, z + run, CONCRETE_DARK, Enum.Material.Concrete)
	end
	-- parede do meio (entre os lances) e corrimão
	box(parent, "ParedeEscada", HOLE.x0 + 5.6, y0, HOLE.z0 + 2, HOLE.x1 - 5.6, y0 + FLOOR - 0.5, zl - 0.2, CONCRETE, Enum.Material.Concrete)
end

local function brickWall(parent, k, x0, z0, x1, z1, window)
	local y0 = levelY(k)
	local y1 = y0 + FLOOR - 1
	local thick = 0.8
	local horizontal = math.abs(x1 - x0) > math.abs(z1 - z0)
	local function piece(a0, a1, b0, b1)
		if horizontal then
			box(parent, "Tijolos", a0, b0, z0 - thick / 2, a1, b1, z0 + thick / 2, BRICK, Enum.Material.Brick)
		else
			box(parent, "Tijolos", x0 - thick / 2, b0, a0, x0 + thick / 2, b1, a1, BRICK, Enum.Material.Brick)
		end
	end
	local a0, a1 = horizontal and math.min(x0, x1) or math.min(z0, z1), horizontal and math.max(x0, x1) or math.max(z0, z1)
	-- parede incompleta: às vezes para no meio (última fiada torta)
	local top = rng:NextNumber() < 0.35 and (y0 + rng:NextInteger(4, 8)) or y1
	if window and top == y1 then
		local mid = (a0 + a1) / 2
		piece(a0, mid - 3, y0, top)
		piece(mid + 3, a1, y0, top)
		piece(mid - 3, mid + 3, y0, y0 + 3.5)
		piece(mid - 3, mid + 3, y0 + 8, top)
	else
		piece(a0, a1, y0, top)
	end
end

local function guardRail(parent, k, x0, z0, x1, z1)
	local y = levelY(k)
	local a, b = Vector3.new(x0, y + 3.2, z0), Vector3.new(x1, y + 3.2, z1)
	bar(parent, "GuardaCorpo", a, b, 0.25, YELLOW, Enum.Material.SmoothPlastic)
	bar(parent, "GuardaCorpo", a - Vector3.new(0, 1.6, 0), b - Vector3.new(0, 1.6, 0), 0.25, BLACK, Enum.Material.SmoothPlastic)
	local len = (b - a).Magnitude
	for d = 0, len, 6 do
		local p = a:Lerp(b, d / math.max(len, 1))
		bar(parent, "PosteGuarda", Vector3.new(p.X, y, p.Z), Vector3.new(p.X, y + 3.4, p.Z), 0.3, YELLOW, Enum.Material.SmoothPlastic)
	end
end

local function buildBuilding()
	local b = K.model("Predio", obra)
	-- base (térreo) e pilares
	box(b, "Piso", BX0 - 1, G, BZ0 - 1, BX1 + 1, levelY(0), BZ1 + 1, CONCRETE_DARK, Enum.Material.Concrete)
	for k = 0, 4 do
		local y0, y1 = levelY(k), levelY(k + 1) - 1
		for _, x in ipairs(COLS_X) do
			for _, z in ipairs(COLS_Z) do
				box(b, "Pilar", x - 1, y0, z - 1, x + 1, y1, z + 1, CONCRETE, Enum.Material.Concrete)
			end
		end
	end
	-- lajes 1 a 4 inteiras; a cobertura (5) só pela metade
	for k = 1, 4 do
		slab(b, k)
	end
	slab(b, 5, BX0 - 1, -20)
	-- ferros saindo dos pilares onde a cobertura não chegou
	for _, x in ipairs(COLS_X) do
		for _, z in ipairs(COLS_Z) do
			if x > -20 then
				local y = levelY(5) - 1
				for _, o in ipairs({ { -0.6, -0.6 }, { 0.6, -0.6 }, { -0.6, 0.6 }, { 0.6, 0.6 } }) do
					bar(b, "Vergalhao", Vector3.new(x + o[1], y, z + o[2]), Vector3.new(x + o[1] * 1.4, y + 4.5, z + o[2] * 1.4), 0.18, RUST, Enum.Material.CorrodedMetal)
				end
			end
		end
	end
	-- forma de madeira e escoras na beira da cobertura (concretagem em andamento)
	box(b, "Forma", -20, levelY(5) - 1, BZ0 - 1, -18.5, levelY(5) + 1.2, BZ1 + 1, PLY, Enum.Material.WoodPlanks)
	for z = BZ0 + 2, BZ1 - 2, 8 do
		bar(b, "Escora", Vector3.new(-14, levelY(4), z), Vector3.new(-14, levelY(5) - 1, z), 0.5, WOOD, Enum.Material.Wood)
	end
	-- escadas
	for k = 0, 4 do
		stairs(b, k)
	end
	-- paredes de tijolo (fundo e lado oeste nos andares de baixo, umas soltas em cima)
	for k = 0, 2 do
		for i = 1, #COLS_X - 1 do
			brickWall(b, k, COLS_X[i] + 1, BZ1, COLS_X[i + 1] - 1, BZ1, true)
		end
		for i = 1, #COLS_Z - 1 do
			if not (k == 0 and i == 1) then -- entrada lateral no térreo
				brickWall(b, k, BX0, COLS_Z[i] + 1, BX0, COLS_Z[i + 1] - 1, true)
			end
		end
	end
	brickWall(b, 3, COLS_X[2] + 1, BZ1, COLS_X[3] - 1, BZ1, false)
	brickWall(b, 0, BX1, COLS_Z[2] + 1, BX1, COLS_Z[3] - 1, true)
	-- guarda-corpos nos andares de cima (frente e lado leste)
	for k = 1, 4 do
		-- vão no meio da frente: passagem para o andaime
		guardRail(b, k, BX0, BZ0 - 0.8, -26, BZ0 - 0.8)
		guardRail(b, k, -14, BZ0 - 0.8, BX1, BZ0 - 0.8)
		guardRail(b, k, BX1 + 0.8, BZ0, BX1 + 0.8, BZ1)
	end
	guardRail(b, 5, BX0, BZ0 - 0.8, -20, BZ0 - 0.8)
	-- placa "use EPI" no térreo
	local sign = box(b, "PlacaEPI", -12, levelY(0) + 4, BZ0 - 1.2, -4, levelY(0) + 7, BZ0 - 1.0, YELLOW, Enum.Material.SmoothPlastic)
	if sign then
		K.addSurfaceText(sign, "⚠ USE CAPACETE", BLACK, YELLOW)
	end
	-- material espalhado nos andares
	for k = 1, 4 do
		local y = levelY(k)
		local x = rng:NextNumber(-34, -4)
		local z = rng:NextNumber(-22, 0)
		box(b, "SacosCimento", x, y, z, x + 3, y + 1.6, z + 2.2, Color3.fromRGB(200, 196, 186), Enum.Material.Fabric)
		box(b, "Tabuas", x + 6, y, z + 6, x + 7.4, y + 0.6, z + 16, WOOD, Enum.Material.WoodPlanks)
	end
end

---------------------------------------------------------------------------
-- Andaime na fachada
---------------------------------------------------------------------------
local function buildScaffold()
	local s = K.model("Andaime", obra)
	local z0, z1 = BZ0 - 6, BZ0 - 1.6
	local top = levelY(5) + 4
	for x = BX0, BX1, 10 do
		for _, z in ipairs({ z0, z1 }) do
			bar(s, "Tubo", Vector3.new(x, G, z), Vector3.new(x, top, z), 0.35, STEEL)
		end
	end
	for k = 0, 5 do
		local y = levelY(k)
		if k > 0 then
			box(s, "Tabua", BX0, y - 0.3, z0 - 0.2, BX1, y, z1 + 0.3, WOOD, Enum.Material.WoodPlanks)
		end
		bar(s, "Travessa", Vector3.new(BX0, y + 3.5, z0), Vector3.new(BX1, y + 3.5, z0), 0.3, STEEL)
		if k < 5 then
			for x = BX0, BX1 - 10, 20 do
				bar(s, "Diagonal", Vector3.new(x, y, z0), Vector3.new(x + 10, y + FLOOR, z0), 0.25, STEEL)
			end
		end
	end
	-- tela verde (metade da fachada)
	local net = box(s, "Tela", BX0, G + 2, z0 - 0.5, -20, top, z0 - 0.4, GREEN_NET, Enum.Material.Fabric, { transparency = 0.45, collide = false, shadow = false })
	if net then
		net.CanQuery = false
	end
	-- escada de treliça (sobe do chão até o último andar do andaime)
	truss(s, "EscadaAndaime", BX1 + 1.2, G, top - 2, (z0 + z1) / 2)
end

---------------------------------------------------------------------------
-- Grua
---------------------------------------------------------------------------
local CX, CZ = 40, 22 -- pé da grua
local CRANE_H = 100

local function buildCrane()
	local c = K.model("Grua", obra)
	box(c, "BaseGrua", CX - 6, G, CZ - 6, CX + 6, G + 2, CZ + 6, CONCRETE, Enum.Material.Concrete)
	-- torre: 4 treliças (dá para subir em qualquer uma) e anéis
	for _, o in ipairs({ { -2, -2 }, { 2, -2 }, { -2, 2 }, { 2, 2 } }) do
		truss(c, "TorreGrua", CX + o[1], G + 2, G + 2 + CRANE_H, CZ + o[2])
	end
	-- travamento por dentro da torre (não encosta nas treliças: dá para subir sem enroscar)
	for y = G + 10, G + CRANE_H - 8, 14 do
		bar(c, "TravaGrua", Vector3.new(CX - 0.8, y, CZ - 0.8), Vector3.new(CX + 0.8, y + 7, CZ + 0.8), 0.35, YELLOW)
		bar(c, "TravaGrua", Vector3.new(CX + 0.8, y + 7, CZ - 0.8), Vector3.new(CX - 0.8, y + 14, CZ + 0.8), 0.35, YELLOW)
	end
	local ytop = G + 2 + CRANE_H
	-- escada de fora (treliça): sai em cima da plataforma da cabine
	truss(c, "EscadaGrua", CX + 5, G + 2, ytop + 4, CZ)
	-- giro + plataforma da cabine
	box(c, "Giro", CX - 4, ytop, CZ - 4, CX + 4, ytop + 1.6, CZ + 4, Color3.fromRGB(60, 60, 64), Enum.Material.Metal)
	local cab = box(c, "Cabine", CX - 4, ytop + 1.6, CZ - 7.8, CX + 1, ytop + 6.6, CZ - 4, YELLOW, Enum.Material.Metal)
	box(c, "VidroCabine", CX - 4.2, ytop + 3.4, CZ - 8, CX + 1.2, ytop + 6, CZ - 7.7, Color3.fromRGB(150, 190, 210), Enum.Material.Glass, { transparency = 0.4 })
	box(c, "PisoCabine", CX - 4, ytop + 1.6, CZ - 4, CX + 4, ytop + 1.9, CZ + 4, Color3.fromRGB(70, 70, 74), Enum.Material.DiamondPlate)
	if cab then
		cab.CanCollide = false
	end
	-- lança (para o lado do prédio, -X) e contra-lança (+X) com os blocos de concreto
	local jibY = ytop + 2.6
	local jib = P(c, "Lanca", Vector3.new(2, 84, 2), at(CX - 4 - 42, jibY, CZ) * CFrame.Angles(0, 0, math.rad(90)), YELLOW, Enum.Material.Metal, { class = "TrussPart" })
	jib.CanCollide = true
	P(c, "ContraLanca", Vector3.new(2, 26, 2), at(CX + 4 + 13, jibY, CZ) * CFrame.Angles(0, 0, math.rad(90)), YELLOW, Enum.Material.Metal, { class = "TrussPart" })
	for i = 0, 2 do
		box(c, "Contrapeso", CX + 18 + i * 2.6, jibY - 5, CZ - 2.2, CX + 20.4 + i * 2.6, jibY - 1, CZ + 2.2, CONCRETE, Enum.Material.Concrete)
	end
	-- torre de cima (A) e os tirantes
	local apex = Vector3.new(CX, jibY + 14, CZ)
	bar(c, "TorreTopo", Vector3.new(CX - 2, jibY + 1, CZ), apex, 0.6, YELLOW)
	bar(c, "TorreTopo", Vector3.new(CX + 2, jibY + 1, CZ), apex, 0.6, YELLOW)
	bar(c, "Tirante", apex, Vector3.new(CX - 60, jibY + 1, CZ), 0.2, BLACK)
	bar(c, "Tirante", apex, Vector3.new(CX + 24, jibY + 1, CZ), 0.2, BLACK)
	-- carrinho, cabo, gancho e um pallet de tijolos pendurado em cima do prédio
	local tx = -24
	box(c, "Carrinho", tx - 2, jibY - 2.2, CZ - 1.6, tx + 2, jibY - 1, CZ + 1.6, Color3.fromRGB(60, 60, 64), Enum.Material.Metal)
	local hookY = levelY(5) + 16
	bar(c, "Cabo", Vector3.new(tx, jibY - 2.2, CZ), Vector3.new(tx, hookY + 1.6, CZ), 0.15, BLACK, Enum.Material.Metal, { collide = false })
	box(c, "Gancho", tx - 0.8, hookY, CZ - 0.8, tx + 0.8, hookY + 1.6, CZ + 0.8, ORANGE, Enum.Material.Metal)
	box(c, "Pallet", tx - 2.4, hookY - 6, CZ - 2.4, tx + 2.4, hookY - 5.4, CZ + 2.4, WOOD, Enum.Material.WoodPlanks)
	box(c, "TijolosPendurados", tx - 2.2, hookY - 5.4, CZ - 2.2, tx + 2.2, hookY - 2.4, CZ + 2.2, BRICK, Enum.Material.Brick)
	for _, o in ipairs({ { -2.2, -2.2 }, { 2.2, -2.2 }, { -2.2, 2.2 }, { 2.2, 2.2 } }) do
		bar(c, "Cinta", Vector3.new(tx + o[1], hookY - 2.4, CZ + o[2]), Vector3.new(tx, hookY, CZ), 0.12, ORANGE, Enum.Material.Fabric, { collide = false })
	end
	-- luz vermelha no topo (avião)
	local beacon = box(c, "LuzTopo", CX - 0.5, apex.Y, CZ - 0.5, CX + 0.5, apex.Y + 1, CZ + 0.5, Color3.fromRGB(255, 40, 40), Enum.Material.Neon)
	if beacon then
		local l = Instance.new("PointLight")
		l.Color = Color3.fromRGB(255, 40, 40)
		l.Range = 16
		l.Brightness = 2
		l.Parent = beacon
	end
	return ytop
end

---------------------------------------------------------------------------
-- Canteiro
---------------------------------------------------------------------------
local function container(parent, x0, y0, z0, color, label)
	local m = K.model("Conteiner", parent)
	local L, Wd, Hh = 20, 8, 8.6
	box(m, "Chao", x0, y0, z0, x0 + L, y0 + 0.4, z0 + Wd, Color3.fromRGB(90, 80, 70), Enum.Material.WoodPlanks)
	box(m, "Teto", x0, y0 + Hh - 0.4, z0, x0 + L, y0 + Hh, z0 + Wd, color, Enum.Material.CorrodedMetal)
	box(m, "Parede", x0, y0, z0 + Wd - 0.4, x0 + L, y0 + Hh, z0 + Wd, color, Enum.Material.CorrodedMetal) -- fundo
	box(m, "Parede", x0, y0, z0, x0 + 0.4, y0 + Hh, z0 + Wd, color, Enum.Material.CorrodedMetal)
	box(m, "Parede", x0 + L - 0.4, y0, z0, x0 + L, y0 + Hh, z0 + Wd, color, Enum.Material.CorrodedMetal)
	-- frente: porta aberta (vão de 4) e janela
	box(m, "Parede", x0, y0, z0, x0 + 3, y0 + Hh, z0 + 0.4, color, Enum.Material.CorrodedMetal)
	box(m, "Parede", x0 + 7, y0, z0, x0 + 11, y0 + Hh, z0 + 0.4, color, Enum.Material.CorrodedMetal)
	box(m, "Parede", x0 + 16, y0, z0, x0 + L, y0 + Hh, z0 + 0.4, color, Enum.Material.CorrodedMetal)
	box(m, "Parede", x0 + 3, y0 + 7, z0, x0 + 7, y0 + Hh, z0 + 0.4, color, Enum.Material.CorrodedMetal)
	box(m, "Parede", x0 + 11, y0, z0, x0 + 16, y0 + 3.5, z0 + 0.4, color, Enum.Material.CorrodedMetal)
	box(m, "Parede", x0 + 11, y0 + 6.8, z0, x0 + 16, y0 + Hh, z0 + 0.4, color, Enum.Material.CorrodedMetal)
	box(m, "Janela", x0 + 11, y0 + 3.5, z0 + 0.1, x0 + 16, y0 + 6.8, z0 + 0.3, Color3.fromRGB(150, 190, 210), Enum.Material.Glass, { transparency = 0.5 })
	-- mesa e plantas da obra
	box(m, "Mesa", x0 + 13, y0 + 3, z0 + 4.5, x0 + 19, y0 + 3.3, z0 + 7.5, WOOD, Enum.Material.Wood)
	box(m, "PeMesa", x0 + 13.2, y0 + 0.4, z0 + 4.7, x0 + 13.6, y0 + 3, z0 + 7.3, BLACK, Enum.Material.Metal)
	box(m, "PeMesa", x0 + 18.4, y0 + 0.4, z0 + 4.7, x0 + 18.8, y0 + 3, z0 + 7.3, BLACK, Enum.Material.Metal)
	box(m, "Planta", x0 + 14, y0 + 3.3, z0 + 5, x0 + 17, y0 + 3.35, z0 + 7, Color3.fromRGB(90, 140, 210), Enum.Material.SmoothPlastic)
	if label then
		local plate = box(m, "PlacaConteiner", x0 + 3.5, y0 + Hh + 0.1, z0 - 0.1, x0 + 16.5, y0 + Hh + 2.1, z0 + 0.1, WHITE, Enum.Material.SmoothPlastic)
		if plate then
			K.addSurfaceText(plate, label, BLACK, WHITE)
		end
	end
	return m
end

local function floodlight(parent, x, z, faceX, faceZ)
	local pole = box(parent, "PosteRefletor", x - 0.4, G, z - 0.4, x + 0.4, G + 22, z + 0.4, STEEL, Enum.Material.Metal)
	local head = P(parent, "Refletor", Vector3.new(3, 2, 1), CFrame.lookAt(at(x, G + 22, z).Position, at(faceX, G, faceZ).Position), Color3.fromRGB(255, 250, 220), Enum.Material.Neon)
	spotLight(head, Enum.NormalId.Front, 60, 80)
	return pole
end

local function buildYard(craneTop)
	local y = K.model("Canteiro", obra)
	-- chão de terra, cascalho na entrada
	box(y, "Chao", -W / 2, G - 0.7, -D / 2, W / 2, G, D / 2, DIRT, Enum.Material.Ground)
	box(y, "Cascalho", -12, G - 0.65, -D / 2 - 6, 12, G - 0.05, -D / 2, Color3.fromRGB(150, 146, 140), Enum.Material.Pebble)
	-- tapume (com o portão aberto na frente)
	local function fence(x0, z0, x1, z1)
		local hz = math.abs(x1 - x0) > math.abs(z1 - z0)
		for t = 0, (hz and math.abs(x1 - x0) or math.abs(z1 - z0)) - 0.1, 12 do
			local len = math.min(12, (hz and math.abs(x1 - x0) or math.abs(z1 - z0)) - t)
			local color = (math.floor(t / 12) % 2 == 0) and Color3.fromRGB(225, 225, 220) or Color3.fromRGB(40, 110, 170)
			if hz then
				local a = math.min(x0, x1) + t
				box(y, "Tapume", a, G, z0 - 0.3, a + len, G + 9, z0 + 0.3, color, Enum.Material.SmoothPlastic)
			else
				local a = math.min(z0, z1) + t
				box(y, "Tapume", x0 - 0.3, G, a, x0 + 0.3, G + 9, a + len, color, Enum.Material.SmoothPlastic)
			end
		end
	end
	fence(-W / 2, -D / 2, -14, -D / 2)
	fence(14, -D / 2, W / 2, -D / 2)
	-- Marco 10.32: tapume do fundo com um BURACO (uma placa caída): entrada escondida, longe da
	-- ronda dos seguranças (ObraGuardService). De noite eles quase não enxergam aqui.
	fence(-W / 2, D / 2, -63, D / 2)
	fence(-57, D / 2, W / 2, D / 2)
	P(y, "TapumeCaido", Vector3.new(6, 0.6, 9), at(-60, G + 0.3, D / 2 + 4.8) * CFrame.Angles(0, math.rad(8), math.rad(4)), Color3.fromRGB(225, 225, 220), Enum.Material.SmoothPlastic)
	box(y, "Palete", -66, G, D / 2 - 10, -60, G + 1.2, D / 2 - 6, WOOD, Enum.Material.WoodPlanks)
	box(y, "PilhaTijolo", -54, G, D / 2 - 14, -48, G + 4, D / 2 - 9, BRICK, Enum.Material.Brick)
	fence(-W / 2, -D / 2, -W / 2, D / 2)
	fence(W / 2, -D / 2, W / 2, D / 2)
	-- portão (folhas abertas) e a placa grande da obra
	box(y, "Portao", -14, G, -D / 2 - 0.3, -14 + 0.6, G + 9, -D / 2 + 12, Color3.fromRGB(40, 110, 170), Enum.Material.Metal)
	box(y, "Portao", 14 - 0.6, G, -D / 2 - 0.3, 14, G + 9, -D / 2 + 12, Color3.fromRGB(40, 110, 170), Enum.Material.Metal)
	for _, x in ipairs({ -26, -10 }) do
		box(y, "PostePlaca", x - 0.4, G, -D / 2 - 1.4, x + 0.4, G + 18, -D / 2 - 0.8, STEEL, Enum.Material.Metal)
	end
	local plate = box(y, "PlacaObra", -30, G + 10, -D / 2 - 1.8, -6, G + 18, -D / 2 - 1.4, Color3.fromRGB(24, 60, 120), Enum.Material.SmoothPlastic)
	if plate then
		K.addSurfaceText(plate, "🏗️ RESIDENCIAL VALE ALTO\nCONSTRUTORA HORIZONTE • ENTREGA 2027", WHITE, Color3.fromRGB(24, 60, 120))
	end
	-- contêineres do escritório (dois andares) com escada
	container(y, 44, G, -60, Color3.fromRGB(230, 230, 226), "ESCRITÓRIO DA OBRA")
	container(y, 44, G + 8.6, -60, Color3.fromRGB(40, 110, 170), "ALMOXARIFADO")
	-- escada (ao longo da frente) até o patamar da porta de cima; treliça do patamar até o teto
	for i = 1, 9 do
		box(y, "DegrauConteiner", 46 - (10 - i) * 1.6, G, -63, 46 - (9 - i) * 1.6, G + i * (8.6 / 9), -60.2, STEEL, Enum.Material.DiamondPlate)
	end
	box(y, "PatamarConteiner", 46, G + 8.4, -63, 54, G + 8.6, -60.2, STEEL, Enum.Material.DiamondPlate)
	truss(y, "EscadaTeto", 53, G + 8.6, G + 18.6, -61.2)
	-- betoneira
	local mx, mz = 22, -40
	box(y, "BaseBetoneira", mx - 2, G, mz - 1.5, mx + 2, G + 2.5, mz + 1.5, ORANGE, Enum.Material.Metal)
	P(y, "Tambor", Vector3.new(4.6, 4, 4), at(mx, G + 4.6, mz) * CFrame.Angles(0, 0, math.rad(60)), ORANGE, Enum.Material.Metal, { shape = Enum.PartType.Cylinder })
	-- tijolos e ferro
	for i = 0, 2 do
		local x = 18 + i * 5
		box(y, "Pallet", x, G, -32, x + 4, G + 0.5, -28, WOOD, Enum.Material.WoodPlanks)
		box(y, "PilhaTijolos", x + 0.2, G + 0.5, -31.8, x + 3.8, G + 0.5 + rng:NextNumber(2.2, 4), -28.2, BRICK, Enum.Material.Brick)
	end
	for i = 0, 5 do
		bar(y, "Ferro", Vector3.new(16, G + 0.3 + i * 0.25, -20 + i * 0.3), Vector3.new(36, G + 0.3 + i * 0.25, -20 + i * 0.3), 0.2, RUST, Enum.Material.CorrodedMetal)
	end
	-- areia e brita
	P(y, "Areia", Vector3.new(14, 14, 14), at(30, G - 3, 0), SAND, Enum.Material.Sand, { shape = Enum.PartType.Ball })
	P(y, "Brita", Vector3.new(12, 12, 12), at(24, G - 2, 12), Color3.fromRGB(120, 118, 114), Enum.Material.Pebble, { shape = Enum.PartType.Ball })
	-- banheiros químicos
	for i = 0, 1 do
		local x = 64 + i * 4.2
		box(y, "Banheiro", x, G, 52, x + 3.8, G + 8, 56, BLUE, Enum.Material.SmoothPlastic)
		box(y, "TetoBanheiro", x - 0.1, G + 8, 51.9, x + 3.9, G + 8.4, 56.1, WHITE, Enum.Material.SmoothPlastic)
		box(y, "PortaBanheiro", x + 0.4, G + 0.4, 51.8, x + 3.4, G + 7.4, 52, Color3.fromRGB(30, 70, 140), Enum.Material.SmoothPlastic)
	end
	-- gerador
	box(y, "Gerador", 52, G, 30, 60, G + 4, 34, Color3.fromRGB(240, 186, 30), Enum.Material.Metal)
	box(y, "Escapamento", 58, G + 4, 31, 58.6, G + 6, 31.6, BLACK, Enum.Material.Metal)
	-- carrinhos de mão e cones
	for i = 0, 2 do
		local x, z = rng:NextNumber(-60, 30), rng:NextNumber(30, 60)
		box(y, "CarrinhoDeMao", x, G + 1, z, x + 1.8, G + 2.2, z + 3, Color3.fromRGB(60, 140, 60), Enum.Material.Metal)
		P(y, "Roda", Vector3.new(0.4, 1.4, 1.4), at(x + 0.9, G + 0.7, z - 0.3), BLACK, Enum.Material.SmoothPlastic, { shape = Enum.PartType.Cylinder })
	end
	for x = -10, 10, 5 do
		box(y, "Cone", x - 0.6, G, -D / 2 + 8 - 0.6, x + 0.6, G + 2, -D / 2 + 8 + 0.6, ORANGE, Enum.Material.SmoothPlastic)
	end
	-- refletores
	floodlight(y, -66, -60, -20, 0)
	floodlight(y, 66, 60, -10, 0)
	floodlight(y, -66, 60, -20, -10)
	floodlight(y, 66, -20, -20, 0)
	return y
end

---------------------------------------------------------------------------
-- Etapa 1: reserva o lote na Estrada do Vale (antes do campo)
---------------------------------------------------------------------------
function ObraBuilder.plan(map, helpers, gameConfig)
	K = helpers
	local R = gameConfig.Rodovia
	local exit = Vector3.new(0, 0, R.ExitZ)
	local a, b = exit, exit + Vector3.new(R.ExitLength, 0, 0)
	-- do outro lado da estrada, mais para dentro do vale; se não couber, tenta outros trechos
	for _, wish in ipairs({ { 800, -1 }, { 820, 1 }, { 640, -1 }, { 980, -1 }, { 980, 1 }, { 300, -1 }, { 1150, -1 } }) do
		local cf = K.lotBeside(a, b, wish[1], wish[2], D)
		-- (fundo +4 como o banco: com +10 a frente do lote encostava na faixa reservada da estrada)
		local area = K.rect(cf, W + 8, D + 4)
		if K.isFree(area) then
			K.occupy(area)
			return { lot = cf, map = map }
		end
	end
	warn("[ObraBuilder] Sem espaço livre para a obra na " .. tostring(R.ValeName))
	return nil
end

-- Etapa 2: monta tudo
function ObraBuilder.build(plan)
	if not plan then
		return nil
	end
	lot = plan.lot
	rng = Random.new(103010)
	spots = {}
	obra = K.model("Obra", plan.map)
	obra:SetAttribute("PlaceName", NAME)
	obra:SetAttribute("MapaPivot", lot) -- o pino do mapa funciona mesmo com streaming
	buildYard()
	task.wait()
	buildBuilding()
	task.wait()
	buildScaffold()
	local craneTop = buildCrane()
	-- pontos da perfuratriz (y = chão onde ela fica deitada)
	local L = levelY
	spot("Escritório da obra (mesa)", 60, G + 3.3, -54, 20)
	spot("Almoxarifado (contêiner de cima)", 50, G + 9, -55, -70)
	spot("Em cima dos contêineres", 56, G + 17.2, -56, 35)
	spot("Cabine da grua", CX - 1.5, craneTop + 1.9, CZ - 1.5, 90)
	spot("Térreo, debaixo da escada", -46, L(0), 2, 0)
	spot("Térreo, atrás da parede", 4, L(0), 14, 120)
	spot("1º andar, canto da frente", -45, L(1), -25, 45)
	spot("2º andar, perto do pilar", -12, L(2), 14, -30)
	spot("3º andar, beirada", 4, L(3), -25, 80)
	spot("4º andar, no meio", -25, L(4), -2, 10)
	spot("Cobertura (laje pela metade)", -30, L(5), 12, -60)
	spot("Andaime do 3º andar", -6, L(3), BZ0 - 3.8, 90)
	spot("Atrás do gerador", 56, G, 37, 0)
	spot("Ao lado da betoneira", 22, G, -35, 15)
	CollectionService:AddTag(obra, "Obra")
	return obra
end

return ObraBuilder
