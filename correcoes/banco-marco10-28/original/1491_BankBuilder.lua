-- BankBuilder (ModuleScript)
-- Caminho: ServerScriptService > Services > BankBuilder
-- Marco 10.20: o BANCO CENTRAL (GameConfig.Bank), num lote grande na Estrada do Vale (saída da
-- rodovia). Visual pelas referências do Luís: prédio neoclássico de pedra branca em cima de um
-- pódio azul-acinzentado, escadaria, pilastras com capitel, janelas altas, frontão na porta,
-- cornija com o nome, balaustrada no telhado e casinha de máquinas em cima. Por dentro: SALÃO
-- enorme (34 de pé-direito) com piso de mármore desenhado, colunas, ilha de caixas de vidro no meio,
-- bancos de madeira, relógio, 2 lustres, mesas da gerência e autoatendimento. Atrás: corredor,
-- sala de segurança (monitores + terminal), diretoria/arquivo (terminal antigo + cofre do diretor),
-- antecâmara de aço (controle duplo: 2 chaves) e o COFRE (modelo 3D do Luís, CofreBanco.glb em
-- ServerStorage > BankModels; sem ele monta um cofre de peças).
-- Fora: praça com bandeiras, estacionamento (leste), beco com o transformador e o funcionário que
-- fuma (preparação), doca com o carro-forte (fundo) e o andaime da reforma (oeste, evento B07).
--
-- O que o BankService usa (nomes e atributos):
--   * Model "Banco" (tag "Banco", atributo PlaceName); Areas: AreaSalao, AreaRestrita, AreaCofre,
--     AreaLote (caixas invisíveis);
--   * PontoAnuncio, GradeFrente (porta de aço da frente), PortaSeguranca + LeitorCartao,
--     TerminalSeguranca, Monitor (atributo Cam), PortaArquivo, TerminalRetro, CofreDiretor,
--     ChaveA, ChaveB, PainelTempo, GradeAntecamara, PortaCofre (Model; gira em volta de PivotCofre),
--     BloqueioCofre, PontoFuradeira, AlavancaEmergencia, SaidaServico (+ TravaServico),
--     Transformador, PontoFumante, LuzAlarme;
--   * Caixas/Gaveta (atributo Index), Pilhas/Pilha (Model com Camada1..3), Ouro/Palete (Model com
--     Camada1..4), Cofrinhos/Cofrinho (atributo Index; peça "Aberto" escondida);
--   * PrateleiraMalotes (Model, evento Avalanche), Andaime (Model, evento Reforma) + JanelaReforma
--     (Vidro e Grade);
--   * NPCs: PontoSeguranca, PontoGerente, PontoCaixa1/2, PontoCliente1..3, PontoVIP, PontoGuardaCosta.
-- Coordenadas do lote: (0, 0, 0) = centro; -Z = frente (rua).

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))
local CityRoads = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CityRoads"))

local BankBuilder = {}

local B = GameConfig.Bank
local K -- ferramentas do MapBuilder

local G = 0.7 -- chão do lote
local F = G + 4 -- piso do banco (em cima do pódio)
local H = 34 -- pé-direito do salão (altura das paredes)
local X0, X1 = -60, 60 -- paredes de fora (leste/oeste)
local ZF = -80 -- fachada (face de fora)
local ZB = 24 -- fundo do prédio principal (começa o bloco do cofre)
local ZS = -8 -- parede do fundo do salão (face do salão)
local VZ = 102 -- fundo do bloco do cofre
local VX = 43.6 -- meia-largura do bloco do cofre (por fora)
-- Marco 10.25: o cofre fica no SUBSOLO (o Luís achou o bloco de fora estranho). Tudo de buildVault
-- é montado VD para baixo e VS para trás; a escada desce pela antecâmara até a antessala dos lasers.
local VD, VS = 22, 18
local VF = F - VD -- piso do subsolo

-- cofre 3D (modelo do Luís, já em studs): pontos conhecidos no arquivo
local GLB = {
	front = Vector3.new(0, 7.85, 40.85),
	hinge = Vector3.new(-4.91, 0.35, 39.11),
	porta = Vector3.new(-0.245, 8.0, 37.505),
}
local VAULT_OFFZ = 62.25 -- arquivo -> lote: (x, y, z) -> (-x, F + y, 62,25 - z)
local HOLE_Y, HOLE_R = 7.965, 4.315 -- centro e raio do furo da porta (acima do chão da sala)
local VAULT_FLOOR = 0.5 -- o chão da sala do cofre fica meio stud acima do piso

local STONE = Color3.fromRGB(236, 233, 225)
local STONE_DARK = Color3.fromRGB(214, 210, 200)
local BASE = Color3.fromRGB(122, 141, 160)
local BEIGE = Color3.fromRGB(214, 196, 168)
local MARBLE = Color3.fromRGB(238, 234, 226)
local MARBLE_DARK = Color3.fromRGB(70, 74, 82)
local GOLD = Color3.fromRGB(214, 170, 74)
local WOOD = Color3.fromRGB(104, 66, 40)
local WOOD_DARK = Color3.fromRGB(70, 44, 28)
local GLASS = Color3.fromRGB(170, 200, 215)
local STEEL = Color3.fromRGB(120, 124, 132)
local STEEL_DARK = Color3.fromRGB(62, 64, 70)
local BLACK = Color3.fromRGB(22, 22, 26)
local WHITE = Color3.fromRGB(248, 248, 248)
local PAVING = Color3.fromRGB(206, 200, 190)
local ASPHALT = Color3.fromRGB(52, 54, 58)
local MONEY = Color3.fromRGB(96, 150, 104)
local MONEY_BAND = Color3.fromRGB(232, 214, 150)
local NAVY = Color3.fromRGB(24, 44, 92)
local CYL = Enum.PartType.Cylinder
local BALL = Enum.PartType.Ball
local NEON = Enum.Material.Neon

local lot -- CFrame do lote
local bank -- Model "Banco"

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

local function at(x, y, z)
	return lot * CFrame.new(x, y, z)
end

-- caixa entre dois cantos (coordenadas do lote)
local function boxAt(parent, name, x0, y0, z0, x1, y1, z1, color, material, extra)
	local sx, sy, sz = math.abs(x1 - x0), math.abs(y1 - y0), math.abs(z1 - z0)
	if sx < 0.01 or sy < 0.01 or sz < 0.01 then
		return nil
	end
	return P(parent, name, Vector3.new(sx, sy, sz), at((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), color, material, extra)
end

local function invisible(parent, name, x0, y0, z0, x1, y1, z1)
	local p = boxAt(parent, name, x0, y0, z0, x1, y1, z1, WHITE, nil, { transparency = 1, collide = false, shadow = false })
	p.CanQuery = false
	p.CanTouch = false
	return p
end

local function marker(name, cf)
	local p = P(bank, name, Vector3.new(1, 1, 1), cf, WHITE, nil, { transparency = 1, collide = false, shadow = false })
	p.CanQuery = false
	p.CanTouch = false
	return p
end

local function light(part, range, brightness, color, kind)
	local l = Instance.new(kind or "PointLight")
	-- Marco 10.24: o salão estava estourado (branco, sem cor); todas as luzes do banco mais fracas
	l.Range = math.min(range, 45)
	l.Brightness = brightness * 0.55
	l.Color = color or Color3.fromRGB(255, 240, 214)
	if kind == "SpotLight" or kind == "SurfaceLight" then
		l.Face = Enum.NormalId.Top
		l.Angle = 70
	end
	l.Parent = part
	return l
end

local function text(part, face, str, color, font, bg)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face or Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0.4
	gui.Parent = part
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = bg or Color3.new(0, 0, 0)
	label.BackgroundTransparency = bg and 0 or 1
	label.TextColor3 = color
	label.Font = font or Enum.Font.Garamond
	label.TextScaled = true
	label.TextWrapped = true
	label.Text = str
	label.Parent = gui
	return gui, label
end

-- Parede com aberturas. axis "x": parede ao longo de X (face no eixo Z, de z0 a z1 de espessura);
-- axis "z": ao longo de Z. a0..a1 = comprimento, y0..y1 = altura. holes = { { a0, a1, b0, b1 } }
-- (b = altura). Monta em faixas verticais: pilar cheio entre aberturas e pedaços em cima/embaixo.
local function wall(parent, name, axis, a0, a1, y0, y1, t0, t1, holes, color, material)
	local cuts = { a0, a1 }
	for _, h in ipairs(holes or {}) do
		table.insert(cuts, h[1])
		table.insert(cuts, h[2])
	end
	table.sort(cuts)
	local function piece(pa0, pa1, py0, py1)
		if pa1 - pa0 < 0.01 or py1 - py0 < 0.01 then
			return
		end
		if axis == "x" then
			boxAt(parent, name, pa0, py0, t0, pa1, py1, t1, color, material)
		else
			boxAt(parent, name, t0, py0, pa0, t1, py1, pa1, color, material)
		end
	end
	for i = 1, #cuts - 1 do
		local s0, s1 = cuts[i], cuts[i + 1]
		if s1 - s0 > 0.01 then
			local mid = (s0 + s1) / 2
			local spans = {}
			for _, h in ipairs(holes or {}) do
				if mid > h[1] and mid < h[2] then
					table.insert(spans, { h[3], h[4] })
				end
			end
			table.sort(spans, function(p, q)
				return p[1] < q[1]
			end)
			local y = y0
			for _, sp in ipairs(spans) do
				piece(s0, s1, y, sp[1])
				y = sp[2]
			end
			piece(s0, s1, y, y1)
		end
	end
end

-- janela: vidro + caixilho escuro + peitoril (na abertura; face = sinal do lado de fora)
local function windowPane(parent, axis, a0, a1, y0, y1, t, out)
	local th = 0.3
	if axis == "x" then
		local glass = boxAt(parent, "Vidro", a0, y0, t - th / 2, a1, y1, t + th / 2, GLASS, Enum.Material.SmoothPlastic, { transparency = 0.55, reflectance = 0.2 })
		glass.CastShadow = false
		boxAt(parent, "Caixilho", (a0 + a1) / 2 - 0.15, y0, t - 0.25, (a0 + a1) / 2 + 0.15, y1, t + 0.25, BLACK, Enum.Material.Metal)
		boxAt(parent, "Caixilho", a0, (y0 + y1) / 2 - 0.15, t - 0.25, a1, (y0 + y1) / 2 + 0.15, t + 0.25, BLACK, Enum.Material.Metal)
		boxAt(parent, "Peitoril", a0 - 0.6, y0 - 0.5, t + out * 0.2, a1 + 0.6, y0 + 0.04, t + out * 1.4, STONE_DARK, Enum.Material.Limestone)
	else
		local glass = boxAt(parent, "Vidro", t - th / 2, y0, a0, t + th / 2, y1, a1, GLASS, Enum.Material.SmoothPlastic, { transparency = 0.55, reflectance = 0.2 })
		glass.CastShadow = false
		boxAt(parent, "Caixilho", t - 0.25, y0, (a0 + a1) / 2 - 0.15, t + 0.25, y1, (a0 + a1) / 2 + 0.15, BLACK, Enum.Material.Metal)
		boxAt(parent, "Caixilho", t - 0.25, (y0 + y1) / 2 - 0.15, a0, t + 0.25, (y0 + y1) / 2 + 0.15, a1, BLACK, Enum.Material.Metal)
		boxAt(parent, "Peitoril", t + out * 0.2, y0 - 0.5, a0 - 0.6, t + out * 1.4, y0 + 0.04, a1 + 0.6, STONE_DARK, Enum.Material.Limestone)
	end
end

-- pilastra com base e capitel. (x, z) = centro da face; out = direção de fora (Vector3 no lote)
local function pilaster(parent, x, z, out, y0, y1)
	local side = Vector3.new(out.Z, 0, -out.X)
	local function blockAt(w, h, d, y, push)
		local c = Vector3.new(x, y, z) + out * push
		local cf = lot * CFrame.fromMatrix(c, side, Vector3.new(0, 1, 0))
		return P(parent, "Pilastra", Vector3.new(w, h, d), cf, STONE, Enum.Material.Limestone)
	end
	blockAt(3, y1 - y0, 1.2, (y0 + y1) / 2, 0.6)
	blockAt(3.8, 1.6, 1.8, y0 + 0.8, 0.9)
	local cap = blockAt(4.2, 1.2, 2.2, y1 + 0.6, 1.1)
	cap.Color = STONE_DARK
	blockAt(3.6, 0.8, 1.9, y1 - 0.4, 0.95)
	-- caneluras (frisos) na pilastra
	for k = -1, 1 do
		local c = Vector3.new(x, (y0 + y1) / 2, z) + out * 1.22 + side * (k * 0.8)
		P(parent, "Canelura", Vector3.new(0.18, y1 - y0 - 2.6, 0.06), lot * CFrame.fromMatrix(c, side, Vector3.new(0, 1, 0)), STONE_DARK, Enum.Material.Limestone, { collide = false, shadow = false })
	end
end

local function column(parent, x, z, y0, y1, r)
	P(parent, "Coluna", Vector3.new(y1 - y0 - 3, r * 2, r * 2), at(x, (y0 + y1) / 2, z) * CFrame.Angles(0, 0, math.rad(90)), MARBLE, Enum.Material.Marble, { shape = CYL })
	boxAt(parent, "BaseColuna", x - r - 0.6, y0, z - r - 0.6, x + r + 0.6, y0 + 1.5, z + r + 0.6, STONE_DARK, Enum.Material.Marble)
	boxAt(parent, "Capitel", x - r - 0.8, y1 - 1.5, z - r - 0.8, x + r + 0.8, y1, z + r + 0.8, GOLD, Enum.Material.Metal)
end

local function ring(parent, name, center, radius, thick, height, color, material, segments)
	segments = segments or 24
	local len = 2 * math.pi * radius / segments + 0.05
	for i = 0, segments - 1 do
		local a = i * 2 * math.pi / segments
		P(parent, name, Vector3.new(len, height, thick), center * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -radius), color, material, { collide = false, shadow = false })
	end
end

local function plant(parent, x, z, y)
	P(parent, "Vaso", Vector3.new(2.6, 2.4, 2.6), at(x, y + 1.2, z), Color3.fromRGB(70, 60, 54), Enum.Material.Slate)
	P(parent, "Folhagem", Vector3.new(3.6, 3.6, 3.6), at(x, y + 3.6, z), Color3.fromRGB(56, 128, 62), Enum.Material.Grass, { shape = BALL, collide = false })
end

local function bench(parent, x, z, y, rotY, len)
	local cf = at(x, y, z) * CFrame.Angles(0, rotY, 0)
	P(parent, "PeBanco", Vector3.new(0.6, 1.6, 1.8), cf * CFrame.new(-len / 2 + 0.6, 0.8, 0), WOOD_DARK, Enum.Material.Wood)
	P(parent, "PeBanco", Vector3.new(0.6, 1.6, 1.8), cf * CFrame.new(len / 2 - 0.6, 0.8, 0), WOOD_DARK, Enum.Material.Wood)
	local seat = P(parent, "Banco", Vector3.new(len, 0.5, 2), cf * CFrame.new(0, 1.85, 0), WOOD, Enum.Material.Wood, { class = "Seat" })
	seat:SetAttribute("SeatText", "Sentar")
	P(parent, "Encosto", Vector3.new(len, 2.4, 0.4), cf * CFrame.new(0, 3.2, 0.85) * CFrame.Angles(math.rad(-10), 0, 0), WOOD, Enum.Material.Wood)
end

-- Marco 10.21: estátua de bronze (pedestal, túnica, tronco, cabeça e braço erguido com louros)
local BRONZE = Color3.fromRGB(92, 120, 104)
local function statue(parent, x, y, z, rotY, scale)
	local s = scale or 1
	local cf = at(x, y, z) * CFrame.Angles(0, rotY or 0, 0)
	local M = Enum.Material.Metal
	local no = { collide = false }
	P(parent, "PedestalEstatua", Vector3.new(2.6 * s, 1.2 * s, 2.6 * s), cf * CFrame.new(0, 0.6 * s, 0), STONE_DARK, Enum.Material.Limestone, no)
	P(parent, "Estatua", Vector3.new(3.4 * s, 1.9 * s, 1.9 * s), cf * CFrame.new(0, 2.9 * s, 0) * CFrame.Angles(0, 0, math.rad(90)), BRONZE, M, { collide = false, shape = CYL })
	P(parent, "Estatua", Vector3.new(1.7 * s, 1.6 * s, 1 * s), cf * CFrame.new(0, 5.4 * s, 0), BRONZE, M, no)
	P(parent, "Estatua", Vector3.new(1.1 * s, 1.1 * s, 1.1 * s), cf * CFrame.new(0, 6.8 * s, 0), BRONZE, M, { collide = false, shape = BALL })
	P(parent, "Estatua", Vector3.new(0.45 * s, 2.2 * s, 0.45 * s), cf * CFrame.new(1.1 * s, 6.5 * s, 0) * CFrame.Angles(0, 0, math.rad(-20)), BRONZE, M, no)
	P(parent, "Estatua", Vector3.new(0.4 * s, 1.7 * s, 0.45 * s), cf * CFrame.new(-0.95 * s, 4.9 * s, 0) * CFrame.Angles(0, 0, math.rad(10)), BRONZE, M, no)
	P(parent, "CoroaEstatua", Vector3.new(0.9 * s, 0.9 * s, 0.9 * s), cf * CFrame.new(1.5 * s, 7.6 * s, 0), GOLD, M, { collide = false, shape = BALL })
end

local function wedge(parent, name, size, cf, color, material)
	return P(parent, name, size, cf, color, material, { class = "WedgePart" })
end

-- Marco 10.21: fachada "de banco central europeu" (inspirada na arquitetura do Banco de España, em
-- Madri): pórtico com 4 colunas gigantes, frontão com relógio, estátuas, sacadas de ferro,
-- lanternas na escadaria e cúpula com tambor de colunas no meio do telhado.
local function buildGrandFacade(shell, roofY)
	-- pórtico (colunas na frente das pilastras do meio)
	for _, x in ipairs({ -15.5, -7.5, 7.5, 15.5 }) do
		column(shell, x, ZF - 3.2, F - 1, F + 31, 1.3)
	end
	boxAt(shell, "Entablamento", -19, F + 31, ZF - 4.8, 19, F + H + 1.5, ZF - 1.4, STONE, Enum.Material.Limestone)
	boxAt(shell, "ArquitravePortico", -19.3, F + 31, ZF - 5.1, 19.3, F + 32.2, ZF - 4.8, STONE_DARK, Enum.Material.Limestone)
	for x = -19.2, 19.2, 1.6 do
		boxAt(shell, "Denticulo", x - 0.4, F + H + 1.05, ZF - 5.3, x + 0.4, F + H + 1.5, ZF - 4.8, STONE_DARK, Enum.Material.Limestone, { collide = false, shadow = false })
	end
	boxAt(shell, "CornijaPortico", -20, F + H + 1.5, ZF - 5.8, 20, roofY, ZF - 1.4, STONE, Enum.Material.Limestone)
	-- frontão grande com relógio no tímpano
	local pw, ph = 40, 8
	for _, s in ipairs({ -1, 1 }) do
		wedge(shell, "FrontaoPortico", Vector3.new(1.6, ph, pw / 2), at(s * pw / 4, roofY + ph / 2, ZF - 5) * CFrame.Angles(0, -s * math.rad(90), 0), STONE, Enum.Material.Limestone)
		local ang = math.atan(ph / (pw / 2))
		P(shell, "CornijaFrontao", Vector3.new(math.sqrt((pw / 2) ^ 2 + ph ^ 2) + 0.6, 0.7, 2.2), at(s * pw / 4, roofY + ph / 2 + 0.35, ZF - 5.1) * CFrame.Angles(0, 0, -s * ang), STONE_DARK, Enum.Material.Limestone, { collide = false })
	end
	local cy, cz = roofY + 3, ZF - 5.85
	P(shell, "RelogioFachada", Vector3.new(0.3, 4.4, 4.4), at(0, cy, cz) * CFrame.Angles(0, math.rad(90), 0), WHITE, Enum.Material.SmoothPlastic, { shape = CYL, collide = false })
	ring(shell, "AroRelogioFachada", at(0, cy, cz - 0.1) * CFrame.Angles(math.rad(90), 0, 0), 2.3, 0.35, 0.4, GOLD, Enum.Material.Metal, 20)
	P(shell, "Ponteiro", Vector3.new(0.25, 1.3, 0.08), at(0, cy, cz - 0.2) * CFrame.Angles(0, 0, math.rad(-60)) * CFrame.new(0, 0.6, 0), BLACK, Enum.Material.SmoothPlastic, { collide = false, shadow = false })
	P(shell, "Ponteiro", Vector3.new(0.18, 1.8, 0.08), at(0, cy, cz - 0.24) * CFrame.Angles(0, 0, math.rad(170)) * CFrame.new(0, 0.85, 0), BLACK, Enum.Material.SmoothPlastic, { collide = false, shadow = false })
	-- estátuas: topo e pontas do frontão, cantos da balaustrada
	statue(shell, 0, roofY + ph - 0.6, ZF - 5, 0, 1.15)
	statue(shell, -18.4, roofY, ZF - 5, 0, 0.9)
	statue(shell, 18.4, roofY, ZF - 5, 0, 0.9)
	statue(shell, X0 - 1.5, roofY + 3.4, ZF - 2, 0, 0.9)
	statue(shell, X1 + 1.5, roofY + 3.4, ZF - 2, 0, 0.9)
	-- sacadas de ferro nas janelas de cima (as do meio ficam atrás do pórtico)
	for _, c in ipairs({ -50, -38, -26, 26, 38, 50 }) do
		boxAt(shell, "Sacada", c - 4, F + 20.6, ZF - 2.4, c + 4, F + 21.2, ZF, STONE, Enum.Material.Limestone)
		for _, x in ipairs({ c - 3, c + 3 }) do
			boxAt(shell, "ConsoleSacada", x - 0.4, F + 19.6, ZF - 1.8, x + 0.4, F + 20.6, ZF, STONE_DARK, Enum.Material.Limestone, { collide = false })
		end
		boxAt(shell, "GradeSacada", c - 3.9, F + 23.4, ZF - 2.32, c + 3.9, F + 23.7, ZF - 2.08, BLACK, Enum.Material.Metal, { collide = false })
		for _, x in ipairs({ c - 3.9, c + 3.7 }) do
			boxAt(shell, "GradeSacada", x, F + 23.4, ZF - 2.3, x + 0.2, F + 23.7, ZF, BLACK, Enum.Material.Metal, { collide = false })
		end
		for x = c - 3.6, c + 3.65, 1.2 do
			boxAt(shell, "GradeSacada", x - 0.08, F + 21.2, ZF - 2.24, x + 0.08, F + 23.4, ZF - 2.16, BLACK, Enum.Material.Metal, { collide = false, shadow = false })
		end
	end
	-- lanternas de ferro na escadaria
	for _, s in ipairs({ -1, 1 }) do
		local x = s * 24.8
		boxAt(shell, "PosteLanterna", x - 0.25, F + 2, ZF - 12.25, x + 0.25, F + 9, ZF - 11.75, BLACK, Enum.Material.Metal)
		local lan = boxAt(shell, "Lanterna", x - 0.8, F + 9, ZF - 12.8, x + 0.8, F + 11.2, ZF - 11.2, Color3.fromRGB(255, 226, 160), NEON, { collide = false, transparency = 0.2 })
		boxAt(shell, "TopoLanterna", x - 1, F + 11.2, ZF - 13, x + 1, F + 11.6, ZF - 11, BLACK, Enum.Material.Metal, { collide = false })
		boxAt(shell, "TopoLanterna", x - 0.15, F + 11.6, ZF - 12.15, x + 0.15, F + 12.4, ZF - 11.85, GOLD, Enum.Material.Metal, { collide = false })
		light(lan, 22, 1.2, Color3.fromRGB(255, 220, 160))
	end

	-- CÚPULA no meio do telhado (em cima da claraboia do salão)
	local DZ, DR = -36, 12
	local dy = roofY + 2
	boxAt(shell, "BaseCupula", -15, roofY - 1, DZ - 15, 15, dy, DZ + 15, STONE_DARK, Enum.Material.Limestone)
	P(shell, "Tambor", Vector3.new(9, DR * 2, DR * 2), at(0, dy + 4.5, DZ) * CFrame.Angles(0, 0, math.rad(90)), STONE, Enum.Material.Limestone, { shape = CYL })
	local center = at(0, dy, DZ)
	for i = 0, 15 do
		local a = i * math.pi / 8
		P(shell, "ColunaTambor", Vector3.new(8, 0.9, 0.9), center * CFrame.Angles(0, a, 0) * CFrame.new(0, 4.5, -(DR + 0.45)) * CFrame.Angles(0, 0, math.rad(90)), WHITE, Enum.Material.Marble, { shape = CYL, collide = false })
		P(shell, "JanelaTambor", Vector3.new(2.2, 5, 0.2), center * CFrame.Angles(0, a + math.pi / 16, 0) * CFrame.new(0, 4.5, -(DR + 0.02)), Color3.fromRGB(40, 52, 66), Enum.Material.SmoothPlastic, { collide = false, reflectance = 0.25, shadow = false })
	end
	ring(shell, "CornijaTambor", at(0, dy + 9.3, DZ), DR + 0.8, 1.6, 0.8, STONE_DARK, Enum.Material.Limestone, 24)
	ring(shell, "FaixaDourada", at(0, dy + 9.9, DZ), DR + 0.25, 0.5, 0.4, GOLD, Enum.Material.Metal, 24)
	P(shell, "Cupula", Vector3.new(DR * 2, DR * 2, DR * 2), at(0, dy + 9, DZ), Color3.fromRGB(78, 92, 104), Enum.Material.Slate, { shape = BALL })
	for i = 0, 7 do
		local base = at(0, dy + 9, DZ) * CFrame.Angles(0, i * math.pi / 4, 0)
		for k = 0, 4 do
			local pm = math.rad(k * 16 + 8)
			P(shell, "NervuraCupula", Vector3.new(0.5, DR * math.rad(16) + 0.15, 0.35), base * CFrame.Angles(pm, 0, 0) * CFrame.new(0, 0, -(DR + 0.1)), GOLD, Enum.Material.Metal, { collide = false, shadow = false })
		end
	end
	local top = dy + 9 + DR
	P(shell, "Lanterna", Vector3.new(4, 4.4, 4.4), at(0, top + 1.6, DZ) * CFrame.Angles(0, 0, math.rad(90)), STONE, Enum.Material.Limestone, { shape = CYL })
	P(shell, "TopoLanterna", Vector3.new(4.6, 4.6, 4.6), at(0, top + 3.8, DZ), Color3.fromRGB(78, 92, 104), Enum.Material.Slate, { shape = BALL })
	boxAt(shell, "Mastro", -0.2, top + 5, DZ - 0.2, 0.2, top + 15, DZ + 0.2, GOLD, Enum.Material.Metal)
	P(shell, "Pinaculo", Vector3.new(0.8, 0.8, 0.8), at(0, top + 15.3, DZ), GOLD, Enum.Material.Metal, { shape = BALL, collide = false })
	boxAt(shell, "Bandeira", 0.2, top + 10.8, DZ - 0.1, 7, top + 14.8, DZ + 0.1, NAVY, Enum.Material.Fabric, { collide = false })
	for _, p in ipairs({ { -13.5, DZ - 13.5 }, { 13.5, DZ - 13.5 }, { -13.5, DZ + 13.5 }, { 13.5, DZ + 13.5 } }) do
		statue(shell, p[1], dy, p[2], p[2] < DZ and 0 or math.pi, 0.8)
	end
end

---------------------------------------------------------------------------
-- Prédio: pódio, paredes, fachada, cornija, telhado
---------------------------------------------------------------------------

local function buildShell(shell)
	-- chão do lote e praça
	boxAt(shell, "Praca", -118, G - 0.4, -131, 118, G, -86, PAVING, Enum.Material.Pavement)
	boxAt(shell, "Gramado", -118, G - 0.4, -86, X0 - 1, G, 125, Color3.fromRGB(104, 168, 80), Enum.Material.Grass)
	boxAt(shell, "Estacionamento", X1 + 1, G - 0.4, -86, 118, G, 125, ASPHALT, Enum.Material.Asphalt)
	boxAt(shell, "Doca", -VX - 1, G - 0.4, VZ, X1 + 1, G, 125, Color3.fromRGB(96, 98, 104), Enum.Material.Concrete)
	for z = -70, 50, 12 do
		boxAt(shell, "Faixa", 74, G, z - 0.2, 104, G + 0.06, z + 0.2, WHITE, Enum.Material.SmoothPlastic, { collide = false })
	end
	-- desenho de pedra na praça (rosa dos ventos)
	for k = 0, 3 do
		P(shell, "DesenhoPraca", Vector3.new(1.2, 0.08, 30), at(0, G + 0.04, -108) * CFrame.Angles(0, math.rad(k * 45), 0), BASE, Enum.Material.Slate, { collide = false, shadow = false })
	end
	ring(shell, "AnelPraca", at(0, G + 0.05, -108), 9, 1, 0.1, BASE, Enum.Material.Slate, 28)

	-- pódio (base azul-acinzentada) e piso
	-- Marco 10.23: o topo do pódio ficava na mesma altura do piso de mármore e os dois brigavam na
	-- tela (o chão piscava e mudava de cor ao mexer a câmera). Agora o pódio termina abaixo do piso.
	-- Marco 10.25: com o vão da escada (x de -21 a 21, z de 11 a 22)
	boxAt(shell, "Podio", X0 - 0.6, G - 0.2, ZF - 0.6, X1 + 0.6, F - 0.3, 10.5, BASE, Enum.Material.Slate)
	boxAt(shell, "Podio", X0 - 0.6, G - 0.2, 22.5, X1 + 0.6, F - 0.3, ZB, BASE, Enum.Material.Slate)
	boxAt(shell, "Podio", X0 - 0.6, G - 0.2, 10.5, -20.5, F - 0.3, 22.5, BASE, Enum.Material.Slate)
	boxAt(shell, "Podio", 20.5, G - 0.2, 10.5, X1 + 0.6, F - 0.3, 22.5, BASE, Enum.Material.Slate)
	boxAt(shell, "SoleiraPorta", -6, F - 0.3, ZF - 0.6, 6, F, ZF + 2, MARBLE, Enum.Material.Marble)
	boxAt(shell, "SoleiraServico", X1 - 2, F - 0.3, 14, X1 + 0.6, F, 20, Color3.fromRGB(150, 150, 150), Enum.Material.Concrete)
	for _, x in ipairs({ -50, -38, -26, -14, 14, 26, 38, 50 }) do
		boxAt(shell, "JanelaPorao", x - 2.5, G + 1, ZF - 0.7, x + 2.5, G + 2.8, ZF - 0.55, BLACK, Enum.Material.Glass)
		for k = -2, 2 do
			boxAt(shell, "GradePorao", x + k - 0.08, G + 1, ZF - 0.85, x + k + 0.08, G + 2.8, ZF - 0.7, STEEL_DARK, Enum.Material.Metal)
		end
	end
	-- escadaria (8 degraus de 0,5) com corrimãos
	for i = 1, 8 do
		boxAt(shell, "Degrau", -24, G, ZF - 1 - (9 - i) * 1.5, 24, G + i * 0.5, ZF - 0.6, Color3.fromRGB(226, 222, 214), Enum.Material.Limestone)
	end
	for _, x in ipairs({ -24.8, 24.8 }) do
		boxAt(shell, "Mureta", x - 0.8, G, ZF - 13.5, x + 0.8, F + 1.2, ZF - 0.6, BASE, Enum.Material.Slate)
		boxAt(shell, "Floreira", x - 0.8, F + 1.2, ZF - 13.5, x + 0.8, F + 2, ZF - 10, Color3.fromRGB(56, 128, 62), Enum.Material.Grass)
	end
	-- piso de mármore em cima do pódio
	boxAt(shell, "PisoBanco", X0 + 2, F - 0.2, ZF + 2, X1 - 2, F, 11, MARBLE, Enum.Material.Marble, { reflectance = 0.04 })
	boxAt(shell, "PisoBanco", X0 + 2, F - 0.2, 22, X1 - 2, F, ZB, MARBLE, Enum.Material.Marble, { reflectance = 0.04 })
	boxAt(shell, "PisoBanco", X0 + 2, F - 0.2, 11, -20, F, 22, MARBLE, Enum.Material.Marble, { reflectance = 0.04 })
	boxAt(shell, "PisoBanco", 20, F - 0.2, 11, X1 - 2, F, 22, MARBLE, Enum.Material.Marble, { reflectance = 0.04 })

	-- FACHADA (z de -80 a -78): porta no meio, 4 janelas de cada lado (2 andares de vidro)
	local holes = { { -5, 5, F, F + 15 } }
	local bays = { -50, -38, -26, -14, 14, 26, 38, 50 }
	for _, c in ipairs(bays) do
		table.insert(holes, { c - 3, c + 3, F + 5, F + 18 })
		table.insert(holes, { c - 3, c + 3, F + 22, F + 28.5 })
	end
	wall(shell, "Fachada", "x", X0, X1, F, F + H, ZF, ZF + 2, holes, STONE, Enum.Material.Limestone)
	for _, c in ipairs(bays) do
		windowPane(shell, "x", c - 3, c + 3, F + 5, F + 18, ZF + 1, -1)
		windowPane(shell, "x", c - 3, c + 3, F + 22, F + 28.5, ZF + 1, -1)
		-- moldura com frontão pequeno em cima da janela de baixo
		boxAt(shell, "Moldura", c - 3.6, F + 18, ZF - 0.9, c + 3.6, F + 19, ZF, STONE_DARK, Enum.Material.Limestone)
		boxAt(shell, "Moldura", c - 4, F + 19, ZF - 1.2, c + 4, F + 19.5, ZF, STONE, Enum.Material.Limestone)
	end
	-- faixa azul (base) por fora, até o peitoril das janelas de baixo
	-- Marco 10.23: a faixa passava reto na frente da porta, como um batente de 2,5 de altura (e na saída
	-- de serviço também). Agora ela para nas duas portas.
	boxAt(shell, "FaixaBase", X0 - 0.6, F - 0.4, ZF - 0.6, -6, F + 2.5, ZF, BASE, Enum.Material.Slate)
	boxAt(shell, "FaixaBase", 6, F - 0.4, ZF - 0.6, X1 + 0.6, F + 2.5, ZF, BASE, Enum.Material.Slate)
	boxAt(shell, "FaixaBase", X0 - 0.6, F - 0.4, ZF, X0, F + 2.5, ZB + 0.6, BASE, Enum.Material.Slate)
	boxAt(shell, "FaixaBase", X1, F - 0.4, ZF, X1 + 0.6, F + 2.5, 14, BASE, Enum.Material.Slate)
	boxAt(shell, "FaixaBase", X1, F - 0.4, 20, X1 + 0.6, F + 2.5, ZB + 0.6, BASE, Enum.Material.Slate)
	boxAt(shell, "FaixaBase", X0, F - 0.4, ZB, X1, F + 2.5, ZB + 0.6, BASE, Enum.Material.Slate)
	-- pilastras da frente (entre as janelas) e nos cantos
	local out = Vector3.new(0, 0, -1)
	for _, x in ipairs({ -56, -44, -32, -20, -8, 8, 20, 32, 44, 56 }) do
		pilaster(shell, x, ZF, out, F + 2.5, F + 31)
	end
	-- porta principal: moldura, frontão triangular e letreiro
	boxAt(shell, "Batente", -6, F, ZF - 0.8, -5, F + 16, ZF, STONE_DARK, Enum.Material.Limestone)
	boxAt(shell, "Batente", 5, F, ZF - 0.8, 6, F + 16, ZF, STONE_DARK, Enum.Material.Limestone)
	boxAt(shell, "Verga", -7, F + 15, ZF - 1.2, 7, F + 17, ZF, STONE_DARK, Enum.Material.Limestone)
	local plate = boxAt(shell, "LetreiroPorta", -6.5, F + 17.2, ZF - 1.3, 6.5, F + 19.2, ZF - 1.1, STONE, Enum.Material.Limestone)
	text(plate, Enum.NormalId.Back, "BANCO CENTRAL", Color3.fromRGB(70, 72, 80), Enum.Font.Garamond)
	local pw, ph = 18, 5
	for _, s in ipairs({ -1, 1 }) do
		local w = Instance.new("WedgePart")
		w.Anchored = true
		w.Size = Vector3.new(1.4, ph, pw / 2)
		w.CFrame = at(s * pw / 4, F + 19.6 + ph / 2, ZF - 1.2) * CFrame.Angles(0, -s * math.rad(90), 0)
		w.Color = STONE
		w.Material = Enum.Material.Limestone
		w.TopSurface = Enum.SurfaceType.Smooth
		w.BottomSurface = Enum.SurfaceType.Smooth
		w.Name = "Frontao"
		w.Parent = shell
	end
	boxAt(shell, "BaseFrontao", -9.6, F + 19.2, ZF - 2, 9.6, F + 19.8, ZF, STONE_DARK, Enum.Material.Limestone)
	local seal = P(shell, "Brasao", Vector3.new(0.3, 2.4, 2.4), at(0, F + 21.4, ZF - 1.95) * CFrame.Angles(0, math.rad(90), 0), GOLD, Enum.Material.Metal, { shape = CYL, collide = false })
	seal.Reflectance = 0.2
	-- portas de madeira abertas para dentro (horário de funcionamento) e vidro interno
	for _, s in ipairs({ -1, 1 }) do
		local door = P(shell, "PortaMadeira", Vector3.new(5, 14.6, 0.5), at(s * 5.2, F + 7.3, ZF + 4.3) * CFrame.Angles(0, math.rad(90), 0), WOOD, Enum.Material.Wood)
		for k = -1, 1 do
			P(shell, "Almofada", Vector3.new(0.2, 3.4, 3.6), door.CFrame * CFrame.new(0, k * 4.4, s * 0.28) * CFrame.Angles(0, math.rad(90), 0), WOOD_DARK, Enum.Material.Wood, { collide = false })
		end
		P(shell, "Puxador", Vector3.new(0.3, 1.6, 0.3), door.CFrame * CFrame.new(2, 0, -s * 0.4), GOLD, Enum.Material.Metal, { collide = false })
	end
	-- porta de aço da frente (some no horário normal; desce no cerco e com o banco fechado)
	local grade = boxAt(bank, "GradeFrente", -5, F, ZF + 0.4, 5, F + 15, ZF + 1.2, STEEL_DARK, Enum.Material.DiamondPlate, { transparency = 1, collide = false })
	grade:SetAttribute("Aberta", true)
	-- cornija com o nome, dentículos e balaustrada
	-- arquitrave e friso: faixas em volta das paredes (por fora)
	local function band(name, y0, y1, d, color)
		-- Marco 10.23: um pouco para dentro da parede (a face de dentro piscava junto com ela)
		boxAt(shell, name, X0 - d, y0, ZF - d, X1 + d, y1, ZF + 1.9, color, Enum.Material.Limestone)
		boxAt(shell, name, X0 - d, y0, ZF + 1.9, X0 + 1.9, y1, ZB - 0.1, color, Enum.Material.Limestone)
		boxAt(shell, name, X1 - 1.9, y0, ZF + 1.9, X1 + d, y1, ZB - 0.1, color, Enum.Material.Limestone)
	end
	band("Arquitrave", F + H - 3, F + H - 1.5, 1.4, STONE_DARK)
	band("Friso", F + H - 1.5, F + H + 1.5, 1.6, STONE)
	local name = boxAt(shell, "NomeFachada", -17, F + 32.4, ZF - 4.95, 17, F + H + 0.9, ZF - 4.85, STONE, Enum.Material.Limestone, { collide = false })
	text(name, Enum.NormalId.Back, B.Name:upper(), Color3.fromRGB(60, 62, 70), Enum.Font.Garamond)
	for x = X0 - 0.5, X1 + 0.5, 1.6 do
		boxAt(shell, "Denticulo", x - 0.4, F + H + 1.5, ZF - 2.2, x + 0.4, F + H + 2.2, ZF - 1.6, STONE_DARK, Enum.Material.Limestone, { collide = false, shadow = false })
	end
	boxAt(shell, "Cornija", X0 - 2.4, F + H + 2.2, ZF - 2.8, X1 + 2.4, F + H + 3, ZB + 1, STONE, Enum.Material.Limestone)
	-- telhado
	boxAt(shell, "Laje", X0 + 1, F + H, ZF + 1, X1 - 1, F + H + 2.2, ZB - 0.5, Color3.fromRGB(150, 152, 156), Enum.Material.Concrete)
	local roofY = F + H + 3
	-- balaustrada (frente e lados)
	local function balusters(xa, za, xb, zb)
		local len = math.sqrt((xb - xa) ^ 2 + (zb - za) ^ 2)
		local n = math.floor(len / 2)
		for k = 0, n do
			local x = xa + (xb - xa) * k / n
			local z = za + (zb - za) * k / n
			P(shell, "Balaustre", Vector3.new(0.7, 2.4, 0.7), at(x, roofY + 1.2, z), STONE, Enum.Material.Limestone, { shape = CYL, shadow = false })
		end
		local mid = Vector3.new((xa + xb) / 2, roofY + 2.7, (za + zb) / 2)
		P(shell, "Corrimao", Vector3.new(1.2, 0.6, len + 1), lot * CFrame.lookAt(mid, Vector3.new(xb, roofY + 2.7, zb)), STONE_DARK, Enum.Material.Limestone)
	end
	balusters(X0 - 1.5, ZF - 2, X1 + 1.5, ZF - 2)
	balusters(X0 - 1.5, ZF - 2, X0 - 1.5, ZB)
	balusters(X1 + 1.5, ZF - 2, X1 + 1.5, ZB)
	for _, x in ipairs({ X0 - 1.5, -8, 8, X1 + 1.5 }) do
		boxAt(shell, "PilarBalaustrada", x - 1, roofY, ZF - 3, x + 1, roofY + 3.4, ZF - 1, STONE_DARK, Enum.Material.Limestone)
	end
	buildGrandFacade(shell, roofY)

	-- LATERAIS (x = -60 e +60): janelas no salão; atrás, janelas menores
	for _, side in ipairs({ -1, 1 }) do
		local xo = side < 0 and X0 or X1 - 2
		local sideHoles = {}
		for _, c in ipairs({ -68, -54, -40, -26 }) do
			table.insert(sideHoles, { c - 3, c + 3, F + 5, F + 18 })
			table.insert(sideHoles, { c - 3, c + 3, F + 22, F + 28.5 })
		end
		if side < 0 then
			table.insert(sideHoles, { 5.5, 10.5, F + 5, F + 11 }) -- janela da diretoria (evento Reforma)
		else
			table.insert(sideHoles, { 14, 20, F, F + 9 }) -- saída de serviço
		end
		if side < 0 then -- Marco 10.24: no leste essa janela ficava atrás dos monitores da segurança
			table.insert(sideHoles, { -2, 2, F + 6, F + 12 })
		end
		table.insert(sideHoles, { -2, 2, F + 22, F + 28.5 }) -- Marco 10.23: janelas do 2º andar
		table.insert(sideHoles, { 9, 15, F + 22, F + 28.5 })
		wall(shell, "Lateral", "z", ZF + 2, ZB, F, F + H, xo, xo + 2, sideHoles, STONE, Enum.Material.Limestone)
		local face = side < 0 and X0 or X1
		for _, c in ipairs({ -68, -54, -40, -26 }) do
			windowPane(shell, "z", c - 3, c + 3, F + 5, F + 18, face - side * 1, side)
			windowPane(shell, "z", c - 3, c + 3, F + 22, F + 28.5, face - side * 1, side)
		end
		if side < 0 then
			windowPane(shell, "z", -2, 2, F + 6, F + 12, face - side * 1, side)
		end
		windowPane(shell, "z", -2, 2, F + 22, F + 28.5, face - side * 1, side)
		windowPane(shell, "z", 9, 15, F + 22, F + 28.5, face - side * 1, side)
		for _, z in ipairs({ -75, -61, -47, -33, -19, 3, 21 }) do
			pilaster(shell, face, z, Vector3.new(side, 0, 0), F + 2.5, F + 31)
		end
	end
	-- fundo do prédio principal (dos lados do bloco do cofre)
	wall(shell, "Fundo", "x", X0, -VX, F, F + H, ZB - 2, ZB, {}, STONE, Enum.Material.Limestone)
	wall(shell, "Fundo", "x", VX, X1, F, F + H, ZB - 2, ZB, {}, STONE, Enum.Material.Limestone)
	boxAt(shell, "FundoAlto", -VX, F, ZB - 2, VX, F + H, ZB, STONE, Enum.Material.Limestone)
	for _, z in ipairs({ -38, -14, 14, 38 }) do
		pilaster(shell, z, ZB, Vector3.new(0, 0, 1), F + 2.5, F + 31)
	end

	-- Marco 10.25: atrás do prédio agora é um pátio (o cofre desceu para o subsolo)
	boxAt(shell, "PatioFundos", X0 - 1, G - 0.4, ZB + 0.6, X1 + 1, G, VZ, PAVING, Enum.Material.Pavement)
	for x = -48, 48, 16 do
		boxAt(shell, "CanteiroPatio", x - 5, G, 60, x + 5, G + 1.2, 66, STONE_DARK, Enum.Material.Limestone)
		boxAt(shell, "TerraPatio", x - 4.5, G + 1.2, 60.5, x + 4.5, G + 1.3, 65.5, Color3.fromRGB(70, 110, 60), Enum.Material.Grass, { collide = false, shadow = false })
		plant(shell, x, 63, G + 1.3)
	end
	-- iluminação da fachada (à noite)
	for _, x in ipairs({ -44, -20, 20, 44 }) do
		local up = boxAt(shell, "Refletor", x - 0.6, G, ZF - 3, x + 0.6, G + 0.6, ZF - 2.2, BLACK, Enum.Material.Metal, { collide = false })
		local l = light(up, 30, 1.4, Color3.fromRGB(255, 226, 180), "SpotLight")
		l.Angle = 50
	end
	-- bandeiras e postes na praça
	for i, x in ipairs({ -36, -30, 30, 36 }) do
		boxAt(shell, "MastroPraca", x - 0.25, G, -100.25, x + 0.25, G + 26, -99.75, STEEL, Enum.Material.Metal)
		local colors = { NAVY, Color3.fromRGB(28, 120, 70), Color3.fromRGB(28, 120, 70), NAVY }
		boxAt(shell, "BandeiraPraca", x + 0.25, G + 21, -100.05, x + 6, G + 25, -99.95, colors[i], Enum.Material.Fabric, { collide = false })
	end
	for _, x in ipairs({ -100, -70, 70, 100 }) do
		K.buildLamp(shell, at(x, G - 0.8, -122))
	end
	for x = -46, 46, 6 do
		if math.abs(x) > 26 then
			P(shell, "Frade", Vector3.new(0.9, 2.4, 0.9), at(x, G + 1.2, -88) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(40, 40, 44), Enum.Material.Metal, { shape = CYL })
		end
	end
	for _, x in ipairs({ -54, -44, 44, 54 }) do
		plant(shell, x, -90, G)
	end
	-- monumento com o nome na praça
	local mono = boxAt(shell, "Monumento", -10, G, -118, 10, G + 5, -115, BASE, Enum.Material.Slate)
	local mt = boxAt(shell, "MonumentoNome", -9.5, G + 0.6, -118.15, 9.5, G + 4.4, -118.05, BASE, Enum.Material.Slate, { collide = false })
	text(mt, Enum.NormalId.Front, "🏦 " .. B.Name, Color3.fromRGB(240, 220, 160), Enum.Font.Garamond)
	mono.CastShadow = true
	-- palmeiras/árvores no gramado oeste
	for _, z in ipairs({ -70, -30, 30, 80 }) do
		if K.palm then
			K.palm(shell, lot:PointToWorldSpace(Vector3.new(-100, G, z)), 1)
		end
	end
end

---------------------------------------------------------------------------
-- Salão
---------------------------------------------------------------------------

-- Marco 10.21: o salão "de banco central": claraboia de vitral, galerias com balaústres,
-- escadaria dupla com tapete vermelho, lambri de mármore e retratos dos presidentes.
local function buildGrandHall(hall)
	local HX0, HX1, HZ0, HZ1 = X0 + 2, X1 - 2, ZF + 2, ZS
	local IRON = Color3.fromRGB(40, 40, 44)
	local CARPET = Color3.fromRGB(130, 30, 36)
	-- claraboia: 8 x 8 vitrais (borda azul, creme, âmbar e o centro vermelho)
	local function vitral(i, j)
		local r = math.max(math.abs(i - 3.5), math.abs(j - 3.5))
		if r > 3 then
			return Color3.fromRGB(46, 76, 150)
		elseif r > 2 then
			return (i + j) % 2 == 0 and Color3.fromRGB(240, 200, 120) or Color3.fromRGB(236, 226, 196)
		elseif r > 1 then
			return Color3.fromRGB(222, 150, 60)
		end
		return Color3.fromRGB(180, 40, 50)
	end
	for i = 0, 7 do
		for j = 0, 7 do
			local x0, z0 = -12 + i * 3, -48 + j * 3
			boxAt(hall, "Vitral", x0, F + H - 0.35, z0, x0 + 3, F + H - 0.15, z0 + 3, vitral(i, j), NEON, { collide = false, shadow = false, transparency = 0.35 })
		end
	end
	for k = 0, 8 do
		boxAt(hall, "CaixilhoVitral", -12 + k * 3 - 0.15, F + H - 0.55, -48, -12 + k * 3 + 0.15, F + H - 0.35, -24, IRON, Enum.Material.Metal, { collide = false, shadow = false })
		boxAt(hall, "CaixilhoVitral", -12, F + H - 0.55, -48 + k * 3 - 0.15, 12, F + H - 0.35, -48 + k * 3 + 0.15, IRON, Enum.Material.Metal, { collide = false, shadow = false })
	end
	boxAt(hall, "MolduraVitral", -13, F + H - 1.2, -49, 13, F + H - 0.4, -48, GOLD, Enum.Material.Metal, { collide = false })
	boxAt(hall, "MolduraVitral", -13, F + H - 1.2, -24, 13, F + H - 0.4, -23, GOLD, Enum.Material.Metal, { collide = false })
	boxAt(hall, "MolduraVitral", -13, F + H - 1.2, -48, -12, F + H - 0.4, -24, GOLD, Enum.Material.Metal, { collide = false })
	boxAt(hall, "MolduraVitral", 12, F + H - 1.2, -48, 13, F + H - 0.4, -24, GOLD, Enum.Material.Metal, { collide = false })
	local glow = boxAt(hall, "LuzClaraboia", -0.5, F + H - 3, -36.5, 0.5, F + H - 2, -35.5, WHITE, nil, { transparency = 1, collide = false, shadow = false })
	light(glow, 50, 1.3, Color3.fromRGB(255, 226, 170))

	-- GALERIAS laterais (andar de cima, F + 20) e ESCADARIA dupla
	for _, s in ipairs({ -1, 1 }) do
		local xi, xo = s * 52, s * 58
		boxAt(hall, "Galeria", xi, F + 19.2, -43.8, xo, F + 20, HZ1, MARBLE, Enum.Material.Marble)
		boxAt(hall, "FrisoGaleria", xi - s * 0.3, F + 19, -43.8, xi, F + 19.6, HZ1, GOLD, Enum.Material.Metal, { collide = false })
		for z = -42, HZ1 - 2, 4 do
			boxAt(hall, "ConsoleGaleria", xi, F + 17.6, z - 0.5, xi + s * 1.4, F + 19.2, z + 0.5, STONE_DARK, Enum.Material.Limestone, { collide = false })
		end
		boxAt(hall, "BaseBalaustrada", xi, F + 20, -43.8, xi + s * 0.8, F + 20.4, HZ1, MARBLE_DARK, Enum.Material.Marble)
		for z = -43, HZ1 - 0.6, 2 do
			P(hall, "Balaustre", Vector3.new(2.3, 0.55, 0.55), at(xi + s * 0.4, F + 21.55, z) * CFrame.Angles(0, 0, math.rad(90)), STONE, Enum.Material.Limestone, { shape = CYL, shadow = false })
		end
		boxAt(hall, "CorrimaoGaleria", xi - s * 0.1, F + 22.7, -43.8, xi + s * 0.9, F + 23.2, HZ1, MARBLE, Enum.Material.Marble)
		boxAt(hall, "CorrimaoGaleria", xi, F + 20, -44.1, s * 54, F + 23.2, -43.7, MARBLE, Enum.Material.Marble)
		-- lance 1: junto à fachada, sobe de x = 24 até 54 (20 degraus de meio stud)
		for k = 1, 20 do
			local h = F + k * 0.5
			local xa, xb = s * (24 + (k - 1) * 1.5), s * (24 + k * 1.5)
			boxAt(hall, "DegrauEscadaria", xa, math.max(F, h - 1), -77.8, xb, h, -73.8, MARBLE, Enum.Material.Marble)
			boxAt(hall, "TapeteEscada", xa, h, -77.2, xb, h + 0.06, -74.4, CARPET, Enum.Material.Fabric, { collide = false, shadow = false })
		end
		boxAt(hall, "PatamarEscadaria", s * 54, F + 9, HZ0, xo, F + 10, -73.8, MARBLE, Enum.Material.Marble)
		boxAt(hall, "TapeteEscada", s * 54, F + 10, -77.2, s * 57.4, F + 10.06, -73.8, CARPET, Enum.Material.Fabric, { collide = false, shadow = false })
		-- lance 2: junto à parede lateral, sobe até a galeria
		for k = 1, 20 do
			local h = F + 10 + k * 0.5
			local za, zb = -73.8 + (k - 1) * 1.5, -73.8 + k * 1.5
			boxAt(hall, "DegrauEscadaria", s * 54, h - 1, za, xo, h, zb, MARBLE, Enum.Material.Marble)
			boxAt(hall, "TapeteEscada", s * 54.6, h, za, s * 57.4, h + 0.06, zb, CARPET, Enum.Material.Fabric, { collide = false, shadow = false })
		end
		-- corrimãos dourados com balaústres
		local function rail(a, b)
			local mid = (a + b) / 2
			P(hall, "CorrimaoEscada", Vector3.new(0.35, 0.35, (b - a).Magnitude), lot * CFrame.lookAt(mid, b), GOLD, Enum.Material.Metal, { collide = false })
		end
		rail(Vector3.new(s * 24, F + 3.4, -73.95), Vector3.new(s * 54, F + 13.4, -73.95))
		rail(Vector3.new(s * 53.95, F + 13.4, -73.8), Vector3.new(s * 53.95, F + 23.4, -43.8))
		for k = 0, 10 do
			local x = s * (24 + 3 * k)
			boxAt(hall, "BalaustreEscada", x - 0.12, F + k, -74.07, x + 0.12, F + k + 3.4, -73.83, GOLD, Enum.Material.Metal, { collide = false, shadow = false })
			local z = -73.8 + 3 * k
			boxAt(hall, "BalaustreEscada", s * 53.83, F + 10 + k, z - 0.12, s * 54.07, F + 13.4 + k, z + 0.12, GOLD, Enum.Material.Metal, { collide = false, shadow = false })
		end
	end

	-- lambri de mármore escuro com friso dourado
	local function wainscot(x0, z0, x1, z1)
		boxAt(hall, "Lambri", x0, F, z0, x1, F + 4, z1, MARBLE_DARK, Enum.Material.Marble, { collide = false })
	end
	wainscot(HX0, HZ0, HX0 + 0.3, HZ1)
	wainscot(HX1 - 0.3, HZ0, HX1, HZ1)
	wainscot(HX0, HZ0, -5, HZ0 + 0.3)
	wainscot(5, HZ0, HX1, HZ0 + 0.3)
	wainscot(HX0, HZ1 - 0.3, -3, HZ1)
	wainscot(3, HZ1 - 0.3, HX1, HZ1)
	boxAt(hall, "FrisoLambri", HX0, F + 4, HZ0, HX0 + 0.4, F + 4.3, HZ1, GOLD, Enum.Material.Metal, { collide = false, shadow = false })
	boxAt(hall, "FrisoLambri", HX1 - 0.4, F + 4, HZ0, HX1, F + 4.3, HZ1, GOLD, Enum.Material.Metal, { collide = false, shadow = false })

	-- retratos dos presidentes na parede do fundo
	local people = {
		{ -40, "Fundador • 1904", Color3.fromRGB(52, 70, 56) },
		{ -22, "Presidenta • 1931", Color3.fromRGB(80, 40, 44) },
		{ 22, "Presidente • 1958", Color3.fromRGB(40, 50, 76) },
		{ 40, "Presidenta • 1987", Color3.fromRGB(70, 58, 40) },
	}
	for i, pp in ipairs(people) do
		local x = pp[1]
		boxAt(hall, "MolduraQuadro", x - 3, F + 11, HZ1 - 0.35, x + 3, F + 19, HZ1, GOLD, Enum.Material.Metal, { collide = false })
		boxAt(hall, "Quadro", x - 2.4, F + 11.6, HZ1 - 0.45, x + 2.4, F + 18.4, HZ1 - 0.35, pp[3], Enum.Material.SmoothPlastic, { collide = false, shadow = false })
		boxAt(hall, "Retrato", x - 1.6, F + 11.6, HZ1 - 0.5, x + 1.6, F + 14.2, HZ1 - 0.45, i % 2 == 0 and Color3.fromRGB(120, 30, 40) or Color3.fromRGB(26, 26, 30), Enum.Material.SmoothPlastic, { collide = false, shadow = false })
		P(hall, "Retrato", Vector3.new(0.06, 1.9, 1.9), at(x, F + 15.4, HZ1 - 0.48) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(214, 176, 140), Enum.Material.SmoothPlastic, { shape = CYL, collide = false, shadow = false })
		local plate = boxAt(hall, "PlacaQuadro", x - 1.8, F + 10, HZ1 - 0.3, x + 1.8, F + 10.7, HZ1 - 0.22, GOLD, Enum.Material.Metal, { collide = false })
		text(plate, Enum.NormalId.Front, pp[2], Color3.fromRGB(40, 30, 20), Enum.Font.Garamond)
	end
end

local function buildHall(hall)
	local HX0, HX1, HZ0, HZ1 = X0 + 2, X1 - 2, ZF + 2, ZS
	-- desenho do piso: faixa escura em volta, rosa dos ventos no meio
	boxAt(hall, "FaixaPiso", HX0 + 3, F, HZ0 + 3, HX1 - 3, F + 0.05, HZ0 + 4.2, MARBLE_DARK, Enum.Material.Marble, { collide = false })
	boxAt(hall, "FaixaPiso", HX0 + 3, F, HZ1 - 4.2, HX1 - 3, F + 0.05, HZ1 - 3, MARBLE_DARK, Enum.Material.Marble, { collide = false })
	boxAt(hall, "FaixaPiso", HX0 + 3, F, HZ0 + 3, HX0 + 4.2, F + 0.05, HZ1 - 3, MARBLE_DARK, Enum.Material.Marble, { collide = false })
	boxAt(hall, "FaixaPiso", HX1 - 4.2, F, HZ0 + 3, HX1 - 3, F + 0.05, HZ1 - 3, MARBLE_DARK, Enum.Material.Marble, { collide = false })
	-- Marco 10.23: cada ponta da estrela e cada anel numa altura (na mesma altura eles piscavam)
	for k = 0, 7 do
		local top = 0.04 + k * 0.02
		P(hall, "Estrela", Vector3.new(0.9, top, k % 2 == 0 and 20 or 13), at(0, F + top / 2, -58) * CFrame.Angles(0, math.rad(k * 22.5), 0), k % 2 == 0 and GOLD or MARBLE_DARK, Enum.Material.Marble, { collide = false, shadow = false })
	end
	ring(hall, "AnelPiso", at(0, F + 0.11, -58), 11, 0.8, 0.22, MARBLE_DARK, Enum.Material.Marble, 32)
	ring(hall, "AnelPiso", at(0, F + 0.12, -58), 7, 0.5, 0.24, GOLD, Enum.Material.Marble, 28)
	-- tapete vermelho da entrada até a ilha
	boxAt(hall, "Tapete", -4, F, HZ0, 4, F + 0.3, -46, Color3.fromRGB(130, 30, 36), Enum.Material.Fabric, { collide = false })
	-- colunas internas (2 fileiras) e teto com caixotões
	for _, x in ipairs({ -46, 46 }) do
		for z = -70, -14, 14 do
			column(hall, x, z, F, F + H, 1.6)
		end
	end
	local VIGA = Color3.fromRGB(196, 186, 160)
	for x = -48, 48, 12 do
		if math.abs(x) < 12 then
			boxAt(hall, "Viga", x - 0.6, F + H - 2, HZ0, x + 0.6, F + H, -48, VIGA, Enum.Material.Limestone, { collide = false })
			boxAt(hall, "Viga", x - 0.6, F + H - 2, -24, x + 0.6, F + H, HZ1, VIGA, Enum.Material.Limestone, { collide = false })
		else
			boxAt(hall, "Viga", x - 0.6, F + H - 2, HZ0, x + 0.6, F + H, HZ1, VIGA, Enum.Material.Limestone, { collide = false })
		end
	end
	for z = -74, -10, 12 do
		if z > -48 and z < -24 then
			boxAt(hall, "Viga", HX0, F + H - 2, z - 0.6, -12, F + H, z + 0.6, VIGA, Enum.Material.Limestone, { collide = false })
			boxAt(hall, "Viga", 12, F + H - 2, z - 0.6, HX1, F + H, z + 0.6, VIGA, Enum.Material.Limestone, { collide = false })
		else
			boxAt(hall, "Viga", HX0, F + H - 2, z - 0.6, HX1, F + H, z + 0.6, VIGA, Enum.Material.Limestone, { collide = false })
		end
	end
	-- lustres
	for _, z in ipairs({ -66, -14 }) do
		local base = at(0, F + 25, z)
		P(hall, "CorrenteLustre", Vector3.new(0.3, H - 25 - 2, 0.3), at(0, F + 25 + (H - 27) / 2, z), GOLD, Enum.Material.Metal, { collide = false })
		ring(hall, "AroLustre", base, 4, 0.4, 0.4, GOLD, Enum.Material.Metal, 20)
		ring(hall, "AroLustre", base * CFrame.new(0, -2, 0), 2.6, 0.4, 0.4, GOLD, Enum.Material.Metal, 16)
		for k = 0, 11 do
			local a = k * math.pi / 6
			local p = P(hall, "Cristal", Vector3.new(0.5, 1.4, 0.5), base * CFrame.new(math.cos(a) * 4, -0.9, math.sin(a) * 4), Color3.fromRGB(255, 244, 214), NEON, { collide = false, shadow = false })
			p.Transparency = 0.15
		end
		local core = P(hall, "LuzLustre", Vector3.new(1.8, 1.8, 1.8), base * CFrame.new(0, -2.4, 0), Color3.fromRGB(255, 236, 196), NEON, { shape = BALL, collide = false, shadow = false })
		light(core, 60, 1.6)
	end
	-- relógio grande na parede do fundo
	local clockCf = at(0, F + 24, ZS - 0.4) * CFrame.Angles(0, math.rad(90), 0)
	P(hall, "Relogio", Vector3.new(0.5, 9, 9), clockCf, WHITE, Enum.Material.SmoothPlastic, { shape = CYL, collide = false })
	ring(hall, "AroRelogio", at(0, F + 24, ZS - 0.6) * CFrame.Angles(math.rad(90), 0, 0), 4.6, 0.5, 0.6, GOLD, Enum.Material.Metal, 24)
	for k = 0, 11 do
		local a = k * math.pi / 6
		P(hall, "Marca", Vector3.new(k % 3 == 0 and 0.5 or 0.3, k % 3 == 0 and 1.2 or 0.7, 0.1), at(math.sin(a) * 3.6, F + 24 + math.cos(a) * 3.6, ZS - 0.7) * CFrame.Angles(0, 0, -a), BLACK, Enum.Material.SmoothPlastic, { collide = false, shadow = false })
	end
	P(hall, "Ponteiro", Vector3.new(0.35, 2.8, 0.1), at(0, F + 24, ZS - 0.8) * CFrame.Angles(0, 0, math.rad(-60)) * CFrame.new(0, 1.3, 0), BLACK, Enum.Material.SmoothPlastic, { collide = false, shadow = false })
	P(hall, "Ponteiro", Vector3.new(0.25, 3.6, 0.1), at(0, F + 24, ZS - 0.85) * CFrame.Angles(0, 0, math.rad(170)) * CFrame.new(0, 1.7, 0), BLACK, Enum.Material.SmoothPlastic, { collide = false, shadow = false })

	-- ILHA DOS CAIXAS (vidro) no meio: 3 guichês na frente e 3 atrás
	local IX, IZ0, IZ1 = 18, -44, -28
	local caixas = Instance.new("Folder")
	caixas.Name = "Caixas"
	caixas.Parent = bank
	local idx = 0
	for _, zc in ipairs({ IZ0, IZ1 }) do
		local outward = zc == IZ0 and -1 or 1
		boxAt(hall, "Balcao", -IX, F, zc - 1.3, IX, F + 3.6, zc + 1.3, WOOD, Enum.Material.Wood)
		boxAt(hall, "TampoBalcao", -IX - 0.3, F + 3.6, zc - 1.6, IX + 0.3, F + 3.9, zc + 1.6, MARBLE_DARK, Enum.Material.Marble)
		local glass = boxAt(hall, "VidroCaixa", -IX, F + 3.9, zc - 0.1, IX, F + 10, zc + 0.1, GLASS, Enum.Material.SmoothPlastic, { transparency = 0.7, reflectance = 0.2 })
		glass.CastShadow = false
		for x = -IX, IX, 12 do
			boxAt(hall, "MontanteVidro", x - 0.2, F + 3.9, zc - 0.2, x + 0.2, F + 10, zc + 0.2, GOLD, Enum.Material.Metal)
		end
		boxAt(hall, "TopoCaixa", -IX - 0.4, F + 10, zc - 1.6, IX + 0.4, F + 11.2, zc + 1.6, WOOD_DARK, Enum.Material.Wood)
		for _, x in ipairs({ -12, 0, 12 }) do
			idx += 1
			-- janelinha do guichê, número e gaveta (lado de dentro)
			boxAt(hall, "Passagem", x - 1.2, F + 3.9, zc - 0.15, x + 1.2, F + 4.6, zc + 0.15, BLACK, Enum.Material.SmoothPlastic, { transparency = 0.4, collide = false })
			local num = boxAt(hall, "NumeroCaixa", x - 1, F + 10.2, zc + outward * 1.62, x + 1, F + 11, zc + outward * 1.66, WOOD_DARK, Enum.Material.Wood, { collide = false })
			text(num, outward < 0 and Enum.NormalId.Front or Enum.NormalId.Back, "CAIXA " .. idx, Color3.fromRGB(240, 220, 160), Enum.Font.Garamond)
			local gaveta = boxAt(caixas, "Gaveta", x - 1.2, F + 2.6, zc - outward * 1.3 - outward * 0.15, x + 1.2, F + 3.4, zc - outward * 1.3 + outward * 0.15, WOOD_DARK, Enum.Material.Wood)
			gaveta:SetAttribute("Index", idx)
			boxAt(hall, "Monitor", x - 0.9, F + 3.9, zc - outward * 0.8 - 0.1, x + 0.9, F + 5.2, zc - outward * 0.8 + 0.1, BLACK, Enum.Material.SmoothPlastic)
		end
	end
	-- laterais da ilha (vidro) com portinhola
	for _, s in ipairs({ -1, 1 }) do
		boxAt(hall, "LateralCaixa", s * IX - 0.3, F, IZ0 + 1.3, s * IX + 0.3, F + 3.6, -38.5, WOOD, Enum.Material.Wood)
		boxAt(hall, "LateralCaixa", s * IX - 0.3, F, -33.5, s * IX + 0.3, F + 3.6, IZ1 - 1.3, WOOD, Enum.Material.Wood)
		local g = boxAt(hall, "VidroCaixa", s * IX - 0.1, F + 3.6, IZ0 + 1.3, s * IX + 0.1, F + 10, IZ1 - 1.3, GLASS, Enum.Material.SmoothPlastic, { transparency = 0.75, collide = false })
		g.CastShadow = false
	end
	boxAt(hall, "TapeteCaixa", -IX + 1, F, IZ0 + 1.4, IX - 1, F + 0.06, IZ1 - 1.4, Color3.fromRGB(110, 26, 30), Enum.Material.Fabric, { collide = false })
	local sign = boxAt(hall, "PlacaCaixas", -8, F + 12, -36.2, 8, F + 14.4, -35.8, NAVY, Enum.Material.SmoothPlastic, { collide = false })
	text(sign, Enum.NormalId.Front, "CAIXAS • ATENDIMENTO", Color3.fromRGB(240, 220, 160), Enum.Font.GothamBold)
	text(sign, Enum.NormalId.Back, "CAIXAS • ATENDIMENTO", Color3.fromRGB(240, 220, 160), Enum.Font.GothamBold)
	-- correntinhas da fila
	for _, x in ipairs({ -10, -6, -2, 2, 6, 10 }) do
		P(hall, "PosteFila", Vector3.new(0.4, 3, 0.4), at(x, F + 1.5, -50), GOLD, Enum.Material.Metal, { shape = CYL, collide = false })
	end
	boxAt(hall, "Fita", -10, F + 2.6, -50.1, 10, F + 2.9, -49.9, Color3.fromRGB(130, 30, 36), Enum.Material.Fabric, { collide = false })
	-- bancos de madeira (frente do salão)
	for _, x in ipairs({ -34, -22, 22, 34 }) do
		bench(hall, x, -64, F, 0, 9)
		bench(hall, x, -56, F, 0, 9)
	end
	-- gerência (leste): mesas, cadeiras, computadores
	for i, z in ipairs({ -66, -50, -34, -18 }) do
		boxAt(hall, "Mesa", 50, F, z - 3, 55, F + 3, z + 3, WOOD, Enum.Material.Wood)
		boxAt(hall, "Computador", 51.5, F + 3, z - 1, 52, F + 5, z + 1, BLACK, Enum.Material.SmoothPlastic)
		local chair = boxAt(hall, "Cadeira", 46.5, F + 1.8, z - 1, 48.5, F + 2.3, z + 1, BLACK, Enum.Material.Fabric, { class = "Seat" })
		chair:SetAttribute("SeatText", "Sentar")
		local lamp = boxAt(hall, "Luminaria", 53.5, F + 3, z + 1.8, 54.1, F + 5, z + 2.4, GOLD, Enum.Material.Metal, { collide = false })
		if i % 2 == 1 then
			light(lamp, 10, 0.8)
		end
	end
	local ger = boxAt(hall, "PlacaGerencia", 56.6, F + 8, -46, 56.8, F + 10, -38, NAVY, Enum.Material.SmoothPlastic, { collide = false })
	text(ger, Enum.NormalId.Left, "GERÊNCIA", Color3.fromRGB(240, 220, 160), Enum.Font.GothamBold)
	-- autoatendimento (oeste)
	for _, z in ipairs({ -60, -50, -40 }) do
		boxAt(hall, "Atm", -57.5, F, z - 2, -54.5, F + 6, z + 2, Color3.fromRGB(40, 70, 120), Enum.Material.SmoothPlastic)
		local tela = boxAt(hall, "TelaAtm", -54.55, F + 3.5, z - 1.2, -54.45, F + 5, z + 1.2, Color3.fromRGB(110, 190, 255), NEON, { collide = false })
		text(tela, Enum.NormalId.Right, "LLC", WHITE, Enum.Font.GothamBold)
	end
	local auto = boxAt(hall, "PlacaAuto", -56.8, F + 8, -56, -56.6, F + 10, -44, NAVY, Enum.Material.SmoothPlastic, { collide = false })
	text(auto, Enum.NormalId.Right, "AUTOATENDIMENTO", Color3.fromRGB(240, 220, 160), Enum.Font.GothamBold)
	for _, p in ipairs({ { -40, -70 }, { 40, -70 }, { -52, -12 }, { 52, -12 } }) do
		plant(hall, p[1], p[2], F)
	end
	-- luzes de parede (arandelas)
	for _, z in ipairs({ -61, -47, -33 }) do
		for _, x in ipairs({ HX0 + 0.4, HX1 - 0.4 }) do
			local a = P(hall, "Arandela", Vector3.new(0.8, 1.6, 0.8), at(x, F + 25, z), Color3.fromRGB(255, 232, 190), NEON, { collide = false, shadow = false })
			light(a, 24, 0.8)
		end
	end
	-- parede do fundo do salão (com a porta de segurança no meio)
	wall(hall, "ParedeFundoSalao", "x", X0 + 2, X1 - 2, F, F + H, ZS, ZS + 2, { { -3, 3, F, F + 9 }, { -57.5, -52.5, F + 20, F + 29 }, { 52.5, 57.5, F + 20, F + 29 } }, STONE, Enum.Material.Limestone)
	-- Marco 10.23: as galerias agora levam ao 2º andar; quadro com o que tem em cada andar
	local dir = boxAt(hall, "Diretorio", 12, F + 1, -71, 19, F + 11, -70.6, NAVY, Enum.Material.SmoothPlastic)
	boxAt(hall, "PeDiretorio", 15, F, -71, 16, F + 1, -70.6, GOLD, Enum.Material.Metal)
	text(dir, Enum.NormalId.Front, "BANCO CENTRAL\n\nTÉRREO\nCaixas • Gerência\nAutoatendimento\n\n2º ANDAR (pelas escadas)\nPresidência • Reuniões • Copa\n\nÁREA RESTRITA\nSegurança • Diretoria\nArquivo • Cofre", Color3.fromRGB(240, 220, 160), Enum.Font.GothamBold)
	boxAt(hall, "Rodape", X0 + 2, F, ZS - 0.2, -3, F + 1, ZS, MARBLE_DARK, Enum.Material.Marble, { collide = false })
	boxAt(hall, "Rodape", 3, F, ZS - 0.2, X1 - 2, F + 1, ZS, MARBLE_DARK, Enum.Material.Marble, { collide = false })
	local restr = boxAt(hall, "PlacaRestrita", -4, F + 10, ZS - 0.15, 4, F + 11.5, ZS - 0.05, Color3.fromRGB(160, 30, 30), Enum.Material.SmoothPlastic, { collide = false })
	text(restr, Enum.NormalId.Front, "ÁREA RESTRITA", WHITE, Enum.Font.GothamBold)
	-- teto do salão
	-- teto do salão (com o buraco da claraboia de vitral no meio)
	local TC = Color3.fromRGB(232, 226, 210)
	boxAt(hall, "TetoSalao", X0 + 2, F + H - 0.4, ZF + 2, X1 - 2, F + H, -48, TC, Enum.Material.Plaster)
	boxAt(hall, "TetoSalao", X0 + 2, F + H - 0.4, -24, X1 - 2, F + H, ZS, TC, Enum.Material.Plaster)
	boxAt(hall, "TetoSalao", X0 + 2, F + H - 0.4, -48, -12, F + H, -24, TC, Enum.Material.Plaster)
	boxAt(hall, "TetoSalao", 12, F + H - 0.4, -48, X1 - 2, F + H, -24, TC, Enum.Material.Plaster)
	buildGrandHall(hall)
end

---------------------------------------------------------------------------
-- Área restrita: corredor, sala de segurança, diretoria/arquivo, antecâmara
---------------------------------------------------------------------------

local function steelDoor(name, x0, x1, z0, z1, h, color)
	local d = boxAt(bank, name, x0, F, z0, x1, F + h, z1, color or STEEL, Enum.Material.Metal)
	d:SetAttribute("Home", d.CFrame)
	return d
end

local function buildRestricted(rest)
	local CH = 16 -- pé-direito da área restrita
	boxAt(rest, "TetoRestrita", X0 + 2, F + CH, ZS + 2, X1 - 2, F + CH + 1, ZB, Color3.fromRGB(200, 200, 196), Enum.Material.Plaster)
	-- paredes internas: corredor (x de -20 a 20, z de -6 a 4) e antecâmara (z de 4 a 24)
	wall(rest, "ParedeCorredor", "z", ZS + 2, 24, F, F + CH, -21, -20, { { -2, 2, F, F + 9 } }, Color3.fromRGB(226, 222, 212), Enum.Material.Plaster)
	wall(rest, "ParedeCorredor", "z", ZS + 2, 24, F, F + CH, 20, 21, { { -2, 2, F, F + 9 } }, Color3.fromRGB(226, 222, 212), Enum.Material.Plaster)
	wall(rest, "ParedeAntecamara", "x", -20, 20, F, F + CH, 4, 5, { { -6, 6, F, F + 10 } }, STEEL_DARK, Enum.Material.DiamondPlate)
	-- piso de chapa na antecâmara, luz vermelha girando (decor) e listras de segurança
	boxAt(rest, "PisoAntecamara", -20, F, 5, 20, F + 0.1, 11, STEEL_DARK, Enum.Material.DiamondPlate, { collide = false })
	for x = -6, 6, 2 do
		boxAt(rest, "Listra", x - 0.5, F + 0.1, 5.2, x + 0.5, F + 0.14, 6.2, Color3.fromRGB(240, 200, 40), Enum.Material.SmoothPlastic, { collide = false })
	end
	for _, x in ipairs({ -12, 12 }) do
		local l = boxAt(rest, "LuzTeto", x - 2, F + CH - 0.3, 12, x + 2, F + CH, 16, Color3.fromRGB(240, 246, 255), NEON, { collide = false })
		light(l, 26, 1.1, Color3.fromRGB(230, 240, 255))
	end
	for _, p in ipairs({ { -40, 8 }, { 0, -1 }, { 40, 8 } }) do
		local l = boxAt(rest, "LuzTeto", p[1] - 2, F + CH - 0.3, p[2] - 2, p[1] + 2, F + CH, p[2] + 2, Color3.fromRGB(255, 246, 230), NEON, { collide = false })
		light(l, 30, 1)
	end
	-- porta de segurança (salão -> corredor) com leitor de crachá
	steelDoor("PortaSeguranca", -3, 3, ZS + 0.6, ZS + 1.4, 9, STEEL)
	local reader = boxAt(bank, "LeitorCartao", 3.6, F + 4, ZS - 0.3, 4.6, F + 5.6, ZS, BLACK, Enum.Material.SmoothPlastic)
	local led = boxAt(bank, "LedLeitor", 3.85, F + 5.2, ZS - 0.36, 4.35, F + 5.45, ZS - 0.3, Color3.fromRGB(230, 50, 50), NEON, { collide = false })
	led.CastShadow = false
	reader.CastShadow = false
	-- grade da antecâmara (sobe depois do controle duplo)
	local gate = Instance.new("Model")
	gate.Name = "GradeAntecamara"
	gate.Parent = bank
	for x = -5.5, 5.5, 1 do
		boxAt(gate, "Barra", x - 0.15, F, 4.35, x + 0.15, F + 10, 4.65, STEEL, Enum.Material.Metal)
	end
	boxAt(gate, "Travessa", -6, F + 4.8, 4.25, 6, F + 5.3, 4.75, STEEL_DARK, Enum.Material.Metal)
	boxAt(gate, "Travessa", -6, F + 9.4, 4.25, 6, F + 9.9, 4.75, STEEL_DARK, Enum.Material.Metal)
	-- chaves do controle duplo (longe uma da outra: precisa de 2 pessoas)
	-- Marco 10.25: as chaves ficam no CORREDOR, do lado de fora da grade que elas abrem (antes
	-- estavam atrás dela e só dava para girar pela parede). Longe uma da outra: precisa de 2 pessoas.
	for _, k in ipairs({ { "ChaveA", -14 }, { "ChaveB", 14 } }) do
		local panel = boxAt(bank, k[1], k[2] - 2, F + 4, 3.6, k[2] + 2, F + 7, 4, STEEL_DARK, Enum.Material.Metal)
		boxAt(rest, "Fechadura", k[2] - 0.4, F + 5.2, 3.3, k[2] + 0.4, F + 5.8, 3.6, GOLD, Enum.Material.Metal, { collide = false })
		local led2 = boxAt(rest, "Led" .. k[1], k[2] - 0.2, F + 6.3, 3.5, k[2] + 0.2, F + 6.6, 3.6, Color3.fromRGB(230, 50, 50), NEON, { collide = false })
		led2:SetAttribute("Chave", k[1])
		local sgn = boxAt(rest, "PlacaChave", k[2] - 1.6, F + 7.4, 3.9, k[2] + 1.6, F + 8.6, 4, BLACK, Enum.Material.SmoothPlastic, { collide = false })
		text(sgn, Enum.NormalId.Front, k[1] == "ChaveA" and "CHAVE 1" or "CHAVE 2", Color3.fromRGB(255, 210, 80), Enum.Font.Code)
		panel.CastShadow = false
	end

	-- SALA DE SEGURANÇA (leste): monitores, terminal, armário
	for i = 1, 6 do
		local row = (i - 1) // 3
		local col = (i - 1) % 3
		local m = boxAt(bank, "Monitor", 57.2, F + 6 + row * 3.4, 0 + col * 5, 57.6, F + 9 + row * 3.4, 4.4 + col * 5, Color3.fromRGB(20, 40, 30), NEON, { collide = false })
		m:SetAttribute("Cam", i)
		text(m, Enum.NormalId.Left, "CAM " .. i .. "\n● REC", Color3.fromRGB(120, 255, 150), Enum.Font.Code)
	end
	boxAt(rest, "MesaSeguranca", 48, F, 0, 54, F + 3, 14, Color3.fromRGB(60, 62, 70), Enum.Material.Metal)
	local term = boxAt(bank, "TerminalSeguranca", 50, F + 3, 6, 51, F + 5.4, 9, BLACK, Enum.Material.SmoothPlastic)
	text(term, Enum.NormalId.Left, "🔒 SISTEMA\nVÉRTICE SEC 5", Color3.fromRGB(120, 200, 255), Enum.Font.Code)
	local chair = boxAt(rest, "CadeiraSeguranca", 44.5, F + 1.8, 0.5, 46.5, F + 2.3, 2.5, BLACK, Enum.Material.Fabric, { class = "Seat" })
	chair:SetAttribute("SeatText", "Sentar")
	-- Marco 10.24: os 2 primeiros armários tampavam a porta da sala (z de -2 a 2): começam depois dela
	for z = 4, 20, 4 do
		boxAt(rest, "Armario", 22, F, z, 25, F + 8, z + 3.6, STEEL, Enum.Material.Metal)
	end
	local ssign = boxAt(rest, "PlacaSeguranca", 21, F + 9.5, -2, 21.1, F + 11, 2, BLACK, Enum.Material.SmoothPlastic, { collide = false })
	text(ssign, Enum.NormalId.Right, "SEGURANÇA", WHITE, Enum.Font.GothamBold)
	-- saída de serviço (parede leste, x = 60, z de 14 a 20): porta e a trava magnética
	local exitDoor = boxAt(bank, "SaidaServico", X1 - 1.6, F, 14, X1 - 0.6, F + 9, 20, STEEL, Enum.Material.Metal, { transparency = 0, collide = true })
	exitDoor:SetAttribute("Home", exitDoor.CFrame)
	boxAt(bank, "TravaServico", X1 - 2.1, F + 7, 13.2, X1 - 1.6, F + 8, 14, Color3.fromRGB(230, 50, 50), NEON, { collide = false })
	local es = boxAt(rest, "PlacaSaida", X1 - 2.2, F + 9.6, 15, X1 - 2.1, F + 10.8, 19, Color3.fromRGB(30, 140, 60), NEON, { collide = false })
	text(es, Enum.NormalId.Left, "SAÍDA", WHITE, Enum.Font.GothamBold)
	-- escadinha da saída até o chão do beco
	for i = 1, 4 do
		boxAt(rest, "DegrauServico", X1 + 0.6, G, 13.5, X1 + 0.6 + (5 - i) * 1.4, G + i, 20.5, Color3.fromRGB(150, 150, 150), Enum.Material.Concrete)
	end

	-- DIRETORIA / ARQUIVO (oeste): mesa, arquivos, terminal antigo, cofre do diretor
	boxAt(rest, "MesaDiretor", -44, F, 2, -36, F + 3, 6, WOOD_DARK, Enum.Material.Wood)
	local dchair = boxAt(rest, "CadeiraDiretor", -41, F + 1.8, 7, -39, F + 2.3, 9, Color3.fromRGB(110, 30, 30), Enum.Material.Leather, { class = "Seat" })
	dchair:SetAttribute("SeatText", "Sentar")
	for x = -56, -46, 3.4 do
		for z = 14, 22, 8 do
			boxAt(rest, "Arquivo", x, F, z - 1.2, x + 3, F + 7, z + 1.2, Color3.fromRGB(150, 140, 120), Enum.Material.Metal)
		end
	end
	boxAt(rest, "MesaRetro", -30, F, 16, -24, F + 3, 22, Color3.fromRGB(150, 130, 100), Enum.Material.Wood)
	local retro = boxAt(bank, "TerminalRetro", -28.5, F + 3, 18, -25.5, F + 5.8, 20.6, Color3.fromRGB(214, 204, 176), Enum.Material.SmoothPlastic)
	text(retro, Enum.NormalId.Front, "C:\\>_", Color3.fromRGB(80, 255, 120), Enum.Font.Code, Color3.fromRGB(10, 20, 10))
	local safe = boxAt(bank, "CofreDiretor", -57.6, F, -3, -54, F + 4.5, 1, Color3.fromRGB(40, 44, 50), Enum.Material.Metal)
	boxAt(rest, "VolanteDiretor", -54, F + 2, -1.6, -53.7, F + 3, -0.6, GOLD, Enum.Material.Metal, { collide = false })
	safe:SetAttribute("Aberto", false)
	local dsign = boxAt(rest, "PlacaDiretoria", -21.1, F + 9.5, -2, -21, F + 11, 2, BLACK, Enum.Material.SmoothPlastic, { collide = false })
	text(dsign, Enum.NormalId.Left, "DIRETORIA", WHITE, Enum.Font.GothamBold)
	-- armário embaixo da janela da reforma (para sair por ela)
	boxAt(rest, "ArmarioJanela", -57.8, F, 4.5, -55, F + 3.2, 11.5, Color3.fromRGB(150, 140, 120), Enum.Material.Metal)
	local jan = Instance.new("Model")
	jan.Name = "JanelaReforma"
	jan.Parent = bank
	windowPane(jan, "z", 5.5, 10.5, F + 5, F + 11, X0 + 1, -1)
	for z = 6, 10, 1 do
		boxAt(jan, "Grade", X0 - 0.3, F + 5, z - 0.1, X0 - 0.1, F + 11, z + 0.1, STEEL_DARK, Enum.Material.Metal)
	end
	-- caixa invisível que segura a janela fechada (o serviço tira no evento)
	boxAt(jan, "Bloqueio", X0, F + 5, 5.5, X0 + 2, F + 11, 10.5, WHITE, nil, { transparency = 1 })
end

---------------------------------------------------------------------------
-- Marco 10.25: escada, antessala dos lasers e túnel de fuga (subsolo)
---------------------------------------------------------------------------

local function buildUnderground(rest)
	local CONC = Color3.fromRGB(120, 122, 126)
	local CONC2 = Color3.fromRGB(92, 94, 100)
	local M = Enum.Material.Concrete
	local TOP = VF + 16
	-- paredes do poço da escada e da antessala (o topo fica embaixo do piso, para não brigar com ele)
	local WALLTOP = F - 0.2
	boxAt(rest, "PocoEscada", -21, VF, 10, 21, WALLTOP, 11, CONC, M)
	boxAt(rest, "PisoSubsolo", -21, VF - 0.6, 10, 21, VF, 42.5, CONC2, Enum.Material.DiamondPlate)
	wall(rest, "PocoEscada", "z", 10, 42, VF, WALLTOP, -21, -20, { { 30, 35, VF, VF + 9 } }, CONC, M)
	boxAt(rest, "PocoEscada", 20, VF, 10, 21, WALLTOP, 42, CONC, M)
	boxAt(rest, "TetoSubsolo", -21, TOP, 22, 21, TOP + 0.2, 42, CONC2, M)
	-- fim do poço (z = 22): a passagem para a antessala fica no pé da escada, no oeste
	boxAt(rest, "ParedeSubsolo", -13, VF, 22, 20, WALLTOP, 23, CONC, M)
	boxAt(rest, "ParedeSubsolo", -20, VF + 10, 22, -13, WALLTOP, 23, CONC, M)
	-- Marco 10.26: escada refeita. Degraus maciços até o chão (antes eram tábuas soltas no ar), lances
	-- mais largos, patamar de verdade na curva, faixa de segurança em cada degrau e corrimão.
	local X0S, X1S = -16, 14 -- onde os lances começam e terminam
	local RUN, RISE = (X1S - X0S) / 22, 0.5
	local EDGE = Color3.fromRGB(240, 200, 40)
	-- 1º lance (z de 11 a 16,4): do térreo para o leste
	for i = 1, 22 do
		local top = F - i * RISE
		boxAt(rest, "DegrauSubsolo", X0S + (i - 1) * RUN, VF, 11, X0S + i * RUN, top, 16.4, CONC, M)
		boxAt(rest, "FaixaDegrau", X0S + (i - 1) * RUN, top, 11, X0S + (i - 1) * RUN + 0.18, top + 0.04, 16.4, EDGE, Enum.Material.SmoothPlastic, { collide = false, shadow = false })
	end
	-- patamar: toda a largura do poço, no meio da descida
	boxAt(rest, "PatamarSubsolo", X1S, VF, 11, 20, F - 11, 22, CONC2, Enum.Material.DiamondPlate)
	-- 2º lance (z de 16,6 a 22): volta para o oeste até o piso do subsolo
	for i = 1, 22 do
		local top = F - 11 - i * RISE
		boxAt(rest, "DegrauSubsolo", X1S - i * RUN, VF, 16.6, X1S - (i - 1) * RUN, top, 22, CONC, M)
		boxAt(rest, "FaixaDegrau", X1S - (i - 1) * RUN - 0.18, top, 16.6, X1S - (i - 1) * RUN, top + 0.04, 22, EDGE, Enum.Material.SmoothPlastic, { collide = false, shadow = false })
	end
	-- muro entre os lances, com corrimão em cima
	boxAt(rest, "EntreLances", X0S, VF, 16.4, X1S, F + 3, 16.6, CONC2, M)
	boxAt(rest, "CorrimaoSubsolo", X0S, F + 3, 16.3, X1S, F + 3.3, 16.7, STEEL_DARK, Enum.Material.Metal)
	-- corrimão do térreo: o vão só fica aberto na entrada da escada
	boxAt(rest, "GuardaCorpo", -8, F, 10.85, 20, F + 3.3, 11, STEEL_DARK, Enum.Material.Metal)
	boxAt(rest, "GuardaCorpo", -20, F, 16.4, X0S, F + 3.3, 16.6, STEEL_DARK, Enum.Material.Metal)
	-- piso do térreo até o primeiro degrau; o vão de cima do 2º lance fica fechado
	boxAt(rest, "CantoEscada", -20, F - 0.2, 11, X0S, F, 16.4, MARBLE, Enum.Material.Marble)
	boxAt(rest, "CantoEscada", -20, VF, 16.6, X0S, VF + 0.1, 22, CONC2, Enum.Material.DiamondPlate)
	local down = boxAt(rest, "PlacaSala", -19.9, F + 5, 7, -19.8, F + 7.4, 11, Color3.fromRGB(160, 30, 30), Enum.Material.SmoothPlastic, { collide = false, shadow = false })
	text(down, Enum.NormalId.Right, "⬇ SUBSOLO\nCOFRE", WHITE, Enum.Font.GothamBold)
	-- luzes: uma em cada lance, uma no patamar e duas na antessala
	for _, p in ipairs({ { 0, 13.7, F + 8, 0.8 }, { 17, 16.5, F - 3, 1.2 }, { 0, 19.3, VF + 14, 1.2 }, { 0, 27, TOP, 2 }, { 0, 38, TOP, 2 } }) do
		local l = boxAt(rest, "LuzTeto", p[1] - 3, p[3] - 0.3, p[2] - 0.5, p[1] + 3, p[3], p[2] + 0.5, Color3.fromRGB(230, 240, 255), NEON, { collide = false, shadow = false })
		light(l, 36, p[4], Color3.fromRGB(220, 232, 255))
	end
	-- listras de perigo e painel da trava de tempo, do lado da porta do cofre
	for x = -6, 6, 2 do
		boxAt(rest, "Listra", x - 0.5, VF, 40, x + 0.5, VF + 0.06, 41.6, Color3.fromRGB(240, 200, 40), Enum.Material.SmoothPlastic, { collide = false, shadow = false })
	end
	local tp = boxAt(bank, "PainelTempo", -12, VF + 6, 41.2, -8, VF + 9, 41.9, BLACK, Enum.Material.SmoothPlastic)
	text(tp, Enum.NormalId.Front, "TRAVA DE TEMPO\n🔒 ATIVA", Color3.fromRGB(255, 80, 80), Enum.Font.Code)
	-- quadro que corta os lasers (na entrada, antes das cortinas) e as 3 cortinas
	local box = boxAt(bank, "QuadroLaser", 18.6, VF + 3, 24, 20, VF + 7.5, 27, Color3.fromRGB(150, 30, 30), Enum.Material.Metal)
	text(box, Enum.NormalId.Left, "⚡ LASERS", WHITE, Enum.Font.GothamBold)
	local folder = Instance.new("Folder")
	folder.Name = "Lasers"
	folder.Parent = bank
	for i, z in ipairs({ 29, 33, 37 }) do
		local l = boxAt(folder, "Laser", -20, VF + 3, z - 0.08, 20, VF + 3.16, z + 0.08, Color3.fromRGB(255, 40, 40), NEON, { collide = false, shadow = false })
		l.CanQuery = false
		l.CanTouch = false
		l:SetAttribute("Index", i)
		l:SetAttribute("Base", lot:ToObjectSpace(l.CFrame))
	end
	-- parede frágil e túnel antigo do esgoto: do lado oeste da antessala até o bueiro no gramado
	local plug = boxAt(bank, "ParedeTunel", -21, VF, 30, -20, VF + 9, 35, Color3.fromRGB(104, 92, 84), Enum.Material.Brick)
	plug:SetAttribute("Home", plug.CFrame)
	local BRICK = Color3.fromRGB(72, 64, 58)
	boxAt(rest, "PisoTunel", -82, VF - 0.6, 29, -21, VF, 36, Color3.fromRGB(60, 62, 56), Enum.Material.Slate)
	boxAt(rest, "TetoTunel", -82, VF + 9, 29, -21, VF + 9.6, 36, BRICK, Enum.Material.Brick)
	boxAt(rest, "ParedeTunel2", -82, VF, 29, -21, VF + 9, 30, BRICK, Enum.Material.Brick)
	boxAt(rest, "ParedeTunel2", -82, VF, 35, -21, VF + 9, 36, BRICK, Enum.Material.Brick)
	boxAt(rest, "ParedeTunel2", -83, VF, 29, -82, VF + 9, 36, BRICK, Enum.Material.Brick)
	boxAt(rest, "AguaTunel", -82, VF, 31.5, -21, VF + 0.1, 33.5, Color3.fromRGB(70, 90, 70), Enum.Material.Glass, { collide = false, shadow = false, transparency = 0.3 })
	for x = -70, -30, 20 do
		local l = boxAt(rest, "LuzTunel", x - 0.4, VF + 8.6, 32, x + 0.4, VF + 9, 33, Color3.fromRGB(255, 220, 150), NEON, { collide = false, shadow = false })
		light(l, 24, 0.9, Color3.fromRGB(255, 210, 140))
	end
	local ladder = Instance.new("TrussPart")
	ladder.Anchored = true
	ladder.Size = Vector3.new(2, 9, 2)
	ladder.CFrame = at(-81, VF + 4.5, 32.5)
	ladder.Color = STEEL_DARK
	ladder.Material = Enum.Material.Metal
	ladder.Name = "EscadaBueiro"
	ladder.Parent = rest
	marker("SaidaTunel", at(-79, VF + 3, 32.5))
	local cover = P(rest, "Bueiro", Vector3.new(0.3, 5, 5), at(-81, G + 0.1, 32.5) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(44, 44, 48), Enum.Material.DiamondPlate, { shape = CYL, collide = false })
	cover.CastShadow = false
	marker("PontoBueiro", at(-77, G + 3, 32.5))
end

-- Marco 10.25: abre o buraco da escada no chão da cidade. O chão (Map > Ground) é uma placa só:
-- a placa que passa aqui vira 4 peças em volta do vão.
local function cutGround(map)
	local a = lot:PointToWorldSpace(Vector3.new(-20.5, 0, 10.5))
	local b = lot:PointToWorldSpace(Vector3.new(20.5, 0, 22.5))
	local hx0, hx1 = math.min(a.X, b.X), math.max(a.X, b.X)
	local hz0, hz1 = math.min(a.Z, b.Z), math.max(a.Z, b.Z)
	for _, g in ipairs(map:GetDescendants()) do
		if g:IsA("BasePart") and g.Name == "Ground" then
			local c, s = g.Position, g.Size
			local x0, x1, z0, z1 = c.X - s.X / 2, c.X + s.X / 2, c.Z - s.Z / 2, c.Z + s.Z / 2
			if x0 < hx0 and x1 > hx1 and z0 < hz0 and z1 > hz1 then
				local function piece(px0, px1, pz0, pz1)
					local p = g:Clone()
					p.Size = Vector3.new(px1 - px0, s.Y, pz1 - pz0)
					p.CFrame = CFrame.new((px0 + px1) / 2, c.Y, (pz0 + pz1) / 2)
					p.Parent = g.Parent
				end
				piece(x0, x1, z0, hz0)
				piece(x0, x1, hz1, z1)
				piece(x0, hx0, hz0, hz1)
				piece(hx1, x1, hz0, hz1)
				g:Destroy()
				return true
			end
		end
	end
	warn("[BankBuilder] Não achei o chão para abrir a escada do subsolo.")
	return false
end

---------------------------------------------------------------------------
-- Marco 10.23: salas novas. Térreo: arquivo separado da diretoria e vestiário dos funcionários.
-- 2º andar (pelas galerias do salão): corredor, sala de reuniões, presidência e copa.
---------------------------------------------------------------------------

local function buildRooms(rest)
	local WALL = Color3.fromRGB(226, 222, 212)
	local PLASTER = Enum.Material.Plaster
	local Y2, TOP = F + 20, F + 33.6
	local function sign(x0, x1, y, z, str)
		local s = boxAt(rest, "PlacaSala", x0, y, z - 0.1, x1, y + 1.4, z, NAVY, Enum.Material.SmoothPlastic, { collide = false, shadow = false })
		text(s, Enum.NormalId.Front, str, Color3.fromRGB(240, 220, 160), Enum.Font.GothamBold)
	end
	local function ceilingLight(x, z, y)
		local l = boxAt(rest, "LuzTeto", x - 2, y - 0.3, z - 2, x + 2, y, z + 2, Color3.fromRGB(255, 246, 230), NEON, { collide = false, shadow = false })
		light(l, 34, 1)
	end
	local function seat(x, z, y, color)
		local c = boxAt(rest, "CadeiraSala", x - 1, y + 1.8, z - 1, x + 1, y + 2.3, z + 1, color or BLACK, Enum.Material.Fabric, { class = "Seat" })
		c:SetAttribute("SeatText", "Sentar")
	end

	-- ARQUIVO (térreo, atrás da diretoria)
	wall(rest, "ParedeArquivo", "x", X0 + 2, -21, F, F + 16, 11.6, 12.4, { { -36, -31, F, F + 9 } }, WALL, PLASTER)
	sign(-37, -30, F + 9.5, 11.6, "ARQUIVO")
	ceilingLight(-40, 17, F + 16)
	for _, x in ipairs({ -44, -38 }) do
		boxAt(rest, "EstanteArquivo", x, F, 19.5, x + 5, F + 8, 21.5, WOOD_DARK, Enum.Material.Wood)
		for k = 0, 2 do
			boxAt(rest, "CaixaArquivo", x + 0.3, F + 1 + k * 2.4, 19.3, x + 4.7, F + 2.8 + k * 2.4, 19.5, Color3.fromRGB(190, 170, 130), Enum.Material.Cardboard, { collide = false, shadow = false })
		end
	end

	-- VESTIÁRIO (térreo, atrás da sala de segurança; a saída de serviço continua livre)
	wall(rest, "ParedeVestiario", "x", 25, 47, F, F + 16, 12.6, 13.4, {}, WALL, PLASTER)
	wall(rest, "ParedeVestiario", "z", 13.4, 22, F, F + 16, 46, 47, { { 15, 19.5, F, F + 9 } }, WALL, PLASTER)
	local vs = boxAt(rest, "PlacaSala", 47, F + 9.5, 14.8, 47.1, F + 10.9, 19.7, NAVY, Enum.Material.SmoothPlastic, { collide = false, shadow = false })
	text(vs, Enum.NormalId.Right, "VESTIÁRIO", Color3.fromRGB(240, 220, 160), Enum.Font.GothamBold)
	ceilingLight(36, 17, F + 16)
	for x = 28, 44, 3 do
		boxAt(rest, "Armarinho", x, F, 20, x + 2.8, F + 8, 22, Color3.fromRGB(70, 90, 120), Enum.Material.Metal)
	end
	bench(rest, 35, 16, F, math.pi, 10)

	-- 2º ANDAR
	boxAt(rest, "Piso2", X0 + 2, F + 17, ZS + 2, X1 - 2, Y2, ZB - 2, MARBLE, Enum.Material.Marble)
	boxAt(rest, "Teto2", X0 + 2, TOP, ZS + 2, X1 - 2, F + H, ZB - 2, Color3.fromRGB(232, 226, 210), PLASTER)
	-- corredor (z de -6 a 2) com tapete, e parede das salas com uma porta para cada
	boxAt(rest, "TapeteCorredor", -56, Y2, -4, 56, Y2 + 0.08, 0, Color3.fromRGB(130, 30, 36), Enum.Material.Fabric, { collide = false, shadow = false })
	wall(rest, "ParedeSalas", "x", X0 + 2, X1 - 2, Y2, TOP, 2, 3, { { -43, -38, Y2, Y2 + 10 }, { -4, 4, Y2, Y2 + 10 }, { 38, 43, Y2, Y2 + 10 } }, WALL, PLASTER)
	boxAt(rest, "LambriCorredor", X0 + 2, Y2, 1.8, -43, Y2 + 3, 2, MARBLE_DARK, Enum.Material.Marble, { collide = false, shadow = false })
	boxAt(rest, "LambriCorredor", -38, Y2, 1.8, -4, Y2 + 3, 2, MARBLE_DARK, Enum.Material.Marble, { collide = false, shadow = false })
	boxAt(rest, "LambriCorredor", 4, Y2, 1.8, 38, Y2 + 3, 2, MARBLE_DARK, Enum.Material.Marble, { collide = false, shadow = false })
	boxAt(rest, "LambriCorredor", 43, Y2, 1.8, X1 - 2, Y2 + 3, 2, MARBLE_DARK, Enum.Material.Marble, { collide = false, shadow = false })
	sign(-44.5, -36.5, Y2 + 10.4, 2, "SALA DE REUNIÕES")
	sign(-6, 6, Y2 + 10.4, 2, "PRESIDÊNCIA")
	sign(36.5, 44.5, Y2 + 10.4, 2, "COPA")
	for _, x in ipairs({ -40, 0, 40 }) do
		ceilingLight(x, -2, TOP)
	end
	for _, x in ipairs({ -22, 22 }) do
		plant(rest, x, 0.5, Y2)
	end
	-- paredes entre as salas
	wall(rest, "ParedeSalas", "z", 3, ZB - 2, Y2, TOP, -22, -21, {}, WALL, PLASTER)
	wall(rest, "ParedeSalas", "z", 3, ZB - 2, Y2, TOP, 21, 22, {}, WALL, PLASTER)

	-- SALA DE REUNIÕES (oeste): mesa comprida, cadeiras, telão
	ceilingLight(-40, 12, TOP)
	boxAt(rest, "MesaReuniao", -50, Y2 + 2.6, 9, -30, Y2 + 3.1, 15, WOOD, Enum.Material.Wood)
	for _, x in ipairs({ -47, -33 }) do
		boxAt(rest, "PeMesa", x - 0.6, Y2, 11.4, x + 0.6, Y2 + 2.6, 12.6, WOOD_DARK, Enum.Material.Wood)
	end
	for x = -47, -33, 7 do
		seat(x, 7.5, Y2)
		seat(x, 16.5, Y2)
	end
	local tv = boxAt(rest, "Telao", -56.6, Y2 + 4, 7, -56.3, Y2 + 10, 17, Color3.fromRGB(16, 22, 40), Enum.Material.SmoothPlastic, { collide = false })
	text(tv, Enum.NormalId.Right, "RESULTADO DO TRIMESTRE\n▲ 12%", Color3.fromRGB(120, 220, 160), Enum.Font.GothamBold)
	plant(rest, -25, 19, Y2)

	-- PRESIDÊNCIA (meio): tapete, mesa grande, estantes, bandeiras, poltronas
	ceilingLight(0, 12, TOP)
	boxAt(rest, "TapetePresidencia", -14, Y2, 6, 14, Y2 + 0.08, 20, Color3.fromRGB(24, 44, 92), Enum.Material.Fabric, { collide = false, shadow = false })
	boxAt(rest, "MesaPresidente", -7, Y2 + 0.08, 12, 7, Y2 + 3.2, 16, WOOD_DARK, Enum.Material.Wood)
	boxAt(rest, "TampoPresidente", -7.3, Y2 + 3.2, 11.7, 7.3, Y2 + 3.5, 16.3, MARBLE_DARK, Enum.Material.Marble)
	boxAt(rest, "ComputadorPresidente", -1.5, Y2 + 3.5, 14.5, 1.5, Y2 + 5.5, 14.8, BLACK, Enum.Material.SmoothPlastic)
	seat(0, 18, Y2 + 0.08, Color3.fromRGB(110, 30, 30))
	seat(-4, 9, Y2 + 0.08, Color3.fromRGB(70, 44, 28))
	seat(4, 9, Y2 + 0.08, Color3.fromRGB(70, 44, 28))
	for x = -20, 12, 8 do
		if x ~= -4 then
			boxAt(rest, "Estante", x, Y2, 20.4, x + 7.6, Y2 + 11, 22, WOOD_DARK, Enum.Material.Wood)
			for k = 1, 3 do
				boxAt(rest, "Livros", x + 0.4, Y2 + k * 2.6, 20.2, x + 7.2, Y2 + k * 2.6 + 1.8, 20.4, ({ Color3.fromRGB(120, 40, 40), Color3.fromRGB(40, 70, 110), Color3.fromRGB(50, 100, 70) })[k], Enum.Material.SmoothPlastic, { collide = false, shadow = false })
			end
		end
	end
	for i, x in ipairs({ -11, 11 }) do
		boxAt(rest, "MastroSala", x - 0.15, Y2, 19.5, x + 0.15, Y2 + 9, 19.8, GOLD, Enum.Material.Metal, { collide = false })
		boxAt(rest, "BandeiraSala", x + 0.15, Y2 + 5.5, 19.6, x + 3, Y2 + 8.5, 19.7, i == 1 and NAVY or Color3.fromRGB(28, 120, 70), Enum.Material.Fabric, { collide = false, shadow = false })
	end

	-- COPA (leste): balcão, geladeira, cafeteira, mesas
	ceilingLight(40, 12, TOP)
	boxAt(rest, "BalcaoCopa", 24, Y2, 18, 56, Y2 + 3.2, 22, Color3.fromRGB(120, 124, 132), Enum.Material.Metal)
	boxAt(rest, "TampoCopa", 24, Y2 + 3.2, 17.8, 56, Y2 + 3.5, 22, MARBLE_DARK, Enum.Material.Marble)
	boxAt(rest, "Geladeira", 50, Y2 + 3.5, 19.5, 55, Y2 + 11, 22, Color3.fromRGB(230, 232, 236), Enum.Material.SmoothPlastic)
	boxAt(rest, "Cafeteira", 30, Y2 + 3.5, 19.5, 32, Y2 + 6, 21, BLACK, Enum.Material.SmoothPlastic)
	boxAt(rest, "Microondas", 36, Y2 + 3.5, 19.5, 40, Y2 + 6, 22, Color3.fromRGB(70, 74, 82), Enum.Material.Metal)
	for _, c in ipairs({ { 31, 10 }, { 49, 10 } }) do
		P(rest, "MesaCopa", Vector3.new(0.4, 7, 7), at(c[1], Y2 + 2.8, c[2]) * CFrame.Angles(0, 0, math.rad(90)), WHITE, Enum.Material.SmoothPlastic, { shape = CYL })
		boxAt(rest, "PeMesa", c[1] - 0.3, Y2, c[2] - 0.3, c[1] + 0.3, Y2 + 2.6, c[2] + 0.3, STEEL_DARK, Enum.Material.Metal)
		seat(c[1] - 4.5, c[2], Y2)
		seat(c[1] + 4.5, c[2], Y2)
	end
end

---------------------------------------------------------------------------
-- Cofre: modelo 3D (ServerStorage > BankModels > CofreBanco) ou de peças
---------------------------------------------------------------------------

local function findPart(root, name)
	local d = root:FindFirstChild(name, true)
	if d and d:IsA("BasePart") then
		return d
	end
	if d then
		for _, x in ipairs(d:GetDescendants()) do
			if x:IsA("BasePart") then
				return x
			end
		end
	end
	return nil
end

local function frameOf(a, b, c)
	local e1 = (b - a).Unit
	local e3 = e1:Cross(c - a).Unit
	local e2 = e3:Cross(e1)
	return CFrame.fromMatrix(a, e1, e2, e3)
end

-- devolve (Model, {porta, moldura, sala, modulo}) já posicionado, ou nil se não tem o modelo
local function placeVaultModel(parent)
	local folder = ServerStorage:FindFirstChild("BankModels")
	local src = folder and folder:FindFirstChild("CofreBanco")
	if not src then
		warn("[BankBuilder] ServerStorage > BankModels > CofreBanco não encontrado: montando o cofre de peças (veja o GUIA do Marco 10.20).")
		return nil
	end
	local m = src:Clone()
	if not m:IsA("Model") then
		local holder = Instance.new("Model")
		m.Parent = holder
		m = holder
	end
	local fm, pd, porta = findPart(m, "FrontMarker"), findPart(m, "PivotDoor"), findPart(m, "Porta_Aco")
	if not (fm and pd and porta) then
		warn("[BankBuilder] CofreBanco sem FrontMarker/PivotDoor/Porta_Aco: montando o cofre de peças.")
		m:Destroy()
		return nil
	end
	-- escala: a distância entre os marcadores tem que bater com o arquivo
	local want = (GLB.front - GLB.hinge).Magnitude
	local have = (fm.Position - pd.Position).Magnitude
	if have > 0.01 and math.abs(have / want - 1) > 0.01 then
		m:ScaleTo(m:GetScale() * want / have)
	end
	-- transformação do arquivo -> Studio (por 3 pontos) e do arquivo -> lote
	local imported = frameOf(fm.Position, pd.Position, porta.Position)
	local file = frameOf(GLB.front, GLB.hinge, GLB.porta)
	local toImported = imported * file:Inverse()
	local target = lot * CFrame.new(0, F, VAULT_OFFZ) * CFrame.Angles(0, math.pi, 0)
	local move = target * toImported:Inverse()
	local parts = {}
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CFrame = move * d.CFrame
			d.Anchored = true
		end
	end
	parts.porta = porta
	parts.moldura = findPart(m, "Moldura_Aco")
	parts.sala = findPart(m, "Sala_Concreto")
	parts.modulo = findPart(m, "Cofrinhos_Latao")
	parts.hinge = pd.Position
	fm:Destroy()
	pd:Destroy()
	m.Name = "Cofre3D"
	m.Parent = parent
	return m, parts
end

local function styleVault(parts)
	local function st(p, color, material, collide, refl)
		if p then
			p.Color = color
			p.Material = material
			p.CanCollide = collide
			p.Reflectance = refl or 0
			if p:IsA("MeshPart") then
				p.TextureID = ""
			end
			for _, c in ipairs(p:GetChildren()) do
				if c:IsA("SurfaceAppearance") then
					c:Destroy()
				end
			end
		end
	end
	st(parts.porta, Color3.fromRGB(150, 154, 162), Enum.Material.Metal, true, 0.08)
	st(parts.moldura, Color3.fromRGB(128, 132, 140), Enum.Material.Metal, false, 0.05)
	st(parts.sala, Color3.fromRGB(150, 146, 138), Enum.Material.Concrete, false)
	st(parts.modulo, Color3.fromRGB(176, 142, 72), Enum.Material.Metal, true, 0.06)
end

local function moneyStack(parent, name, cf, layers, gold)
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	P(m, "Palete", Vector3.new(6, 0.8, 4.4), cf * CFrame.new(0, 0.4, 0), Color3.fromRGB(150, 116, 74), Enum.Material.WoodPlanks)
	for i = 1, layers do
		local layer = Instance.new("Model")
		layer.Name = "Camada" .. i
		layer.Parent = m
		local y = 0.8 + (i - 0.5) * (gold and 0.75 or 1.1)
		if gold then
			for bx = -2, 2 do
				for bz = -1, 1, 2 do
					local bar = P(layer, "Barra", Vector3.new(0.9, 0.6, 1.8), cf * CFrame.new(bx * 1.05, y, bz * 1) * CFrame.Angles(0, (i % 2) * math.rad(90) * 0, 0), GOLD, Enum.Material.Metal, { collide = false, reflectance = 0.25 })
					bar.CastShadow = false
				end
			end
		else
			for bx = -1, 1 do
				for bz = -1, 1, 2 do
					P(layer, "Maco", Vector3.new(1.7, 1, 1.9), cf * CFrame.new(bx * 1.85, y, bz * 1.05), MONEY, Enum.Material.Fabric, { collide = false })
					P(layer, "Cinta", Vector3.new(0.35, 1.04, 1.94), cf * CFrame.new(bx * 1.85, y, bz * 1.05), MONEY_BAND, Enum.Material.Fabric, { collide = false, shadow = false })
				end
			end
		end
	end
	-- peça para o botão (invisível, por cima)
	local hit = P(m, "Botao", Vector3.new(5.6, 1, 4), cf * CFrame.new(0, 0.8 + layers * (gold and 0.75 or 1.1) + 0.5, 0), WHITE, nil, { transparency = 1, collide = false })
	hit.CanQuery = false
	m:SetAttribute("Camadas", layers)
	return m
end

local function buildVault(vault)
	local m, parts = placeVaultModel(vault)
	local hingeLocal
	local doorModel = Instance.new("Model")
	doorModel.Name = "PortaCofre"
	doorModel.Parent = bank
	-- colisão (invisível) da sala: chão, paredes e teto; parede da frente com o vão da porta
	local CY = F + 15.15
	local function coll(name, ...)
		local p = boxAt(vault, name, ...)
		p.Transparency = m and 1 or 0
		p.Color = Color3.fromRGB(150, 146, 138)
		p.Material = Enum.Material.Concrete
		return p
	end
	coll("ChaoCofre", -41.4, F, 24.6, 41.4, F + VAULT_FLOOR, 100)
	coll("ParedeCofre", -41.6, F, 24.6, -40.3, CY, 100)
	coll("ParedeCofre", 40.3, F, 24.6, 41.6, CY, 100)
	coll("ParedeCofre", -41.6, F, 99.4, 41.6, CY, 100.1)
	-- Marco 10.25: o teto fica visível (no subsolo, sem o bloco em volta, aparecia o gramado)
	coll("TetoCofre", -41.6, CY, 24, 41.6, F + 16.2, 100.1).Transparency = 0
	local hy0, hy1 = F + HOLE_Y - HOLE_R, F + HOLE_Y + HOLE_R
	coll("FrenteCofre", -41.6, F, 23.95, -HOLE_R, CY, 24.7)
	coll("FrenteCofre", HOLE_R, F, 23.95, 41.6, CY, 24.7)
	coll("FrenteCofre", -HOLE_R, F, 23.95, HOLE_R, hy0, 24.7)
	coll("FrenteCofre", -HOLE_R, hy1, 23.95, HOLE_R, CY, 24.7)
	-- degraus até o vão (dos dois lados)
	for i, y in ipairs({ 1.2, 2.4 }) do
		boxAt(vault, "DegrauCofre", -4, F, 24 - 5 + (i - 1) * 2.5, 4, F + y, 24 - 5 + i * 2.5, STEEL_DARK, Enum.Material.DiamondPlate)
		boxAt(vault, "DegrauCofre", -4, F, 24.7 + 5 - i * 2.5, 4, F + VAULT_FLOOR + y, 24.7 + 5 - (i - 1) * 2.5, STEEL_DARK, Enum.Material.DiamondPlate)
	end
	boxAt(vault, "Soleira", -4, F, 23.95, 4, hy0, 24.7, STEEL, Enum.Material.Metal)
	local block = boxAt(bank, "BloqueioCofre", -HOLE_R, hy0, 23.4, HOLE_R, hy1, 24.0, WHITE, nil, { transparency = 1 })
	block.CanCollide = true
	if m then
		styleVault(parts)
		parts.porta.Parent = doorModel
		hingeLocal = lot:PointToObjectSpace(parts.hinge)
		-- cofrinhos: o módulo original e cópias pelas paredes do fundo e dos lados
		local mod = parts.modulo
		if mod then
			local L0 = lot:ToObjectSpace(mod.CFrame)
			local rot = L0.Rotation
			local size = mod.Size
			local function clone(cf)
				local c = mod:Clone()
				c.CFrame = lot * cf
				c.Parent = vault
			end
			for _, dx in ipairs({ -16.4, -32.8, -49.2 }) do
				clone(CFrame.new(dx, 0, 0) * L0)
			end
			for _, s in ipairs({ -1, 1 }) do
				for _, z in ipairs({ 40, 56.4, 72.8 }) do
					clone(CFrame.new(s * (40.2 - size.Z / 2), L0.Y, z) * CFrame.Angles(0, s * math.rad(90), 0) * rot)
				end
			end
		end
	else
		-- cofre de peças (sem o modelo 3D): porta redonda de aço e um volante
		local center = at(0, F + HOLE_Y, 25.2)
		P(doorModel, "Porta", Vector3.new(2.8, HOLE_R * 2 + 0.6, HOLE_R * 2 + 0.6), center * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(150, 154, 162), Enum.Material.Metal, { shape = CYL, reflectance = 0.08 })
		for k = 0, 3 do
			P(doorModel, "Raio", Vector3.new(0.4, 6, 0.4), at(0, F + HOLE_Y, 23.4) * CFrame.Angles(0, 0, math.rad(k * 45)), GOLD, Enum.Material.Metal, { collide = false })
		end
		hingeLocal = Vector3.new(HOLE_R + 0.6, F, 23.9)
		for x = -40, 40, 10 do
			boxAt(vault, "PrateleiraCofrinhos", x - 4.6, F, 92, x + 4.6, F + 14, 99.4, Color3.fromRGB(176, 142, 72), Enum.Material.Metal)
		end
	end
	marker("PivotCofre", at(hingeLocal.X, F + HOLE_Y, hingeLocal.Z))
	marker("PontoFuradeira", at(0, F + HOLE_Y - 1, 21.5))
	-- luzes do cofre e enfeites
	for _, x in ipairs({ -24, 0, 24 }) do
		for _, z in ipairs({ 40, 64, 88 }) do
			local l = boxAt(vault, "LuzCofre", x - 1.5, F + 14.6, z - 0.6, x + 1.5, F + 15.1, z + 0.6, Color3.fromRGB(255, 248, 228), NEON, { collide = false })
			if z == 64 or x == 0 then
				light(l, 45, 2) -- Marco 10.25: no subsolo não entra luz de fora
			end
		end
	end
	-- dinheiro (6 pilhas) e ouro (2 paletes)
	local pilhas = Instance.new("Folder")
	pilhas.Name = "Pilhas"
	pilhas.Parent = bank
	local i = 0
	for _, z in ipairs({ 46, 64 }) do
		for _, x in ipairs({ -20, 0, 20 }) do
			i += 1
			local s = moneyStack(pilhas, "Pilha", at(x, F + VAULT_FLOOR, z), B.MoneyGrabs, false)
			s:SetAttribute("Index", i)
		end
	end
	local ouro = Instance.new("Folder")
	ouro.Name = "Ouro"
	ouro.Parent = bank
	for k, x in ipairs({ -10, 10 }) do
		local s = moneyStack(ouro, "Palete", at(x, F + VAULT_FLOOR, 82), B.GoldGrabs, true)
		s:SetAttribute("Index", k)
	end
	-- mesas de contagem
	for _, x in ipairs({ -27, 27 }) do
		boxAt(vault, "MesaContagem", x - 3, F + VAULT_FLOOR, 54, x + 3, F + VAULT_FLOOR + 3.2, 58, STEEL, Enum.Material.Metal)
		boxAt(vault, "MaquinaContar", x - 1, F + VAULT_FLOOR + 3.2, 55.2, x + 1, F + VAULT_FLOOR + 4.4, 56.8, Color3.fromRGB(60, 62, 70), Enum.Material.SmoothPlastic)
	end
	-- cofrinhos que dão para abrir (botões na frente das paredes de cofrinhos)
	local cof = Instance.new("Folder")
	cof.Name = "Cofrinhos"
	cof.Parent = bank
	local spots = {
		{ -31.4, 3, 44 }, { -31.4, 6, 60 }, { -31.4, 2, 76 },
		{ 31.4, 4, 42 }, { 31.4, 7, 58 }, { 31.4, 3, 74 },
		{ -28, 5, 90.5 }, { -6, 3, 90.5 }, { 12, 6, 90.5 }, { 26, 4, 90.5 },
	}
	for k, sp in ipairs(spots) do
		local box = boxAt(cof, "Cofrinho", sp[1] - 0.8, F + VAULT_FLOOR + sp[2], sp[3] - 0.8, sp[1] + 0.8, F + VAULT_FLOOR + sp[2] + 1.2, sp[3] + 0.8, Color3.fromRGB(176, 142, 72), Enum.Material.Metal, { transparency = 1, collide = false })
		box:SetAttribute("Index", k)
		box.CanQuery = false
		local open = boxAt(box, "Aberto", sp[1] - 0.7, F + VAULT_FLOOR + sp[2] + 0.1, sp[3] - 0.7, sp[1] + 0.7, F + VAULT_FLOOR + sp[2] + 1.1, sp[3] + 0.7, BLACK, Enum.Material.SmoothPlastic, { transparency = 1, collide = false })
		open.CanQuery = false
	end
	-- prateleira de malotes (evento Avalanche) atrás do ouro
	local rack = Instance.new("Model")
	rack.Name = "PrateleiraMalotes"
	rack.Parent = bank
	boxAt(rack, "Estrutura", -16, F + VAULT_FLOOR, 86.5, -4, F + VAULT_FLOOR + 9, 88.5, STEEL_DARK, Enum.Material.Metal)
	for k = 0, 3 do
		for x = -15, -5, 2.5 do
			P(rack, "Malote", Vector3.new(2, 1.6, 1.6), at(x, F + VAULT_FLOOR + 1.4 + k * 2.2, 87), Color3.fromRGB(70, 90, 140), Enum.Material.Fabric, { collide = false })
		end
	end
	-- alavanca de emergência (por dentro, perto da porta)
	local lever = boxAt(bank, "AlavancaEmergencia", 8, F + VAULT_FLOOR + 3, 25, 9, F + VAULT_FLOOR + 6, 25.6, Color3.fromRGB(220, 40, 40), Enum.Material.SmoothPlastic)
	lever.CastShadow = false
	local ls = boxAt(vault, "PlacaAlavanca", 7, F + VAULT_FLOOR + 6.4, 25, 10, F + VAULT_FLOOR + 7.4, 25.1, BLACK, Enum.Material.SmoothPlastic, { collide = false })
	text(ls, Enum.NormalId.Back, "EMERGÊNCIA", Color3.fromRGB(255, 220, 80), Enum.Font.GothamBold)
end

---------------------------------------------------------------------------
-- Fora: beco, transformador, doca, carro-forte, andaime
---------------------------------------------------------------------------

local function buildOutside(out)
	-- transformador (preparação: cortar energia e telefone)
	local tr = boxAt(bank, "Transformador", 66, G, 34, 72, G + 7, 40, Color3.fromRGB(90, 110, 90), Enum.Material.Metal)
	local warnSign = boxAt(out, "PlacaPerigo", 65.9, G + 4, 35.5, 66, G + 6, 38.5, Color3.fromRGB(240, 200, 40), Enum.Material.SmoothPlastic, { collide = false })
	text(warnSign, Enum.NormalId.Left, "⚡ PERIGO\nALTA TENSÃO", BLACK, Enum.Font.GothamBold)
	tr.CastShadow = true
	boxAt(out, "CercaTrafo", 64, G, 32, 64.3, G + 4, 42, STEEL, Enum.Material.DiamondPlate, { transparency = 0.4 })
	-- funcionário fumando no beco (preparação: crachá)
	marker("PontoFumante", at(66, G + 3, 26) * CFrame.Angles(0, math.rad(-90), 0))
	boxAt(out, "Lixeira", 74, G, 22, 78, G + 4, 26, Color3.fromRGB(40, 90, 50), Enum.Material.Metal)
	-- doca e carro-forte (enfeite)
	local van = Instance.new("Model")
	van.Name = "CarroForte"
	van.Parent = out
	boxAt(van, "Bau", 40, G + 1.6, 106, 50, G + 9, 122, Color3.fromRGB(235, 235, 235), Enum.Material.SmoothPlastic)
	boxAt(van, "Cabine", 40.4, G + 1.6, 102, 49.6, G + 7.5, 106, Color3.fromRGB(235, 235, 235), Enum.Material.SmoothPlastic)
	boxAt(van, "Parabrisa", 40.8, G + 4.5, 101.9, 49.2, G + 7, 102.1, BLACK, Enum.Material.Glass)
	local vs = boxAt(van, "LetreiroForte", 39.9, G + 4, 108, 40, G + 7, 120, NAVY, Enum.Material.SmoothPlastic, { collide = false })
	text(vs, Enum.NormalId.Left, "LLC VALORES", WHITE, Enum.Font.GothamBlack)
	for _, z in ipairs({ 105, 118 }) do
		for _, x in ipairs({ 40, 50 }) do
			P(van, "Roda", Vector3.new(1.2, 3.2, 3.2), at(x, G + 1.6, z), BLACK, Enum.Material.SmoothPlastic, { shape = CYL })
		end
	end
	boxAt(out, "PlataformaDoca", -20, G, VZ, 20, F, VZ + 6, Color3.fromRGB(150, 150, 150), Enum.Material.Concrete)
	-- andaime da reforma (evento B07): fica guardado e aparece no evento
	local sc = Instance.new("Model")
	sc.Name = "Andaime"
	sc.Parent = bank
	for _, x in ipairs({ -69, -62.5 }) do
		for _, z in ipairs({ 2, 14 }) do
			boxAt(sc, "Tubo", x - 0.25, G, z - 0.25, x + 0.25, F + 14, z + 0.25, Color3.fromRGB(190, 120, 40), Enum.Material.Metal)
		end
	end
	boxAt(sc, "Plataforma", -69.5, F + 4.4, 1.6, -60.4, F + 4.8, 14.4, Color3.fromRGB(150, 116, 74), Enum.Material.WoodPlanks)
	boxAt(sc, "Plataforma", -69.5, F + 11.4, 1.6, -60.4, F + 11.8, 14.4, Color3.fromRGB(150, 116, 74), Enum.Material.WoodPlanks)
	local truss = Instance.new("TrussPart")
	truss.Anchored = true
	truss.Size = Vector3.new(2, F + 4.8 - G, 2)
	truss.CFrame = at(-70.5, G + (F + 4.8 - G) / 2, 8)
	truss.Color = Color3.fromRGB(190, 120, 40)
	truss.Material = Enum.Material.Metal
	truss.Name = "Escada"
	truss.Parent = sc
	local tap = boxAt(sc, "Tapume", -75, G, -6, -74.6, G + 7, 22, Color3.fromRGB(40, 110, 170), Enum.Material.WoodPlanks)
	text(tap, Enum.NormalId.Left, "🚧 REFORMA DA FACHADA", WHITE, Enum.Font.GothamBold)
	for x = -72, -63, 3 do
		boxAt(sc, "Lona", x - 1.4, F + 4.8, 1.6, x + 1.4, F + 14, 1.7, Color3.fromRGB(40, 130, 70), Enum.Material.Fabric, { transparency = 0.35, collide = false })
	end
end

---------------------------------------------------------------------------

local function buildMarkers()
	-- áreas
	invisible(bank, "AreaSalao", X0 + 2, F - 1, ZF + 1.5, X1 - 2, F + H, ZS)
	invisible(bank, "AreaRestrita", X0 + 2, F - 1, ZS, X1 - 2, F + 16, ZB)
	invisible(bank, "AreaCofre", -41, VF - 1, 24.6 + VS, 41, VF + 16, 100 + VS)
	invisible(bank, "AreaSubsolo", -21, VF - 1, 10, 21, F, 42.5)
	invisible(bank, "AreaLote", -B.LotW / 2, VF - 3, -B.LotD / 2, B.LotW / 2, G + 60, B.LotD / 2)
	-- Marco 10.24: dentro do banco o céu é abaixado (LightingController), como no quartel e nas lojas
	invisible(bank, "ZonaInterna", X0, F - 1, ZF, X1, F + H + 1, ZB):SetAttribute("Indoor", true)
	invisible(bank, "ZonaInterna", -83, VF - 1, 10, VX, F - 1, 120):SetAttribute("Indoor", true)
	-- anúncio, NPCs
	marker("PontoAnuncio", at(0, F + 3, -52))
	marker("PontoSeguranca", at(-9, F + 3, -72) * CFrame.Angles(0, math.rad(180), 0))
	marker("PontoSeguranca2", at(-54.5, F + 23, -30) * CFrame.Angles(0, math.rad(-90), 0)) -- galeria oeste
	marker("PontoGerente", at(44, F + 3, -28) * CFrame.Angles(0, math.rad(-90), 0)) -- Marco 10.25: fora da cadeira (o "Sentar" roubava o E)
	marker("PontoCaixa1", at(-6, F + 3, -40) * CFrame.Angles(0, 0, 0))
	marker("PontoCaixa2", at(6, F + 3, -32) * CFrame.Angles(0, math.rad(180), 0))
	marker("PontoCliente1", at(-6, F + 3, -48) * CFrame.Angles(0, math.rad(180), 0))
	marker("PontoCliente2", at(-28, F + 3, -66))
	marker("PontoCliente3", at(28, F + 3, -66))
	marker("PontoVIP", at(36, F + 3, -46) * CFrame.Angles(0, math.rad(-90), 0))
	marker("PontoGuardaCosta", at(33, F + 3, -50) * CFrame.Angles(0, math.rad(-150), 0))
	marker("PontoSaida", at(0, F + 3, -84))
	marker("PontoRival", at(88, G + 3, 70))
	marker("PontoHeli", at(0, F + 90, -20))
	-- luzes de alarme (piscam no alarme)
	for _, p in ipairs({ { -50, -76.8 }, { 50, -76.8 }, { -50, ZS - 0.4 }, { 50, ZS - 0.4 }, { 0, 21.5 } }) do
		local l = boxAt(bank, "LuzAlarme", p[1] - 0.6, F + 14, p[2] - 0.3, p[1] + 0.6, F + 15, p[2] + 0.3, Color3.fromRGB(120, 30, 30), NEON, { collide = false })
		l.CastShadow = false
	end
end

-- Etapa 1 (antes do campo): reserva o lote na beira da Estrada do Vale
function BankBuilder.plan(map, helpers)
	K = helpers
	local R = GameConfig.Rodovia
	local exit = Vector3.new(0, 0, R.ExitZ)
	local a, b = exit, exit + Vector3.new(R.ExitLength, 0, 0)
	local cf = K.lotBeside(a, b, B.Road.T, B.Road.Side, B.LotD)
	local area = K.rect(cf, B.LotW + 8, B.LotD + 4)
	if not K.isFree(area) then
		warn("[BankBuilder] Sem espaço livre para o banco na " .. R.ValeName)
		return nil
	end
	K.occupy(area)
	return { lot = cf, map = map }
end

-- Etapa 2: monta o prédio
function BankBuilder.build(plan)
	if not plan then
		return nil
	end
	lot = plan.lot
	bank = K.model("Banco", plan.map)
	bank:SetAttribute("PlaceName", B.Name)
	local shell = K.model("Predio", bank)
	local hall = K.model("Salao", bank)
	local rest = K.model("Restrita", bank)
	local vault = K.model("Cofre", bank)
	local out = K.model("Fora", bank)
	buildShell(shell)
	buildHall(hall)
	buildRestricted(rest)
	buildRooms(rest)
	buildUnderground(rest)
	-- tudo do cofre sai VD abaixo e VS atrás
	local base = lot
	lot = base * CFrame.new(0, -VD, VS)
	buildVault(vault)
	lot = base
	cutGround(plan.map)
	buildOutside(out)
	buildMarkers()
	bank.WorldPivot = lot * CFrame.new(0, F, -20)
	CollectionService:AddTag(bank, "Banco")
	local n = 0
	for _, d in ipairs(bank:GetDescendants()) do
		if d:IsA("BasePart") then
			n += 1
		end
	end
	print(("[BankBuilder] %s montado com %d peças."):format(B.Name, n))
	return bank
end

return BankBuilder
