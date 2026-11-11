-- ParkBuilder (ModuleScript)
-- Caminho: ServerScriptService > Services > ParkBuilder
-- Marco 7.2: parque de diversões MigueLândia, montado por script (chamado pelo MapBuilder).
--   * estacionamento, entrada com duas torres e a placa "MigueLândia", bilheterias e catracas;
--   * castelo no meio, chafariz, barracas de comida, bancos, postes, árvores e balões;
--   * roda gigante e carrossel DE VERDADE: giram com física (motor) e dá para sentar com E;
--   * barco pirata, chapéu mexicano, queda livre e montanha-russa: se mexem só de enfeite
--     (o ParkController anima no aparelho de cada jogador; o servidor deixa parado).
-- Coordenadas locais do parque: (0, 0, 0) = centro; -Z = lado da entrada (virado para a avenida).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))
local ParkPath = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ParkPath"))

local ParkBuilder = {}

local P = GameConfig.Park
local HALF = P.Size / 2
local GATE_Z = -HALF + 60 -- a cerca da frente (antes dela fica o estacionamento)
local BALL, CYL = Enum.PartType.Ball, Enum.PartType.Cylinder -- Marco 9: faltavam (lâmpadas e xícaras saíam quadradas)

local PINK = Color3.fromRGB(255, 125, 185)
local BLUE = Color3.fromRGB(70, 140, 255)
local YELLOW = Color3.fromRGB(255, 210, 60)
local PURPLE = Color3.fromRGB(140, 80, 220)
local RED = Color3.fromRGB(230, 60, 60)
local GREEN = Color3.fromRGB(80, 190, 100)
local ORANGE = Color3.fromRGB(250, 145, 40)
local WHITE = Color3.fromRGB(250, 250, 250)
local CREAM = Color3.fromRGB(252, 240, 222)
local PATH = Color3.fromRGB(236, 205, 165)
local METAL = Color3.fromRGB(120, 125, 135)
local GOLD = Color3.fromRGB(235, 185, 50)
local COLORS = { RED, ORANGE, YELLOW, GREEN, BLUE, PURPLE, PINK }

local K -- ferramentas do MapBuilder (makePart, model, addSurfaceText, buildTree, buildLamp)
local base -- CFrame do centro do parque

local function at(x, y, z)
	return base * CFrame.new(x, y, z)
end

local function part(parent, name, size, cf, color, material, extra)
	local props = { Name = name, Size = size, CFrame = cf, Color = color, Material = material }
	for k, v in pairs(extra or {}) do
		props[k] = v
	end
	return K.makePart(parent, props)
end

-- Cilindro em pé: centro da base em (x, y0, z) no parque
local function column(parent, name, x, y0, z, height, radius, color, material, extra)
	return part(parent, name, Vector3.new(height, radius * 2, radius * 2), at(x, y0 + height / 2, z) * CFrame.Angles(0, 0, math.rad(90)), color, material, (function()
		local e = { Shape = Enum.PartType.Cylinder }
		for k, v in pairs(extra or {}) do
			e[k] = v
		end
		return e
	end)())
end

-- Triângulo qualquer (pontos no mundo) feito com 2 cunhas (WedgePart): é assim que se faz
-- telhado pontudo liso no Roblox sem modelo 3D
local function triangle(parent, a, b, c, color, material, thickness)
	local ab, ac, bc = b - a, c - a, c - b
	local abd, acd, bcd = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)
	if abd > acd and abd > bcd then
		c, a = a, c
	elseif acd > bcd and acd > abd then
		a, b = b, a
	end
	ab, ac, bc = b - a, c - a, c - b
	local right = ac:Cross(ab).Unit
	local up = bc:Cross(right).Unit
	local back = bc.Unit
	local height = math.abs(ab:Dot(up))
	local th = thickness or 0.2
	local w1 = K.makePart(parent, { ClassName = "WedgePart", Name = "Telha", Size = Vector3.new(th, height, math.abs(ab:Dot(back))), CFrame = CFrame.fromMatrix((a + b) / 2, right, up, back), Color = color, Material = material, CanCollide = false })
	local w2 = K.makePart(parent, { ClassName = "WedgePart", Name = "Telha", Size = Vector3.new(th, height, math.abs(ac:Dot(back))), CFrame = CFrame.fromMatrix((a + c) / 2, -right, up, -back), Color = color, Material = material, CanCollide = false })
	return w1, w2
end

-- Telhado cônico liso de torre: "sides" faces triangulares (stripes = cor das faces alternadas),
-- beiral redondo embaixo e bolinha dourada na ponta
local function cone(parent, x, y0, z, radius, height, color, stripes, sides)
	sides = sides or 16
	local apex = at(x, y0 + height, z).Position
	local r = radius / math.cos(math.pi / sides) -- o polígono cobre o círculo da torre
	for i = 0, sides - 1 do
		local a0, a1 = i * math.pi * 2 / sides, (i + 1) * math.pi * 2 / sides
		local p0 = at(x + math.cos(a0) * r, y0, z + math.sin(a0) * r).Position
		local p1 = at(x + math.cos(a1) * r, y0, z + math.sin(a1) * r).Position
		triangle(parent, p0, p1, apex, (stripes and i % 2 == 1) and stripes or color, Enum.Material.SmoothPlastic)
	end
	column(parent, "Beiral", x, y0 - 0.6, z, 0.8, radius + 0.5, GOLD, Enum.Material.SmoothPlastic, { CanCollide = false })
	part(parent, "ConeTip", Vector3.new(1.2, 1.2, 1.2), at(x, y0 + height + 0.4, z), GOLD, Enum.Material.Metal, { Shape = Enum.PartType.Ball, CanCollide = false })
end

-- Viga entre dois pontos do mundo
local function beam(parent, name, a, b, thickness, color, material, extra)
	local len = (b - a).Magnitude
	return part(parent, name, Vector3.new(thickness, thickness, len), CFrame.lookAt((a + b) / 2, b), color, material, extra)
end

local function flag(parent, x, y0, z, color)
	part(parent, "FlagPole", Vector3.new(0.3, 6, 0.3), at(x, y0 + 3, z), WHITE, Enum.Material.Metal, { CanCollide = false })
	part(parent, "Flag", Vector3.new(0.1, 1.8, 3), at(x, y0 + 5, z + 1.6), color, Enum.Material.Fabric, { CanCollide = false })
end

-- Placa com texto nas duas faces
local function board(parent, name, size, cf, text, textColor, bg, backText)
	local b = part(parent, name, size, cf, bg, Enum.Material.SmoothPlastic)
	K.addSurfaceText(b, text, textColor, bg)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	gui.Parent = b
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = bg
	label.TextColor3 = textColor
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.Text = backText or text
	label.Parent = gui
	return b
end

local function light(parentPart, range, color, brightness)
	local l = Instance.new("PointLight")
	l.Range = range
	l.Color = color or Color3.fromRGB(255, 230, 180)
	l.Brightness = brightness or 1
	l.Parent = parentPart
end

local function weldAll(root, parts)
	for _, p in ipairs(parts) do
		if p ~= root then
			local w = Instance.new("WeldConstraint")
			w.Part0 = root
			w.Part1 = p
			w.Parent = root
		end
		p.Anchored = false
	end
end

local function attachmentAt(parentPart, worldCf, name)
	local a = Instance.new("Attachment")
	a.Name = name or "Attachment"
	a.CFrame = parentPart.CFrame:ToObjectSpace(worldCf)
	a.Parent = parentPart
	return a
end

---------------------------------------------------------------------------
-- Chão, caminhos, cerca e estacionamento
---------------------------------------------------------------------------

local function buildGrounds(m)
	local f = K.model("Chao", m)
	-- Marco 10.31: no píer da Costa do Sol o chão é de tábua (o gramado vira deck)
	if K.pier then
		part(f, "Deck", Vector3.new(P.Size - 4, 0.2, HALF - GATE_Z - 2), at(0, 0.1, (GATE_Z + HALF) / 2), Color3.fromRGB(176, 140, 98), Enum.Material.WoodPlanks)
		for _, x in ipairs({ -150, -75, 75, 150 }) do
			part(f, "Canteiro", Vector3.new(30, 0.25, HALF - GATE_Z - 40), at(x, 0.12, (GATE_Z + HALF) / 2), Color3.fromRGB(110, 195, 95), Enum.Material.Grass)
		end
	else
		part(f, "Grama", Vector3.new(P.Size - 4, 0.2, HALF - GATE_Z - 2), at(0, 0.1, (GATE_Z + HALF) / 2), Color3.fromRGB(110, 195, 95), Enum.Material.Grass)
	end
	local function path(x, z, sx, sz)
		part(f, "Caminho", Vector3.new(sx, 0.3, sz), at(x, 0.25, z), PATH, Enum.Material.Pavement)
	end
	path(0, (GATE_Z + 30) / 2, 28, 30 - GATE_Z) -- avenida principal até o castelo
	path(0, -80, 400, 16) -- caminho atravessado
	path(-130, 55, 14, 270) -- lado esquerdo
	path(130, -10, 14, 140) -- lado direito (até a montanha-russa)
	path(0, 195, 274, 14) -- fundo
	-- volta em octógono em torno do castelo
	for i = 0, 7 do
		local a0, a1 = i * math.pi / 4, (i + 1) * math.pi / 4
		local p0 = Vector3.new(math.cos(a0) * 64, 0, 40 + math.sin(a0) * 58)
		local p1 = Vector3.new(math.cos(a1) * 64, 0, 40 + math.sin(a1) * 58)
		local mid = (p0 + p1) / 2
		local len = (p1 - p0).Magnitude + 10
		part(f, "Caminho", Vector3.new(12, 0.3, len), base * CFrame.lookAt(Vector3.new(mid.X, 0.26, mid.Z), Vector3.new(p1.X, 0.26, p1.Z)), PATH, Enum.Material.Pavement)
	end

	-- Estacionamento na frente da entrada
	local parkZ = (-HALF + GATE_Z - 8) / 2
	if K.pier then
		-- no píer não tem carro: a frente vira uma praça de tábua com bancos (LitoralBuilder)
		part(f, "PracaDoPier", Vector3.new(P.Size - 4, 0.4, GATE_Z + HALF - 10), at(0, 0.1, parkZ), Color3.fromRGB(168, 132, 92), Enum.Material.WoodPlanks)
		part(f, "Calcada", Vector3.new(120, 0.6, 12), at(0, 0.3, GATE_Z - 4), Color3.fromRGB(200, 200, 205), Enum.Material.Concrete)
		return
	end
	part(f, "Estacionamento", Vector3.new(320, 0.4, GATE_Z + HALF - 10), at(0, 0.3, parkZ), Color3.fromRGB(70, 72, 78), Enum.Material.Asphalt)
	for x = -150, 150, 12 do
		if math.abs(x) > 40 then
			part(f, "Vaga", Vector3.new(0.4, 0.05, 16), at(x, 0.52, GATE_Z - 20), WHITE, nil, { CanCollide = false })
		end
	end
	-- calçada da entrada
	part(f, "Calcada", Vector3.new(120, 0.6, 12), at(0, 0.3, GATE_Z - 4), Color3.fromRGB(200, 200, 205), Enum.Material.Concrete)
end

local function buildFence(m)
	local f = K.model("Cerca", m)
	local H = 4
	local function wall(x, z, sx, sz)
		part(f, "Muro", Vector3.new(sx, H, sz), at(x, H / 2, z), CREAM, Enum.Material.Brick)
		part(f, "Faixa", Vector3.new(sx + 0.2, 0.6, sz + 0.2), at(x, H + 0.3, z), PINK)
	end
	local gap = 44 -- abertura da entrada (entre as torres)
	local sideLen = HALF - gap
	wall(-(gap + sideLen / 2), GATE_Z, sideLen, 1.2)
	wall(gap + sideLen / 2, GATE_Z, sideLen, 1.2)
	wall(-HALF + 1, (GATE_Z + HALF) / 2, 1.2, HALF - GATE_Z)
	wall(HALF - 1, (GATE_Z + HALF) / 2, 1.2, HALF - GATE_Z)
	wall(0, HALF - 1, P.Size, 1.2)
	-- pilares com bolinha colorida
	local k = 0
	local function pillar(x, z)
		k += 1
		part(f, "Pilar", Vector3.new(2, H + 2, 2), at(x, (H + 2) / 2, z), WHITE, Enum.Material.Brick)
		part(f, "Bola", Vector3.new(2.2, 2.2, 2.2), at(x, H + 3, z), COLORS[k % #COLORS + 1], nil, { Shape = Enum.PartType.Ball })
	end
	for x = -HALF + 1, HALF - 1, 22 do
		if math.abs(x) > gap then
			pillar(x, GATE_Z)
		end
		pillar(x, HALF - 1)
	end
	for z = GATE_Z + 22, HALF - 20, 22 do
		pillar(-HALF + 1, z)
		pillar(HALF - 1, z)
	end
	-- Fradinhos na entrada: gente passa, carro não
	for x = -36, 36, 4.5 do
		part(f, "Fradinho", Vector3.new(1, 3, 1), at(x, 1.5, GATE_Z - 6), YELLOW, Enum.Material.Metal)
	end
end

---------------------------------------------------------------------------
-- Entrada com a placa
---------------------------------------------------------------------------

-- cf: centro do quiosque no chão, frente (-Z) virada para o estacionamento
local function buildTicketBooth(parent, cf)
	local b = K.model("Bilheteria", parent)
	local R, H = 5.2, 7.5
	local function p(n, size, off, c, mat, extra)
		return part(b, n, size, cf * off, c, mat, extra)
	end
	p("Base", Vector3.new(1, R * 2 + 1.4, R * 2 + 1.4), CFrame.new(0, 0.5, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(140, 60, 160), nil, { Shape = Enum.PartType.Cylinder })
	-- 8 lados: pilares dourados, rodapé listrado e vidro em cima (a frente tem a janelinha do balcão)
	for i = 0, 7 do
		local a = i * math.pi / 4 + math.pi / 8
		local mid = CFrame.Angles(0, -a, 0) * CFrame.new(0, 0, -R * math.cos(math.pi / 8))
		local side = 2 * R * math.sin(math.pi / 8)
		local front = i == 0 or i == 7 -- os dois lados virados para -Z (estacionamento)
		p("Rodape", Vector3.new(side, 3.2, 0.4), mid * CFrame.new(0, 2.6, 0), i % 2 == 0 and RED or CREAM)
		if front then
			p("Balcao", Vector3.new(side, 0.3, 1.4), mid * CFrame.new(0, 4.35, -0.4), Color3.fromRGB(150, 95, 55), Enum.Material.WoodPlanks)
		else
			p("Vidro", Vector3.new(side - 0.3, 3.4, 0.2), mid * CFrame.new(0, 5.9, 0), Color3.fromRGB(170, 215, 245), Enum.Material.SmoothPlastic, { Transparency = 0.45 })
		end
		p("Friso", Vector3.new(side, 0.8, 0.5), mid * CFrame.new(0, H - 0.4, 0), YELLOW)
		local corner = CFrame.Angles(0, -(a - math.pi / 8), 0) * CFrame.new(0, 0, -R)
		p("Pilar", Vector3.new(0.5, H, 0.5), corner * CFrame.new(0, H / 2 + 1, 0), GOLD, Enum.Material.Metal)
	end
	p("Teto", Vector3.new(0.4, R * 2, R * 2), CFrame.new(0, H + 1, 0) * CFrame.Angles(0, 0, math.rad(90)), CREAM, nil, { Shape = Enum.PartType.Cylinder })
	-- atendente (boneco simples) e plaquinha de preço
	p("Atendente", Vector3.new(1.6, 2, 1), CFrame.new(0, 5.2, 1.4), Color3.fromRGB(60, 110, 200))
	p("Cabeca", Vector3.new(1.1, 1.1, 1.1), CFrame.new(0, 6.8, 1.4), Color3.fromRGB(240, 200, 160), nil, { Shape = Enum.PartType.Ball })
	p("Chapeu", Vector3.new(0.4, 1.4, 1.4), CFrame.new(0, 7.45, 1.4) * CFrame.Angles(0, 0, math.rad(90)), RED, nil, { Shape = Enum.PartType.Cylinder })
	local price = p("Preco", Vector3.new(3.4, 1.2, 0.2), CFrame.new(0, 3.5, -R - 0.15), WHITE)
	K.addSurfaceText(price, "ENTRADA GRÁTIS", Color3.fromRGB(40, 140, 60), WHITE)
	-- telhado de circo: cone listrado, bandeirinha e placa
	local top = cf * CFrame.new(0, H + 1.2, 0)
	local apex = (top * CFrame.new(0, 6, 0)).Position
	local rr = (R + 1.2) / math.cos(math.pi / 16)
	for i = 0, 15 do
		local a0, a1 = i * math.pi / 8, (i + 1) * math.pi / 8
		triangle(b, (top * CFrame.new(math.cos(a0) * rr, 0, math.sin(a0) * rr)).Position, (top * CFrame.new(math.cos(a1) * rr, 0, math.sin(a1) * rr)).Position, apex, i % 2 == 0 and RED or WHITE, Enum.Material.SmoothPlastic)
	end
	for i = 0, 15 do
		local a = (i + 0.5) * math.pi / 8
		p("Franja", Vector3.new(1, 1, 1), CFrame.new(0, H + 0.9, 0) * CFrame.new(math.cos(a) * (R + 1.1), 0, math.sin(a) * (R + 1.1)), i % 2 == 0 and RED or WHITE, nil, { Shape = Enum.PartType.Ball, CanCollide = false })
	end
	part(b, "Bola", Vector3.new(1.2, 1.2, 1.2), CFrame.new(apex + Vector3.new(0, 0.4, 0)), GOLD, Enum.Material.Metal, { Shape = Enum.PartType.Ball, CanCollide = false })
	part(b, "Mastro", Vector3.new(0.2, 3, 0.2), CFrame.new(apex + Vector3.new(0, 1.9, 0)), WHITE, nil, { CanCollide = false })
	part(b, "Bandeira", Vector3.new(0.1, 1.2, 2), CFrame.new(apex + Vector3.new(0, 2.7, 1)), YELLOW, Enum.Material.Fabric, { CanCollide = false })
	board(b, "PlacaIngresso", Vector3.new(8, 1.8, 0.3), cf * CFrame.new(0, H + 2.4, -R - 1.6), "INGRESSOS", WHITE, PURPLE, "INGRESSOS")
	p("SuportePlaca", Vector3.new(0.3, 1.4, 1.6), CFrame.new(0, H + 1.6, -R - 0.9), GOLD, Enum.Material.Metal, { CanCollide = false })
end

local function buildEntrance(m)
	local e = K.model("Entrada", m)
	for _, sx in ipairs({ -1, 1 }) do
		local x = sx * 34
		column(e, "Torre", x, 0, GATE_Z, 38, 9, sx < 0 and PINK or BLUE, Enum.Material.SmoothPlastic)
		for _, y in ipairs({ 10, 24 }) do
			column(e, "Anel", x, y, GATE_Z, 1.5, 9.4, YELLOW)
		end
		for _, y in ipairs({ 16, 29 }) do
			part(e, "Janela", Vector3.new(2.4, 3.6, 0.4), at(x, y, GATE_Z - 8.9), Color3.fromRGB(255, 230, 140), Enum.Material.Neon, { CanCollide = false })
		end
		column(e, "Beiral", x, 38, GATE_Z, 1.5, 10.5, WHITE)
		cone(e, x, 39.5, GATE_Z, 11, 20, sx < 0 and BLUE or PINK, WHITE)
		flag(e, x, 60.5, GATE_Z, sx < 0 and YELLOW or RED)
		-- Bilheteria: quiosque redondo com vidros, balcão e telhado listrado de circo
		buildTicketBooth(e, at(sx * 58, 0, GATE_Z - 11))
	end
	-- Arco com a placa
	part(e, "Arco", Vector3.new(60, 7, 6), at(0, 33, GATE_Z), PURPLE)
	part(e, "ArcoFaixa", Vector3.new(60.2, 1, 6.2), at(0, 29.8, GATE_Z), YELLOW)
	local sign = board(e, "PlacaMigueLandia", Vector3.new(48, 12, 1), at(0, 43, GATE_Z - 1), P.Name, YELLOW, Color3.fromRGB(110, 50, 190), "VOLTE SEMPRE!")
	-- moldura rosa em volta da placa
	for _, y in ipairs({ 36.5, 49.5 }) do
		part(e, "Moldura", Vector3.new(50, 1, 1.4), at(0, y, GATE_Z - 1), PINK)
	end
	for _, x in ipairs({ -24.5, 24.5 }) do
		part(e, "Moldura", Vector3.new(1, 14, 1.4), at(x, 43, GATE_Z - 1), PINK)
	end
	-- luzinhas em volta da placa
	for i = 0, 23 do
		local x = -23.5 + i * (47 / 23)
		for _, y in ipairs({ 36.2, 49.8 }) do
			part(e, "Luz", Vector3.new(0.8, 0.8, 0.8), at(x, y, GATE_Z - 1.6), COLORS[i % #COLORS + 1], Enum.Material.Neon, { Shape = Enum.PartType.Ball, CanCollide = false })
		end
	end
	light(sign, 28, Color3.fromRGB(255, 220, 255), 0.7)
	-- arco de bolas coloridas por cima de tudo
	for i = 0, 18 do
		local a = math.rad(15 + i * (150 / 18))
		local x, y = math.cos(a) * 26, 52 + math.sin(a) * 12
		part(e, "Balao", Vector3.new(3, 3.4, 3), at(x, y, GATE_Z - 0.5), COLORS[i % #COLORS + 1], nil, { Shape = Enum.PartType.Ball, CanCollide = false })
	end
	-- estrela no alto
	for i = 0, 1 do
		part(e, "Estrela", Vector3.new(5, 5, 1), at(0, 66, GATE_Z - 0.5) * CFrame.Angles(0, 0, math.rad(45 * i)), YELLOW, Enum.Material.Neon, { CanCollide = false })
	end
	-- catracas
	for x = -12, 12, 6 do
		part(e, "Catraca", Vector3.new(1.2, 3.4, 4), at(x, 1.7, GATE_Z + 4), METAL, Enum.Material.Metal)
	end
end

---------------------------------------------------------------------------
-- Castelo e chafariz
---------------------------------------------------------------------------

-- string.upper não mexe nas letras com acento: "MigueLândia" virava "MIGUELâNDIA"
local ACCENTS = { ["á"] = "Á", ["â"] = "Â", ["ã"] = "Ã", ["à"] = "À", ["é"] = "É", ["ê"] = "Ê", ["í"] = "Í", ["ó"] = "Ó", ["ô"] = "Ô", ["õ"] = "Õ", ["ú"] = "Ú", ["ç"] = "Ç" }
local function upper(s)
	for a, b in pairs(ACCENTS) do
		s = s:gsub(a, b)
	end
	return string.upper(s)
end

-- Castelo (Marco 7.4): bem maior, com cores de conto de fadas (lilás, azul e dourado, sem
-- branco estourado) e salão do trono por dentro: piso xadrez, tapete vermelho, colunas,
-- lustres, escadas para a galeria e trono para sentar.
local function buildCastle(m)
	local c = K.model("Castelo", m)
	local cz = 40
	-- Marco 7.5: lilás mais forte (o claro de antes ficava branco estourado no sol)
	local WALL = Color3.fromRGB(196, 160, 214)
	local TRIM = Color3.fromRGB(160, 120, 190)
	local ROYAL = Color3.fromRGB(45, 80, 200)
	local ROSE = Color3.fromRGB(235, 105, 165)
	local GLASS = Color3.fromRGB(70, 100, 180)
	local WARM = Color3.fromRGB(255, 214, 140)
	local function box(name, size, x, y, z, color, mat, extra)
		return part(c, name, size, at(x, y, z), color, mat, extra)
	end
	local FRONT, BACK, SIDE = cz - 30, cz + 22, 28 -- paredes do salão (lado de fora)
	local FLOOR = 4 -- altura do piso de dentro
	local TOP = 40 -- altura das paredes

	-- Base de pedra e escadaria da frente
	box("Base", Vector3.new(96, FLOOR, 76), 0, FLOOR / 2, cz, Color3.fromRGB(190, 178, 196), Enum.Material.Cobblestone)
	for i = 0, 4 do
		box("Degrau", Vector3.new(30, 0.8 * (5 - i), 1.6), 0, 0.4 * (5 - i), cz - 38 - 1.6 * (4 - i) - 0.8, Color3.fromRGB(210, 200, 215), Enum.Material.Marble)
	end
	-- Paredes (a da frente tem a porta: 12 de largura e 16 de altura)
	local H = TOP - FLOOR
	local midY = FLOOR + H / 2
	box("Parede", Vector3.new(2, H, BACK - FRONT), -SIDE + 1, midY, (FRONT + BACK) / 2, WALL)
	box("Parede", Vector3.new(2, H, BACK - FRONT), SIDE - 1, midY, (FRONT + BACK) / 2, WALL)
	box("Parede", Vector3.new(SIDE * 2, H, 2), 0, midY, BACK - 1, WALL)
	box("Parede", Vector3.new(SIDE - 6, H, 2), -(SIDE + 6) / 2, midY, FRONT + 1, WALL)
	box("Parede", Vector3.new(SIDE - 6, H, 2), (SIDE + 6) / 2, midY, FRONT + 1, WALL)
	box("Parede", Vector3.new(12, TOP - (FLOOR + 16), 2), 0, (TOP + FLOOR + 16) / 2, FRONT + 1, WALL)
	box("Teto", Vector3.new(SIDE * 2, 1, BACK - FRONT), 0, TOP - 0.5, (FRONT + BACK) / 2, TRIM)
	-- faixas, rodapé e ameias
	for _, y in ipairs({ FLOOR + 0.6, TOP - 2 }) do
		box("Faixa", Vector3.new(SIDE * 2 + 0.4, 1.2, 0.3), 0, y, FRONT - 0.15, y < 10 and TRIM or GOLD)
		box("Faixa", Vector3.new(SIDE * 2 + 0.4, 1.2, 0.3), 0, y, BACK + 0.15, y < 10 and TRIM or GOLD)
		box("Faixa", Vector3.new(0.3, 1.2, BACK - FRONT), -SIDE - 0.15, y, (FRONT + BACK) / 2, y < 10 and TRIM or GOLD)
		box("Faixa", Vector3.new(0.3, 1.2, BACK - FRONT), SIDE + 0.15, y, (FRONT + BACK) / 2, y < 10 and TRIM or GOLD)
	end
	for x = -SIDE + 1, SIDE - 1, 4 do
		box("Ameia", Vector3.new(2, 2.4, 2), x, TOP + 1.2, FRONT + 1, WALL)
		box("Ameia", Vector3.new(2, 2.4, 2), x, TOP + 1.2, BACK - 1, WALL)
	end
	for z = FRONT + 5, BACK - 5, 4 do
		box("Ameia", Vector3.new(2, 2.4, 2), -SIDE + 1, TOP + 1.2, z, WALL)
		box("Ameia", Vector3.new(2, 2.4, 2), SIDE - 1, TOP + 1.2, z, WALL)
	end
	-- Janelas (vidro azul com moldura dourada, por fora e por dentro)
	local function window(x, y, z, alongX, w, h)
		local thin = alongX and Vector3.new(w, h, 0.2) or Vector3.new(0.2, h, w)
		local frame = alongX and Vector3.new(w + 0.8, h + 0.8, 0.15) or Vector3.new(0.15, h + 0.8, w + 0.8)
		local off = alongX and Vector3.new(0, 0, 1.12) or Vector3.new(1.12, 0, 0)
		for _, s in ipairs({ -1, 1 }) do
			local pos = Vector3.new(x, y, z) + off * s
			box("Moldura", frame, pos.X, pos.Y, pos.Z, GOLD)
			local g = Vector3.new(x, y, z) + off * s * 1.06
			box("Janela", thin, g.X, g.Y, g.Z, GLASS, Enum.Material.SmoothPlastic, { CanCollide = false })
		end
		-- topo em arco (meio disco dourado atravessando a parede)
		part(c, "JanelaArco", Vector3.new(2.5, w, w), at(x, y + h / 2, z) * (alongX and CFrame.Angles(0, math.rad(90), 0) or CFrame.new()), GOLD, nil, { Shape = Enum.PartType.Cylinder })
	end
	for _, z in ipairs({ cz - 18, cz - 9, cz, cz + 9 }) do
		for _, sx in ipairs({ -1, 1 }) do
			window(sx * (SIDE - 1), 14, z, false, 3.4, 6)
			window(sx * (SIDE - 1), 29, z, false, 3.4, 6)
		end
	end
	for _, x in ipairs({ -19, 19 }) do
		window(x, 14, FRONT + 1, true, 3.4, 6)
		window(x, 29, FRONT + 1, true, 3.4, 6)
	end
	-- rosácea em cima da porta
	local facingZ = CFrame.Angles(0, math.rad(90), 0) -- cilindro "deitado" virado para a frente
	part(c, "Rosacea", Vector3.new(0.5, 8, 8), at(0, 33.5, FRONT - 0.1) * facingZ, GOLD, nil, { Shape = Enum.PartType.Cylinder, CanCollide = false })
	part(c, "Rosacea", Vector3.new(0.6, 6.8, 6.8), at(0, 33.5, FRONT - 0.25) * facingZ, ROSE, Enum.Material.SmoothPlastic, { Shape = Enum.PartType.Cylinder, CanCollide = false })
	-- Porta: moldura dourada, frontão pontudo, portas abertas e a placa
	box("PortalLado", Vector3.new(1, 16, 0.6), -6.5, FLOOR + 8, FRONT - 0.3, GOLD)
	box("PortalLado", Vector3.new(1, 16, 0.6), 6.5, FLOOR + 8, FRONT - 0.3, GOLD)
	box("PortalTopo", Vector3.new(14, 1, 0.6), 0, FLOOR + 16.5, FRONT - 0.3, GOLD)
	triangle(c, at(-8, FLOOR + 17, FRONT - 0.4).Position, at(8, FLOOR + 17, FRONT - 0.4).Position, at(0, FLOOR + 22, FRONT - 0.4).Position, ROYAL, Enum.Material.SmoothPlastic, 0.4)
	for _, sx in ipairs({ -1, 1 }) do
		part(c, "PortaAberta", Vector3.new(6, 15.6, 0.5), at(sx * 6, FLOOR + 7.8, FRONT + 2) * CFrame.Angles(0, sx * math.rad(-80), 0) * CFrame.new(-sx * 3, 0, 0), Color3.fromRGB(110, 60, 140), Enum.Material.Wood)
	end
	board(c, "PlacaCastelo", Vector3.new(20, 2.6, 0.4), at(0, FLOOR + 23.9, FRONT - 0.4), "CASTELO DA " .. upper(P.Name), WHITE, PURPLE)

	-- Torres: 4 nos cantos, 2 do lado da porta e a torre grande do meio
	local function tower(x, z, y0, height, radius, roofColor, roofH)
		column(c, "Torre", x, y0, z, height, radius, WALL)
		column(c, "AnelTorre", x, y0 + height - 3, z, 1.2, radius + 0.35, GOLD)
		column(c, "AnelTorre", x, y0 + height * 0.45, z, 0.8, radius + 0.25, TRIM)
		for k = 0, 3 do
			local a = k * math.pi / 2 + math.pi / 4
			local wx, wz = x + math.cos(a) * (radius + 0.05), z + math.sin(a) * (radius + 0.05)
			part(c, "Janela", Vector3.new(0.3, 3.2, 1.8), at(wx, y0 + height * 0.7, wz) * CFrame.Angles(0, -a, 0), WARM, nil, { CanCollide = false })
		end
		cone(c, x, y0 + height, z, radius + 1.4, roofH, roofColor)
		flag(c, x, y0 + height + roofH + 0.8, z, COLORS[(math.floor(x + z) % #COLORS) + 1])
	end
	tower(-SIDE - 2, FRONT + 1, FLOOR, 50, 7, ROSE, 22)
	tower(SIDE + 2, FRONT + 1, FLOOR, 50, 7, ROSE, 22)
	tower(-SIDE - 2, BACK - 1, FLOOR, 56, 7, ROYAL, 24)
	tower(SIDE + 2, BACK - 1, FLOOR, 56, 7, ROYAL, 24)
	tower(-13.5, FRONT - 1, FLOOR, 44, 3.2, PURPLE, 14)
	tower(13.5, FRONT - 1, FLOOR, 44, 3.2, PURPLE, 14)
	-- torre grande no meio do telhado, com sacada redonda e 4 torrinhas
	local TZ = cz + 2
	column(c, "TorreMeio", 0, TOP, TZ, 40, 11, WALL)
	column(c, "Sacada", 0, TOP + 21, TZ, 1, 13.5, TRIM)
	column(c, "SacadaBorda", 0, TOP + 22, TZ, 0.6, 13.6, GOLD, nil, { CanCollide = false })
	for k = 0, 7 do
		local a = k * math.pi / 4
		part(c, "Janela", Vector3.new(0.3, 5, 2.4), at(math.cos(a) * 11.05, TOP + 31, TZ + math.sin(a) * 11.05) * CFrame.Angles(0, -a, 0), GLASS, Enum.Material.SmoothPlastic, { CanCollide = false })
		part(c, "Janela", Vector3.new(0.3, 5, 2.4), at(math.cos(a) * 11.05, TOP + 12, TZ + math.sin(a) * 11.05) * CFrame.Angles(0, -a, 0), WARM, nil, { CanCollide = false })
	end
	column(c, "AnelMeio", 0, TOP + 38, TZ, 1.4, 11.4, GOLD)
	cone(c, 0, TOP + 40, TZ, 12.5, 34, ROYAL, nil, 20)
	flag(c, 0, TOP + 75, TZ, PINK)
	for k = 0, 3 do
		local a = k * math.pi / 2 + math.pi / 4
		local tx, tz = math.cos(a) * 11.5, TZ + math.sin(a) * 11.5
		column(c, "Torrinha", tx, TOP + 26, tz, 18, 2.6, WALL)
		column(c, "AnelTorrinha", tx, TOP + 42, tz, 0.6, 2.9, GOLD)
		cone(c, tx, TOP + 44, tz, 3.2, 10, ROSE, nil, 12)
	end

	-- Salão do trono
	local IN_X, IN_Z0, IN_Z1 = SIDE - 2, FRONT + 2, BACK - 2 -- parte de dentro das paredes
	for x = -IN_X + 2, IN_X - 2, 4 do
		for z = IN_Z0 + 2, IN_Z1 - 2, 4 do
			local odd = (math.floor((x + IN_X) / 4) + math.floor((z - IN_Z0) / 4)) % 2 == 1
			box("Piso", Vector3.new(4, 0.2, 4), x, FLOOR + 0.1, z, odd and Color3.fromRGB(230, 170, 205) or Color3.fromRGB(250, 244, 250), Enum.Material.Marble)
		end
	end
	box("Tapete", Vector3.new(6, 0.1, IN_Z1 - IN_Z0 - 10), 0, FLOOR + 0.25, (IN_Z0 + IN_Z1) / 2 - 5, Color3.fromRGB(190, 30, 50), Enum.Material.Fabric)
	box("TapeteBorda", Vector3.new(6.6, 0.08, IN_Z1 - IN_Z0 - 10), 0, FLOOR + 0.24, (IN_Z0 + IN_Z1) / 2 - 5, GOLD, Enum.Material.Fabric)
	-- colunas com capitel dourado
	for _, x in ipairs({ -13, 13 }) do
		for z = IN_Z0 + 8, IN_Z1 - 16, 10 do
			column(c, "Coluna", x, FLOOR, z, 1.2, 2.2, GOLD)
			column(c, "Coluna", x, FLOOR + 1.2, z, 22, 1.5, Color3.fromRGB(222, 205, 230), Enum.Material.Marble)
			column(c, "Capitel", x, FLOOR + 23.2, z, 1.4, 2.3, GOLD)
		end
	end
	-- lustres
	for _, z in ipairs({ cz - 12, cz + 6 }) do
		box("Corrente", Vector3.new(0.2, 6, 0.2), 0, TOP - 4, z, GOLD, Enum.Material.Metal, { CanCollide = false })
		column(c, "Lustre", 0, TOP - 9, z, 0.6, 4, GOLD, Enum.Material.Metal, { CanCollide = false })
		for k = 0, 7 do
			local a = k * math.pi / 4
			box("Vela", Vector3.new(0.5, 0.5, 0.5), math.cos(a) * 3.6, TOP - 8, z + math.sin(a) * 3.6, WARM, Enum.Material.Neon, { Shape = Enum.PartType.Ball, CanCollide = false })
		end
		local core = box("LustreLuz", Vector3.new(1.4, 1.4, 1.4), 0, TOP - 9.6, z, WARM, Enum.Material.SmoothPlastic, { Shape = Enum.PartType.Ball, CanCollide = false })
		light(core, 30, Color3.fromRGB(255, 220, 170), 0.6) -- Marco 7.5: era 45 / 2 (salão estourado)
	end
	-- estandartes nas paredes do lado
	for _, z in ipairs({ cz - 12, cz, cz + 12 }) do
		for _, sx in ipairs({ -1, 1 }) do
			box("Estandarte", Vector3.new(0.2, 12, 4), sx * (IN_X - 0.15), FLOOR + 20, z, sx < 0 and PURPLE or ROSE, Enum.Material.Fabric, { CanCollide = false })
			box("Brasao", Vector3.new(0.3, 2, 2), sx * (IN_X - 0.3), FLOOR + 22, z, GOLD, nil, { Shape = Enum.PartType.Ball, CanCollide = false })
		end
	end
	-- escadas dos dois lados até a galeria do fundo
	local GALLERY_Y = FLOOR + 16
	local STEPS = 20
	local stairZ0 = IN_Z1 - 12 - STEPS * 1.4
	for _, sx in ipairs({ -1, 1 }) do
		for k = 1, STEPS do
			local top = FLOOR + 0.8 * k
			box("Degrau", Vector3.new(6, top - FLOOR, 1.4), sx * (IN_X - 3), FLOOR + (top - FLOOR) / 2, stairZ0 + 1.4 * (k - 0.5), Color3.fromRGB(200, 180, 210), Enum.Material.Marble)
		end
	end
	box("Galeria", Vector3.new(IN_X * 2, 0.8, 12), 0, GALLERY_Y - 0.4, IN_Z1 - 6, Color3.fromRGB(200, 180, 210), Enum.Material.Marble)
	for x = -IN_X + 7, IN_X - 7, 3 do
		box("Grade", Vector3.new(0.3, 3, 0.3), x, GALLERY_Y + 1.5, IN_Z1 - 12, GOLD, Enum.Material.Metal)
	end
	box("Corrimao", Vector3.new(IN_X * 2 - 13, 0.4, 0.5), 0, GALLERY_Y + 3, IN_Z1 - 12, GOLD, Enum.Material.Metal)
	-- trono no fundo, embaixo da galeria
	for k = 0, 2 do
		box("Palanque", Vector3.new(16 - k * 3, 0.6, 9 - k * 1.6), 0, FLOOR + 0.5 + k * 0.6, IN_Z1 - 5 + k * 0.8, k == 1 and GOLD or Color3.fromRGB(150, 40, 120))
	end
	local throneZ = IN_Z1 - 3
	local seat = Instance.new("Seat")
	seat.Name = "Trono"
	seat.Anchored = true
	seat.Size = Vector3.new(3.4, 0.8, 3)
	seat.CFrame = at(0, FLOOR + 2.6, throneZ)
	seat.Color = Color3.fromRGB(120, 40, 150)
	seat.Material = Enum.Material.Fabric
	seat.TopSurface = Enum.SurfaceType.Smooth
	seat:SetAttribute("SeatText", "Trono")
	seat.Parent = c
	box("TronoBase", Vector3.new(4, 1.4, 3.4), 0, FLOOR + 1.6, throneZ, GOLD, Enum.Material.Metal)
	box("TronoEncosto", Vector3.new(4, 7, 0.8), 0, FLOOR + 5.5, throneZ + 1.8, GOLD, Enum.Material.Metal)
	box("TronoAlmofada", Vector3.new(3, 5.4, 0.3), 0, FLOOR + 5.3, throneZ + 1.3, Color3.fromRGB(120, 40, 150), Enum.Material.Fabric)
	for _, sx in ipairs({ -1, 1 }) do
		box("TronoBraco", Vector3.new(0.6, 1.4, 3), sx * 2, FLOOR + 3.4, throneZ, GOLD, Enum.Material.Metal)
		box("TronoBola", Vector3.new(0.8, 0.8, 0.8), sx * 2, FLOOR + 9.3, throneZ + 1.8, GOLD, Enum.Material.Metal, { Shape = Enum.PartType.Ball })
	end
	box("Coroa", Vector3.new(1.8, 1.2, 0.4), 0, FLOOR + 9.6, throneZ + 1.8, Color3.fromRGB(255, 215, 60), Enum.Material.Neon)
	-- quadros na parede do fundo (paisagem simples) e em cima do trono
	for _, x in ipairs({ -16, 16 }) do
		box("Quadro", Vector3.new(8, 6, 0.3), x, FLOOR + 8, IN_Z1 - 0.15, GOLD)
		box("QuadroCeu", Vector3.new(7, 3, 0.3), x, FLOOR + 9.2, IN_Z1 - 0.3, Color3.fromRGB(120, 190, 250))
		box("QuadroGrama", Vector3.new(7, 2, 0.3), x, FLOOR + 6.7, IN_Z1 - 0.3, Color3.fromRGB(90, 180, 90))
		box("QuadroSol", Vector3.new(1.2, 1.2, 0.4), x + 2, FLOOR + 9.8, IN_Z1 - 0.4, YELLOW, nil, { Shape = Enum.PartType.Ball })
	end
	-- luz de fora (à noite)
	for _, x in ipairs({ -20, 20 }) do
		local spot = box("Luz", Vector3.new(1, 1, 1), x, 1, FRONT - 10, WHITE, Enum.Material.Neon, { Transparency = 1, CanCollide = false })
		light(spot, 26, Color3.fromRGB(255, 200, 255), 0.5) -- Marco 7.5: era 60 / 2 (fachada estourada)
	end
	-- jardim com arbustos na frente
	for _, sx in ipairs({ -1, 1 }) do
		for k = 0, 3 do
			box("Arbusto", Vector3.new(4, 3, 4), sx * (20 + k * 6), FLOOR + 1.5, FRONT - 4, Color3.fromRGB(70, 150, 80), Enum.Material.Grass, { Shape = Enum.PartType.Ball })
		end
	end
end

local function buildFountain(m)
	local f = K.model("Chafariz", m)
	local z = -80
	column(f, "Borda", 0, 0, z, 2.4, 15, Color3.fromRGB(220, 220, 230), Enum.Material.Marble)
	column(f, "Agua", 0, 0.2, z, 2.4, 13.6, Color3.fromRGB(80, 170, 255), Enum.Material.SmoothPlastic, { Transparency = 0.3, CanCollide = false })
	column(f, "Coluna", 0, 0, z, 9, 1.6, Color3.fromRGB(220, 220, 230), Enum.Material.Marble)
	column(f, "Bacia", 0, 9, z, 1.2, 5, Color3.fromRGB(220, 220, 230), Enum.Material.Marble)
	column(f, "AguaBacia", 0, 9.5, z, 0.9, 4.4, Color3.fromRGB(80, 170, 255), Enum.Material.SmoothPlastic, { Transparency = 0.3, CanCollide = false })
	local jet = column(f, "Jato", 0, 10, z, 6, 0.6, Color3.fromRGB(170, 220, 255), Enum.Material.Neon, { Transparency = 0.4, CanCollide = false })
	local water = Instance.new("ParticleEmitter")
	water.Color = ColorSequence.new(Color3.fromRGB(200, 235, 255))
	water.Size = NumberSequence.new(0.5, 0.2)
	water.Speed = NumberRange.new(10, 14)
	water.SpreadAngle = Vector2.new(25, 25)
	water.Acceleration = Vector3.new(0, -30, 0)
	water.Lifetime = NumberRange.new(0.9, 1.2)
	water.Rate = 40
	-- O ParticleEmitter solta para o "cima" de quem o segura: um Attachment em pé no topo do jato
	local spout = Instance.new("Attachment")
	spout.Name = "Bico"
	spout.Parent = jet
	spout.WorldCFrame = CFrame.new((jet.CFrame * CFrame.new(3, 0, 0)).Position)
	water.Parent = spout
	-- canteiros de flores em volta
	for i = 0, 7 do
		local a = i * math.pi / 4 + math.pi / 8
		local x, zz = math.cos(a) * 21, z + math.sin(a) * 21
		if math.abs(x) > 16 then
			part(f, "Canteiro", Vector3.new(5, 1, 5), at(x, 0.5, zz), Color3.fromRGB(110, 80, 60), Enum.Material.Ground)
			for j = 0, 3 do
				part(f, "Flor", Vector3.new(1, 1, 1), at(x - 1.2 + (j % 2) * 2.4, 1.3, zz - 1.2 + math.floor(j / 2) * 2.4), COLORS[(i + j) % #COLORS + 1], nil, { Shape = Enum.PartType.Ball, CanCollide = false })
			end
		end
	end
end

---------------------------------------------------------------------------
-- Roda gigante (física: motor na roda, cabines penduradas que ficam sempre retas)
---------------------------------------------------------------------------

local function buildFerrisWheel(m)
	local w = K.model("RodaGigante", m)
	local wx, wz = -140, 100
	local AXLE_Y, R = 51, 40
	-- eixo da roda apontando para a entrada: quem chega pela avenida vê a roda de frente
	local hubCf = at(wx, AXLE_Y, wz) * CFrame.Angles(0, math.rad(90), 0)
	local function onWheel(xoff, angle, radius)
		return (hubCf * CFrame.new(xoff, math.cos(angle) * radius, math.sin(angle) * radius)).Position
	end
	-- Estrutura parada (pés em A dos dois lados e eixo)
	for _, s in ipairs({ -1, 1 }) do
		for _, dz in ipairs({ -30, 30 }) do
			beam(w, "Pe", (hubCf * CFrame.new(s * 10, -AXLE_Y, dz)).Position, (hubCf * CFrame.new(s * 7, 0, 0)).Position, 2.2, WHITE, Enum.Material.Metal)
		end
		beam(w, "Travessa", (hubCf * CFrame.new(s * 9, -AXLE_Y + 16, -21)).Position, (hubCf * CFrame.new(s * 9, -AXLE_Y + 16, 21)).Position, 1.2, WHITE, Enum.Material.Metal)
	end
	local axle = part(w, "Eixo", Vector3.new(20, 3, 3), hubCf, METAL, Enum.Material.Metal, { Shape = Enum.PartType.Cylinder })
	-- Parte que gira
	local spinning = {}
	local hub = part(w, "Cubo", Vector3.new(9, 8, 8), hubCf, YELLOW, Enum.Material.SmoothPlastic, { Shape = Enum.PartType.Cylinder, CanCollide = false })
	local SEG = 24
	for _, s in ipairs({ -1, 1 }) do
		for i = 0, SEG - 1 do
			local a0, a1 = i * math.pi * 2 / SEG, (i + 1) * math.pi * 2 / SEG
			table.insert(spinning, beam(w, "Aro", onWheel(s * 3, a0, R), onWheel(s * 3, a1, R), 1, PINK, Enum.Material.Metal, { CanCollide = false }))
			table.insert(spinning, beam(w, "AroDentro", onWheel(s * 3, a0, R * 0.55), onWheel(s * 3, a1, R * 0.55), 0.7, BLUE, Enum.Material.Metal, { CanCollide = false }))
			table.insert(spinning, part(w, "Lampada", Vector3.new(1, 1, 1), CFrame.new(onWheel(s * 3.6, a0, R)), COLORS[i % #COLORS + 1], Enum.Material.Neon, { Shape = Enum.PartType.Ball, CanCollide = false }))
			if i % 2 == 0 then
				table.insert(spinning, beam(w, "Raio", onWheel(s * 2.5, a0, 3), onWheel(s * 3, a0, R), 0.6, WHITE, Enum.Material.Metal, { CanCollide = false }))
			end
		end
	end
	-- 12 cabines
	local cabins = {}
	for k = 0, 11 do
		local angle = k * math.pi * 2 / 12
		local pivot = onWheel(0, angle, R)
		local bar = beam(w, "Barra", onWheel(-3.5, angle, R), onWheel(3.5, angle, R), 0.7, WHITE, Enum.Material.Metal, { CanCollide = false })
		table.insert(spinning, bar)
		local g = CFrame.new(pivot) * hubCf.Rotation -- cabine sempre reta (de pé, alinhada com o eixo)
		local color = COLORS[k % #COLORS + 1]
		local cabin = K.model("Cabine" .. (k + 1), w)
		local parts = {}
		local function add(name, size, offset, c, extra)
			local p = part(cabin, name, size, g * offset, c, Enum.Material.SmoothPlastic, extra)
			table.insert(parts, p)
			return p
		end
		local floor = add("Piso", Vector3.new(4.6, 0.5, 5), CFrame.new(0, -8.5, 0), color)
		add("Haste", Vector3.new(0.5, 2.8, 0.5), CFrame.new(0, -1.4, 0), METAL, { CanCollide = false })
		add("Teto", Vector3.new(5, 0.5, 5.6), CFrame.new(0, -3, 0), color)
		for _, px in ipairs({ -2.1, 2.1 }) do
			for _, pz in ipairs({ -2.4, 2.4 }) do
				add("Poste", Vector3.new(0.3, 5.2, 0.3), CFrame.new(px, -5.75, pz), WHITE)
			end
		end
		for _, pz in ipairs({ -2.35, 2.35 }) do
			add("Parede", Vector3.new(4.6, 2.2, 0.3), CFrame.new(0, -7.15, pz), WHITE)
		end
		for _, px in ipairs({ -2.15, 2.15 }) do
			add("Parede", Vector3.new(0.3, 2.2, 5), CFrame.new(px, -7.15, 0), color)
		end
		for _, side in ipairs({ -1, 1 }) do
			local seat = Instance.new("Seat")
			seat.Name = "Banco"
			seat.Anchored = true
			seat.Size = Vector3.new(3.6, 0.6, 1.4)
			seat.CFrame = g * CFrame.new(0, -7.9, side * 1.5) * CFrame.Angles(0, side > 0 and 0 or math.pi, 0)
			seat.Color = CREAM
			seat.Material = Enum.Material.Fabric
			seat.TopSurface = Enum.SurfaceType.Smooth
			seat:SetAttribute("SeatText", "Roda gigante")
			seat.Parent = cabin
			table.insert(parts, seat)
		end
		weldAll(floor, parts)
		-- dobradiça solta na barra + "giroscópio" que mantém a cabine reta
		local a0 = attachmentAt(bar, g, "Pendurar")
		local a1 = attachmentAt(floor, g, "Pendurar")
		local hinge = Instance.new("HingeConstraint")
		hinge.Attachment0 = a0
		hinge.Attachment1 = a1
		hinge.Parent = floor
		local align = Instance.new("AlignOrientation")
		align.Mode = Enum.OrientationAlignmentMode.OneAttachment
		align.Attachment0 = a1
		align.CFrame = hubCf.Rotation
		align.MaxTorque = 1e7
		align.Responsiveness = 25
		align.Parent = floor
		table.insert(cabins, floor)
	end
	weldAll(hub, spinning)
	hub.Anchored = false
	local motor = Instance.new("HingeConstraint")
	motor.Name = "Motor"
	motor.Attachment0 = attachmentAt(axle, hubCf, "Motor")
	motor.Attachment1 = attachmentAt(hub, hubCf, "Motor")
	motor.ActuatorType = Enum.ActuatorType.Motor
	motor.AngularVelocity = P.WheelSpeed
	motor.MotorMaxTorque = 1e10
	motor.MotorMaxAcceleration = 0.5
	motor.Parent = hub
	-- Plataforma de embarque embaixo da roda
	local bottom = onWheel(0, math.pi, R)
	part(w, "Plataforma", Vector3.new(16, 1.4, 18), CFrame.new(bottom.X, 0.7, bottom.Z) * hubCf.Rotation, Color3.fromRGB(190, 120, 70), Enum.Material.WoodPlanks)
	board(w, "PlacaRoda", Vector3.new(14, 3, 0.4), at(wx + 14, 5, wz - 14), "RODA GIGANTE", WHITE, PINK)
	part(w, "PostePlaca", Vector3.new(0.5, 4, 0.5), at(wx + 14, 2, wz - 14), METAL, Enum.Material.Metal)
	light(hub, 32, Color3.fromRGB(255, 180, 255), 0.8)
	w:SetAttribute("Physics", true)
end

---------------------------------------------------------------------------
-- Carrossel (física: o piso gira num motor; cavalinhos com banco)
---------------------------------------------------------------------------

local function buildCarousel(m)
	local c = K.model("Carrossel", m)
	local cx, cz = 120, -118
	local center = at(cx, 0, cz)
	local baseCol = column(c, "Base", cx, 0, cz, 1, 20, Color3.fromRGB(200, 60, 80))
	column(c, "BaseBorda", cx, 0, cz, 0.6, 20.6, YELLOW)
	local spinning = {}
	local function add(p)
		table.insert(spinning, p)
		return p
	end
	local floor = column(c, "Piso", cx, 1.3, cz, 0.8, 18, Color3.fromRGB(250, 235, 200), Enum.Material.WoodPlanks)
	add(column(c, "Mastro", cx, 2.1, cz, 16, 3, YELLOW, Enum.Material.SmoothPlastic, { CanCollide = false }))
	add(column(c, "Espelho", cx, 6, cz, 8, 3.3, Color3.fromRGB(190, 220, 255), Enum.Material.SmoothPlastic, { CanCollide = false }))
	add(column(c, "Teto", cx, 18, cz, 1.6, 21, RED, Enum.Material.SmoothPlastic, { CanCollide = false }))
	for i = 0, 5 do
		local r = 21 * (1 - i / 6)
		add(column(c, "Cupula", cx, 19.6 + i * 1.4, cz, 1.4, r, i % 2 == 0 and WHITE or RED, Enum.Material.SmoothPlastic, { CanCollide = false }))
	end
	add(part(c, "Topo", Vector3.new(2, 2, 2), at(cx, 28.8, cz), YELLOW, Enum.Material.Neon, { Shape = Enum.PartType.Ball, CanCollide = false }))
	for i = 0, 23 do
		local a = i * math.pi * 2 / 24
		add(part(c, "Lampada", Vector3.new(0.8, 0.8, 0.8), center * CFrame.new(math.cos(a) * 21.2, 18.4, math.sin(a) * 21.2), COLORS[i % #COLORS + 1], Enum.Material.Neon, { Shape = Enum.PartType.Ball, CanCollide = false }))
	end
	-- 12 cavalinhos virados no sentido do giro
	for i = 0, 11 do
		local a = i * math.pi * 2 / 12
		local r = i % 2 == 0 and 14 or 10
		local pos = Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
		local tangent = Vector3.new(pos.Z, 0, -pos.X).Unit
		local h = center * CFrame.lookAt(pos, pos + tangent)
		local color = ({ WHITE, Color3.fromRGB(140, 90, 60), Color3.fromRGB(40, 40, 45), Color3.fromRGB(230, 200, 150) })[i % 4 + 1]
		local y = i % 2 == 0 and 5 or 6
		-- poste na frente da sela (passa pelo pescoço), não no meio de quem senta
		add(part(c, "Poste", Vector3.new(0.4, 16, 0.4), h * CFrame.new(0, 10.1, -1.35), YELLOW, Enum.Material.Metal, { CanCollide = false }))
		add(part(c, "Corpo", Vector3.new(1.6, 1.8, 4), h * CFrame.new(0, y, 0), color))
		add(part(c, "Pescoco", Vector3.new(1.2, 2.2, 1.2), h * CFrame.new(0, y + 1.4, -1.9) * CFrame.Angles(math.rad(-25), 0, 0), color))
		add(part(c, "Cabeca", Vector3.new(1.2, 1.1, 2), h * CFrame.new(0, y + 2.4, -2.7), color))
		add(part(c, "Crina", Vector3.new(0.4, 1.8, 1.6), h * CFrame.new(0, y + 1.9, -1.4), COLORS[i % #COLORS + 1], nil, { CanCollide = false }))
		add(part(c, "Rabo", Vector3.new(0.4, 2, 0.4), h * CFrame.new(0, y - 0.2, 2.2) * CFrame.Angles(math.rad(30), 0, 0), COLORS[i % #COLORS + 1], nil, { CanCollide = false }))
		for _, lx in ipairs({ -0.5, 0.5 }) do
			for _, lz in ipairs({ -1.4, 1.4 }) do
				add(part(c, "Perna", Vector3.new(0.4, 2, 0.4), h * CFrame.new(lx, y - 1.8, lz) * CFrame.Angles(math.rad(lz < 0 and -25 or 25), 0, 0), color, nil, { CanCollide = false }))
			end
		end
		local seat = Instance.new("Seat")
		seat.Name = "Sela"
		seat.Anchored = true
		seat.Size = Vector3.new(1.4, 0.4, 1.8)
		seat.CFrame = h * CFrame.new(0, y + 1.1, 0.5)
		seat.Color = RED
		seat.TopSurface = Enum.SurfaceType.Smooth
		seat:SetAttribute("SeatText", "Carrossel")
		seat.Parent = c
		add(seat)
	end
	weldAll(floor, spinning)
	floor.Anchored = false
	local axisCf = center * CFrame.new(0, 1.2, 0) * CFrame.Angles(0, 0, math.rad(90)) -- X da dobradiça = para cima
	local motor = Instance.new("HingeConstraint")
	motor.Name = "Motor"
	motor.Attachment0 = attachmentAt(baseCol, axisCf, "Motor")
	motor.Attachment1 = attachmentAt(floor, axisCf, "Motor")
	motor.ActuatorType = Enum.ActuatorType.Motor
	motor.AngularVelocity = P.CarouselSpeed
	motor.MotorMaxTorque = 1e10
	motor.MotorMaxAcceleration = 0.5
	motor.Parent = floor
	board(c, "PlacaCarrossel", Vector3.new(12, 3, 0.4), at(cx, 5, cz + 26) * CFrame.Angles(0, math.pi, 0), "CARROSSEL", WHITE, RED)
	part(c, "PostePlaca", Vector3.new(0.5, 4, 0.5), at(cx, 2, cz + 26), METAL, Enum.Material.Metal)
	c:SetAttribute("Physics", true)
end

---------------------------------------------------------------------------
-- Brinquedos que andam sozinhos (Marco 7.4): barco pirata, chapéu mexicano, queda livre,
-- montanha-russa e xícaras. Cada parte que se mexe é um "carro": uma peça Root com o resto
-- soldado nela, levada pelo servidor (AlignPosition/AlignOrientation rígidos) para o lugar que a
-- função de movimento diz. Física do servidor = todo mundo vê igual e dá para ir sentado.
-- Todos têm um ciclo: parado para embarcar -> funcionando -> parado de novo.
---------------------------------------------------------------------------

local cars = {} -- { root = Part, move = function(t) -> CFrame }

local function newCar(parent, name, pivot)
	local car = K.model(name, parent)
	local root = part(car, "Root", Vector3.new(1, 1, 1), pivot, WHITE, nil, { Transparency = 1, CanCollide = false })
	return car, root
end

local function rideSeat(parent, cf, text, size)
	local seat = Instance.new("Seat")
	seat.Name = "Banco"
	seat.Anchored = true
	seat.Size = size or Vector3.new(1.8, 0.4, 1.8)
	seat.CFrame = cf
	seat.Color = RED
	seat.Material = Enum.Material.Fabric
	seat.TopSurface = Enum.SurfaceType.Smooth
	seat.CanCollide = false
	seat:SetAttribute("SeatText", text)
	seat.Parent = parent
	return seat
end

-- solda tudo do carro na Root e registra o movimento (a física liga no start)
local function finishCar(car, root, move)
	for _, p in ipairs(car:GetDescendants()) do
		if p:IsA("BasePart") and p ~= root then
			local w = Instance.new("WeldConstraint")
			w.Part0 = root
			w.Part1 = p
			w.Parent = p
			p.CanCollide = false
			p.Massless = true
		end
	end
	table.insert(cars, { root = root, move = move, car = car })
end

local function smooth(f)
	f = math.clamp(f, 0, 1)
	return f * f * (3 - 2 * f)
end

-- Giro com ciclo: parado até "start", acelera em "ramp" s até w rad/s, gira, desacelera até
-- "stop", parado até o fim do ciclo T. Devolve o ângulo (contínuo entre ciclos) e a velocidade.
local function spinCycle(t, T, start, ramp, stop, w)
	local function inCycle(tau)
		if tau < start then
			return 0, 0
		end
		local full = (stop - ramp) - (start + ramp)
		local a1 = w * ramp / 2
		if tau < start + ramp then
			local d = tau - start
			return w * d * d / (2 * ramp), w * d / ramp
		elseif tau < stop - ramp then
			return a1 + w * (tau - start - ramp), w
		elseif tau < stop then
			local d = tau - (stop - ramp)
			return a1 + w * full + w * d - w * d * d / (2 * ramp), w * (1 - d / ramp)
		end
		return a1 * 2 + w * full, 0
	end
	local laps = math.floor(t / T)
	local total = inCycle(T)
	local angle, speed = inCycle(t - laps * T)
	return (laps * total + angle) % (math.pi * 2), speed
end

-- Chapéu mexicano: o chapéu gira e as cadeirinhas voam para fora conforme a velocidade
local function buildSwingRide(m)
	local s = K.model("ChapeuMexicano", m)
	local cx, cz = -120, -118
	local center = at(cx, 0, cz)
	column(s, "Base", cx, 0, cz, 1, 12, Color3.fromRGB(60, 120, 200))
	column(s, "BaseBorda", cx, 0, cz, 0.6, 12.6, YELLOW)
	column(s, "Torre", cx, 1, cz, 26, 2.5, WHITE, Enum.Material.Metal)
	local T, START, RAMP, STOP, W = 36, 10, 4, 33, 1.2
	local function spin(t)
		return spinCycle(t, T, START, RAMP, STOP, W)
	end
	local top, topRoot = newCar(s, "Giro", center * CFrame.new(0, 26, 0))
	column(top, "Chapeu", cx, 26, cz, 1.2, 14, YELLOW, nil, { CanCollide = false })
	cone(top, cx, 27.2, cz, 13.5, 7, PURPLE, YELLOW, 16)
	for i = 0, 15 do
		local a = i * math.pi * 2 / 16
		part(top, "Lampada", Vector3.new(0.7, 0.7, 0.7), center * CFrame.new(math.cos(a) * 14.2, 26, math.sin(a) * 14.2), COLORS[i % #COLORS + 1], Enum.Material.Neon, { Shape = BALL, CanCollide = false })
	end
	finishCar(top, topRoot, function(t)
		return center * CFrame.Angles(0, (spin(t)), 0) * CFrame.new(0, 26, 0)
	end)
	local L = 13 -- comprimento das correntes
	for i = 0, 15 do
		local a0 = i * math.pi * 2 / 16
		local hang = center * CFrame.Angles(0, -a0, 0) * CFrame.new(12, 26, 0) -- ponto de pendurar (X = para fora)
		local chair, root = newCar(s, "Cadeira" .. (i + 1), hang)
		for _, dx in ipairs({ -0.8, 0.8 }) do
			part(chair, "Corrente", Vector3.new(0.12, L, 0.12), hang * CFrame.new(dx, -L / 2, 0), METAL, Enum.Material.Metal)
		end
		local color = COLORS[i % #COLORS + 1]
		part(chair, "Cadeira", Vector3.new(1.8, 0.4, 1.8), hang * CFrame.new(0, -L, 0), color)
		part(chair, "Encosto", Vector3.new(1.8, 1.8, 0.3), hang * CFrame.new(0, -L + 1, 0.9), color)
		-- quem senta olha no sentido do giro (-Z local da cadeira)
		rideSeat(chair, hang * CFrame.new(0, -L + 0.3, 0), "Chapéu mexicano", Vector3.new(1.6, 0.3, 1.6))
		finishCar(chair, root, function(t)
			local angle, w = spin(t)
			local tilt = math.rad(42) * (w / W) ^ 2
			return center * CFrame.Angles(0, angle - a0, 0) * CFrame.new(12, 26, 0) * CFrame.Angles(0, 0, tilt)
		end)
	end
	-- plataforma de embarque e placa
	board(s, "Placa", Vector3.new(14, 3, 0.4), at(cx, 5, cz + 30) * CFrame.Angles(0, math.pi, 0), "CHAPÉU MEXICANO", WHITE, PURPLE)
	part(s, "PostePlaca", Vector3.new(0.5, 4, 0.5), at(cx, 2, cz + 30), METAL, Enum.Material.Metal)
end

-- Barco pirata: balança como um pêndulo, cada vez mais alto, e para devagar
local function buildPirateShip(m)
	local b = K.model("BarcoPirata", m)
	local cx, cz = -175, 0
	local PIVOT_Y = 27
	for _, dz in ipairs({ -7, 7 }) do
		for _, dx in ipairs({ -14, 14 }) do
			beam(b, "Pe", (at(cx + dx, 0, cz + dz)).Position, (at(cx, PIVOT_Y, cz + dz)).Position, 1.6, Color3.fromRGB(90, 60, 40), Enum.Material.Wood)
		end
	end
	part(b, "Eixo", Vector3.new(1.4, 1.4, 16), at(cx, PIVOT_Y, cz), METAL, Enum.Material.Metal)
	-- plataforma para embarcar dos dois lados do casco parado
	for _, side in ipairs({ -1, 1 }) do
		part(b, "Plataforma", Vector3.new(26, 1, 3), at(cx, 7.5, cz + side * 6.2), Color3.fromRGB(150, 95, 55), Enum.Material.WoodPlanks)
		for _, dx in ipairs({ -11, 0, 11 }) do
			part(b, "PePlataforma", Vector3.new(0.8, 7, 0.8), at(cx + dx, 3.5, cz + side * 7.3), Color3.fromRGB(90, 60, 40), Enum.Material.Wood)
		end
	end
	part(b, "Escada", Vector3.new(4, 1, 12), at(cx + 10, 4.0, cz - 12.15) * CFrame.Angles(math.rad(-42), 0, 0), Color3.fromRGB(150, 95, 55), Enum.Material.WoodPlanks)
	local pivot = at(cx, PIVOT_Y, cz)
	local ship, root = newCar(b, "Navio", pivot)
	local WOOD = Color3.fromRGB(150, 95, 55)
	part(ship, "Casco", Vector3.new(30, 2, 7), at(cx, 8, cz), WOOD, Enum.Material.WoodPlanks)
	for _, side in ipairs({ -1, 1 }) do
		part(ship, "Lateral", Vector3.new(32, 4, 0.6), at(cx, 10.5, cz + side * 3.6), Color3.fromRGB(120, 70, 40), Enum.Material.WoodPlanks)
		part(ship, "Faixa", Vector3.new(32.2, 0.6, 0.7), at(cx, 11.6, cz + side * 3.6), YELLOW)
		beam(ship, "Braco", at(cx - 8, 10, cz + side * 5).Position, at(cx, PIVOT_Y, cz + side * 5).Position, 0.8, METAL, Enum.Material.Metal)
		beam(ship, "Braco", at(cx + 8, 10, cz + side * 5).Position, at(cx, PIVOT_Y, cz + side * 5).Position, 0.8, METAL, Enum.Material.Metal)
	end
	for _, side in ipairs({ -1, 1 }) do
		part(ship, "Proa", Vector3.new(3, 7, 7), at(cx + side * 16, 11, cz), WOOD, Enum.Material.WoodPlanks)
	end
	part(ship, "Cabeca", Vector3.new(2, 4, 2), at(cx - 18, 15, cz), GREEN)
	part(ship, "Olho", Vector3.new(2.1, 0.6, 0.6), at(cx - 18.2, 16, cz), YELLOW, Enum.Material.Neon)
	for x = -12, 12, 4 do
		if x ~= 0 then
			part(ship, "BancoBarco", Vector3.new(1.2, 1, 6), at(cx + x, 9.5, cz), RED)
			for _, dz in ipairs({ -1.6, 1.6 }) do
				rideSeat(ship, at(cx + x, 10.2, cz + dz) * CFrame.Angles(0, math.rad(x < 0 and -90 or 90), 0), "Barco pirata", Vector3.new(1.2, 0.3, 1.6))
			end
		end
	end
	part(ship, "Mastro", Vector3.new(0.6, 12, 0.6), at(cx, 15, cz), WOOD, Enum.Material.Wood)
	part(ship, "Vela", Vector3.new(0.2, 7, 6), at(cx, 17, cz), WHITE, Enum.Material.Fabric)
	part(ship, "Caveira", Vector3.new(0.3, 2, 2), at(cx + 0.2, 17.5, cz), Color3.fromRGB(30, 30, 30))
	local T, START, STOP, AMP, PERIOD = 40, 10, 36, math.rad(55), 7
	finishCar(ship, root, function(t)
		local tau = t % T
		local angle = 0
		if tau > START and tau < STOP then
			local env = smooth((tau - START) / 8) * smooth((STOP - tau) / 8)
			angle = AMP * env * math.sin((tau - START) * math.pi * 2 / PERIOD)
		end
		return pivot * CFrame.Angles(0, 0, angle)
	end)
	board(b, "Placa", Vector3.new(14, 3, 0.4), at(cx + 22, 5, cz) * CFrame.Angles(0, math.rad(-90), 0), "BARCO PIRATA", WHITE, Color3.fromRGB(40, 40, 50))
	part(b, "PostePlaca", Vector3.new(0.5, 4, 0.5), at(cx + 22, 2, cz), METAL, Enum.Material.Metal)
end

-- Queda livre: as cadeiras em volta da torre sobem devagar, esperam lá em cima e despencam
local function buildDropTower(m)
	local d = K.model("QuedaLivre", m)
	local cx, cz = 172, 20
	local HEIGHT = 74
	part(d, "Base", Vector3.new(16, 1, 16), at(cx, 0.5, cz), Color3.fromRGB(60, 60, 70), Enum.Material.Concrete)
	part(d, "Torre", Vector3.new(6, 90, 6), at(cx, 45, cz), RED, Enum.Material.Metal)
	for y = 6, 84, 12 do
		part(d, "Faixa", Vector3.new(6.2, 2, 6.2), at(cx, y, cz), WHITE, Enum.Material.Metal)
	end
	part(d, "Topo", Vector3.new(9, 3, 9), at(cx, 91.5, cz), YELLOW)
	local top = part(d, "Luz", Vector3.new(2, 2, 2), at(cx, 94, cz), RED, Enum.Material.Neon, { Shape = BALL })
	light(top, 30, Color3.fromRGB(255, 80, 80), 2)
	local pivot = at(cx, 0, cz)
	local ring, root = newCar(d, "Cadeiras", pivot)
	column(ring, "Anel", cx, 2.6, cz, 1, 6.6, YELLOW)
	for i = 0, 7 do
		local a = i * math.pi / 4
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		local cf = pivot * CFrame.lookAt(dir * 5, dir * 10) -- -Z = para fora da torre
		local color = COLORS[i % #COLORS + 1]
		part(ring, "Encosto", Vector3.new(1.8, 3, 0.4), cf * CFrame.new(0, 4.5, 0.6), color)
		part(ring, "Trava", Vector3.new(1.6, 0.3, 0.3), cf * CFrame.new(0, 5.6, -0.9), WHITE, Enum.Material.Metal)
		rideSeat(ring, cf * CFrame.new(0, 3.3, -0.3), "Queda livre", Vector3.new(1.8, 0.4, 1.6))
	end
	local T = 30
	finishCar(ring, root, function(t)
		local c = t % T
		local h = 0
		if c >= 9 and c < 21 then
			h = HEIGHT * smooth((c - 9) / 12)
		elseif c >= 21 and c < 24 then
			h = HEIGHT
		elseif c >= 24 and c < 25.3 then
			local f = (c - 24) / 1.3
			h = HEIGHT * (1 - f * f)
		elseif c >= 25.3 and c < 26.5 then
			h = 3 * math.sin((c - 25.3) / 1.2 * math.pi) -- freio: quica um pouquinho
		end
		return pivot + Vector3.new(0, h, 0)
	end)
	board(d, "Placa", Vector3.new(12, 3, 0.4), at(cx - 14, 5, cz) * CFrame.Angles(0, math.rad(90), 0), "QUEDA LIVRE", WHITE, RED)
	part(d, "PostePlaca", Vector3.new(0.5, 4, 0.5), at(cx - 14, 2, cz), METAL, Enum.Material.Metal)
end

-- Montanha-russa: trilho com subidas e descidas (ParkPath); o trem espera na estação, dá uma
-- volta (rápido embaixo, devagar em cima, freia chegando na estação) e espera de novo
local function buildCoaster(m)
	local r = K.model("MontanhaRussa", m)
	local origin = at(100, 0, 132)
	local track = K.model("Trilho", r)
	local pts = ParkPath.points()
	local n = #pts
	for i = 1, n do
		local p = origin * pts[i]
		local q = origin * pts[i % n + 1]
		local t = (q - p).Unit
		local side = t:Cross(Vector3.yAxis).Unit * ParkPath.Gauge
		for _, s in ipairs({ -1, 1 }) do
			beam(track, "Trilho", p + side * s, q + side * s + t * 0.2, 0.45, RED, Enum.Material.Metal, { CanCollide = false })
		end
		beam(track, "Viga", p - Vector3.new(0, 0.9, 0), q - Vector3.new(0, 0.9, 0) + t * 0.2, 0.9, YELLOW, Enum.Material.Metal, { CanCollide = false })
		if i % 3 == 0 then
			part(track, "Dormente", Vector3.new(ParkPath.Gauge * 2 + 0.8, 0.3, 0.6), CFrame.lookAt(p - Vector3.new(0, 0.35, 0), q - Vector3.new(0, 0.35, 0)), METAL, Enum.Material.Metal, { CanCollide = false })
		end
		if i % 6 == 0 then
			local h = p.Y - 1.3
			part(track, "Pilar", Vector3.new(1, h, 1), CFrame.new(p.X, h / 2, p.Z), WHITE, Enum.Material.Metal)
		end
	end
	-- estação no ponto mais baixo do trilho: o trilho é reordenado para começar nela
	local low = 1
	for i = 2, n do
		if pts[i].Y < pts[low].Y then
			low = i
		end
	end
	local path = {}
	for k = 0, n - 1 do
		path[k + 1] = origin * pts[(low - 1 + k) % n + 1]
	end
	local top = -math.huge
	for _, p in ipairs(path) do
		top = math.max(top, p.Y)
	end
	local dist = { 0 }
	for i = 1, n do
		dist[i + 1] = dist[i] + (path[i % n + 1] - path[i]).Magnitude
	end
	local total = dist[n + 1]
	local times = { 0 }
	for i = 1, n do
		local p, q = path[i], path[i % n + 1]
		local s = (dist[i] + dist[i + 1]) / 2
		local near = math.clamp(math.min(s, total - s) / 45, 0.22, 1) -- devagar perto da estação
		local speed = (16 + math.sqrt(math.max(0, top - (p.Y + q.Y) / 2) * 2 * 30)) * near
		times[i + 1] = times[i] + (q - p).Magnitude / speed
	end
	local LAP, WAIT = times[n + 1], 14
	local function pointAt(s)
		s = s % total
		local lo, hi = 1, n
		while lo < hi do
			local mid = math.floor((lo + hi + 1) / 2)
			if dist[mid] <= s then
				lo = mid
			else
				hi = mid - 1
			end
		end
		local f = (s - dist[lo]) / (dist[lo + 1] - dist[lo])
		return path[lo]:Lerp(path[lo % n + 1], f)
	end
	local function distanceAt(c)
		if c <= WAIT then
			return 0
		end
		local rest = math.min(c - WAIT, LAP)
		local lo, hi = 1, n
		while lo < hi do
			local mid = math.floor((lo + hi + 1) / 2)
			if times[mid] <= rest then
				lo = mid
			else
				hi = mid - 1
			end
		end
		local f = (rest - times[lo]) / (times[lo + 1] - times[lo])
		return dist[lo] + f * (dist[lo + 1] - dist[lo])
	end
	local function carCf(s)
		local p, q = pointAt(s), pointAt(s + 1.5)
		return CFrame.lookAt(p, q) * CFrame.new(0, 0.3, 0)
	end
	-- estação: plataforma na altura do trilho, com escada
	local st = path[1]
	local ahead = pointAt(8)
	local stCf = CFrame.lookAt(st, Vector3.new(ahead.X, st.Y, ahead.Z)) -- -Z = sentido do trem
	local stY = st.Y - 1.4
	for _, side in ipairs({ -1, 1 }) do
		part(r, "Plataforma", Vector3.new(4, 1, 30), stCf * CFrame.new(side * 4.6, -1.4, 10), Color3.fromRGB(150, 95, 55), Enum.Material.WoodPlanks)
	end
	part(r, "Estacao", Vector3.new(14, 0.6, 32), stCf * CFrame.new(0, 7.2, 10), BLUE)
	for _, side in ipairs({ -1, 1 }) do
		for _, dz in ipairs({ -4, 10, 24 }) do
			local pos = (stCf * CFrame.new(side * 6.4, 0, dz)).Position
			part(r, "PilarEstacao", Vector3.new(0.6, stY + 8.6, 0.6), CFrame.new(pos.X, (stY + 8.6) / 2, pos.Z), WHITE, Enum.Material.Metal)
		end
	end
	for k = 0, math.floor(stY / 0.8) do
		local pos = (stCf * CFrame.new(-7.2 - k * 1.2, 0, 22)).Position
		local h = stY - k * 0.8
		if h > 0.2 then
			part(r, "Degrau", Vector3.new(1.2, h, 3), CFrame.new(pos.X, h / 2, pos.Z) * stCf.Rotation, Color3.fromRGB(150, 95, 55), Enum.Material.WoodPlanks)
		end
	end
	-- trem de 4 carrinhos com 2 lugares cada
	local train = K.model("Trem", r)
	for i = 1, 4 do
		local back = -(i - 1) * 6
		local cf = carCf(back)
		local car, root = newCar(train, "Carro" .. i, cf)
		local color = COLORS[(i * 2) % #COLORS + 1]
		part(car, "Corpo", Vector3.new(3.6, 1.6, 5), cf * CFrame.new(0, 0.6, 0), color)
		part(car, "Encosto", Vector3.new(3.4, 1.6, 0.5), cf * CFrame.new(0, 2, 2.2), Color3.fromRGB(40, 40, 50))
		part(car, "Barra", Vector3.new(3.4, 0.3, 0.3), cf * CFrame.new(0, 2.6, -0.8), YELLOW, Enum.Material.Metal)
		for _, sx in ipairs({ -0.85, 0.85 }) do
			rideSeat(car, cf * CFrame.new(sx, 1.55, 0.8), "Montanha-russa", Vector3.new(1.5, 0.3, 1.6))
		end
		if i == 1 then
			part(car, "Frente", Vector3.new(3.6, 2.4, 1), cf * CFrame.new(0, 1, -2.6), YELLOW)
		end
		finishCar(car, root, function(t)
			local c = t % (WAIT + LAP)
			return carCf(distanceAt(c) + back)
		end)
	end
	board(r, "Placa", Vector3.new(16, 3, 0.4), at(130, 5, 64), "MONTANHA-RUSSA", WHITE, BLUE)
	part(r, "PostePlaca", Vector3.new(0.5, 4, 0.5), at(130, 2, 64), METAL, Enum.Material.Metal)
end

-- Xícaras malucas: o piso gira devagar e cada xícara gira rápido em volta dela mesma
local function buildTeacups(m)
	local x = K.model("Xicaras", m)
	local cx, cz = 88, -40
	local center = at(cx, 0, cz)
	column(x, "Base", cx, 0, cz, 0.8, 17, Color3.fromRGB(120, 200, 230))
	column(x, "Borda", cx, 0, cz, 0.5, 17.6, YELLOW)
	local T, START, RAMP, STOP = 32, 9, 3, 30
	local plate, plateRoot = newCar(x, "Piso", center * CFrame.new(0, 0.8, 0))
	column(plate, "Prato", cx, 0.8, cz, 0.4, 15.5, Color3.fromRGB(250, 240, 250))
	column(plate, "Bule", cx, 1.2, cz, 5, 3, PINK)
	column(plate, "BuleTampa", cx, 6.2, cz, 1, 2.2, GOLD)
	part(plate, "BuleBico", Vector3.new(0.8, 0.8, 4), center * CFrame.new(3.6, 4.6, 0) * CFrame.Angles(0, math.rad(90), math.rad(-35)), PINK)
	finishCar(plate, plateRoot, function(t)
		return center * CFrame.Angles(0, (spinCycle(t, T, START, RAMP, STOP, 0.45)), 0) * CFrame.new(0, 0.8, 0)
	end)
	local CUP = { PINK, BLUE, YELLOW, GREEN, PURPLE, ORANGE }
	for i = 0, 5 do
		local a0 = i * math.pi / 3
		local spot = center * CFrame.Angles(0, -a0, 0) * CFrame.new(10, 1, 0)
		local cup, root = newCar(x, "Xicara" .. (i + 1), spot)
		local color = CUP[i + 1]
		local upright = CFrame.Angles(0, 0, math.rad(90)) -- cilindro em pé
		part(cup, "Fundo", Vector3.new(0.6, 7.2, 7.2), spot * CFrame.new(0, 0.3, 0) * upright, color, nil, { Shape = CYL })
		for k = 0, 9 do
			local a = k * math.pi / 5
			part(cup, "Lado", Vector3.new(2.4, 2.6, 0.4), spot * CFrame.Angles(0, -a, 0) * CFrame.new(0, 1.6, -3.5), color)
		end
		part(cup, "Asa", Vector3.new(0.5, 1.8, 1.8), spot * CFrame.new(3.9, 1.8, 0), color, nil, { Shape = CYL })
		part(cup, "Mesinha", Vector3.new(1.6, 1.2, 1.2), spot * CFrame.new(0, 1.4, 0) * upright, GOLD, nil, { Shape = CYL })
		for k = 0, 2 do
			local a = k * math.pi * 2 / 3
			rideSeat(cup, spot * CFrame.Angles(0, -a, 0) * CFrame.new(0, 1, -2.2) * CFrame.Angles(0, math.pi, 0), "Xícara maluca", Vector3.new(1.6, 0.3, 1.4))
		end
		finishCar(cup, root, function(t)
			local plateAngle = spinCycle(t, T, START, RAMP, STOP, 0.45)
			local own = spinCycle(t, T, START, RAMP, STOP, 1.6 + 0.2 * (i % 3))
			return center * CFrame.Angles(0, plateAngle - a0, 0) * CFrame.new(10, 1, 0) * CFrame.Angles(0, own, 0)
		end)
	end
	board(x, "Placa", Vector3.new(14, 3, 0.4), at(cx, 5, cz - 21), "XÍCARAS MALUCAS", WHITE, PINK)
	part(x, "PostePlaca", Vector3.new(0.5, 4, 0.5), at(cx, 2, cz - 21), METAL, Enum.Material.Metal)
end

-- Camas elásticas: encostou, pula alto (o ParkController do aparelho dá o impulso)
local function buildTrampolines(m)
	local tr = K.model("CamasElasticas", m)
	local cx, cz = -80, -40
	part(tr, "Piso", Vector3.new(40, 0.4, 26), at(cx, 0.4, cz), Color3.fromRGB(90, 160, 90), Enum.Material.Grass)
	for i = 0, 5 do
		local x = cx - 14 + (i % 3) * 14
		local z = cz - 6 + math.floor(i / 3) * 12
		column(tr, "Aro", x, 0.4, z, 2.4, 5.2, COLORS[i % #COLORS + 1])
		local bed = column(tr, "Lona", x, 2.8, z, 0.2, 4.6, Color3.fromRGB(30, 30, 40), Enum.Material.Fabric)
		bed:SetAttribute("Trampoline", true)
		for k = 0, 5 do
			local a = k * math.pi / 3
			part(tr, "Mola", Vector3.new(0.3, 2.4, 0.3), at(x + math.cos(a) * 4.9, 1.6, z + math.sin(a) * 4.9), METAL, Enum.Material.Metal)
		end
	end
	board(tr, "Placa", Vector3.new(14, 3, 0.4), at(cx, 5, cz - 15), "CAMAS ELÁSTICAS", WHITE, GREEN)
	part(tr, "PostePlaca", Vector3.new(0.5, 4, 0.5), at(cx, 2, cz - 15), METAL, Enum.Material.Metal)
end

---------------------------------------------------------------------------
-- Barracas, bancos, postes, árvores e balões
---------------------------------------------------------------------------

-- Lanches das barracas (Marco 7.4): peças em relação à base do lanche (em pé, +Y para cima).
-- Usado para enfeitar o balcão e para o lanche que a pessoa leva na mão.
local BALL, CYL = Enum.PartType.Ball, Enum.PartType.Cylinder
local function up(y)
	return CFrame.new(0, y, 0) * CFrame.Angles(0, 0, math.rad(90)) -- cilindro em pé
end
local SNACKS = {
	Pipoca = {
		{ Vector3.new(1.1, 0.9, 0.9), up(0.55), RED, CYL },
		{ Vector3.new(1.12, 0.3, 0.92), up(0.55), WHITE, CYL },
		{ Vector3.new(0.45, 0.45, 0.45), CFrame.new(0.15, 1.15, 0.1), Color3.fromRGB(255, 240, 190), BALL },
		{ Vector3.new(0.45, 0.45, 0.45), CFrame.new(-0.18, 1.2, -0.05), Color3.fromRGB(255, 230, 160), BALL },
		{ Vector3.new(0.45, 0.45, 0.45), CFrame.new(0, 1.3, 0.15), Color3.fromRGB(255, 245, 210), BALL },
	},
	AlgodaoDoce = {
		{ Vector3.new(1.4, 0.12, 0.12), up(0.7), WHITE, CYL },
		{ Vector3.new(1.1, 1.1, 1.1), CFrame.new(0, 1.7, 0), Color3.fromRGB(255, 150, 205), BALL },
		{ Vector3.new(0.8, 0.8, 0.8), CFrame.new(0.3, 1.9, 0.1), Color3.fromRGB(255, 175, 220), BALL },
		{ Vector3.new(0.8, 0.8, 0.8), CFrame.new(-0.3, 1.6, -0.1), Color3.fromRGB(255, 130, 195), BALL },
	},
	Sorvete = {
		{ Vector3.new(0.9, 0.45, 0.45), up(0.45), Color3.fromRGB(210, 160, 90), CYL },
		{ Vector3.new(0.4, 0.6, 0.6), up(1.0), Color3.fromRGB(210, 160, 90), CYL },
		{ Vector3.new(0.75, 0.75, 0.75), CFrame.new(0, 1.35, 0), Color3.fromRGB(255, 160, 190), BALL },
		{ Vector3.new(0.65, 0.65, 0.65), CFrame.new(0, 1.85, 0), Color3.fromRGB(120, 80, 50), BALL },
		{ Vector3.new(0.2, 0.2, 0.2), CFrame.new(0, 2.2, 0), RED, BALL },
	},
	CachorroQuente = {
		{ Vector3.new(1.6, 0.4, 0.45), CFrame.new(0, 0.35, 0) * CFrame.Angles(0, math.rad(90), 0) * CFrame.Angles(0, 0, 0), Color3.fromRGB(225, 170, 100), nil },
		{ Vector3.new(1.9, 0.32, 0.32), CFrame.new(0, 0.6, 0) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(190, 70, 50), CYL },
		{ Vector3.new(1.5, 0.08, 0.12), CFrame.new(0, 0.78, 0) * CFrame.Angles(0, math.rad(90), 0), YELLOW, nil },
	},
	Refri = {
		{ Vector3.new(1.3, 0.7, 0.7), up(0.65), Color3.fromRGB(230, 40, 40), CYL },
		{ Vector3.new(0.12, 0.74, 0.74), up(1.33), WHITE, CYL },
		{ Vector3.new(0.12, 0.7, 0.12), CFrame.new(0.15, 1.7, 0) * CFrame.Angles(0, 0, math.rad(-12)), WHITE, nil },
	},
	Churros = {
		{ Vector3.new(0.5, 0.6, 0.6), up(0.25), WHITE, CYL },
		{ Vector3.new(2.2, 0.3, 0.3), up(1.2), Color3.fromRGB(190, 120, 50), CYL },
		{ Vector3.new(0.3, 0.32, 0.32), up(2.3), Color3.fromRGB(110, 60, 30), CYL },
	},
	-- Marco 10.31: lanches da orla (Costa do Sol)
	Coco = {
		{ Vector3.new(1.5, 1.5, 1.5), CFrame.new(0, 0.8, 0), Color3.fromRGB(95, 160, 70), BALL },
		{ Vector3.new(0.5, 0.52, 0.52), up(1.6), Color3.fromRGB(235, 225, 190), CYL },
		{ Vector3.new(1.4, 0.12, 0.12), CFrame.new(0.15, 2.1, 0) * CFrame.Angles(0, 0, math.rad(-15)), Color3.fromRGB(255, 120, 170), CYL },
	},
	Acai = {
		{ Vector3.new(1.0, 1.0, 1.0), up(0.5), Color3.fromRGB(245, 245, 245), CYL },
		{ Vector3.new(0.3, 1.02, 1.02), up(1.05), Color3.fromRGB(85, 25, 80), CYL },
		{ Vector3.new(0.35, 0.35, 0.35), CFrame.new(0.2, 1.3, 0.1), Color3.fromRGB(230, 60, 80), BALL },
		{ Vector3.new(0.3, 0.3, 0.3), CFrame.new(-0.2, 1.28, -0.1), Color3.fromRGB(250, 220, 90), BALL },
	},
	Picole = {
		{ Vector3.new(0.18, 0.9, 0.25), CFrame.new(0, 0.45, 0), Color3.fromRGB(225, 195, 140), nil },
		{ Vector3.new(0.8, 1.5, 0.4), CFrame.new(0, 1.55, 0), Color3.fromRGB(255, 140, 170), nil },
		{ Vector3.new(0.82, 0.5, 0.42), CFrame.new(0, 2.1, 0), Color3.fromRGB(110, 70, 45), nil },
	},
	Milho = {
		{ Vector3.new(0.25, 0.8, 0.25), CFrame.new(0, 0.4, 0), Color3.fromRGB(225, 195, 140), nil },
		{ Vector3.new(2.0, 0.65, 0.65), up(1.6), Color3.fromRGB(250, 205, 60), CYL },
		{ Vector3.new(1.2, 0.2, 0.7), CFrame.new(0.4, 1.1, 0) * CFrame.Angles(0, 0, math.rad(25)), Color3.fromRGB(120, 170, 80), nil },
	},
}
ParkBuilder.SNACKS = SNACKS

local function buildSnack(parent, cf, kind, scale, partFn)
	local list = {}
	for _, s in ipairs(SNACKS[kind] or {}) do
		local offset = s[2] - s[2].Position + s[2].Position * scale
		table.insert(list, partFn(parent, "Lanche", s[1] * scale, cf * offset, s[3], nil, { Shape = s[4], CanCollide = false }))
	end
	return list
end
ParkBuilder.buildSnack = buildSnack

-- Barraca de lanche: carrinho com toldo listrado (sem peças encostadas na mesma face, que
-- faziam a cor "piscar"), placa com luzinhas e lanches no balcão. E = pegar um lanche.
local function buildStand(parent, cf, name, color, snack)
	local s = K.model("Barraca", parent)
	local function p(n, size, off, c, mat, extra)
		return part(s, n, size, cf * off, c, mat, extra)
	end
	local counter = p("Balcao", Vector3.new(9, 3.6, 4), CFrame.new(0, 1.8, 0), WHITE)
	p("Tampo", Vector3.new(9.6, 0.3, 4.6), CFrame.new(0, 3.75, -0.1), Color3.fromRGB(150, 95, 55), Enum.Material.WoodPlanks)
	p("Painel", Vector3.new(8.4, 2.4, 0.15), CFrame.new(0, 1.9, -2.15), color)
	p("Rodape", Vector3.new(9.2, 0.5, 4.2), CFrame.new(0, 0.25, 0), Color3.fromRGB(60, 60, 66))
	for _, x in ipairs({ -3, 0, 3 }) do
		p("Bolinha", Vector3.new(0.7, 0.7, 0.7), CFrame.new(x, 1.9, -2.3), WHITE, nil, { Shape = BALL, CanCollide = false })
	end
	p("Fundo", Vector3.new(9, 7.5, 0.6), CFrame.new(0, 3.75, 2.3), color)
	for _, x in ipairs({ -4.3, 4.3 }) do
		p("Poste", Vector3.new(0.35, 4, 0.35), CFrame.new(x, 5.9, -1.8), GOLD, Enum.Material.Metal)
	end
	-- toldo: 6 listras lado a lado, inclinadas, e a franja redonda na frente
	for i = 0, 5 do
		p("Toldo", Vector3.new(10.2 / 6, 0.3, 5.4), CFrame.new(-5.1 + (i + 0.5) * (10.2 / 6), 8.3, 0.3) * CFrame.Angles(math.rad(-14), 0, 0), i % 2 == 0 and color or WHITE, Enum.Material.Fabric)
	end
	for i = 0, 5 do
		-- meio disco pendurado na beirada (a metade de cima some atrás do toldo)
		p("Franja", Vector3.new(0.25, 1.7, 1.7), CFrame.new(-5.1 + (i + 0.5) * (10.2 / 6), 7.55, -2.3) * CFrame.Angles(0, math.rad(90), 0), i % 2 == 0 and color or WHITE, Enum.Material.Fabric, { Shape = CYL, CanCollide = false })
	end
	-- placa com moldura dourada e luzinhas que piscam (ParkController)
	local sign = p("Placa", Vector3.new(8, 1.8, 0.3), CFrame.new(0, 10.6, 0.9), color)
	K.addSurfaceText(sign, name, WHITE, color)
	p("Moldura", Vector3.new(8.6, 2.4, 0.2), CFrame.new(0, 10.6, 1.12), GOLD)
	for i = 0, 7 do
		local bulb = p("Luz", Vector3.new(0.4, 0.4, 0.4), CFrame.new(-3.85 + i * 1.1, 11.95, 0.9), COLORS[i % #COLORS + 1], Enum.Material.Neon, { Shape = BALL, CanCollide = false })
		bulb:SetAttribute("Blink", i % 2)
	end
	-- lanches de enfeite no balcão
	if snack then
		for i, x in ipairs({ -3, -1, 1, 3 }) do
			buildSnack(s, cf * CFrame.new(x, 3.9, -0.6 + (i % 2) * 0.5), snack, 1, part)
		end
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "SnackPrompt"
		prompt.ActionText = "Pegar"
		prompt.ObjectText = name
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.MaxActivationDistance = 9
		prompt.RequiresLineOfSight = false
		prompt.Parent = counter
		counter:SetAttribute("Snack", snack)
	end
end

local function buildBench(parent, cf)
	local b = K.model("Banco", parent)
	local seat = Instance.new("Seat")
	seat.Name = "Assento"
	seat.Anchored = true
	seat.Size = Vector3.new(5, 0.5, 1.6)
	seat.CFrame = cf * CFrame.new(0, 1.6, 0)
	seat.Color = Color3.fromRGB(170, 110, 60)
	seat.Material = Enum.Material.WoodPlanks
	seat.TopSurface = Enum.SurfaceType.Smooth
	seat.Parent = b
	part(b, "Encosto", Vector3.new(5, 1.6, 0.3), cf * CFrame.new(0, 2.6, 0.8), Color3.fromRGB(170, 110, 60), Enum.Material.WoodPlanks)
	for _, x in ipairs({ -2, 2 }) do
		part(b, "Pe", Vector3.new(0.4, 1.4, 1.4), cf * CFrame.new(x, 0.7, 0), Color3.fromRGB(50, 50, 55), Enum.Material.Metal)
	end
end

local function buildBalloons(parent, cf)
	local b = K.model("Baloes", parent)
	part(b, "Carrinho", Vector3.new(3, 2.4, 2), cf * CFrame.new(0, 1.2, 0), RED)
	for i = 0, 6 do
		local a = i * math.pi * 2 / 7
		local top = cf * CFrame.new(math.cos(a) * 1.6, 9 + (i % 3), math.sin(a) * 1.6)
		beam(b, "Fio", (cf * CFrame.new(0, 2.4, 0)).Position, top.Position, 0.08, WHITE, nil, { CanCollide = false })
		part(b, "Balao", Vector3.new(2, 2.4, 2), top, COLORS[i % #COLORS + 1], nil, { Shape = Enum.PartType.Ball, CanCollide = false })
	end
end

local function buildDecor(m)
	local d = K.model("Enfeites", m)
	-- barracas dos dois lados da avenida principal
	local stands = {
		{ 24, -130, "PIPOCA", RED, "Pipoca" },
		{ -24, -130, "ALGODÃO DOCE", PINK, "AlgodaoDoce" },
		{ 24, -40, "SORVETE", BLUE, "Sorvete" },
		{ -24, -40, "CACHORRO-QUENTE", ORANGE, "CachorroQuente" },
		{ -150, -60, "REFRI", GREEN, "Refri" },
		{ 150, -60, "CHURROS", PURPLE, "Churros" },
	}
	for _, s in ipairs(stands) do
		local face = s[1] > 0 and math.rad(90) or math.rad(-90)
		if math.abs(s[1]) > 100 then
			face = 0 -- as de longe ficam viradas para o caminho atravessado
		end
		buildStand(d, at(s[1], 0.4, s[2]) * CFrame.Angles(0, face, 0), s[3], s[4], s[5])
	end
	-- postes e bancos na avenida principal
	for z = GATE_Z + 14, 10, 28 do
		for _, sx in ipairs({ -1, 1 }) do
			K.buildLamp(d, at(sx * 16, -0.4, z))
		end
	end
	for _, z in ipairs({ -150, -105, -58, -15 }) do
		for _, sx in ipairs({ -1, 1 }) do
			buildBench(d, at(sx * 17, 0.4, z) * CFrame.Angles(0, sx > 0 and math.rad(-90) or math.rad(90), 0))
		end
	end
	-- postes no caminho atravessado e nos laterais
	for x = -190, 190, 40 do
		if math.abs(x) > 20 then
			K.buildLamp(d, at(x, -0.4, -90))
		end
	end
	for z = -40, 180, 40 do
		K.buildLamp(d, at(-139, -0.4, z))
	end
	-- carrinhos de balão
	buildBalloons(d, at(10, 0.4, GATE_Z + 14))
	buildBalloons(d, at(-60, 0.4, -88))
	buildBalloons(d, at(70, 0.4, 90))
	-- árvores encostadas na cerca
	local function okTree(x, z)
		return not (x > 10 and z > 50) -- não planta embaixo da montanha-russa
	end
	for x = -HALF + 10, HALF - 10, 26 do
		K.buildTree(d, (at(x, 0, HALF - 9)).Position, 1.2)
		if math.abs(x) > 60 then
			K.buildTree(d, (at(x, 0, GATE_Z + 9)).Position, 1.1)
		end
	end
	for z = GATE_Z + 30, HALF - 30, 26 do
		K.buildTree(d, (at(-HALF + 9, 0, z)).Position, 1.2)
		if okTree(HALF - 9, z) then
			K.buildTree(d, (at(HALF - 9, 0, z)).Position, 1.2)
		end
	end
end

---------------------------------------------------------------------------

-- cf: centro do parque, com a frente (-Z) virada para a avenida. kit: funções do MapBuilder.
function ParkBuilder.build(parent, cf, kit)
	K = kit
	base = cf
	local m = K.model("MigueLandia", parent)
	m:SetAttribute("ParkName", P.Name)
	m:SetAttribute("Size", P.Size)
	buildGrounds(m)
	buildFence(m)
	buildEntrance(m)
	buildCastle(m)
	buildFountain(m)
	buildFerrisWheel(m)
	buildCarousel(m)
	buildSwingRide(m)
	buildPirateShip(m)
	buildDropTower(m)
	buildCoaster(m)
	buildTeacups(m)
	buildTrampolines(m)
	buildDecor(m)
	m.WorldPivot = cf
	return m
end

-- Lanche na mão (Marco 7.4): preso na mão direita; o BikeAnimator do aparelho levanta o braço.
local SNACK_TIME = 45 -- segundos até "acabar de comer"

local function giveSnack(player, kind, timeOverride)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local hand = character and (character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm"))
	if not hand or not humanoid or humanoid.Health <= 0 or character:FindFirstChild("CarriedItem") then
		return -- quem está carregando coisa do trabalho não pega lanche
	end
	local old = character:FindFirstChild("Lanche")
	if old then
		old:Destroy()
	end
	local snack = Instance.new("Model")
	snack.Name = "Lanche"
	local grip = hand.Name == "RightHand" and CFrame.new(0, -0.2, 0) or CFrame.new(0, -1, 0)
	-- com o antebraço para a frente, a frente da mão (-Z) aponta para cima: o lanche fica em pé
	local base = hand.CFrame * grip * CFrame.Angles(-math.pi / 2, 0, 0) * CFrame.new(0, -0.3, 0)
	local function snackPart(parent, name, size, cf, color, _, extra)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.CFrame = cf
		p.Color = color
		if extra.Shape then
			p.Shape = extra.Shape
		end
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Massless = true
		local weld = Instance.new("Weld")
		weld.Part0 = hand
		weld.Part1 = p
		weld.C0 = hand.CFrame:ToObjectSpace(cf)
		weld.Parent = p
		p.Parent = parent
		return p
	end
	buildSnack(snack, base, kind, 0.45, snackPart)
	snack.Parent = character
	task.delay(timeOverride or SNACK_TIME, function()
		if snack.Parent then
			snack:Destroy()
		end
	end)
	return true
end

ParkBuilder.giveSnack = giveSnack -- Marco 10.31: lanches da orla (LitoralService)

-- Depois que o mapa está no Workspace: o servidor cuida da física de todos os brinquedos
-- (assim todo mundo vê girando igual) e das barracas de lanche.
function ParkBuilder.start(m)
	for _, ride in ipairs(m:GetChildren()) do
		if ride:GetAttribute("Physics") then
			for _, p in ipairs(ride:GetDescendants()) do
				if p:IsA("BasePart") and not p.Anchored then
					p.RootPriority = 127 -- quem senta nunca vira a "base" do brinquedo (ver abaixo)
					pcall(function()
						p:SetNetworkOwner(nil)
					end)
				end
			end
		end
	end
	-- brinquedos com movimento calculado: Root solta, presa no alvo por AlignPosition/AlignOrientation
	local live = {}
	for _, c in ipairs(cars) do
		if c.root.Parent then
			for _, p in ipairs(c.car:GetDescendants()) do
				if p:IsA("BasePart") then
					p.Anchored = false
					p.RootPriority = 127
				end
			end
			local a = Instance.new("Attachment")
			a.Name = "Alvo"
			a.Parent = c.root
			local ap = Instance.new("AlignPosition")
			ap.Mode = Enum.PositionAlignmentMode.OneAttachment
			ap.Attachment0 = a
			ap.RigidityEnabled = true
			ap.Parent = c.root
			local ao = Instance.new("AlignOrientation")
			ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
			ao.Attachment0 = a
			ao.RigidityEnabled = true
			ao.Parent = c.root
			pcall(function()
				c.root:SetNetworkOwner(nil)
			end)
			table.insert(live, { move = c.move, ap = ap, ao = ao })
		end
	end
	local function step()
		local now = Workspace:GetServerTimeNow()
		for _, c in ipairs(live) do
			local cf = c.move(now)
			c.ap.Position = cf.Position
			c.ao.CFrame = cf
		end
	end
	step()
	RunService.Heartbeat:Connect(step)
	-- Marco 7.5: na hora em que alguém senta, o boneco é soldado no brinquedo. Antes o Roblox
	-- podia escolher o boneco como "base" e passar a física para o aparelho do jogador: o
	-- brinquedo pulava até a pessoa e voltava (Luís viu na Queda Livre e nos outros). Com
	-- RootPriority alto o boneco é que vai até o banco, e a física volta sempre para o servidor.
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("Seat") and not d.Anchored then
			d:GetPropertyChangedSignal("Occupant"):Connect(function()
				task.defer(function()
					pcall(function()
						d:SetNetworkOwner(nil)
					end)
				end)
			end)
		end
	end
	-- barracas: E = pegar o lanche
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("ProximityPrompt") and d.Name == "SnackPrompt" then
			local kind = d.Parent:GetAttribute("Snack")
			d.Triggered:Connect(function(player)
				giveSnack(player, kind)
			end)
		end
	end
end

return ParkBuilder
