-- JewelryBuilder (ModuleScript)
-- Caminho: ServerScriptService > Services > JewelryBuilder
-- Marco 10.8: a joalheria do Bairro Horizonte (GameConfig.Jewelry), montada no lote "novidade" da
-- Rua das Magnólias (chamada pelo HorizonteBuilder). Visual com base nas referências do Luís:
-- fachada de vidro com caixilho branco e letreiro preto, loja preta por dentro com anéis de luz no
-- teto e no chão, balcões pretos com tampo de vidro e filete branco, joias douradas, pedestal no meio,
-- armários de parede, sofás laranja e plantas. Do lado: estacionamento (oeste) e beco com a escada do
-- telhado, o quadro de energia e a saída de emergência (leste).
-- Marco 10.9: a loja cresceu para o oeste: ÁREA RESTRITA (x de -76 a -32) com corredor, sala de
-- segurança (monitores + terminal), escritório do gerente (gaveta com o código), estoque e o COFRE
-- (porta redonda que desliza, cortinas de laser, gavetas de ouro e o Diamante Estrela). A porta dos
-- funcionários (leitor de cartão) fica na parede oeste do salão. O estacionamento ficou mais estreito.
-- O que o JewelryService usa (nomes e atributos):
--   * Model "Joalheria" (tag "Joalheria", atributo PlaceName);
--   * Vitrines/Vitrine (Model, atributos Loot, Index, Minigame, Barulho, SemCacos) com a peça
--     "Vidro" (vidro, tampa ou frente da gaveta) e a pasta "Joias";
--   * Alvos do reconhecimento: peças com o atributo Alvo ("cam1", "cam2", "cam3", "leitor",
--     "quadro", "duto");
--   * PontoReconhecimento, PontoAnuncio, Duto, QuadroEnergia, SaidaEmergencia (+ BarraAntipanico,
--     PortaFora e TravaSaida), Grade (porta de aço que desce), Gas (fumaça), LuzAlarme, PlacaFechado,
--     Area (salão), AreaRestrita, AreaCofre (caixas invisíveis), PontoFuncionario1 (gerente) /
--     PontoFuncionario2, PontoSeguranca, PontoCliente;
--   * PortaFuncionarios + LeitorCartao, Terminal, Monitor (atributo Cam), GavetaGerente,
--     PortaCofre + VolanteCofre (deslizam juntos), PainelCofre, Lasers/Laser (atributo Cortina) e
--     CortinaLaser (caixas invisíveis, atributo Index).
-- Coordenadas do lote: (0, 0, 0) = centro; -Z = frente (rua). Lote: 330 x 60.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))

local JewelryBuilder = {}

local J = GameConfig.Jewelry
local K -- ferramentas do MapBuilder

local G = 0.7 -- piso do lote
local F = 1.0 -- piso da loja
local W, Z0, Z1 = 64, -20, 26 -- largura do prédio, frente e fundo (z)
local HALF = W / 2
local CEIL = 16 -- pé-direito
local ROOF = F + CEIL + 1 -- topo da laje do telhado
-- Marco 10.9: área restrita (oeste do salão)
local WX = -76 -- parede oeste da área restrita
local SX = -HALF -- parede entre o salão e a área restrita (x = -32)
local DOORZ, DOORW, DOORH = 5, 5, 8 -- porta dos funcionários (centro z, largura, altura)
local CZ0, CZ1 = 2, 8 -- corredor (z)
local MIDX = -50 -- divisória entre o cofre/estoque (oeste) e o escritório/segurança (leste)
local VZ0 = 10 -- o cofre começa aqui (parede grossa de 8 a 10)
local VDX0, VDX1, VDY0, VDY1 = -64.5, -59.5, 0.8, 6.4 -- vão da porta do cofre (x e altura)
local LASER_Z = { 13.8, 16.4, 19 } -- cortinas de laser (z)

local BLACK = Color3.fromRGB(16, 16, 19)
local BLACK_SOFT = Color3.fromRGB(28, 28, 32)
local FLOOR = Color3.fromRGB(62, 64, 70)
local WHITE = Color3.fromRGB(245, 245, 245)
local GOLD = Color3.fromRGB(224, 178, 80)
local GOLD_DARK = Color3.fromRGB(176, 128, 50)
local GLASS = Color3.fromRGB(200, 215, 225)
local ORANGE = Color3.fromRGB(236, 146, 42)
local PAVING = Color3.fromRGB(214, 208, 198)
local ASPHALT = Color3.fromRGB(52, 54, 58)
local LEAF = Color3.fromRGB(56, 140, 62)
local BALL = Enum.PartType.Ball
local CYL = Enum.PartType.Cylinder
local NEON = Enum.Material.Neon

local function P(parent, name, size, cf, color, material, extra)
	extra = extra or {}
	local p = K.makePart(parent, {
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
	return p
end

local function light(part, range, brightness, color, kind)
	local l = Instance.new(kind or "PointLight")
	l.Range = range
	l.Brightness = brightness
	l.Color = color or Color3.fromRGB(255, 244, 228)
	if kind == "SurfaceLight" then
		l.Face = Enum.NormalId.Bottom
		l.Angle = 120
	end
	l.Parent = part
	return l
end

-- Texto num lado da peça (SurfaceGui)
local function text(part, face, str, color, font, bg)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face or Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	gui.Parent = part
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = bg or Color3.new(0, 0, 0)
	label.BackgroundTransparency = bg and 0 or 1
	label.TextColor3 = color
	label.Font = font or Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextWrapped = true
	label.Text = str
	label.Parent = gui
	return gui, label
end

-- Anel feito de pedaços (luz do teto, filete do chão)
local function ring(parent, name, center, radius, thick, height, color, material, segments)
	segments = segments or 28
	local len = 2 * math.pi * radius / segments + 0.05
	for i = 0, segments - 1 do
		local a = i * 2 * math.pi / segments
		local cf = center * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -radius)
		P(parent, name, Vector3.new(len, height, thick), cf, color, material, { collide = false, shadow = false })
	end
end

---------------------------------------------------------------------------
-- Joias (peças pequenas douradas)
---------------------------------------------------------------------------

local GEMS = { Color3.fromRGB(235, 245, 255), Color3.fromRGB(220, 40, 60), Color3.fromRGB(40, 120, 230), Color3.fromRGB(40, 190, 110) }

local function jewel(parent, kind, cf, k)
	local gem = GEMS[(k % #GEMS) + 1]
	if kind == "aneis" then
		P(parent, "Aro", Vector3.new(0.12, 0.42, 0.42), cf * CFrame.new(0, 0.24, 0) * CFrame.Angles(0, math.rad(90), 0), GOLD, Enum.Material.Metal, { shape = CYL, collide = false, reflectance = 0.3, shadow = false })
		P(parent, "Pedra", Vector3.new(0.2, 0.2, 0.2), cf * CFrame.new(0, 0.5, 0), gem, Enum.Material.Glass, { shape = BALL, collide = false, reflectance = 0.4, shadow = false })
		P(parent, "Suporte", Vector3.new(0.36, 0.12, 0.3), cf * CFrame.new(0, 0.06, 0), BLACK_SOFT, Enum.Material.Fabric, { collide = false, shadow = false })
	elseif kind == "relogios" then
		P(parent, "Pulseira", Vector3.new(0.34, 0.12, 0.9), cf * CFrame.new(0, 0.06, 0), GOLD_DARK, Enum.Material.Metal, { collide = false, reflectance = 0.25, shadow = false })
		P(parent, "Caixa", Vector3.new(0.12, 0.46, 0.46), cf * CFrame.new(0, 0.12, 0) * CFrame.Angles(0, 0, math.rad(90)), GOLD, Enum.Material.Metal, { shape = CYL, collide = false, reflectance = 0.3, shadow = false })
		P(parent, "Mostrador", Vector3.new(0.02, 0.36, 0.36), cf * CFrame.new(0, 0.185, 0) * CFrame.Angles(0, 0, math.rad(90)), k % 2 == 0 and WHITE or BLACK, Enum.Material.SmoothPlastic, { shape = CYL, collide = false, shadow = false })
	else -- colares: busto pequeno com o colar
		P(parent, "Busto", Vector3.new(0.5, 0.7, 0.3), cf * CFrame.new(0, 0.35, 0), BLACK_SOFT, Enum.Material.Fabric, { collide = false, shadow = false })
		for j = -2, 2 do
			local a = math.rad(j * 28)
			P(parent, "Conta", Vector3.new(0.09, 0.09, 0.09), cf * CFrame.new(math.sin(a) * 0.2, 0.62 - math.cos(a) * 0.2, -0.17), GOLD, Enum.Material.Metal, { shape = BALL, collide = false, reflectance = 0.3, shadow = false })
		end
		P(parent, "Pingente", Vector3.new(0.14, 0.14, 0.14), cf * CFrame.new(0, 0.38, -0.18), gem, Enum.Material.Glass, { shape = BALL, collide = false, reflectance = 0.4, shadow = false })
	end
end

local caseCount = 0
-- mini = qual minigame (GameConfig.Jewelry.Minigame); noise = barulho no medidor de alerta
local function newCase(parent, kind, mini, noise, noShards)
	caseCount += 1
	local m = K.model("Vitrine", parent)
	m:SetAttribute("Loot", kind)
	m:SetAttribute("Index", caseCount)
	m:SetAttribute("Minigame", mini or "vitrine")
	m:SetAttribute("Barulho", noise or J.Noise.Glass)
	m:SetAttribute("SemCacos", noShards or nil)
	local joias = Instance.new("Folder")
	joias.Name = "Joias"
	joias.Parent = m
	return m, joias
end

-- Balcão comprido: cf = centro no chão; comprimento no eixo X do cf. Tampo de vidro dividido em
-- vitrines (uma por tipo da lista kinds).
local function counter(parent, store, cf, length, depth, kinds)
	local h = 3.2
	P(parent, "BalcaoBase", Vector3.new(length, h, depth), cf * CFrame.new(0, h / 2, 0), BLACK, Enum.Material.SmoothPlastic, { reflectance = 0.06 })
	for _, s in ipairs({ -1, 1 }) do
		P(parent, "Filete", Vector3.new(length + 0.1, 0.08, 0.08), cf * CFrame.new(0, h + 0.02, s * (depth / 2 + 0.02)), WHITE, NEON, { collide = false, shadow = false })
	end
	local seg = length / #kinds
	for i, kind in ipairs(kinds) do
		local x = -length / 2 + seg * (i - 0.5)
		local m, joias = newCase(store, kind)
		local glass = P(m, "Vidro", Vector3.new(seg - 0.12, 1.5, depth - 0.1), cf * CFrame.new(x, h + 0.75, 0), GLASS, Enum.Material.Glass, { transparency = 0.75, reflectance = 0.15 })
		glass.CastShadow = false
		P(m, "Fundo", Vector3.new(seg - 0.2, 0.06, depth - 0.3), cf * CFrame.new(x, h + 0.03, 0), BLACK_SOFT, Enum.Material.Fabric, { collide = false })
		local n = math.max(3, math.floor(seg / 1.3))
		for k = 1, n do
			local jx = x - seg / 2 + seg * (k - 0.5) / n
			jewel(joias, kind, cf * CFrame.new(jx, h + 0.06, (k % 2 == 0) and 0.35 or -0.35), k)
		end
	end
end

-- Armário de parede com 2 nichos de vidro (embaixo e em cima). cf = centro no chão, frente = -Z do cf.
local function cabinet(parent, store, cf, length, kinds)
	local depth, h = 3, 10
	P(parent, "Armario", Vector3.new(length, h, depth), cf * CFrame.new(0, h / 2, depth / 2), BLACK, Enum.Material.SmoothPlastic, { reflectance = 0.05 })
	for i, kind in ipairs(kinds) do
		local y = 2.6 + (i - 1) * 3.4
		local m, joias = newCase(store, "blindada", "blindada", J.Noise.Armored)
		P(m, "Nicho", Vector3.new(length - 1, 2.6, 0.2), cf * CFrame.new(0, y + 1.3, depth - 0.6), Color3.fromRGB(46, 46, 52), Enum.Material.Fabric, { collide = false })
		P(m, "Prateleira", Vector3.new(length - 1, 0.12, depth - 0.6), cf * CFrame.new(0, y, depth / 2 - 0.2), BLACK_SOFT, Enum.Material.Fabric, { collide = false })
		local lamp = P(m, "LuzNicho", Vector3.new(length - 1.2, 0.08, 0.2), cf * CFrame.new(0, y + 2.5, 0.3), Color3.fromRGB(255, 236, 200), NEON, { collide = false, shadow = false })
		light(lamp, 6, 0.6, Color3.fromRGB(255, 230, 190))
		local glass = P(m, "Vidro", Vector3.new(length - 0.8, 2.8, 0.12), cf * CFrame.new(0, y + 1.3, -0.06), Color3.fromRGB(170, 200, 215), Enum.Material.Glass, { transparency = 0.62, reflectance = 0.25 })
		glass.CastShadow = false
		local n = math.max(3, math.floor((length - 1) / 1.4))
		for k = 1, n do
			local jx = -(length - 1) / 2 + (length - 1) * (k - 0.5) / n
			jewel(joias, kind, cf * CFrame.new(jx, y + 0.06, depth / 2 - 0.3) * CFrame.Angles(0, math.pi, 0), k)
		end
	end
end

local function sofa(parent, cf, length)
	P(parent, "SofaBase", Vector3.new(length, 1.4, 3.2), cf * CFrame.new(0, 0.7, 0), ORANGE, Enum.Material.Fabric)
	local seat = P(parent, "SofaAssento", Vector3.new(length - 1.6, 0.5, 2.6), cf * CFrame.new(0, 1.65, -0.2), ORANGE, Enum.Material.Fabric, { class = "Seat" })
	seat.Transparency = 0
	P(parent, "SofaEncosto", Vector3.new(length, 3, 0.9), cf * CFrame.new(0, 2.1, 1.2), ORANGE, Enum.Material.Fabric)
	for _, s in ipairs({ -1, 1 }) do
		P(parent, "SofaBraco", Vector3.new(0.8, 2.3, 3.2), cf * CFrame.new(s * (length / 2 - 0.4), 1.15, 0), Color3.fromRGB(226, 136, 36), Enum.Material.Fabric)
	end
end

local function plant(parent, pos, scale)
	scale = scale or 1
	local m = K.model("Planta", parent)
	P(m, "Vaso", Vector3.new(1.6 * scale, 1.5 * scale, 1.5 * scale), CFrame.new(pos + Vector3.new(0, 0.8 * scale, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(190, 192, 198), Enum.Material.Metal, { shape = CYL, reflectance = 0.35 })
	local top = pos + Vector3.new(0, 1.6 * scale, 0)
	for k = 0, 8 do
		local a = k * math.pi * 2 / 9
		local tilt = math.rad(25 + (k % 3) * 15)
		local leaf = CFrame.new(top) * CFrame.Angles(0, a, 0) * CFrame.Angles(tilt, 0, 0) * CFrame.new(0, 1.6 * scale, 0)
		P(m, "Folha", Vector3.new(0.7 * scale, 3.4 * scale, 0.1), leaf, k % 2 == 0 and LEAF or Color3.fromRGB(72, 160, 70), Enum.Material.Grass, { collide = false, shadow = false })
	end
	return m
end

-- Cartaz na parede: frente virada para dir
local function poster(parent, pos, dir, w, h, icon, title, sub)
	local board = P(parent, "Cartaz", Vector3.new(w, h, 0.1), CFrame.lookAt(pos, pos + dir), Color3.fromRGB(22, 22, 26), Enum.Material.SmoothPlastic, { collide = false })
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 30
	gui.LightInfluence = 0.2
	gui.Parent = board
	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
	bg.BorderSizePixel = 0
	bg.Parent = gui
	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new(Color3.fromRGB(60, 60, 70), Color3.fromRGB(10, 10, 12))
	grad.Rotation = 90
	grad.Parent = bg
	local big = Instance.new("TextLabel")
	big.BackgroundTransparency = 1
	big.Size = UDim2.fromScale(1, 0.66)
	big.Text = icon
	big.TextScaled = true
	big.Font = Enum.Font.GothamBlack
	big.TextColor3 = Color3.new(1, 1, 1)
	big.Parent = bg
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Position = UDim2.fromScale(0.05, 0.68)
	t.Size = UDim2.fromScale(0.9, 0.16)
	t.Text = title
	t.TextScaled = true
	t.Font = Enum.Font.Fondamento
	t.TextColor3 = GOLD
	t.Parent = bg
	local s = Instance.new("TextLabel")
	s.BackgroundTransparency = 1
	s.Position = UDim2.fromScale(0.1, 0.85)
	s.Size = UDim2.fromScale(0.8, 0.09)
	s.Text = sub
	s.TextScaled = true
	s.Font = Enum.Font.GothamMedium
	s.TextColor3 = Color3.fromRGB(200, 200, 205)
	s.Parent = bg
	return board
end

local function securityCamera(parent, pos, lookAt, alvo)
	local m = K.model("CameraSeguranca", parent)
	local body = P(m, "Camera", Vector3.new(0.9, 0.9, 1.8), CFrame.lookAt(pos, lookAt), Color3.fromRGB(225, 225, 228), Enum.Material.SmoothPlastic, { collide = false })
	body:SetAttribute("Alvo", alvo)
	P(m, "Lente", Vector3.new(0.2, 0.6, 0.6), body.CFrame * CFrame.new(0, 0, -0.95) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(10, 10, 14), Enum.Material.Glass, { shape = CYL, collide = false, reflectance = 0.5 })
	local led = P(m, "Led", Vector3.new(0.14, 0.14, 0.14), body.CFrame * CFrame.new(0.3, 0.3, -0.8), Color3.fromRGB(255, 30, 30), NEON, { shape = BALL, collide = false })
	led:SetAttribute("CameraLed", true)
	P(m, "Suporte", Vector3.new(0.25, 1.2, 0.25), CFrame.new(pos + Vector3.new(0, 0.9, 0)), Color3.fromRGB(80, 80, 86), Enum.Material.Metal, { collide = false })
	return body
end

---------------------------------------------------------------------------
-- Marco 10.9: área restrita (oeste do salão)
---------------------------------------------------------------------------

local STEEL = Color3.fromRGB(150, 154, 162)
local STEEL_DARK = Color3.fromRGB(70, 74, 82)
local WALL_IN = Color3.fromRGB(58, 60, 66) -- paredes de dentro da área restrita
local WOOD = Color3.fromRGB(92, 62, 42)
local CARDBOARD = Color3.fromRGB(170, 130, 86)

local function invisible(parent, name, size, cf)
	local p = P(parent, name, size, cf, WHITE, Enum.Material.SmoothPlastic, { collide = false, transparency = 1, shadow = false })
	p.CanQuery = false
	p.CanTouch = false
	return p
end

-- Parede no eixo X (z fixo) de x0 a x1, com vãos { a, b, altura }
local function wallX(parent, at, z, x0, x1, thick, gaps, color, material)
	local cuts = {}
	for _, g in ipairs(gaps or {}) do
		table.insert(cuts, g)
	end
	table.sort(cuts, function(a, b)
		return a[1] < b[1]
	end)
	local x = x0
	local h = CEIL + 1
	for _, g in ipairs(cuts) do
		if g[1] > x then
			P(parent, "Parede", Vector3.new(g[1] - x, h, thick), at((x + g[1]) / 2, F + h / 2, z), color, material)
		end
		P(parent, "Parede", Vector3.new(g[2] - g[1], h - g[3], thick), at((g[1] + g[2]) / 2, F + g[3] + (h - g[3]) / 2, z), color, material)
		x = g[2]
	end
	if x1 > x then
		P(parent, "Parede", Vector3.new(x1 - x, h, thick), at((x + x1) / 2, F + h / 2, z), color, material)
	end
end

-- Parede no eixo Z (x fixo) de z0 a z1 (sem vão)
local function wallZ(parent, at, x, z0, z1, thick, color, material)
	local h = CEIL + 1
	P(parent, "Parede", Vector3.new(thick, h, z1 - z0), at(x, F + h / 2, (z0 + z1) / 2), color, material)
end

local function roomSign(parent, at, x, y, z, faceDir, str, color, bg)
	local s = P(parent, "PlacaSala", Vector3.new(4.4, 0.9, 0.1), at(x, y, z), bg or BLACK, Enum.Material.SmoothPlastic, { collide = false })
	s.CFrame = CFrame.lookAt(s.Position, s.Position + faceDir)
	text(s, Enum.NormalId.Front, str, color or WHITE, Enum.Font.GothamBlack, bg or BLACK)
	return s
end

local function ceilingLight(parent, at, x, z, range, color)
	local lamp = P(parent, "LuzTeto", Vector3.new(3, 0.12, 0.6), at(x, F + CEIL - 0.1, z), WHITE, NEON, { collide = false, shadow = false })
	light(lamp, range or 20, 0.8, color)
	return lamp
end

-- Monitor na parede (cf: frente = -Z)
local function monitor(parent, cf, cam, label)
	local m = P(parent, "Monitor", Vector3.new(3.6, 2.2, 0.25), cf, Color3.fromRGB(14, 14, 16), Enum.Material.SmoothPlastic, { collide = false })
	m:SetAttribute("Cam", cam)
	local gui, l = text(m, Enum.NormalId.Front, label, Color3.fromRGB(150, 255, 170), Enum.Font.Code, Color3.fromRGB(16, 34, 28))
	gui.Name = "Tela"
	l.Name = "Texto"
	return m
end

-- Parede de cofrinhos (gavetas) com uma gaveta que dá para arrombar (Vitrine "ouro").
-- cf = centro no chão encostado na parede, frente = -Z do cf
local function depositWall(parent, store, cf)
	local w, h, d = 2.6, 7, 0.8
	P(parent, "ParedeCofrinhos", Vector3.new(w, h, d), cf * CFrame.new(0, h / 2, d / 2), STEEL_DARK, Enum.Material.DiamondPlate)
	for _, row in ipairs({ 0, 2 }) do
		local door = P(parent, "Cofrinho", Vector3.new(2.2, 2, 0.12), cf * CFrame.new(0, 1.3 + row * 2.2, -0.04), STEEL, Enum.Material.Metal, { collide = false, reflectance = 0.15 })
		door.CastShadow = false
		P(parent, "Fechadura", Vector3.new(0.25, 0.25, 0.1), cf * CFrame.new(0.7, 1.3 + row * 2.2, -0.12), GOLD_DARK, Enum.Material.Metal, { collide = false, shadow = false })
	end
	local m, joias = newCase(store, "ouro", "gaveta", 5, true)
	local front = P(m, "Vidro", Vector3.new(2.2, 2, 0.14), cf * CFrame.new(0, 3.5, -0.05), Color3.fromRGB(186, 160, 96), Enum.Material.Metal, { reflectance = 0.25 })
	front.CastShadow = false
	P(m, "Puxador", Vector3.new(0.9, 0.18, 0.18), cf * CFrame.new(0, 3.5, -0.2), GOLD, Enum.Material.Metal, { collide = false, shadow = false })
	for k = 0, 2 do
		P(joias, "BarraOuro", Vector3.new(1.4, 0.3, 0.5), cf * CFrame.new(0, 2.75 + k * 0.32, 0.25), GOLD, Enum.Material.Metal, { collide = false, reflectance = 0.35, shadow = false })
	end
	return m
end

-- Caixa de entrega do estoque (Vitrine com tampa de papelão; sem cacos)
local function stockBox(parent, store, cf, kind)
	P(parent, "MesaEstoque", Vector3.new(5, 3, 3), cf * CFrame.new(0, 1.5, 0), STEEL_DARK, Enum.Material.Metal)
	local m, joias = newCase(store, kind, "gaveta", 3, true)
	P(m, "Caixa", Vector3.new(2.6, 1.2, 1.8), cf * CFrame.new(0, 3.6, 0), CARDBOARD, Enum.Material.Cardboard, { collide = false })
	local lid = P(m, "Vidro", Vector3.new(2.7, 0.14, 1.9), cf * CFrame.new(0, 4.27, 0), Color3.fromRGB(150, 112, 72), Enum.Material.Cardboard)
	lid.CastShadow = false
	local tape = P(m, "Fita", Vector3.new(0.4, 0.02, 1.92), cf * CFrame.new(0, 4.35, 0), Color3.fromRGB(210, 190, 140), Enum.Material.SmoothPlastic, { collide = false, shadow = false })
	tape.CastShadow = false
	for k = -1, 1 do
		P(joias, "Estojo", Vector3.new(0.6, 0.4, 0.6), cf * CFrame.new(k * 0.75, 4.55, 0), Color3.fromRGB(120, 20, 40), Enum.Material.Fabric, { collide = false, shadow = false })
	end
	return m
end

local function buildRestricted(store, shell, cases, at, pos, dir)
	local wing = K.model("AlaRestrita", store)
	local midX = (WX + SX) / 2
	local depth = Z1 - Z0
	-- piso, teto e paredes de fora
	P(shell, "Piso", Vector3.new(SX - WX, 0.6, depth), at(midX, F - 0.3, (Z0 + Z1) / 2), Color3.fromRGB(78, 80, 86), Enum.Material.Concrete)
	P(shell, "Teto", Vector3.new(SX - WX, 1, depth), at(midX, F + CEIL + 0.5, (Z0 + Z1) / 2), BLACK, Enum.Material.SmoothPlastic)
	P(shell, "ParedeOesteRestrita", Vector3.new(1, CEIL + 1, depth), at(WX + 0.5, F + (CEIL + 1) / 2, (Z0 + Z1) / 2), BLACK, Enum.Material.SmoothPlastic, { reflectance = 0.08 })
	P(shell, "ParedeFrenteRestrita", Vector3.new(SX - WX, CEIL + 1, 1), at(midX, F + (CEIL + 1) / 2, Z0 + 0.5), BLACK, Enum.Material.SmoothPlastic, { reflectance = 0.12 })
	P(shell, "ParedeFundoRestrita", Vector3.new(SX - WX, CEIL + 1, 1), at(midX, F + (CEIL + 1) / 2, Z1 - 0.5), BLACK, Enum.Material.SmoothPlastic, { reflectance = 0.08 })
	-- fachada da área restrita: filete dourado e a plaquinha "Sala Privé"
	P(shell, "FileteFachada", Vector3.new(SX - WX, 0.25, 0.2), at(midX, F + 12, Z0 - 0.05), GOLD, Enum.Material.Metal, { collide = false, reflectance = 0.3 })
	local plaque = P(shell, "PlacaPrive", Vector3.new(14, 2.2, 0.1), at(midX, F + 8, Z0 - 0.06), BLACK, Enum.Material.SmoothPlastic, { collide = false })
	text(plaque, Enum.NormalId.Front, J.Name .. "  •  Sala Privé", GOLD, Enum.Font.Fondamento)

	-- divisórias de dentro
	local doorH = 8
	-- corredor, lado do fundo (z = 8): cofre (parede grossa de aço, 8 a 10) e escritório
	wallX(wing, at, (CZ1 + VZ0) / 2, WX + 1, MIDX - 1, VZ0 - CZ1, { { VDX0, VDX1, VDY1 } }, STEEL_DARK, Enum.Material.DiamondPlate)
	P(wing, "SoleiraCofre", Vector3.new(VDX1 - VDX0, VDY0, VZ0 - CZ1), at((VDX0 + VDX1) / 2, F + VDY0 / 2, (CZ1 + VZ0) / 2), STEEL, Enum.Material.DiamondPlate)
	wallX(wing, at, CZ1 + 0.5, MIDX - 1, SX, 1, { { -45, -41, doorH } }, WALL_IN, Enum.Material.SmoothPlastic)
	-- corredor, lado da frente (z = 2): estoque e sala de segurança
	wallX(wing, at, CZ0 - 0.5, WX + 1, SX, 1, { { -66, -62, doorH }, { -45, -41, doorH } }, WALL_IN, Enum.Material.SmoothPlastic)
	-- divisórias no meio (x = -50)
	wallZ(wing, at, MIDX, CZ1, Z1 - 1, 2, STEEL_DARK, Enum.Material.DiamondPlate)
	wallZ(wing, at, MIDX, Z0 + 1, CZ0 - 1, 1, WALL_IN, Enum.Material.SmoothPlastic)
	-- forro de aço por dentro do cofre
	P(wing, "PisoCofre", Vector3.new(MIDX - 1 - (WX + 1), 0.06, Z1 - 1 - VZ0), at((WX + 1 + MIDX - 1) / 2, F + 0.03, (VZ0 + Z1 - 1) / 2), STEEL_DARK, Enum.Material.DiamondPlate, { collide = false })

	-- porta dos funcionários (desliza para dentro da parede) + leitor de cartão do lado do salão
	local door = P(store, "PortaFuncionarios", Vector3.new(0.4, DOORH, DOORW), at(SX + 0.5, F + DOORH / 2, DOORZ), Color3.fromRGB(96, 100, 108), Enum.Material.Metal, { reflectance = 0.1 })
	door:SetAttribute("Closed", door.CFrame)
	door:SetAttribute("Open", door.CFrame + dir(0, DOORW - 0.2))
	local staffSign = roomSign(shell, at, SX + 1.06, F + DOORH + 0.8, DOORZ, dir(1, 0), "🔒 SOMENTE FUNCIONÁRIOS", WHITE, Color3.fromRGB(120, 24, 30))
	staffSign.Size = Vector3.new(4.6, 0.9, 0.1)
	local reader = P(store, "LeitorCartao", Vector3.new(0.25, 1.1, 0.75), at(SX + 1.12, F + 4.4, DOORZ + DOORW / 2 + 0.75), Color3.fromRGB(24, 24, 28), Enum.Material.SmoothPlastic)
	reader:SetAttribute("Alvo", "leitor")
	local led = P(store, "LedLeitor", Vector3.new(0.1, 0.18, 0.18), at(SX + 1.27, F + 4.75, DOORZ + DOORW / 2 + 0.75), Color3.fromRGB(255, 40, 40), NEON, { collide = false, shadow = false, shape = BALL })
	led.CastShadow = false
	roomSign(wing, at, SX - 0.06, F + DOORH + 0.8, DOORZ, dir(-1, 0), "SALÃO  ➜", WHITE, BLACK)

	-- corredor
	for _, x in ipairs({ -70, -56, -38 }) do
		ceilingLight(wing, at, x, (CZ0 + CZ1) / 2, 18)
	end
	plant(wing, pos(WX + 2.5, F, (CZ0 + CZ1) / 2), 0.9)
	poster(wing, pos(-58.5, F + 9.5, CZ0 + 0.06), dir(0, 1), 6, 4, "⚠️", "Área restrita", "Câmeras e alarme 24 h")
	roomSign(wing, at, -43, F + doorH + 0.8, CZ0 + 0.06, dir(0, 1), "SEGURANÇA", Color3.fromRGB(150, 200, 255))
	roomSign(wing, at, -64, F + doorH + 0.8, CZ0 + 0.06, dir(0, 1), "ESTOQUE", WHITE)
	roomSign(wing, at, -43, F + doorH + 0.8, CZ1 - 0.06, dir(0, -1), "GERÊNCIA", GOLD)
	roomSign(wing, at, -62, F + 10.2, CZ1 - 0.06, dir(0, -1), "COFRE", Color3.fromRGB(255, 90, 90))

	-- sala de segurança (x de -49 a -32, z de -19 a 1): monitores, terminal, rack
	P(wing, "MesaSeguranca", Vector3.new(12, 3, 3), at(-41, F + 1.5, -16.2), Color3.fromRGB(36, 38, 44), Enum.Material.SmoothPlastic)
	for i, x in ipairs({ -45.5, -41, -36.5 }) do
		local cf = CFrame.lookAt(pos(x, F + 7, Z0 + 1.2), pos(x, F + 7, Z0 + 5))
		monitor(wing, cf, i, ("CAM %d\nAO VIVO"):format(i))
	end
	local term = P(store, "Terminal", Vector3.new(2.6, 1.8, 0.2), CFrame.lookAt(pos(-41, F + 3.95, -16.4), pos(-41, F + 3.95, -10)), Color3.fromRGB(14, 14, 16), Enum.Material.SmoothPlastic, { collide = false })
	local tgui, tl = text(term, Enum.NormalId.Front, "🔒 SISTEMA\nOpala Sec 3.1", Color3.fromRGB(120, 200, 255), Enum.Font.Code, Color3.fromRGB(10, 20, 36))
	tgui.Name = "Tela"
	tl.Name = "Texto"
	P(wing, "Teclado", Vector3.new(2, 0.1, 0.7), at(-41, F + 3.05, -15.2), Color3.fromRGB(30, 30, 34), Enum.Material.SmoothPlastic, { collide = false })
	P(wing, "Cadeira", Vector3.new(1.8, 2.2, 1.8), at(-41, F + 1.1, -13), Color3.fromRGB(30, 30, 34), Enum.Material.Fabric)
	P(wing, "RackServidor", Vector3.new(3, 8, 2.4), at(-47, F + 4, -3), Color3.fromRGB(26, 26, 30), Enum.Material.Metal)
	for k = 0, 5 do
		local l = P(wing, "LedRack", Vector3.new(0.12, 0.12, 0.12), at(-45.45, F + 1.5 + k * 1.1, -3.5 + (k % 2) * 0.6), k % 3 == 0 and Color3.fromRGB(255, 180, 40) or Color3.fromRGB(60, 255, 120), NEON, { collide = false, shadow = false })
		l.CastShadow = false
	end
	ceilingLight(wing, at, -41, -9, 18, Color3.fromRGB(220, 235, 255))

	-- escritório do gerente (x de -49 a -32, z de 9 a 25): mesa com a gaveta do código
	P(wing, "Tapete", Vector3.new(10, 0.06, 8), at(-41, F + 0.03, 18), Color3.fromRGB(110, 30, 36), Enum.Material.Fabric, { collide = false })
	P(wing, "MesaGerente", Vector3.new(8, 3, 3.4), at(-41, F + 1.5, 18), WOOD, Enum.Material.Wood)
	local drawer = P(store, "GavetaGerente", Vector3.new(2.2, 0.9, 0.2), at(-38.5, F + 2.2, 16.25), Color3.fromRGB(120, 84, 56), Enum.Material.Wood)
	P(wing, "PuxadorGaveta", Vector3.new(0.8, 0.12, 0.12), at(-38.5, F + 2.2, 16.1), GOLD, Enum.Material.Metal, { collide = false, shadow = false })
	drawer.CastShadow = false
	P(wing, "CadeiraGerente", Vector3.new(2, 4, 2), at(-41, F + 2, 21), Color3.fromRGB(20, 20, 24), Enum.Material.Leather)
	P(wing, "Estante", Vector3.new(10, 9, 1.6), at(-41, F + 4.5, Z1 - 1.8), WOOD, Enum.Material.Wood)
	for k = 0, 7 do
		P(wing, "Livro", Vector3.new(0.6, 1.6, 1.2), at(-45 + k * 1.1, F + 6.3, Z1 - 2.2), ({ Color3.fromRGB(150, 40, 40), Color3.fromRGB(40, 80, 150), GOLD_DARK })[k % 3 + 1], Enum.Material.SmoothPlastic, { collide = false, shadow = false })
	end
	P(wing, "Monitorzinho", Vector3.new(1.6, 1.1, 0.12), CFrame.lookAt(pos(-43, F + 3.7, 18.6), pos(-43, F + 3.7, 10)), Color3.fromRGB(16, 16, 18), Enum.Material.SmoothPlastic, { collide = false })
	plant(wing, pos(-35, F, 23.5), 0.9)
	poster(wing, pos(SX - 0.06, F + 8.5, 16), dir(-1, 0), 8, 5, "🏆", "Funcionário do mês", "Gerente Rui")
	ceilingLight(wing, at, -41, 15, 20, Color3.fromRGB(255, 236, 210))

	-- estoque (x de -75 a -51, z de -19 a 1): prateleiras e 2 caixas de entrega
	for _, z in ipairs({ -16, -9 }) do
		P(wing, "Prateleira", Vector3.new(2.4, 8, 5), at(WX + 2.4, F + 4, z), STEEL_DARK, Enum.Material.Metal)
		for k = 0, 2 do
			P(wing, "CaixaPapelao", Vector3.new(2, 1.6, 1.8), at(WX + 2.4, F + 1.3 + k * 2.6, z + (k - 1) * 1.4), CARDBOARD, Enum.Material.Cardboard, { collide = false })
		end
	end
	stockBox(wing, cases, at(-62, F, -14), "relogios")
	stockBox(wing, cases, at(-56, F, -6) * CFrame.Angles(0, math.rad(90), 0), "colares")
	P(wing, "Palete", Vector3.new(4, 0.5, 4), at(-70, F + 0.25, -3), Color3.fromRGB(150, 116, 78), Enum.Material.WoodPlanks)
	P(wing, "CaixaGrande", Vector3.new(3.4, 3, 3.4), at(-70, F + 2, -3), CARDBOARD, Enum.Material.Cardboard)
	ceilingLight(wing, at, -63, -9, 22)

	-- COFRE (x de -75 a -51, z de 10 a 25)
	local vcx = (VDX0 + VDX1) / 2
	-- a porta redonda fica do lado de dentro, cobrindo o vão (ao abrir: recua e desliza para o leste)
	local doorCf = at(vcx, F + (VDY0 + VDY1) / 2, VZ0 + 0.85) * CFrame.Angles(0, math.rad(90), 0)
	local vdoor = P(store, "PortaCofre", Vector3.new(1.6, 7.6, 7.6), doorCf, STEEL, Enum.Material.Metal, { shape = CYL, reflectance = 0.2 })
	vdoor:SetAttribute("PartePortaCofre", true)
	local wheel = P(store, "VolanteCofre", Vector3.new(0.4, 3.2, 3.2), doorCf * CFrame.new(1, 0, 0), Color3.fromRGB(190, 192, 198), Enum.Material.Metal, { shape = CYL, collide = false, reflectance = 0.3 })
	wheel:SetAttribute("PartePortaCofre", true)
	for k = 0, 2 do
		local spoke = P(store, "RaioVolante", Vector3.new(0.3, 3.8, 0.3), doorCf * CFrame.new(1.15, 0, 0) * CFrame.Angles(math.rad(k * 60), 0, 0), Color3.fromRGB(205, 206, 210), Enum.Material.Metal, { collide = false })
		spoke:SetAttribute("PartePortaCofre", true)
	end
	for k = 0, 5 do
		local a = math.rad(k * 60 + 30)
		local bolt = P(store, "TrincoCofre", Vector3.new(0.3, 0.7, 0.7), doorCf * CFrame.new(-0.85, math.sin(a) * 3.1, math.cos(a) * 3.1), Color3.fromRGB(110, 112, 118), Enum.Material.Metal, { shape = CYL, collide = false })
		bolt:SetAttribute("PartePortaCofre", true)
	end
	-- moldura (lado do corredor)
	P(wing, "MolduraCofre", Vector3.new(VDX1 - VDX0 + 1.2, 0.6, 0.5), at(vcx, F + VDY1 + 0.3, CZ1 - 0.2), STEEL, Enum.Material.Metal, { reflectance = 0.15 })
	for _, x in ipairs({ VDX0 - 0.3, VDX1 + 0.3 }) do
		P(wing, "MolduraCofre", Vector3.new(0.6, VDY1 + 0.6, 0.5), at(x, F + (VDY1 + 0.6) / 2, CZ1 - 0.2), STEEL, Enum.Material.Metal, { reflectance = 0.15 })
	end
	local pad = P(store, "PainelCofre", Vector3.new(1.2, 1.6, 0.2), CFrame.lookAt(pos(VDX1 + 1.6, F + 4.6, CZ1 - 0.2), pos(VDX1 + 1.6, F + 4.6, 0)), Color3.fromRGB(28, 28, 32), Enum.Material.SmoothPlastic, { collide = false })
	local pgui, pl = text(pad, Enum.NormalId.Front, "🔢\n- - - -", Color3.fromRGB(255, 90, 90), Enum.Font.Code, Color3.fromRGB(20, 8, 8))
	pgui.Name = "Tela"
	pl.Name = "Texto"
	-- lasers: emissores nas paredes e 5 feixes por cortina
	local lasers = Instance.new("Folder")
	lasers.Name = "Lasers"
	lasers.Parent = store
	local x0, x1 = WX + 1, MIDX - 1
	local lx = (x0 + x1) / 2
	for i, z in ipairs(LASER_Z) do
		for _, x in ipairs({ x0 + 0.2, x1 - 0.2 }) do
			P(wing, "EmissorLaser", Vector3.new(0.4, 6, 0.4), at(x, F + 3.3, z), Color3.fromRGB(20, 20, 24), Enum.Material.Metal, { collide = false })
		end
		for k = 0, 4 do
			local beam = P(lasers, "Laser", Vector3.new(x1 - x0 - 0.6, 0.1, 0.1), at(lx, F + 0.9 + k * 1.2, z), Color3.fromRGB(255, 30, 40), NEON, { collide = false, shadow = false, transparency = 0.15 })
			beam.CanQuery = false
			beam.CanTouch = false
			beam:SetAttribute("Cortina", i)
		end
		local box = invisible(store, "CortinaLaser", Vector3.new(x1 - x0, 7, 1.4), at(lx, F + 3.5, z))
		box:SetAttribute("Index", i)
	end
	-- gavetas de ouro (entre as cortinas) e o pedestal do Diamante Estrela no fundo
	for _, z in ipairs({ 21.2, 23.8 }) do
		depositWall(wing, cases, at(x0 + 0.8, F, z) * CFrame.Angles(0, math.rad(-90), 0))
		depositWall(wing, cases, at(x1 - 0.8, F, z) * CFrame.Angles(0, math.rad(90), 0))
	end
	local dz = 22.6
	P(wing, "PedestalCofre", Vector3.new(3, 3.6, 3), at(lx, F + 1.8, dz), BLACK, Enum.Material.SmoothPlastic, { reflectance = 0.06 })
	for _, s in ipairs({ -1, 1 }) do
		P(wing, "Filete", Vector3.new(3.1, 0.08, 0.08), at(lx, F + 3.62, dz + s * 1.52), GOLD, NEON, { collide = false, shadow = false })
		P(wing, "Filete", Vector3.new(0.08, 0.08, 3.1), at(lx + s * 1.52, F + 3.62, dz), GOLD, NEON, { collide = false, shadow = false })
	end
	do
		local m, joias = newCase(cases, "diamante", "diamante", J.Noise.Armored)
		local glass = P(m, "Vidro", Vector3.new(2.6, 2.6, 2.6), at(lx, F + 4.9, dz), GLASS, Enum.Material.Glass, { transparency = 0.72, reflectance = 0.2 })
		glass.CastShadow = false
		local gem = P(joias, "Diamante", Vector3.new(1.2, 1.2, 1.2), at(lx, F + 4.95, dz) * CFrame.Angles(math.rad(45), 0, math.rad(45)), Color3.fromRGB(200, 235, 255), Enum.Material.Glass, { collide = false, reflectance = 0.5 })
		gem:SetAttribute("Gira", true)
		P(joias, "Almofada", Vector3.new(1.6, 0.25, 1.6), at(lx, F + 3.75, dz), Color3.fromRGB(120, 20, 30), Enum.Material.Fabric, { collide = false })
		local spot = P(joias, "BrilhoDiamante", Vector3.new(0.3, 0.3, 0.3), at(lx, F + 4.2, dz - 1), Color3.fromRGB(180, 230, 255), NEON, { collide = false, transparency = 1 })
		light(spot, 10, 1.6, Color3.fromRGB(170, 220, 255))
		local sparkle = Instance.new("ParticleEmitter")
		sparkle.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		sparkle.Rate = 5
		sparkle.Lifetime = NumberRange.new(0.6, 1)
		sparkle.Speed = NumberRange.new(0.2, 0.6)
		sparkle.Size = NumberSequence.new(0.45)
		sparkle.Color = ColorSequence.new(Color3.fromRGB(200, 240, 255))
		sparkle.LightEmission = 1
		sparkle.Parent = gem
	end
	for _, z in ipairs({ 12, 22 }) do
		ceilingLight(wing, at, lx, z, 16, Color3.fromRGB(255, 220, 220))
	end

	-- alarme do corredor e as caixas invisíveis das áreas
	for _, x in ipairs({ -68, -40 }) do
		local a = P(store, "LuzAlarme", Vector3.new(0.9, 0.9, 0.9), at(x, F + CEIL - 0.5, (CZ0 + CZ1) / 2), Color3.fromRGB(90, 20, 20), Enum.Material.SmoothPlastic, { shape = BALL, collide = false })
		a.CastShadow = false
	end
	local area = invisible(store, "AreaRestrita", Vector3.new(SX - (WX + 1), CEIL, depth - 2), at((WX + 1 + SX) / 2, F + CEIL / 2, (Z0 + Z1) / 2))
	area.CastShadow = false
	invisible(store, "AreaCofre", Vector3.new(x1 - x0, CEIL, Z1 - 1 - VZ0), at(lx, F + CEIL / 2, (VZ0 + Z1 - 1) / 2))
	return wing
end

---------------------------------------------------------------------------
-- Prédio
---------------------------------------------------------------------------

function JewelryBuilder.build(parent, item, helpers)
	K = helpers
	caseCount = 0
	local lot = item.lot
	local function at(x, y, z)
		return lot * CFrame.new(x, y, z)
	end
	local function pos(x, y, z)
		return lot:PointToWorldSpace(Vector3.new(x, y, z))
	end
	local function dir(x, z)
		return lot:VectorToWorldSpace(Vector3.new(x, 0, z))
	end
	local store = K.model("Joalheria", parent)
	store:SetAttribute("PlaceName", J.Name)
	local shell = K.model("Predio", store)
	local inside = K.model("Salao", store)
	local cases = Instance.new("Folder")
	cases.Name = "Vitrines"
	cases.Parent = store

	-- chão do lote: calçadão na frente, estacionamento (oeste), beco (leste) e jardim
	P(shell, "Calcadao", Vector3.new(item.w, 0.3, 10), at(0, G - 0.1, -25), PAVING, Enum.Material.Concrete)
	P(shell, "Estacionamento", Vector3.new(86, 0.3, 50), at(-121, G - 0.1, 5), ASPHALT, Enum.Material.Asphalt)
	for x = -158, -84, 12 do
		P(shell, "Faixa", Vector3.new(0.4, 0.05, 14), at(x, G + 0.06, 18), WHITE, Enum.Material.SmoothPlastic, { collide = false })
		P(shell, "Faixa", Vector3.new(0.4, 0.05, 14), at(x, G + 0.06, -8), WHITE, Enum.Material.SmoothPlastic, { collide = false })
	end
	local parkSign = P(shell, "PlacaEstacionamento", Vector3.new(6, 2, 0.3), at(-121, G + 6, -19), Color3.fromRGB(30, 70, 160))
	text(parkSign, Enum.NormalId.Front, "🅿️ Clientes " .. J.Name, WHITE)
	P(shell, "PlacaPoste", Vector3.new(0.4, 5, 0.4), at(-121, G + 2.5, -19), Color3.fromRGB(70, 72, 78), Enum.Material.Metal)
	P(shell, "Beco", Vector3.new(16, 0.3, 50), at(HALF + 8, G - 0.1, 5), Color3.fromRGB(70, 72, 76), Enum.Material.Concrete)
	P(shell, "Jardim", Vector3.new(item.w / 2 - 48, 0.3, 50), at((48 + item.w / 2) / 2, G - 0.1, 5), Color3.fromRGB(112, 178, 82), Enum.Material.Grass)
	for _, x in ipairs({ 70, 105, 140 }) do
		if K.palm then
			K.palm(shell, pos(x, G, 0), 1)
		end
	end
	for _, x in ipairs({ -140, -110, -80, -50, 60, 120 }) do
		K.buildLamp(shell, at(x, G - 0.8, -27))
	end
	-- frades na frente do vidro (carro não entra na loja)
	for x = -30, 30, 5 do
		if math.abs(x) > 4 then
			P(shell, "Frade", Vector3.new(0.9, 2.4, 0.9), at(x, G + 1.2, -23.5) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(40, 40, 44), Enum.Material.Metal, { shape = CYL })
		end
	end
	for _, x in ipairs({ -26, 26 }) do
		plant(shell, pos(x, G + 0.15, -27.5), 1.1)
	end

	-- piso, paredes e telhado
	P(shell, "Piso", Vector3.new(W, 0.6, Z1 - Z0), at(0, F - 0.3, (Z0 + Z1) / 2), FLOOR, Enum.Material.Marble, { reflectance = 0.05 })
	P(shell, "Teto", Vector3.new(W, 1, Z1 - Z0), at(0, F + CEIL + 0.5, (Z0 + Z1) / 2), BLACK, Enum.Material.SmoothPlastic)
	P(shell, "ParedeFundo", Vector3.new(W, CEIL + 1, 1), at(0, F + (CEIL + 1) / 2, Z1 - 0.5), BLACK, Enum.Material.SmoothPlastic, { reflectance = 0.08 })
	-- Marco 10.9: parede oeste com o vão da porta dos funcionários (z de 2,5 a 7,5)
	local d0, d1 = DOORZ - DOORW / 2, DOORZ + DOORW / 2
	P(shell, "ParedeOeste", Vector3.new(1, CEIL + 1, d0 - Z0), at(SX + 0.5, F + (CEIL + 1) / 2, (Z0 + d0) / 2), BLACK, Enum.Material.SmoothPlastic, { reflectance = 0.08 })
	P(shell, "ParedeOeste", Vector3.new(1, CEIL + 1, Z1 - d1), at(SX + 0.5, F + (CEIL + 1) / 2, (d1 + Z1) / 2), BLACK, Enum.Material.SmoothPlastic, { reflectance = 0.08 })
	P(shell, "ParedeOeste", Vector3.new(1, CEIL + 1 - DOORH, DOORW), at(SX + 0.5, F + DOORH + (CEIL + 1 - DOORH) / 2, DOORZ), BLACK, Enum.Material.SmoothPlastic, { reflectance = 0.08 })
	-- parede leste com o vão da saída de emergência (z de -2,5 a 2,5, 8 de altura)
	local EZ, EW, EH = 0, 5, 8
	P(shell, "ParedeLeste", Vector3.new(1, CEIL + 1, (EZ - EW / 2) - Z0), at(HALF - 0.5, F + (CEIL + 1) / 2, (Z0 + EZ - EW / 2) / 2), BLACK, Enum.Material.SmoothPlastic, { reflectance = 0.08 })
	P(shell, "ParedeLeste", Vector3.new(1, CEIL + 1, Z1 - (EZ + EW / 2)), at(HALF - 0.5, F + (CEIL + 1) / 2, (EZ + EW / 2 + Z1) / 2), BLACK, Enum.Material.SmoothPlastic, { reflectance = 0.08 })
	P(shell, "ParedeLeste", Vector3.new(1, CEIL + 1 - EH, EW), at(HALF - 0.5, F + EH + (CEIL + 1 - EH) / 2, EZ), BLACK, Enum.Material.SmoothPlastic, { reflectance = 0.08 })
	-- platibanda do telhado
	P(shell, "Platibanda", Vector3.new(0.8, 1.6, Z1 - Z0), at(HALF - 0.4, ROOF + 0.8, (Z0 + Z1) / 2), BLACK_SOFT)
	P(shell, "Platibanda", Vector3.new(0.8, 1.6, Z1 - Z0), at(WX + 0.4, ROOF + 0.8, (Z0 + Z1) / 2), BLACK_SOFT)
	P(shell, "Platibanda", Vector3.new(HALF - WX, 1.6, 0.8), at((WX + HALF) / 2, ROOF + 0.8, Z1 - 0.4), BLACK_SOFT)
	P(shell, "Platibanda", Vector3.new(SX - WX, 1.6, 0.8), at((WX + SX) / 2, ROOF + 0.8, Z0 + 0.4), BLACK_SOFT)

	-- fachada: vidro com caixilho branco, porta no meio e o letreiro preto em cima
	local glassTop = F + 12
	P(shell, "LetreiroFundo", Vector3.new(W + 0.4, ROOF + 1.6 - glassTop, 1.2), at(0, (glassTop + ROOF + 1.6) / 2, Z0 - 0.1), BLACK, Enum.Material.Glass, { reflectance = 0.25 })
	local sign = P(shell, "Letreiro", Vector3.new(44, 4.2, 0.1), at(0, glassTop + 3.6, Z0 - 0.75), BLACK, Enum.Material.SmoothPlastic, { collide = false })
	text(sign, Enum.NormalId.Front, J.Name, WHITE, Enum.Font.Fondamento)
	local slogan = P(shell, "Slogan", Vector3.new(18, 1, 0.1), at(0, glassTop + 1.05, Z0 - 0.75), BLACK, Enum.Material.SmoothPlastic, { collide = false })
	text(slogan, Enum.NormalId.Front, J.Slogan, GOLD, Enum.Font.GothamMedium)
	local signLight = P(shell, "LuzLetreiro", Vector3.new(W, 0.2, 0.3), at(0, glassTop + 0.15, Z0 - 0.9), WHITE, NEON, { collide = false, shadow = false })
	light(signLight, 14, 0.8, Color3.fromRGB(255, 250, 240))
	P(shell, "Rodape", Vector3.new(W, 0.6, 0.6), at(0, F + 0.3, Z0), WHITE, Enum.Material.SmoothPlastic)
	P(shell, "Travessa", Vector3.new(W, 0.5, 0.6), at(0, glassTop - 0.25, Z0), WHITE, Enum.Material.SmoothPlastic)
	local DOOR = 5 -- meia largura da porta
	local mullions = { -HALF + 0.25, -22, -13, -DOOR, DOOR, 13, 22, HALF - 0.25 }
	for _, x in ipairs(mullions) do
		P(shell, "Caixilho", Vector3.new(0.5, glassTop - F, 0.6), at(x, (F + glassTop) / 2, Z0), WHITE, Enum.Material.SmoothPlastic)
	end
	for i = 1, #mullions - 1 do
		local a, b = mullions[i], mullions[i + 1]
		if not (a == -DOOR and b == DOOR) then
			local g = P(shell, "VidroFachada", Vector3.new(b - a - 0.5, glassTop - F - 1, 0.2), at((a + b) / 2, (F + glassTop) / 2 + 0.05, Z0), Color3.fromRGB(40, 46, 54), Enum.Material.Glass, { transparency = 0.6, reflectance = 0.18 })
			g.CastShadow = false
		end
	end
	-- porta de aço (desce quando o alarme toca): começa enrolada em cima da porta
	local box = P(shell, "CaixaGrade", Vector3.new(2 * DOOR + 1, 1.1, 1.1), at(0, glassTop - 1.1, Z0 - 0.75), Color3.fromRGB(70, 72, 78), Enum.Material.Metal)
	box.CastShadow = false
	local grade = P(store, "Grade", Vector3.new(2 * DOOR, 0.3, 0.25), at(0, glassTop - 1.8, Z0 - 0.75), Color3.fromRGB(150, 152, 158), Enum.Material.DiamondPlate, { collide = false })
	grade:SetAttribute("Bottom", F)
	grade:SetAttribute("Top", glassTop - 1.65)
	local closed = P(store, "PlacaFechado", Vector3.new(7, 1.6, 0.1), at(0, F + 6, Z0 - 0.95), Color3.fromRGB(180, 30, 30), Enum.Material.SmoothPlastic, { collide = false, transparency = 1 })
	local closedGui = text(closed, Enum.NormalId.Front, "FECHADO • PERÍCIA DA POLÍCIA", WHITE, Enum.Font.GothamBlack, Color3.fromRGB(180, 30, 30))
	closedGui.Enabled = false
	local mat = P(inside, "Tapete", Vector3.new(2 * DOOR, 0.06, 4), at(0, F + 0.03, Z0 + 2.5), Color3.fromRGB(30, 30, 34), Enum.Material.Fabric, { collide = false })
	mat.CastShadow = false

	-- saída de emergência (leste): abre só por dentro; a PM arromba por fora
	local door = P(store, "SaidaEmergencia", Vector3.new(0.4, EH, EW), at(HALF - 0.5, F + EH / 2, EZ), Color3.fromRGB(150, 40, 40), Enum.Material.Metal)
	door:SetAttribute("Closed", door.CFrame)
	local bar = P(store, "BarraAntipanico", Vector3.new(0.3, 0.4, EW - 1), at(HALF - 1, F + 3.6, EZ), Color3.fromRGB(200, 200, 205), Enum.Material.Metal, { collide = false })
	bar.CastShadow = false
	local outside = P(store, "PortaFora", Vector3.new(0.2, 1.2, 1.2), at(HALF + 0.05, F + 3.6, EZ + 1.6), Color3.fromRGB(120, 120, 126), Enum.Material.Metal, { collide = false })
	outside.CastShadow = false
	local exitSign = P(inside, "PlacaSaida", Vector3.new(0.1, 0.9, 3), at(HALF - 1.05, F + EH + 0.8, EZ), Color3.fromRGB(30, 150, 70), Enum.Material.SmoothPlastic, { collide = false })
	exitSign.CFrame = CFrame.lookAt(exitSign.Position, exitSign.Position - dir(1, 0))
	exitSign.Size = Vector3.new(3, 0.9, 0.1)
	text(exitSign, Enum.NormalId.Front, "🏃 SAÍDA DE EMERGÊNCIA", WHITE, Enum.Font.GothamBlack, Color3.fromRGB(30, 150, 70))
	-- Marco 10.9: trava magnética (tranca no lockdown) com a luzinha (verde = livre, vermelha = trancada)
	local lock = P(store, "TravaSaida", Vector3.new(0.6, 0.7, 2.4), at(HALF - 1.3, F + EH - 0.4, EZ), Color3.fromRGB(60, 62, 68), Enum.Material.Metal, { collide = false })
	lock.CastShadow = false
	local lockLed = P(store, "LedTrava", Vector3.new(0.12, 0.25, 0.25), at(HALF - 1.65, F + EH - 0.4, EZ + 0.8), Color3.fromRGB(60, 255, 120), NEON, { collide = false, shadow = false, shape = BALL })
	lockLed.CastShadow = false

	-- beco: escada do telhado, quadro de energia, caçamba
	local truss = P(shell, "EscadaTelhado", Vector3.new(2, 20, 2), at(HALF + 1.2, G + 10, 20), Color3.fromRGB(70, 72, 78), Enum.Material.Metal, { class = "TrussPart" })
	truss.CastShadow = false
	local fuse = P(store, "QuadroEnergia", Vector3.new(0.6, 3, 2.4), at(HALF + 0.3, F + 4, 12), Color3.fromRGB(150, 152, 150), Enum.Material.Metal)
	fuse:SetAttribute("Alvo", "quadro")
	text(fuse, Enum.NormalId.Right, "⚡\nENERGIA", Color3.fromRGB(255, 210, 40), Enum.Font.GothamBlack)
	P(shell, "Cacamba", Vector3.new(4, 3.4, 7), at(HALF + 10, G + 1.7, 20), Color3.fromRGB(40, 110, 60), Enum.Material.Metal)
	P(shell, "Caixas", Vector3.new(2.4, 2, 2.4), at(HALF + 11, G + 1, 10), Color3.fromRGB(160, 120, 80), Enum.Material.Cardboard)
	local alleyLamp = P(shell, "LuzBeco", Vector3.new(0.8, 0.3, 1.4), at(HALF + 0.6, F + 11, 6), Color3.fromRGB(255, 220, 160), NEON, { collide = false })
	light(alleyLamp, 20, 0.7, Color3.fromRGB(255, 210, 150))

	-- telhado: duto de ventilação (gás) e ar-condicionado
	local duct = P(store, "Duto", Vector3.new(4, 2.4, 4), at(8, ROOF + 1.2, 10), Color3.fromRGB(165, 168, 172), Enum.Material.Metal)
	duct:SetAttribute("Alvo", "duto")
	P(shell, "DutoGrade", Vector3.new(3.4, 0.1, 3.4), at(8, ROOF + 2.45, 10), Color3.fromRGB(60, 62, 66), Enum.Material.DiamondPlate, { collide = false })
	P(shell, "DutoCano", Vector3.new(1.6, 6, 1.6), at(8, ROOF - 2, 10), Color3.fromRGB(120, 122, 126), Enum.Material.Metal, { collide = false })
	for _, x in ipairs({ -16, -6 }) do
		P(shell, "ArCondicionado", Vector3.new(5, 3, 4), at(x, ROOF + 1.5, 18), Color3.fromRGB(205, 208, 210), Enum.Material.Metal)
		P(shell, "Ventilador", Vector3.new(0.2, 3, 3), at(x, ROOF + 3.05, 18) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(50, 52, 56), Enum.Material.Metal, { shape = CYL, collide = false })
	end

	-- cartazes de fora (lado do estacionamento) e o logotipo do fundo
	poster(shell, pos(WX - 0.1, F + 8.5, 3), dir(-1, 0), 30, 13, "💍", "Brilho Eterno", "A nova coleção " .. J.Name)
	poster(shell, pos(HALF + 0.1, F + 10.5, -12), dir(1, 0), 12, 8, "💎", J.Name, "Joias que contam histórias")

	-- teto: 3 anéis de luz em cima do pedestal e 2 barras perto da porta
	local center = at(0, F + CEIL - 0.25, 2)
	for _, r in ipairs({ 4, 7.5, 11 }) do
		ring(inside, "AnelLuz", center, r, 0.3, 0.12, WHITE, NEON, r < 6 and 20 or 30)
	end
	for _, z in ipairs({ -15, -11 }) do
		P(inside, "BarraLuz", Vector3.new(18, 0.12, 0.35), at(0, F + CEIL - 0.25, z), WHITE, NEON, { collide = false, shadow = false })
	end
	for _, p in ipairs({ { -12, -6 }, { 12, -6 }, { -12, 14 }, { 12, 14 }, { 0, 2 } }) do
		local holder = P(inside, "Luz", Vector3.new(0.4, 0.1, 0.4), at(p[1], F + CEIL - 0.4, p[2]), WHITE, NEON, { collide = false, shadow = false, transparency = 1 })
		light(holder, 26, 0.9, Color3.fromRGB(255, 246, 232))
	end
	-- chão: anéis brancos em volta do pedestal
	local floorC = at(0, F + 0.02, 2)
	for _, r in ipairs({ 5, 8, 11.5 }) do
		ring(inside, "AnelChao", floorC, r, 0.18, 0.03, Color3.fromRGB(200, 200, 205), Enum.Material.SmoothPlastic, 30)
	end

	-- balcões: os dois da entrada (em U), os dois do fundo e os armários de parede
	local rotZ = CFrame.Angles(0, math.rad(90), 0)
	counter(inside, cases, at(-9, F, -2) * rotZ, 20, 3.4, { "aneis", "relogios", "colares" })
	counter(inside, cases, at(9, F, -2) * rotZ, 20, 3.4, { "colares", "aneis", "relogios" })
	counter(inside, cases, at(0, F, 14.5), 20, 3.4, { "relogios", "colares", "aneis" })
	counter(inside, cases, at(0, F, 19.5), 20, 3.4, { "aneis", "relogios", "colares" })
	cabinet(inside, cases, at(-HALF + 4, F, 16) * CFrame.Angles(0, math.rad(-90), 0), 12, { "relogios", "colares" })
	cabinet(inside, cases, at(HALF - 4, F, 16) * CFrame.Angles(0, math.rad(90), 0), 12, { "colares", "relogios" })

	-- pedestal do meio: Colar Imperial (Marco 10.9: o Diamante Estrela foi para o cofre)
	P(inside, "Pedestal", Vector3.new(2.8, 3.6, 2.8), at(0, F + 1.8, 2), BLACK, Enum.Material.SmoothPlastic, { reflectance = 0.06 })
	for _, s in ipairs({ -1, 1 }) do
		P(inside, "Filete", Vector3.new(2.9, 0.08, 0.08), at(0, F + 3.62, 2 + s * 1.42), WHITE, NEON, { collide = false, shadow = false })
		P(inside, "Filete", Vector3.new(0.08, 0.08, 2.9), at(s * 1.42, F + 3.62, 2), WHITE, NEON, { collide = false, shadow = false })
	end
	do
		local m, joias = newCase(cases, "colar", "colar", J.Noise.Armored)
		local glass = P(m, "Vidro", Vector3.new(2.5, 2.5, 2.5), at(0, F + 4.85, 2), GLASS, Enum.Material.Glass, { transparency = 0.75, reflectance = 0.15 })
		glass.CastShadow = false
		local bust = P(joias, "Busto", Vector3.new(1.3, 1.8, 0.7), at(0, F + 4.55, 2), BLACK_SOFT, Enum.Material.Fabric, { collide = false })
		for j = -4, 4 do
			local a = math.rad(j * 17)
			P(joias, "Conta", Vector3.new(0.16, 0.16, 0.16), at(math.sin(a) * 0.5, F + 5.25 - math.cos(a) * 0.5, 2 - 0.38), GOLD, Enum.Material.Metal, { shape = BALL, collide = false, reflectance = 0.3, shadow = false })
		end
		local gem = P(joias, "Esmeralda", Vector3.new(0.4, 0.4, 0.4), at(0, F + 4.62, 2 - 0.42), Color3.fromRGB(40, 200, 120), Enum.Material.Glass, { shape = BALL, collide = false, reflectance = 0.45 })
		P(joias, "Almofada", Vector3.new(1.6, 0.25, 1.6), at(0, F + 3.75, 2), Color3.fromRGB(120, 20, 30), Enum.Material.Fabric, { collide = false })
		local spot = P(joias, "BrilhoColar", Vector3.new(0.3, 0.3, 0.3), at(0, F + 4.2, 1), Color3.fromRGB(180, 255, 210), NEON, { collide = false, transparency = 1 })
		light(spot, 8, 1.2, Color3.fromRGB(200, 255, 220))
		bust.CastShadow = false
		local sparkle = Instance.new("ParticleEmitter")
		sparkle.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		sparkle.Rate = 4
		sparkle.Lifetime = NumberRange.new(0.6, 1)
		sparkle.Speed = NumberRange.new(0.2, 0.6)
		sparkle.Size = NumberSequence.new(0.4)
		sparkle.Color = ColorSequence.new(Color3.fromRGB(200, 240, 255))
		sparkle.LightEmission = 1
		sparkle.Parent = gem
	end

	-- sofás laranja, plantas e cartazes de dentro
	sofa(inside, at(-HALF + 3, F, -9) * CFrame.Angles(0, math.rad(-90), 0), 10)
	sofa(inside, at(HALF - 3, F, -9) * CFrame.Angles(0, math.rad(90), 0), 10)
	for _, p in ipairs({ { -HALF + 3, -17 }, { -HALF + 3, -1.5 }, { HALF - 3, -17 }, { HALF - 3, -1.5 }, { -HALF + 3, 23 }, { HALF - 3, 23 } }) do
		plant(inside, pos(p[1], F, p[2]), 1)
	end
	poster(inside, pos(-HALF + 1.06, F + 9, -8), dir(1, 0), 13, 8, "💎", "Coleção Diamante", "Lapidação exclusiva")
	poster(inside, pos(HALF - 1.06, F + 9, -8), dir(-1, 0), 13, 8, "💍", "Para sempre", "Alianças sob medida")
	poster(inside, pos(0, F + 10, Z1 - 1.06), dir(0, -1), 26, 9, "✨", J.Name, J.Slogan)

	-- Marco 10.9: área restrita (porta dos funcionários, segurança, escritório, estoque e cofre)
	buildRestricted(store, shell, cases, at, pos, dir)

	-- catálogo da entrada (reconhecimento) e o ponto do anúncio do assalto
	local stand = P(inside, "PontoReconhecimento", Vector3.new(1.6, 3.4, 1.2), at(-4, F + 1.7, -15), BLACK, Enum.Material.SmoothPlastic)
	stand.Name = "PontoReconhecimento"
	P(inside, "Catalogo", Vector3.new(1.3, 0.12, 1), at(-4, F + 3.47, -15) * CFrame.Angles(math.rad(-15), 0, 0), GOLD, Enum.Material.Metal, { collide = false })
	stand.Parent = store
	local announce = P(store, "PontoAnuncio", Vector3.new(1, 1, 1), at(0, F + 3, -8), WHITE, Enum.Material.SmoothPlastic, { collide = false, transparency = 1 })
	announce.CastShadow = false

	-- câmeras (alvos do reconhecimento)
	securityCamera(inside, pos(-HALF + 1.6, F + CEIL - 1.8, Z0 + 1.6), pos(0, F, 4), "cam1")
	securityCamera(inside, pos(HALF - 1.6, F + CEIL - 1.8, Z1 - 1.6), pos(0, F, -6), "cam2")
	securityCamera(inside, pos(-HALF + 1.6, F + CEIL - 1.8, Z1 - 1.6), pos(0, F, -6), "cam3")

	-- alarme (giroflex vermelho no teto e em cima do letreiro), fumaça do gás e área do salão
	for _, p in ipairs({ { -14, F + CEIL - 0.5, -10 }, { 14, F + CEIL - 0.5, -10 }, { 0, F + CEIL - 0.5, 22 }, { 0, ROOF + 2.2, Z0 - 0.4 } }) do
		local a = P(store, "LuzAlarme", Vector3.new(0.9, 0.9, 0.9), at(p[1], p[2], p[3]), Color3.fromRGB(90, 20, 20), Enum.Material.SmoothPlastic, { shape = BALL, collide = false })
		a.CastShadow = false
	end
	local gas = P(store, "Gas", Vector3.new(W - 4, 1, Z1 - Z0 - 4), at(0, F + CEIL - 2, (Z0 + Z1) / 2), WHITE, Enum.Material.SmoothPlastic, { collide = false, transparency = 1 })
	gas.CastShadow = false
	local smoke = Instance.new("ParticleEmitter")
	smoke.Name = "Fumaca"
	smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
	smoke.Color = ColorSequence.new(Color3.fromRGB(150, 230, 120))
	smoke.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.2, 0.55), NumberSequenceKeypoint.new(1, 1) })
	smoke.Size = NumberSequence.new(6, 12)
	smoke.Lifetime = NumberRange.new(4, 6)
	smoke.Speed = NumberRange.new(1, 3)
	smoke.Acceleration = Vector3.new(0, -2.5, 0)
	smoke.SpreadAngle = Vector2.new(180, 180)
	smoke.Rate = 60
	smoke.Enabled = false
	smoke.Parent = gas
	local area = P(store, "Area", Vector3.new(W - 2, CEIL, Z1 - Z0 - 1.5), at(0, F + CEIL / 2, (Z0 + Z1) / 2 + 0.25), WHITE, Enum.Material.SmoothPlastic, { collide = false, transparency = 1 })
	area.CanQuery = false
	area.CanTouch = false
	area.CastShadow = false

	-- onde ficam os NPCs
	for name, p in pairs({ PontoFuncionario1 = { -5, 23.5, 0 }, PontoFuncionario2 = { 6, 23.5, 0 }, PontoSeguranca = { 12, -16, 0 }, PontoCliente = { -15, -4, 90 } }) do
		local cf = at(p[1], F, p[2]) * CFrame.Angles(0, math.rad(p[3]), 0)
		local spot = P(store, name, Vector3.new(1, 0.2, 1), cf, WHITE, Enum.Material.SmoothPlastic, { collide = false, transparency = 1 })
		spot.CanQuery = false
		spot.CastShadow = false
	end

	store.WorldPivot = at(0, F, -2)
	CollectionService:AddTag(store, "Joalheria")
	return store
end

return JewelryBuilder
