-- PrisonBuilder (ModuleScript)
-- Caminho: ServerScriptService > Services > PrisonBuilder
-- Marco 8: Penitenciária de Little Little Kinder, montada por script (chamada pelo MapBuilder).
-- Inspirada na planta que o Luís mandou, só que maior e com o nosso toque:
--   * cerca dupla com arame farpado em volta de tudo e 4 torres de vigia nos cantos (dá para subir);
--   * portal de entrada com o nome, guarita com cancela, estacionamento, caixa d'água e galpão;
--   * prédio da Administração e Visitas, ligado por uma passarela coberta à área de segurança;
--   * área de segurança com cerca própria, rua de ronda, 4 pavilhões de celas (dá para entrar),
--     um pátio de banho de sol para cada pavilhão (quadra de basquete, campinho, horta e academia),
--     refeitório e a torre de controle redonda no meio.
-- Marco 8.1 (pedidos do Luís): portas de grade que abrem nas celas e pavilhões, cercas mais altas,
-- Base da PM com 2 andares (porta com cartão: só policial), garagem de viaturas da polícia,
-- lavanderia, biblioteca, estações de tarefa do Presidiário, bancos para sentar e bolas de verdade.
-- Quem mexe nas portas, nas bolas e nos presos é o PrisonService; aqui é só a construção.
-- Coordenadas locais: (0, 0, 0) = centro no chão; -Z = lado da entrada (virado para a estrada).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))

local PrisonBuilder = {}

local PR = GameConfig.Prison
local HW, HD = PR.Width / 2, PR.Depth / 2 -- meia largura (x) e meia profundidade (z)

-- Cores: paredes claras com faixas cor de telha, como na planta, e telhado cinza
local WALL = Color3.fromRGB(242, 239, 232)
local TERRA = Color3.fromRGB(205, 105, 70)
local TERRA_DARK = Color3.fromRGB(170, 82, 55)
local ROOF = Color3.fromRGB(92, 97, 106)
local CONCRETE = Color3.fromRGB(184, 184, 178)
local PAVING = Color3.fromRGB(214, 208, 196)
local ASPHALT = Color3.fromRGB(62, 64, 68)
local METAL = Color3.fromRGB(105, 110, 118)
local STEEL = Color3.fromRGB(175, 180, 186)
local GLASS = Color3.fromRGB(150, 200, 230)
local FENCE = Color3.fromRGB(90, 95, 102)
local WOOD = Color3.fromRGB(150, 105, 65)
local WHITE = Color3.fromRGB(250, 250, 250)
local NAVY = Color3.fromRGB(35, 60, 110)
local LINE = Color3.fromRGB(245, 245, 240)

local K -- ferramentas do MapBuilder (makePart, model, addSurfaceText, buildTree, buildLamp, gableRoof)
local base -- CFrame do centro

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

-- Caixa com o centro da BASE em (x, y0, z), em coordenadas da prisão
local function box(parent, name, sx, sy, sz, x, y0, z, color, material, extra)
	return part(parent, name, Vector3.new(sx, sy, sz), at(x, y0 + sy / 2, z), color, material, extra)
end

-- Cilindro em pé: centro da base em (x, y0, z)
local function column(parent, name, x, y0, z, height, radius, color, material, extra)
	local e = { Shape = Enum.PartType.Cylinder }
	for k, v in pairs(extra or {}) do
		e[k] = v
	end
	return part(parent, name, Vector3.new(height, radius * 2, radius * 2), at(x, y0 + height / 2, z) * CFrame.Angles(0, 0, math.rad(90)), color, material, e)
end

-- Placa com texto. A frente do texto aponta para "facing" (vetor no espaço da prisão).
local function sign(parent, text, w, h, x, y, z, facing, textColor, bgColor)
	local p = base * CFrame.new(x, y, z)
	local look = base:VectorToWorldSpace(facing)
	local board = part(parent, "Placa", Vector3.new(w, h, 0.4), CFrame.lookAt(p.Position, p.Position + look), bgColor, Enum.Material.SmoothPlastic, { CanCollide = false })
	K.addSurfaceText(board, text, textColor, bgColor)
	return board
end

local function light(parent, range, brightness, color)
	local l = Instance.new("PointLight")
	l.Range = range
	l.Brightness = brightness
	l.Color = color or Color3.fromRGB(255, 245, 225)
	l.Shadows = false
	l.Parent = parent
	return l
end

-- Faixa colorida em volta de um prédio, só por fora das paredes (cf = centro do prédio no chão)
local function band(parent, cf, w, d, y0, h, color)
	for _, s in ipairs({ -1, 1 }) do
		part(parent, "Faixa", Vector3.new(w + 0.4, h, 0.2), cf * CFrame.new(0, y0 + h / 2, s * (d / 2 + 0.1)), color, Enum.Material.SmoothPlastic, { CanCollide = false })
		part(parent, "Faixa", Vector3.new(0.2, h, d + 0.4), cf * CFrame.new(s * (w / 2 + 0.1), y0 + h / 2, 0), color, Enum.Material.SmoothPlastic, { CanCollide = false })
	end
end

-- Banco de sentar (Seat): a pessoa senta virada para "facing" (vetor no espaço da prisão)
local function seat(parent, size, x, y, z, facing, color, text)
	local p = base * CFrame.new(x, y, z)
	local s = part(parent, "Assento", size, CFrame.lookAt(p.Position, p.Position + base:VectorToWorldSpace(facing)), color, Enum.Material.Fabric, { ClassName = "Seat" })
	s:SetAttribute("SeatText", text or "Banco")
	return s
end

-- Marca uma peça como estação de tarefa do Presidiário (o JobSiteBuilder registra)
local function station(p, name, text)
	p:SetAttribute("PrisonStation", name)
	p:SetAttribute("StationText", text)
	return p
end

-- Porta que abre girando na dobradiça (o PrisonService gira; aqui só monta).
-- hinge = posição da dobradiça no chão (mundo); along = direção da porta fechada (mundo);
-- swing = para que lado ela abre (mundo); style = "Grade" | "Vidro"; access = "All" | "Police"
local function door(parent, hinge, along, swing, width, height, style, access, label)
	local d = K.model("Porta", parent)
	along = Vector3.new(along.X, 0, along.Z).Unit
	local frame = CFrame.fromMatrix(hinge, along, Vector3.yAxis) -- +X = ao longo da porta
	local function f(x, y, z)
		return frame * CFrame.new(x, y, z)
	end
	local hingePart = part(d, "Dobradica", Vector3.new(0.3, height, 0.3), f(0, height / 2, 0), METAL, Enum.Material.Metal, { CanCollide = false })
	d.PrimaryPart = hingePart
	local panel
	if style == "Grade" then
		local BAR = Color3.fromRGB(70, 74, 82)
		part(d, "Moldura", Vector3.new(0.35, height, 0.35), f(width - 0.2, height / 2, 0), BAR, Enum.Material.Metal)
		for _, y in ipairs({ 0.3, height / 2, height - 0.3 }) do
			part(d, "Travessa", Vector3.new(width, 0.35, 0.3), f(width / 2, y, 0), BAR, Enum.Material.Metal)
		end
		local n = math.max(2, math.floor(width / 0.9))
		for k = 1, n - 1 do
			part(d, "Grade", Vector3.new(0.22, height - 0.3, 0.22), f(width * k / n, height / 2, 0), BAR, Enum.Material.Metal)
		end
		-- placa invisível que segura o aviso e não deixa passar entre as grades
		panel = part(d, "Painel", Vector3.new(width, height, 0.2), f(width / 2, height / 2, 0), BAR, Enum.Material.Metal, { Transparency = 1 })
		part(d, "Fechadura", Vector3.new(0.5, 0.8, 0.5), f(width - 0.6, height * 0.45, 0), Color3.fromRGB(200, 170, 60), Enum.Material.Metal, { CanCollide = false })
	else
		local DARK = Color3.fromRGB(40, 50, 65)
		panel = part(d, "Painel", Vector3.new(width - 0.4, height - 0.4, 0.25), f(width / 2, height / 2, 0), GLASS, Enum.Material.SmoothPlastic, { Transparency = 0.45 })
		part(d, "Moldura", Vector3.new(width, 0.4, 0.35), f(width / 2, height - 0.2, 0), DARK, Enum.Material.Metal)
		part(d, "Moldura", Vector3.new(width, 0.4, 0.35), f(width / 2, 0.2, 0), DARK, Enum.Material.Metal)
		part(d, "Moldura", Vector3.new(0.4, height, 0.35), f(width - 0.2, height / 2, 0), DARK, Enum.Material.Metal)
		part(d, "Puxador", Vector3.new(0.2, 2.4, 0.5), f(width - 0.9, height * 0.45, 0), STEEL, Enum.Material.Metal, { CanCollide = false })
	end
	-- para que lado gira: +90° leva a ponta da porta para o -Z da dobradiça
	local angle = (frame.LookVector:Dot(swing) > 0) and 90 or -90
	d:SetAttribute("PrisonDoor", true)
	d:SetAttribute("Access", access)
	d:SetAttribute("OpenAngle", angle)
	d:SetAttribute("Label", label or (access == "Police" and "Porta da PM" or "Portão"))
	d.WorldPivot = hingePart.CFrame
	return d, panel
end

-- Leitor de cartão (enfeite ao lado das portas da polícia)
local function cardReader(parent, cf)
	part(parent, "LeitorCartao", Vector3.new(0.8, 1.2, 0.25), cf, Color3.fromRGB(30, 35, 45), Enum.Material.SmoothPlastic, { CanCollide = false })
	part(parent, "LuzLeitor", Vector3.new(0.3, 0.15, 0.1), cf * CFrame.new(0, 0.35, -0.15), Color3.fromRGB(60, 220, 90), Enum.Material.Neon, { CanCollide = false })
end

---------------------------------------------------------------------------
-- Cerca: postes, tela (meio transparente), corrimão e rolo de arame farpado em cima
---------------------------------------------------------------------------

local function fenceLine(parent, x1, z1, x2, z2, height, razor)
	local a, b = Vector3.new(x1, 0, z1), Vector3.new(x2, 0, z2)
	local len = (b - a).Magnitude
	if len < 0.5 then
		return
	end
	local mid = (a + b) / 2
	local frame = base * CFrame.lookAt(mid, b) -- -Z ao longo da cerca
	local function f(x, y, z)
		return frame * CFrame.new(x, y, z)
	end
	part(parent, "Tela", Vector3.new(0.15, height - 0.6, len), f(0, height / 2 + 0.2, 0), FENCE, Enum.Material.DiamondPlate, { Transparency = 0.55, CastShadow = false })
	part(parent, "Corrimao", Vector3.new(0.35, 0.35, len), f(0, height, 0), METAL, Enum.Material.Metal)
	part(parent, "Rodape", Vector3.new(0.5, 0.5, len), f(0, 0.25, 0), CONCRETE, Enum.Material.Concrete)
	local posts = math.max(1, math.floor(len / 10 + 0.5))
	for i = 0, posts do
		local z = -len / 2 + len * i / posts
		part(parent, "Poste", Vector3.new(0.6, height + 1, 0.6), f(0, (height + 1) / 2, z), METAL, Enum.Material.Metal)
		if razor then
			-- braço inclinado para dentro segurando o arame
			part(parent, "Braco", Vector3.new(0.3, 2.4, 0.3), f(0.6, height + 1.9, z) * CFrame.Angles(0, 0, math.rad(-30)), METAL, Enum.Material.Metal)
		end
	end
	if razor then
		part(parent, "ArameFarpado", Vector3.new(len, 1.8, 1.8), f(0.5, height + 1.6, 0) * CFrame.Angles(0, math.rad(90), 0), STEEL, Enum.Material.Metal, { Shape = Enum.PartType.Cylinder, Transparency = 0.35, CanCollide = false, CastShadow = false })
	end
end

-- Retângulo de cerca com aberturas: gaps = { side = "front"/"back"/"left"/"right", c = centro, w = largura }
local function fenceRect(parent, x1, z1, x2, z2, height, razor, gaps)
	local function run(side, fixed, from, to, horizontal)
		local cuts = {}
		for _, g in ipairs(gaps or {}) do
			if g.side == side then
				table.insert(cuts, g)
			end
		end
		table.sort(cuts, function(p, q)
			return p.c < q.c
		end)
		local s = from
		for _, g in ipairs(cuts) do
			local e = g.c - g.w / 2
			if horizontal then
				fenceLine(parent, s, fixed, e, fixed, height, razor)
			else
				fenceLine(parent, fixed, s, fixed, e, height, razor)
			end
			s = g.c + g.w / 2
		end
		if horizontal then
			fenceLine(parent, s, fixed, to, fixed, height, razor)
		else
			fenceLine(parent, fixed, s, fixed, to, height, razor)
		end
	end
	run("front", z1, x1, x2, true)
	run("back", z2, x1, x2, true)
	run("left", x1, z1, z2, false)
	run("right", x2, z1, z2, false)
end

---------------------------------------------------------------------------
-- Torre de vigia (cantos): coluna, cabine com vidro, telhado cor de telha, holofote e escada
---------------------------------------------------------------------------

local function guardTower(parent, x, z, inward)
	local t = K.model("TorreVigia", parent)
	local H = 26
	box(t, "Coluna", 7, H, 7, x, 0, z, WALL, Enum.Material.Concrete)
	box(t, "Faixa", 7.4, 1.2, 7.4, x, 1, z, TERRA, Enum.Material.SmoothPlastic)
	-- cabine
	box(t, "Piso", 14, 1, 14, x, H, z, CONCRETE, Enum.Material.Concrete)
	local openX = inward.X > 0 and 1 or -1 -- lado da escada fica aberto
	for _, s in ipairs({ -1, 1 }) do
		box(t, "Mureta", 14, 3, 0.6, x, H + 1, z + s * 6.7, WALL, Enum.Material.Concrete)
		box(t, "Vidro", 13, 4, 0.2, x, H + 4, z + s * 6.7, GLASS, Enum.Material.SmoothPlastic, { Transparency = 0.6 })
		if s ~= openX then
			box(t, "Mureta", 0.6, 3, 14, x + s * 6.7, H + 1, z, WALL, Enum.Material.Concrete)
			box(t, "Vidro", 0.2, 4, 13, x + s * 6.7, H + 4, z, GLASS, Enum.Material.SmoothPlastic, { Transparency = 0.6 })
		end
	end
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			box(t, "Pilar", 0.8, 5, 0.8, x + sx * 6.6, H + 1, z + sz * 6.6, TERRA, Enum.Material.SmoothPlastic)
		end
	end
	box(t, "Telhado", 16, 1, 16, x, H + 6, z, TERRA, Enum.Material.SmoothPlastic)
	box(t, "Telhado", 11, 1.2, 11, x, H + 7, z, TERRA_DARK, Enum.Material.SmoothPlastic)
	box(t, "Telhado", 5, 1.2, 5, x, H + 8.2, z, TERRA_DARK, Enum.Material.SmoothPlastic)
	-- holofote virado para dentro da prisão
	local lamp = box(t, "Holofote", 1.6, 1.6, 1.6, x + inward.X * 6, H + 6.5, z + inward.Z * 6, Color3.fromRGB(255, 250, 225), Enum.Material.Neon, { CanCollide = false })
	local spot = Instance.new("SpotLight")
	spot.Face = Enum.NormalId.Front
	spot.Angle = 50
	spot.Range = 45
	spot.Brightness = 1.5
	spot.Shadows = false
	spot.Parent = lamp
	local p = lamp.Position
	lamp.CFrame = CFrame.lookAt(p, p + base:VectorToWorldSpace(inward * 3 - Vector3.new(0, 1, 0)))
	-- escada de treliça (lado de dentro) até a cabine, do lado que não tem mureta
	part(t, "Escada", Vector3.new(2, H + 2, 2), at(x + openX * 8.2, (H + 2) / 2, z), METAL, Enum.Material.Metal, { ClassName = "TrussPart" })
	return t
end

---------------------------------------------------------------------------
-- Terreno: pisos, ruas internas e caminhos
---------------------------------------------------------------------------

local IN_X1, IN_X2, IN_Z1, IN_Z2 = -HW + 20, HW - 20, -95, HD - 18 -- cerca da área de segurança
local RING = 12 -- rua de ronda por dentro da cerca de segurança

local function buildGrounds(m)
	local g = K.model("Pisos", m)
	-- área de segurança: concreto claro
	box(g, "PisoSeguranca", IN_X2 - IN_X1, 0.1, IN_Z2 - IN_Z1, 0, 0, (IN_Z1 + IN_Z2) / 2, CONCRETE, Enum.Material.Concrete)
	-- miolo com grama mais escura entre os pátios (o concreto fica como rua de ronda em volta)
	box(g, "Gramado", IN_X2 - IN_X1 - 2 * RING, 0.2, IN_Z2 - IN_Z1 - 2 * RING, 0, 0, (IN_Z1 + IN_Z2) / 2, Color3.fromRGB(105, 165, 80), Enum.Material.Grass)
	-- estrada da entrada até a praça da administração
	box(g, "Estrada", 24, 0.3, 112, 0, 0, -HD + 54, ASPHALT, Enum.Material.Asphalt)
	for z = -HD + 6, -HD + 104, 10 do
		box(g, "Faixa", 0.6, 0.32, 5, 0, 0, z, Color3.fromRGB(240, 200, 60), Enum.Material.SmoothPlastic)
	end
	-- praça na frente da administração
	box(g, "Praca", 150, 0.36, 30, 0, 0, -187, PAVING, Enum.Material.Pavement)
	-- estacionamento (lado direito de quem entra)
	local PX1, PX2, PZ1, PZ2 = 34, 214, -250, -196
	box(g, "Estacionamento", PX2 - PX1, 0.3, PZ2 - PZ1, (PX1 + PX2) / 2, 0, (PZ1 + PZ2) / 2, ASPHALT, Enum.Material.Asphalt)
	box(g, "Acesso", PX1 - 12, 0.3, 20, (PX1 + 12) / 2, 0, -212, ASPHALT, Enum.Material.Asphalt)
	for x = PX1 + 10, PX2 - 6, 11 do
		box(g, "Vaga", 0.5, 0.32, 18, x, 0, PZ1 + 10, LINE, Enum.Material.SmoothPlastic)
		box(g, "Vaga", 0.5, 0.32, 18, x, 0, PZ2 - 10, LINE, Enum.Material.SmoothPlastic)
	end
	-- acesso das viaturas: da estrada até a garagem da polícia (passa na frente do galpão)
	box(g, "AcessoViaturas", 160, 0.3, 10, -155, 0, -198, ASPHALT, Enum.Material.Asphalt)
	box(g, "PatioViaturas", 78, 0.3, 63, -199, 0, -171.5, ASPHALT, Enum.Material.Asphalt)
	box(g, "CalcadaPM", 80, 0.34, 18, -115, 0, -184, PAVING, Enum.Material.Pavement)
	-- caminhos dentro da área de segurança: em cruz até a torre
	box(g, "Caminho", 10, 0.26, 177 - (IN_Z1 + RING), 0, 0, (IN_Z1 + RING + 177) / 2, PAVING, Enum.Material.Pavement)
	box(g, "Caminho", 180, 0.26, 10, 0, 0, 82, PAVING, Enum.Material.Pavement)
end

---------------------------------------------------------------------------
-- Portal da entrada, guarita e cancela
---------------------------------------------------------------------------

local function buildEntrance(m)
	local e = K.model("Entrada", m)
	local z = -HD + 2
	for _, s in ipairs({ -1, 1 }) do
		box(e, "PilarPortal", 5, 20, 5, s * 16, 0, z, TERRA, Enum.Material.Brick)
		box(e, "TopoPilar", 6, 1, 6, s * 16, 20, z, WALL, Enum.Material.Concrete)
	end
	-- Marco 9.14: viga mais alta e nome em duas linhas (antes o nome saía fora da placa)
	box(e, "VigaPortal", 37, 7, 2.4, 0, 15, z, NAVY, Enum.Material.SmoothPlastic)
	local nome = string.gsub(PR.Name, " de ", "\nDE ")
	sign(e, string.upper(nome), 33, 5.4, 0, 15.5, z - 1.3, Vector3.new(0, 0, -1), WHITE, NAVY)
	sign(e, string.upper(nome), 33, 5.4, 0, 15.5, z + 1.3, Vector3.new(0, 0, 1), WHITE, NAVY)
	-- guarita à direita, com a cancela levantada (por enquanto tudo aberto)
	local gx, gz = 21, -HD + 22
	box(e, "Guarita", 8, 9, 9, gx, 0, gz, WALL, Enum.Material.Concrete)
	box(e, "Faixa", 8.3, 1.4, 9.3, gx, 0, gz, TERRA, Enum.Material.SmoothPlastic)
	box(e, "Janela", 0.2, 3.5, 7, gx - 4.1, 4, gz, GLASS, Enum.Material.SmoothPlastic, { Transparency = 0.4 })
	box(e, "Janela", 6, 3.5, 0.2, gx, 4, gz - 4.6, GLASS, Enum.Material.SmoothPlastic, { Transparency = 0.4 })
	box(e, "TelhadoGuarita", 11, 0.8, 12, gx, 9, gz, TERRA, Enum.Material.SmoothPlastic)
	box(e, "BaseCancela", 1.2, 3.5, 1.2, 13.5, 0, gz - 6, Color3.fromRGB(240, 200, 40), Enum.Material.SmoothPlastic)
	part(e, "Cancela", Vector3.new(0.4, 0.4, 22), at(13.5, 3.4, gz - 6) * CFrame.Angles(0, math.rad(90), 0) * CFrame.Angles(math.rad(70), 0, 0) * CFrame.new(0, 0, -10), Color3.fromRGB(230, 50, 45), Enum.Material.SmoothPlastic, { CanCollide = false })
	sign(e, "PORTARIA", 6, 1.4, gx, 7.2, gz - 4.75, Vector3.new(0, 0, -1), WHITE, NAVY)
	-- postes ao longo da estrada
	for zz = -HD + 30, -HD + 100, 35 do
		for _, s in ipairs({ -1, 1 }) do
			if s == -1 or zz > -200 then
				K.buildLamp(e, at(s * 14.5, -0.8, zz))
			end
		end
	end
end

---------------------------------------------------------------------------
-- Administração e Visitas (entra-se pela frente) + passarela coberta até a área de segurança
---------------------------------------------------------------------------

local ADM_W, ADM_D, ADM_H = 120, 50, 15
local ADM_Z = -150 -- centro

local function buildAdmin(m)
	local a = K.model("Administracao", m)
	local zF, zB = ADM_Z - ADM_D / 2, ADM_Z + ADM_D / 2
	local T = 1
	box(a, "Piso", ADM_W, 0.6, ADM_D, 0, 0, ADM_Z, Color3.fromRGB(225, 220, 210), Enum.Material.SmoothPlastic)
	-- fundo com porta para a passarela
	box(a, "Parede", (ADM_W - 8) / 2, ADM_H, T, -(ADM_W + 8) / 4, 0, zB - T / 2, WALL, Enum.Material.Concrete)
	box(a, "Parede", (ADM_W - 8) / 2, ADM_H, T, (ADM_W + 8) / 4, 0, zB - T / 2, WALL, Enum.Material.Concrete)
	box(a, "Parede", 8, ADM_H - 9, T, 0, 9, zB - T / 2, WALL, Enum.Material.Concrete)
	for _, s in ipairs({ -1, 1 }) do
		box(a, "Parede", T, ADM_H, ADM_D, s * (ADM_W / 2 - T / 2), 0, ADM_Z, WALL, Enum.Material.Concrete)
	end
	-- frente: porta larga no meio, vidraça dos lados e faixa de cima
	local DOOR = 10
	local sideW = (ADM_W - DOOR) / 2
	for _, s in ipairs({ -1, 1 }) do
		local cx = s * (DOOR / 2 + sideW / 2)
		box(a, "Mureta", sideW, 1.5, T, cx, 0, zF + T / 2, WALL, Enum.Material.Concrete)
		box(a, "Vidraca", sideW - 1, 7.5, 0.3, cx, 1.5, zF + T / 2, GLASS, Enum.Material.SmoothPlastic, { Transparency = 0.5 })
		for k = 1, 5 do
			box(a, "Montante", 0.5, 7.5, T, cx - sideW / 2 + k * sideW / 6, 1.5, zF + T / 2, TERRA, Enum.Material.SmoothPlastic)
		end
		box(a, "Batente", 0.8, 9, T + 0.2, s * (DOOR / 2 + 0.4), 0, zF + T / 2, TERRA, Enum.Material.SmoothPlastic)
	end
	box(a, "Parede", ADM_W, ADM_H - 9, T, 0, 9, zF + T / 2, WALL, Enum.Material.Concrete)
	-- faixas cor de telha, laje, platibanda e marquise
	band(a, at(0, 0, ADM_Z), ADM_W, ADM_D, 0, 1.2, TERRA)
	box(a, "Teto", ADM_W, 0.6, ADM_D, 0, ADM_H, ADM_Z, WHITE, Enum.Material.SmoothPlastic)
	box(a, "Laje", ADM_W + 1, 0.6, ADM_D + 1, 0, ADM_H + 0.6, ADM_Z, ROOF, Enum.Material.Concrete)
	for _, s in ipairs({ -1, 1 }) do
		box(a, "Platibanda", ADM_W + 1, 2, 0.8, 0, ADM_H + 0.6, ADM_Z + s * (ADM_D / 2 + 0.1), TERRA, Enum.Material.SmoothPlastic)
		box(a, "Platibanda", 0.8, 2, ADM_D + 1, s * (ADM_W / 2 + 0.1), ADM_H + 0.6, ADM_Z, TERRA, Enum.Material.SmoothPlastic)
	end
	box(a, "Marquise", 30, 0.8, 10, 0, 10, zF - 5, WHITE, Enum.Material.SmoothPlastic, { CanCollide = false })
	for _, s in ipairs({ -1, 1 }) do
		column(a, "PilarMarquise", s * 13, 0, zF - 9, 10, 0.6, TERRA, Enum.Material.SmoothPlastic)
	end
	sign(a, "ADMINISTRAÇÃO E VISITAS", 40, 3.4, 0, 12.6, zF - 0.6, Vector3.new(0, 0, -1), NAVY, WHITE)
	-- dentro: balcão de recepção, sala de espera, mesas de visita e armários
	box(a, "Balcao", 18, 4, 3, 0, 0.6, zF + 12, Color3.fromRGB(235, 230, 220), Enum.Material.SmoothPlastic)
	box(a, "TampoBalcao", 18.6, 0.4, 3.6, 0, 4.6, zF + 12, TERRA, Enum.Material.SmoothPlastic)
	sign(a, "RECEPÇÃO", 10, 2, 0, 11, zF + 13.6, Vector3.new(0, 0, -1), WHITE, NAVY)
	for row = 0, 2 do
		for _, s in ipairs({ -1, 1 }) do
			local cx, cz = s * 40, zF + 8 + row * 7
			box(a, "Banco", 16, 0.6, 2.2, cx, 2, cz, Color3.fromRGB(60, 110, 170), Enum.Material.SmoothPlastic)
			box(a, "Encosto", 16, 2.2, 0.5, cx, 2.6, cz + 1, Color3.fromRGB(60, 110, 170), Enum.Material.SmoothPlastic)
			box(a, "PeBanco", 15, 1.4, 1, cx, 0.6, cz, METAL, Enum.Material.Metal)
			for k = -1, 1 do
				seat(a, Vector3.new(2.6, 0.3, 1.8), cx + k * 5, 2.75, cz - 0.2, Vector3.new(0, 0, -1), Color3.fromRGB(60, 110, 170), "Banco").Transparency = 1
			end
		end
	end
	for k = 0, 3 do
		for _, s in ipairs({ -1, 1 }) do
			local cx, cz = s * (14 + k * 11), zB - 12
			if math.abs(cx) < 56 then
				box(a, "MesaVisita", 5, 0.4, 5, cx, 3.2, cz, WHITE, Enum.Material.SmoothPlastic)
				column(a, "PeMesa", cx, 0.6, cz, 2.6, 0.4, METAL, Enum.Material.Metal)
				for _, d in ipairs({ -1, 1 }) do
					box(a, "Cadeira", 2, 2, 2, cx, 0.6, cz + d * 3.6, Color3.fromRGB(240, 140, 60), Enum.Material.SmoothPlastic)
					seat(a, Vector3.new(1.8, 0.3, 1.8), cx, 2.75, cz + d * 3.6, Vector3.new(0, 0, -d), Color3.fromRGB(240, 140, 60), "Cadeira").Transparency = 1
				end
			end
		end
	end
	for k = 0, 5 do
		box(a, "Armario", 3, 7, 2, -55 + k * 3.2, 0.6, zB - 2.2, Color3.fromRGB(120, 150, 175), Enum.Material.Metal)
	end
	for _, x in ipairs({ -35, 0, 35 }) do
		local lamp = box(a, "Luminaria", 8, 0.2, 2, x, ADM_H - 0.2, ADM_Z, Color3.fromRGB(255, 250, 235), Enum.Material.Neon, { CanCollide = false })
		light(lamp, 24, 0.6)
	end
	-- mastros com bandeiras e jardim na frente
	for i, flag in ipairs({
		{ -34, Color3.fromRGB(0, 150, 60), Color3.fromRGB(250, 210, 30) },
		{ -26, NAVY, WHITE },
		{ 26, TERRA, WHITE },
	}) do
		local fx, fz = flag[1], zF - 14
		column(a, "Mastro", fx, 0, fz, 22, 0.25, STEEL, Enum.Material.Metal)
		box(a, "Bandeira", 5, 3.4, 0.2, fx + 2.7, 18, fz, flag[2], Enum.Material.Fabric, { CanCollide = false })
		box(a, "Losango", 2.4, 1.6, 0.24, fx + 2.7, 18.9, fz, flag[3], Enum.Material.Fabric, { CanCollide = false })
		if i == 1 then
			box(a, "Circulo", 1.2, 0.9, 0.28, fx + 2.7, 19.25, fz, NAVY, Enum.Material.Fabric, { CanCollide = false })
		end
	end
	for _, s in ipairs({ -1, 1 }) do
		box(a, "Canteiro", 34, 1, 5, s * 40, 0, zF - 3.5, Color3.fromRGB(140, 110, 80), Enum.Material.Ground)
		for k = 0, 5 do
			part(a, "Arbusto", Vector3.new(3.2, 3.2, 3.2), at(s * 40 - 14 + k * 5.6, 1.9, zF - 3.5), Color3.fromRGB(70, 150, 70), Enum.Material.Grass, { Shape = Enum.PartType.Ball })
		end
	end
	-- passarela coberta: do fundo da administração até dentro da área de segurança
	local p = K.model("Passarela", m)
	local z1, z2 = zB, IN_Z1 + RING
	local len, mid = z2 - z1, (z1 + z2) / 2
	box(p, "Piso", 9, 0.6, len, 0, 0, mid, PAVING, Enum.Material.SmoothPlastic)
	for _, s in ipairs({ -1, 1 }) do
		box(p, "Parede", 0.8, 3, len, s * 4.5, 0, mid, WALL, Enum.Material.Concrete)
		box(p, "Vidro", 0.3, 4.5, len, s * 4.5, 3, mid, GLASS, Enum.Material.SmoothPlastic, { Transparency = 0.5 })
		box(p, "Parede", 0.8, 2.5, len, s * 4.5, 7.5, mid, WALL, Enum.Material.Concrete)
	end
	box(p, "Teto", 11, 0.8, len + 1, 0, 10, mid, TERRA, Enum.Material.SmoothPlastic)
	sign(p, "ÁREA DE SEGURANÇA", 9, 1.6, 0, 8.6, z2 - 0.4, Vector3.new(0, 0, -1), WHITE, Color3.fromRGB(190, 40, 40))
	-- portão de vidro da PM no fim da passarela: só o Policial abre (cartão)
	for _, s in ipairs({ -1, 1 }) do
		door(p, at(s * 4.1, 0.6, z2 - 2).Position, base:VectorToWorldSpace(Vector3.new(-s, 0, 0)), base:VectorToWorldSpace(Vector3.new(0, 0, 1)), 4.1, 7.6, "Vidro", "Police", "Portão da PM")
	end
	for _, dz in ipairs({ -3.4, -0.6 }) do
		local rp = at(-4.05, 4.6, z2 + dz).Position
		cardReader(p, CFrame.lookAt(rp, rp + base:VectorToWorldSpace(Vector3.new(1, 0, 0))))
	end
	-- onde o preso solto aparece (na frente da administração) e o teste de prisão (só no Studio)
	box(a, "SaidaPrisao", 4, 1, 4, 0, 0.5, zF - 20, WHITE, Enum.Material.SmoothPlastic, { Transparency = 1, CanCollide = false })
	box(a, "TestePrisao", 2, 3, 2, 11, 0.6, zF + 9.5, WHITE, Enum.Material.SmoothPlastic, { Transparency = 1, CanCollide = false })
end

---------------------------------------------------------------------------
-- Caixa d'água, galpão e árvores da parte da frente
---------------------------------------------------------------------------

local function buildFrontYard(m)
	local f = K.model("AreaExterna", m)
	-- caixa d'água alta cor de telha (como na planta), com a caixa branca em cima
	local wx, wz = -HW + 42, -HD + 46
	column(f, "CaixaDagua", wx, 0, wz, 46, 4.5, TERRA, Enum.Material.Concrete)
	column(f, "Anel", wx, 14, wz, 1, 4.8, WALL, Enum.Material.SmoothPlastic)
	column(f, "Anel", wx, 30, wz, 1, 4.8, WALL, Enum.Material.SmoothPlastic)
	column(f, "Reservatorio", wx, 46, wz, 9, 8, WALL, Enum.Material.SmoothPlastic)
	column(f, "TampaReservatorio", wx, 55, wz, 1, 8.6, TERRA_DARK, Enum.Material.SmoothPlastic)
	-- galpão com telhado arredondado (meio cilindro)
	local GX, GZ, GW, GD, GH = -150, -225, 80, 36, 9
	box(f, "PisoGalpao", GW, 0.5, GD, GX, 0, GZ, CONCRETE, Enum.Material.Concrete)
	for _, s in ipairs({ -1, 1 }) do
		box(f, "ParedeGalpao", GW, GH, 0.8, GX, 0, GZ + s * (GD / 2 - 0.4), WALL, Enum.Material.Concrete)
	end
	box(f, "ParedeGalpao", 0.8, GH, GD, GX - GW / 2 + 0.4, 0, GZ, WALL, Enum.Material.Concrete)
	box(f, "ParedeGalpao", 0.8, GH, GD, GX + GW / 2 - 0.4, 0, GZ, WALL, Enum.Material.Concrete)
	part(f, "TelhadoGalpao", Vector3.new(GW + 2, GD + 1, GD + 1), at(GX, GH, GZ) , WHITE, Enum.Material.Metal, { Shape = Enum.PartType.Cylinder })
	-- o cilindro inteiro afundaria no chão: deixamos só a metade de cima com uma laje por dentro
	box(f, "ForroGalpao", GW, 0.6, GD, GX, GH - 0.3, GZ, WHITE, Enum.Material.SmoothPlastic)
	box(f, "PortaoGalpao", 14, 8, 0.4, GX + 18, 0.5, GZ + GD / 2 + 0.2, METAL, Enum.Material.Metal)
	box(f, "FaixaGalpao", GW + 0.4, 1.2, GD + 0.4, GX, 0, GZ, TERRA, Enum.Material.SmoothPlastic, { CanCollide = false })
	sign(f, "ALMOXARIFADO", 16, 2.4, GX - 14, 6, GZ + GD / 2 + 0.5, Vector3.new(0, 0, 1), WHITE, NAVY)
	-- árvores pela frente e pelo gramado
	for _, pos in ipairs({
		{ -40, -255 }, { -70, -255 }, { -100, -262 }, { -80, -112 }, { -150, -112 }, { -230, -112 },
		{ 90, -115 }, { 130, -120 }, { 180, -140 }, { 215, -170 }, { 230, -120 }, { 88, -186 },
	}) do
		K.buildTree(f, at(pos[1], 0, pos[2]).Position, 1.1)
	end
end

---------------------------------------------------------------------------
-- Pavilhão de celas (dá para entrar): corredor no meio e celas dos dois lados
-- cf = centro do pavilhão no chão; -Z local = lado do pátio; doorX = ponta com a porta (+1/-1)
---------------------------------------------------------------------------

local BL, BD, BH = 132, 34, 14 -- comprimento, largura e altura do pavilhão
local CELL_W = 9
local CELLS = 12 -- por lado
local YARD_SLOT = 6 -- no lado do pátio, essa vaga vira a passagem para o banho de sol

local function cellBlock(parent, cf, letter, doorX)
	local b = K.model("Pavilhao" .. letter, parent)
	local function L(x, y, z)
		return cf * CFrame.new(doorX * x, y, z)
	end
	local function bx(name, sx, sy, sz, x, y0, z, color, material, extra)
		-- tamanho no eixo x local não muda com o espelho (caixas são simétricas)
		return part(b, name, Vector3.new(sx, sy, sz), L(x, y0 + sy / 2, z), color, material, extra)
	end
	local T = 1
	local hx, hz = BL / 2, BD / 2
	local x0 = -hx + T -- começo das celas
	local hallX = x0 + CELLS * CELL_W -- daqui até a porta é o hall de entrada

	bx("Piso", BL, 0.6, BD, 0, 0, 0, Color3.fromRGB(205, 205, 200), Enum.Material.SmoothPlastic)
	bx("Corredor", hallX - x0, 0.62, 9, (x0 + hallX) / 2, 0, 0, Color3.fromRGB(170, 175, 180), Enum.Material.SmoothPlastic)
	-- parede do fundo (lado sem pátio) inteira
	bx("Parede", BL, BH, T, 0, 0, hz - T / 2, WALL, Enum.Material.Concrete)
	-- parede do lado do pátio com a passagem na vaga YARD_SLOT
	local gx1, gx2 = x0 + (YARD_SLOT - 1) * CELL_W, x0 + YARD_SLOT * CELL_W
	bx("Parede", gx1 + hx, BH, T, (-hx + gx1) / 2, 0, -hz + T / 2, WALL, Enum.Material.Concrete)
	bx("Parede", hx - gx2, BH, T, (gx2 + hx) / 2, 0, -hz + T / 2, WALL, Enum.Material.Concrete)
	bx("Parede", CELL_W, BH - 9, T, (gx1 + gx2) / 2, 9, -hz + T / 2, WALL, Enum.Material.Concrete)
	-- pontas: a da porta tem uma abertura no corredor
	bx("Parede", T, BH, BD, -hx + T / 2, 0, 0, WALL, Enum.Material.Concrete)
	bx("Parede", T, BH, (BD - 7) / 2, hx - T / 2, 0, -(BD + 7) / 4, WALL, Enum.Material.Concrete)
	bx("Parede", T, BH, (BD - 7) / 2, hx - T / 2, 0, (BD + 7) / 4, WALL, Enum.Material.Concrete)
	bx("Parede", T, BH - 9, 7, hx - T / 2, 9, 0, WALL, Enum.Material.Concrete)
	-- por fora: faixa de baixo e platibanda cor de telha, laje com claraboia no meio
	band(b, cf, BL, BD, 0, 1.5, TERRA)
	bx("Teto", BL, 0.4, BD, 0, BH, 0, WHITE, Enum.Material.SmoothPlastic)
	bx("Laje", BL + 1, 0.6, (BD - 4) / 2, 0, BH + 0.4, -(BD + 4) / 4, ROOF, Enum.Material.Concrete)
	bx("Laje", BL + 1, 0.6, (BD - 4) / 2, 0, BH + 0.4, (BD + 4) / 4, ROOF, Enum.Material.Concrete)
	bx("Claraboia", BL - 6, 1.2, 4.4, 0, BH + 0.2, 0, GLASS, Enum.Material.SmoothPlastic, { Transparency = 0.45 })
	for _, s in ipairs({ -1, 1 }) do
		bx("Platibanda", BL + 1, 2.2, 0.8, 0, BH + 0.4, s * (hz + 0.1), TERRA, Enum.Material.SmoothPlastic)
		bx("Platibanda", 0.8, 2.2, BD + 1, s * (hx + 0.1), BH + 0.4, 0, TERRA, Enum.Material.SmoothPlastic)
	end
	-- letreiro em cima da porta (virado para fora da ponta)
	local outward = cf:VectorToWorldSpace(Vector3.new(doorX, 0, 0))
	local sp = L(hx + 0.35, 11.3, 0).Position
	local board = part(b, "Placa", Vector3.new(14, 3, 0.4), CFrame.lookAt(sp, sp + outward), NAVY, Enum.Material.SmoothPlastic, { CanCollide = false })
	K.addSurfaceText(board, "PAVILHÃO " .. letter, WHITE, NAVY)
	local yardSign = L((gx1 + gx2) / 2, 11.3, -hz - 0.35).Position
	local board2 = part(b, "Placa", Vector3.new(8, 2, 0.4), CFrame.lookAt(yardSign, yardSign + cf:VectorToWorldSpace(Vector3.new(0, 0, -1))), TERRA, Enum.Material.SmoothPlastic, { CanCollide = false })
	K.addSurfaceText(board2, "PÁTIO " .. letter, WHITE, TERRA)

	-- celas
	local BAR = Color3.fromRGB(70, 74, 82)
	for _, s in ipairs({ -1, 1 }) do
		for i = 1, CELLS do
			local cx = x0 + (i - 0.5) * CELL_W
			local zFront, zBack = s * 4.5, s * (hz - T)
			local depth = math.abs(zBack - zFront)
			local zMid = (zFront + zBack) / 2
			-- divisória entre celas
			bx("Divisoria", 0.5, BH, depth, x0 + i * CELL_W, 0, zMid, WALL, Enum.Material.Concrete)
			if s == -1 and i == YARD_SLOT then
				-- passagem para o pátio: vira um corredor curto (o portão fica na parede do pátio)
				bx("Passagem", CELL_W, 0.62, depth, cx, 0, zMid, Color3.fromRGB(170, 175, 180), Enum.Material.SmoothPlastic)
				bx("Divisoria", 0.5, BH, depth, x0 + (i - 1) * CELL_W, 0, zMid, WALL, Enum.Material.Concrete)
			else
				local cellName = letter .. string.format("%02d", (s == -1 and 0 or CELLS) + i)
				-- grades da frente e a porta de grade (fechada; abre com E)
				for k = 0, 4 do
					bx("Grade", 0.25, 9, 0.25, cx - 4 + k * 1.05, 0.6, zFront, BAR, Enum.Material.Metal)
				end
				bx("Batente", 0.4, 9, 0.4, cx + 0.95, 0.6, zFront, BAR, Enum.Material.Metal)
				bx("TravessaGrade", 5.4, 0.35, 0.35, cx - 1.8, 4.5, zFront, BAR, Enum.Material.Metal, { CanCollide = false })
				bx("Cabeceira", CELL_W, BH - 9.6, 0.6, cx, 9.6, zFront, WALL, Enum.Material.Concrete)
				door(b, L(cx + 1.2, 0.6, zFront).Position, cf:VectorToWorldSpace(Vector3.new(doorX, 0, 0)), cf:VectorToWorldSpace(Vector3.new(0, 0, s)), 3, 9, "Grade", "All", "Cela " .. cellName)
				-- onde o preso aparece (invisível)
				local spawnPart = bx("CelaSpawn", 2, 1, 2, cx + 1, 0.7, zMid, WHITE, Enum.Material.SmoothPlastic, { Transparency = 1, CanCollide = false })
				spawnPart.CanQuery = false
				spawnPart.CanTouch = false
				spawnPart:SetAttribute("Cell", cellName)
				-- cama encostada na divisória (dá para sentar), privada e pia no fundo
				local bedX = cx - CELL_W / 2 + 2.1
				bx("Cama", 3.4, 1.6, 7, bedX, 0.6, zBack - s * 4, METAL, Enum.Material.Metal)
				bx("Colchao", 3.2, 0.6, 6.8, bedX, 2.2, zBack - s * 4, Color3.fromRGB(235, 235, 225), Enum.Material.Fabric)
				local bedPos = L(bedX, 2.95, zBack - s * 4.5).Position
				local bedSeat = part(b, "Assento", Vector3.new(2.6, 0.3, 2.6), CFrame.lookAt(bedPos, bedPos + cf:VectorToWorldSpace(Vector3.new(doorX, 0, 0))), Color3.fromRGB(235, 235, 225), Enum.Material.Fabric, { ClassName = "Seat", Transparency = 1 })
				bedSeat:SetAttribute("SeatText", "Cama")
				bx("Travesseiro", 2.6, 0.5, 1.4, bedX, 2.8, zBack - s * 1.2, WHITE, Enum.Material.Fabric)
				bx("Privada", 1.6, 1.6, 1.8, cx + 3, 0.6, zBack - s * 1.2, STEEL, Enum.Material.Metal)
				bx("Pia", 1.6, 0.5, 1.2, cx + 3, 4, zBack - s * 0.8, STEEL, Enum.Material.Metal)
				-- janelinha com grade (vidro por dentro e por fora da parede)
				for _, face in ipairs({ -0.1, T + 0.1 }) do
					local wz = zBack + s * face
					bx("Janela", 3, 2, 0.12, cx, 9.5, wz, Color3.fromRGB(60, 80, 100), Enum.Material.SmoothPlastic, { CanCollide = false })
					for k = -1, 1 do
						bx("GradeJanela", 0.2, 2.2, 0.2, cx + k * 0.9, 9.4, wz + s * 0.05, BAR, Enum.Material.Metal, { CanCollide = false })
					end
				end
				-- número da cela em cima da grade
				local np = L(cx, 10.6, zFront - s * 0.35).Position
				local num = part(b, "NumeroCela", Vector3.new(2.4, 1, 0.2), CFrame.lookAt(np, np + cf:VectorToWorldSpace(Vector3.new(0, 0, -s))), NAVY, Enum.Material.SmoothPlastic, { CanCollide = false })
				K.addSurfaceText(num, cellName, WHITE, NAVY)
			end
		end
	end
	-- portão de grade na entrada do pavilhão (duas folhas que abrem para fora)
	for _, side in ipairs({ -1, 1 }) do
		door(b, L(hx - 0.5, 0.6, side * 3.5).Position, cf:VectorToWorldSpace(Vector3.new(0, 0, -side)), cf:VectorToWorldSpace(Vector3.new(doorX, 0, 0)), 3.5, 8.4, "Grade", "All", "Pavilhão " .. letter)
	end
	-- portão de grade na passagem para o pátio (duas folhas que abrem para o pátio)
	for _, side in ipairs({ -1, 1 }) do
		local hingeX = side < 0 and gx1 + 0.3 or gx2 - 0.3
		door(b, L(hingeX, 0.6, -hz + 0.5).Position, cf:VectorToWorldSpace(Vector3.new(-side * doorX, 0, 0)), cf:VectorToWorldSpace(Vector3.new(0, 0, -1)), CELL_W / 2 - 0.3, 8.4, "Grade", "All", "Pátio " .. letter)
	end
	-- hall de entrada: mesa do guarda
	bx("MesaGuarda", 3, 3.4, 8, hallX + 7, 0.6, hz - 7, Color3.fromRGB(120, 130, 145), Enum.Material.SmoothPlastic)
	bx("CadeiraGuarda", 2, 2, 2, hallX + 9.5, 0.6, hz - 7, NAVY, Enum.Material.SmoothPlastic)
	-- luz do corredor: faixa de neon e poucas lâmpadas fracas (para não estourar)
	bx("LuzCorredor", hallX - x0, 0.2, 1, (x0 + hallX) / 2, BH - 0.4, 0, Color3.fromRGB(255, 250, 235), Enum.Material.Neon, { CanCollide = false })
	for _, x in ipairs({ x0 + 20, (x0 + hallX) / 2, hallX - 20, hallX + 8 }) do
		local lamp = bx("Lampada", 1.5, 0.3, 1.5, x, BH - 0.6, 0, Color3.fromRGB(255, 250, 235), Enum.Material.Neon, { CanCollide = false })
		light(lamp, 22, 0.5)
	end
	return b
end

---------------------------------------------------------------------------
-- Pátios de banho de sol (um por pavilhão), cada um com uma coisa diferente
---------------------------------------------------------------------------

local function bench(parent, x, z, rot)
	local cf = at(x, 0, z) * CFrame.Angles(0, rot or 0, 0)
	part(parent, "Banco", Vector3.new(7, 0.6, 2), cf * CFrame.new(0, 2, 0), CONCRETE, Enum.Material.Concrete)
	local s = part(parent, "Assento", Vector3.new(6, 0.3, 1.8), cf * CFrame.new(0, 2.45, 0), CONCRETE, Enum.Material.Concrete, { ClassName = "Seat", Transparency = 1 })
	s:SetAttribute("SeatText", "Banco")
	for _, s in ipairs({ -1, 1 }) do
		part(parent, "PeBanco", Vector3.new(0.8, 2, 1.6), cf * CFrame.new(s * 2.8, 1, 0), CONCRETE, Enum.Material.Concrete)
	end
end

-- Bola solta de verdade (física). O PrisonService devolve ela ao lugar se sair do pátio.
local function looseBall(parent, name, size, cf, color)
	local ball = part(parent, name, Vector3.new(size, size, size), cf, color, Enum.Material.SmoothPlastic, { Shape = Enum.PartType.Ball })
	ball.Anchored = false
	ball:SetAttribute("Ball", true)
	ball:SetAttribute("BallHome", cf.Position)
	return ball
end

local function basketball(y, cx, cz)
	box(y, "Quadra", 46, 0.1, 26, cx, 0.35, cz, Color3.fromRGB(200, 95, 60), Enum.Material.SmoothPlastic)
	box(y, "Linha", 0.4, 0.12, 26, cx, 0.36, cz, LINE, Enum.Material.SmoothPlastic)
	for _, s in ipairs({ -1, 1 }) do
		box(y, "Linha", 46, 0.12, 0.4, cx, 0.36, cz + s * 13, LINE, Enum.Material.SmoothPlastic)
		box(y, "Linha", 0.4, 0.12, 26, cx + s * 23, 0.36, cz, LINE, Enum.Material.SmoothPlastic)
		box(y, "Garrafao", 10, 0.11, 10, cx + s * 18, 0.355, cz, Color3.fromRGB(170, 70, 45), Enum.Material.SmoothPlastic)
		local hx = cx + s * 24.5
		box(y, "PosteCesta", 0.8, 11, 0.8, hx, 0, cz, METAL, Enum.Material.Metal)
		box(y, "Tabela", 0.3, 3.5, 6, hx - s * 1, 9, cz, WHITE, Enum.Material.SmoothPlastic)
		box(y, "BracoCesta", 1.5, 0.4, 0.4, hx - s * 0.5, 10, cz, METAL, Enum.Material.Metal)
		column(y, "Aro", hx - s * 2, 9.3, cz, 0.2, 0.9, Color3.fromRGB(240, 110, 30), Enum.Material.Metal, { CanCollide = false })
	end
	looseBall(y, "BolaBasquete", 1.5, at(cx - 4, 1.4, cz + 2), Color3.fromRGB(230, 110, 35))
end

local function soccer(y, cx, cz)
	box(y, "Campinho", 52, 0.1, 30, cx, 0.35, cz, Color3.fromRGB(80, 160, 70), Enum.Material.Grass)
	box(y, "Linha", 0.4, 0.12, 30, cx, 0.36, cz, LINE, Enum.Material.SmoothPlastic)
	column(y, "Circulo", cx, 0.36, cz, 0.12, 4, LINE, Enum.Material.SmoothPlastic)
	column(y, "Circulo", cx, 0.37, cz, 0.12, 3.6, Color3.fromRGB(80, 160, 70), Enum.Material.Grass)
	for _, s in ipairs({ -1, 1 }) do
		box(y, "Linha", 52, 0.12, 0.4, cx, 0.36, cz + s * 15, LINE, Enum.Material.SmoothPlastic)
		box(y, "Linha", 0.4, 0.12, 30, cx + s * 26, 0.36, cz, LINE, Enum.Material.SmoothPlastic)
		local gx = cx + s * 26
		for _, d in ipairs({ -1, 1 }) do
			box(y, "Trave", 0.5, 6, 0.5, gx, 0.3, cz + d * 5, WHITE, Enum.Material.SmoothPlastic)
		end
		box(y, "Travessao", 0.5, 0.5, 10.5, gx, 6.1, cz, WHITE, Enum.Material.SmoothPlastic)
		box(y, "Rede", 3, 6, 10, gx + s * 1.5, 0.3, cz, WHITE, Enum.Material.Fabric, { Transparency = 0.75, CanCollide = false })
	end
	looseBall(y, "Bola", 1.6, at(cx + 6, 1.4, cz - 3), WHITE)
end

local function garden(y, cx, cz)
	local PLANTS = { Color3.fromRGB(60, 150, 60), Color3.fromRGB(90, 175, 70), Color3.fromRGB(230, 90, 60), Color3.fromRGB(240, 200, 60) }
	for row = 0, 4 do
		local rz = cz - 16 + row * 8
		station(box(y, "Canteiro", 48, 0.8, 4.5, cx, 0.3, rz, Color3.fromRGB(110, 80, 55), Enum.Material.Ground), "Horta_Canteiro", "Canteiro da horta")
		for k = 0, 9 do
			local c = PLANTS[(row + k) % #PLANTS + 1]
			part(y, "Planta", Vector3.new(1.6, 1.6, 1.6), at(cx - 22 + k * 4.9, 1.6, rz), (k % 2 == 0) and PLANTS[1] or c, Enum.Material.Grass, { Shape = Enum.PartType.Ball, CanCollide = false })
		end
	end
	-- caixa d'água pequena, regador e ferramentas
	station(column(y, "Tonel", cx + 30, 0.3, cz - 14, 4, 2, Color3.fromRGB(40, 110, 190), Enum.Material.SmoothPlastic), "Horta_Regador", "Regador (tonel de água)")
	station(box(y, "Carrinho", 3, 1.6, 5, cx + 30, 0.6, cz + 6, Color3.fromRGB(230, 60, 50), Enum.Material.Metal), "Horta_Cesto", "Carrinho da colheita")
	box(y, "Galpaozinho", 8, 8, 6, cx - 32, 0.3, cz - 12, WOOD, Enum.Material.WoodPlanks)
	box(y, "TelhaGalpao", 9, 0.6, 7, cx - 32, 8.3, cz - 12, TERRA, Enum.Material.SmoothPlastic)
	sign(y, "HORTA", 6, 1.6, cx - 32, 6, cz - 8.8, Vector3.new(0, 0, 1), WHITE, Color3.fromRGB(60, 140, 60))
end

local function gym(y, cx, cz)
	box(y, "PisoAcademia", 48, 0.1, 28, cx, 0.35, cz, Color3.fromRGB(70, 75, 85), Enum.Material.Rubber)
	-- barras fixas
	for k = 0, 2 do
		local bxp = cx - 18 + k * 7
		for _, s in ipairs({ -1, 1 }) do
			box(y, "PosteBarra", 0.5, 8 - k, 0.5, bxp + s * 2.5, 0.3, cz - 8, METAL, Enum.Material.Metal)
		end
		part(y, "Barra", Vector3.new(5.5, 0.35, 0.35), at(bxp, 8.3 - k, cz - 8), STEEL, Enum.Material.Metal)
	end
	-- bancos de supino com halteres
	for k = 0, 2 do
		local x = cx + 4 + k * 8
		box(y, "Supino", 1.8, 2, 5, x, 0.3, cz + 4, NAVY, Enum.Material.Fabric)
		seat(y, Vector3.new(1.6, 0.3, 2), x, 2.45, cz + 4.5, Vector3.new(0, 0, -1), NAVY, "Supino").Transparency = 1
		for _, s in ipairs({ -1, 1 }) do
			box(y, "Suporte", 0.4, 4, 0.4, x + s * 1.8, 0.3, cz + 1.8, METAL, Enum.Material.Metal)
		end
		part(y, "BarraSupino", Vector3.new(7, 0.3, 0.3), at(x, 4.3, cz + 1.8), STEEL, Enum.Material.Metal)
		for _, s in ipairs({ -1, 1 }) do
			part(y, "Anilha", Vector3.new(0.4, 2.2, 2.2), at(x + s * 3, 4.3, cz + 1.8), Color3.fromRGB(30, 30, 35), Enum.Material.Rubber, { Shape = Enum.PartType.Cylinder })
		end
	end
	-- paralelas e saco de pancada
	for _, s in ipairs({ -1, 1 }) do
		part(y, "Paralela", Vector3.new(0.35, 0.35, 8), at(cx - 6 + s * 1.2, 4.5, cz + 8), STEEL, Enum.Material.Metal)
		for _, d in ipairs({ -1, 1 }) do
			box(y, "PostePar", 0.4, 4.2, 0.4, cx - 6 + s * 1.2, 0.3, cz + 8 + d * 3.5, METAL, Enum.Material.Metal)
		end
	end
	box(y, "Trave", 0.5, 10, 0.5, cx + 20, 0.3, cz - 10, METAL, Enum.Material.Metal)
	box(y, "BracoSaco", 4, 0.4, 0.4, cx + 18.2, 10, cz - 10, METAL, Enum.Material.Metal)
	column(y, "SacoPancada", cx + 16.5, 3, cz - 10, 5, 1.2, Color3.fromRGB(200, 40, 40), Enum.Material.Fabric)
end

local function buildSecureArea(m)
	local s = K.model("AreaSeguranca", m)
	-- cerca da área de segurança (mais alta, com arame), com abertura para a passarela
	fenceRect(s, IN_X1, IN_Z1, IN_X2, IN_Z2, PR.SecureFence, true, { { side = "front", c = 0, w = 10 } })
	-- em cima da passarela a cerca continua (não dá para pular pelo telhado)
	box(s, "Tela", 10, PR.SecureFence - 10.6, 0.15, 0, 10.8, IN_Z1, FENCE, Enum.Material.DiamondPlate, { Transparency = 0.55, CastShadow = false })
	sign(s, "ÁREA DE SEGURANÇA MÁXIMA", 22, 2.4, 22, 13, IN_Z1 - 0.4, Vector3.new(0, 0, -1), WHITE, Color3.fromRGB(190, 40, 40))
	-- 4 pavilhões e seus pátios. Coluna da esquerda e da direita; fileira da frente e de trás.
	local XC = 141
	local ROWS = {
		{ z = -40, yard = 1, rot = math.pi }, -- fileira da frente: o pátio fica atrás (para +z)
		{ z = 205, yard = -1, rot = 0 }, -- fileira de trás: o pátio fica na frente (para -z)
	}
	local letters = { { "A", "B" }, { "C", "D" } }
	local extras = { { basketball, soccer }, { garden, gym } }
	for r, row in ipairs(ROWS) do
		for c, sx in ipairs({ -1, 1 }) do
			local letter = letters[r][c]
			local cf = at(sx * XC, 0, row.z) * CFrame.Angles(0, row.rot, 0)
			-- a porta fica na ponta virada para o meio da prisão (x = 0)
			local towardCenter = -sx
			local localX = cf:VectorToObjectSpace(base:VectorToWorldSpace(Vector3.new(towardCenter, 0, 0))).X
			cellBlock(s, cf, letter, localX > 0 and 1 or -1)
			-- pátio encostado no lado do pavilhão virado para o meio
			local y = K.model("Patio" .. letter, s)
			local zNear = row.z + row.yard * (BD / 2)
			local zFar = zNear + row.yard * 62
			local zc = (zNear + zFar) / 2
			local x1, x2 = sx * XC - BL / 2, sx * XC + BL / 2
			box(y, "PisoPatio", BL, 0.17, 62, sx * XC, 0.15, zc, Color3.fromRGB(196, 194, 186), Enum.Material.Concrete)
			-- cerca do pátio: as duas pontas e o lado de longe; abertura do lado do meio
			local gapX = sx < 0 and x2 or x1
			local otherX = sx < 0 and x1 or x2
			fenceLine(y, otherX, zNear, otherX, zFar, PR.YardFence, false)
			fenceLine(y, gapX, zNear, gapX, zc - 5, PR.YardFence, false)
			fenceLine(y, gapX, zc + 5, gapX, zFar, PR.YardFence, false)
			fenceLine(y, x1, zFar, x2, zFar, PR.YardFence, false)
			extras[r][c](y, sx * XC + sx * 6, zc)
			for k = -1, 1, 2 do
				bench(y, sx * XC - sx * 50, zc + k * 18, math.pi / 2)
			end
			-- bebedouro
			box(y, "Bebedouro", 1.6, 3.4, 1.6, sx * XC - sx * 58, 0.2, zc + 26, STEEL, Enum.Material.Metal)
		end
	end
	return s
end

---------------------------------------------------------------------------
-- Refeitório (dá para entrar) no fundo e torre de controle redonda no meio
---------------------------------------------------------------------------

local function buildCanteen(m)
	local r = K.model("Refeitorio", m)
	local W, D, H, Z = 96, 46, 13, 200
	local zF, zB = Z - D / 2, Z + D / 2
	local T = 1
	box(r, "Piso", W, 0.6, D, 0, 0, Z, Color3.fromRGB(230, 225, 212), Enum.Material.SmoothPlastic)
	box(r, "Parede", W, H, T, 0, 0, zB - T / 2, WALL, Enum.Material.Concrete)
	for _, sx in ipairs({ -1, 1 }) do
		box(r, "Parede", T, H, D, sx * (W / 2 - T / 2), 0, Z, WALL, Enum.Material.Concrete)
		box(r, "Parede", (W - 10) / 2, H, T, sx * (W + 10) / 4, 0, zF + T / 2, WALL, Enum.Material.Concrete)
		for k = 0, 3 do
			box(r, "Janela", 6, 4, 0.2, sx * (12 + k * 9), 5, zF - 0.05, GLASS, Enum.Material.SmoothPlastic, { Transparency = 0.3, CanCollide = false })
		end
	end
	box(r, "Parede", 10, H - 9, T, 0, 9, zF + T / 2, WALL, Enum.Material.Concrete)
	band(r, at(0, 0, Z), W, D, 0, 1.4, TERRA)
	box(r, "Teto", W, 0.4, D, 0, H, Z, WHITE, Enum.Material.SmoothPlastic)
	K.gableRoof(r, at(0, 0, Z), W, D, H + 0.4, TERRA, WALL)
	sign(r, "REFEITÓRIO", 18, 3, 0, 10.8, zF - 0.4, Vector3.new(0, 0, -1), WHITE, TERRA)
	-- mesas compridas com bancos
	for row = 0, 2 do
		for _, sx in ipairs({ -1, 1 }) do
			local tx, tz = sx * 24, zF + 9 + row * 9
			box(r, "Mesa", 30, 0.5, 3.4, tx, 3, tz, Color3.fromRGB(205, 205, 200), Enum.Material.Metal)
			box(r, "PeMesa", 28, 2.4, 0.8, tx, 0.6, tz, METAL, Enum.Material.Metal)
			for _, d in ipairs({ -1, 1 }) do
				box(r, "BancoMesa", 30, 0.5, 1.4, tx, 1.8, tz + d * 2.8, Color3.fromRGB(60, 110, 170), Enum.Material.SmoothPlastic)
				box(r, "PeBancoMesa", 28, 1.2, 0.6, tx, 0.6, tz + d * 2.8, METAL, Enum.Material.Metal)
				for k = -1, 1 do
					seat(r, Vector3.new(2.6, 0.3, 1.4), tx + k * 9, 2.45, tz + d * 2.8, Vector3.new(0, 0, -d), Color3.fromRGB(60, 110, 170), "Banco").Transparency = 1
				end
			end
		end
	end
	-- balcão de servir com as panelas
	station(box(r, "BalcaoServir", 50, 3.8, 3, 0, 0.6, zB - 6, STEEL, Enum.Material.Metal), "Cozinha_Balcao", "Balcão de servir")
	-- cozinha ao lado do balcão (canto esquerdo do fundo): fogão com panelões; geladeira no canto direito
	station(box(r, "Fogao", 14, 3.6, 3, -37, 0.6, zB - 2.6, Color3.fromRGB(60, 62, 68), Enum.Material.Metal), "Cozinha_Panela", "Fogão da cozinha")
	for k = 0, 2 do
		column(r, "Panelao", -42 + k * 5, 4.2, zB - 2.6, 2, 1.6, STEEL, Enum.Material.Metal)
	end
	box(r, "Geladeira", 5, 9, 3, 40, 0.6, zB - 2.6, WHITE, Enum.Material.Metal)
	station(box(r, "ArmarioLimpeza", 2, 7, 5, W / 2 - 2, 0.6, zF + 6, Color3.fromRGB(60, 120, 190), Enum.Material.Metal), "Limpeza_Armario", "Armário de limpeza")
	for i, spot in ipairs({ { 0, zF + 12 }, { 0, zF + 26 }, { -43, zF + 20 } }) do
		station(box(r, "Sujeira", 5, 0.08, 5, spot[1], 0.62, spot[2], Color3.fromRGB(240, 130, 40), Enum.Material.SmoothPlastic, { Transparency = 1, CanCollide = false }), "Limpeza_Sujeira_" .. i, "Sujeira")
	end
	-- TV na parede (em cima da cozinha)
	box(r, "MolduraTV", 11, 6.4, 0.4, 0, 5.6, zB - 1.2, Color3.fromRGB(20, 20, 24), Enum.Material.SmoothPlastic, { CanCollide = false })
	sign(r, "📺 JORNAL LITTLE LIFE", 10, 5.6, 0, 8.8, zB - 1.45, Vector3.new(0, 0, -1), WHITE, Color3.fromRGB(30, 90, 160))
	for k = 0, 4 do
		column(r, "Panela", -16 + k * 8, 4.4, zB - 6, 1.4, 1.5, Color3.fromRGB(150, 155, 160), Enum.Material.Metal)
	end
	for k = 0, 5 do
		box(r, "Bandeja", 2.4, 0.2, 1.8, 22 + (k % 2) * 0.2, 4.4 + k * 0.22, zB - 6, Color3.fromRGB(240, 140, 60), Enum.Material.SmoothPlastic)
	end
	for _, x in ipairs({ -28, 0, 28 }) do
		local lamp = box(r, "Luminaria", 8, 0.2, 2, x, H - 0.2, Z, Color3.fromRGB(255, 250, 235), Enum.Material.Neon, { CanCollide = false })
		light(lamp, 22, 0.5)
	end
end

-- Prédio de um andar com telhado de duas águas e porta na ponta virada para o meio (x = 0)
local SIDE_W, SIDE_D, SIDE_H = 100, 40, 12
local function sideBuilding(m, name, title, sx, z, color, fill)
	local b = K.model(name, m)
	local X = sx * (90 + SIDE_W / 2 - 4)
	local T = 1
	local doorEnd = X - sx * (SIDE_W / 2 - T / 2)
	box(b, "Piso", SIDE_W, 0.6, SIDE_D, X, 0, z, Color3.fromRGB(232, 232, 228), Enum.Material.SmoothPlastic)
	for _, s in ipairs({ -1, 1 }) do
		box(b, "Parede", SIDE_W, SIDE_H, T, X, 0, z + s * (SIDE_D / 2 - T / 2), WALL, Enum.Material.Concrete)
		box(b, "Parede", T, SIDE_H, (SIDE_D - 8) / 2, doorEnd, 0, z + s * (SIDE_D + 8) / 4, WALL, Enum.Material.Concrete)
		for k = 0, 4 do
			box(b, "Janela", 7, 4, 0.2, X - SIDE_W / 2 + 12 + k * 19, 5, z + s * (SIDE_D / 2 + 0.05), GLASS, Enum.Material.SmoothPlastic, { Transparency = 0.3, CanCollide = false })
		end
	end
	box(b, "Parede", T, SIDE_H, SIDE_D, X + sx * (SIDE_W / 2 - T / 2), 0, z, WALL, Enum.Material.Concrete)
	box(b, "Parede", T, SIDE_H - 9, 8, doorEnd, 9, z, WALL, Enum.Material.Concrete)
	band(b, at(X, 0, z), SIDE_W, SIDE_D, 0, 1.4, color)
	box(b, "Teto", SIDE_W, 0.4, SIDE_D, X, SIDE_H, z, WHITE, Enum.Material.SmoothPlastic)
	K.gableRoof(b, at(X, 0, z), SIDE_W, SIDE_D, SIDE_H + 0.4, TERRA, WALL)
	sign(b, title, 16, 2.6, doorEnd - sx * 0.8, 10.4, z, Vector3.new(-sx, 0, 0), WHITE, color)
	fill(b, X, z, sx)
	for _, dx in ipairs({ -25, 25 }) do
		local lamp = box(b, "Luminaria", 8, 0.2, 2, X + dx, SIDE_H - 0.2, z, Color3.fromRGB(255, 250, 235), Enum.Material.Neon, { CanCollide = false })
		light(lamp, 22, 0.5)
	end
end

-- Enfermaria: macas com lençol, biombos e armário de remédios
local function infirmary(b, X, z, sx)
	for k = 0, 5 do
		for _, s in ipairs({ -1, 1 }) do
			local x, zz = X - sx * 30 + sx * k * 12, z + s * 13
			box(b, "Maca", 4, 2.4, 8, x, 0.6, zz, STEEL, Enum.Material.Metal)
			box(b, "Lencol", 3.8, 0.5, 7.8, x, 3, zz, WHITE, Enum.Material.Fabric)
			box(b, "Travesseiro", 3, 0.5, 1.5, x, 3.5, zz + s * 3, WHITE, Enum.Material.Fabric)
			if k < 5 then
				box(b, "Biombo", 0.3, 6, 7, x + sx * 6, 0.6, zz, Color3.fromRGB(150, 200, 200), Enum.Material.Fabric, { Transparency = 0.2 })
			end
		end
	end
	box(b, "ArmarioRemedios", 2, 8, 10, X + sx * (SIDE_W / 2 - 2.5), 0.6, z, WHITE, Enum.Material.SmoothPlastic)
	box(b, "Cruz", 0.3, 4, 1.2, X + sx * (SIDE_W / 2 - 3.6), 4, z, Color3.fromRGB(220, 40, 40), Enum.Material.SmoothPlastic)
	box(b, "Cruz", 0.3, 1.2, 4, X + sx * (SIDE_W / 2 - 3.6), 5.4, z, Color3.fromRGB(220, 40, 40), Enum.Material.SmoothPlastic)
end

-- Escola e oficinas: carteiras com lousa e bancadas de marcenaria
local function school(b, X, z, sx)
	local front = X - sx * (SIDE_W / 2 - 3)
	box(b, "Lousa", 0.3, 5, 16, X + sx * 2, 4, z - 10, Color3.fromRGB(40, 80, 60), Enum.Material.SmoothPlastic)
	for row = 0, 2 do
		for col = 0, 3 do
			local x, zz = X - sx * (6 + row * 7), z - 16 + col * 4.4
			box(b, "Carteira", 3, 0.4, 3, x, 3, zz, WOOD, Enum.Material.Wood)
			box(b, "PeCarteira", 2.6, 2.4, 0.4, x, 0.6, zz, METAL, Enum.Material.Metal)
			box(b, "Cadeira", 2, 2, 2, x - sx * 2.6, 0.6, zz, Color3.fromRGB(60, 110, 170), Enum.Material.SmoothPlastic)
			seat(b, Vector3.new(1.8, 0.3, 1.8), x - sx * 2.6, 2.75, zz, Vector3.new(sx, 0, 0), Color3.fromRGB(60, 110, 170), "Cadeira").Transparency = 1
		end
	end
	for k = 0, 3 do
		local x = X + sx * (12 + k * 9)
		station(box(b, "Bancada", 6, 3.6, 4, x, 0.6, z + 12, WOOD, Enum.Material.WoodPlanks), "Of_Bancada", "Bancada da oficina")
		box(b, "Tabua", 4, 0.4, 1.2, x, 4.2, z + 12, Color3.fromRGB(205, 160, 110), Enum.Material.Wood)
	end
	box(b, "Estante", 14, 7, 2, front + sx * 14, 0.6, z + 18, WOOD, Enum.Material.Wood)
	station(box(b, "PilhaMadeira", 3, 2.4, 6, X + sx * 46, 0.6, z + 12, Color3.fromRGB(190, 140, 90), Enum.Material.WoodPlanks), "Of_Madeira", "Pilha de madeira")
end

local function buildControlTower(m)
	local t = K.model("TorreControle", m)
	local X, Z, H = 0, 82, 30
	column(t, "Canteiro", X, 0.3, Z, 0.8, 16, Color3.fromRGB(110, 80, 55), Enum.Material.Ground)
	for k = 0, 11 do
		local a = k * math.pi / 6
		part(t, "Flor", Vector3.new(2.4, 2.4, 2.4), at(X + math.cos(a) * 13.5, 1.7, Z + math.sin(a) * 13.5), (k % 2 == 0) and Color3.fromRGB(240, 200, 60) or Color3.fromRGB(230, 90, 120), Enum.Material.Grass, { Shape = Enum.PartType.Ball, CanCollide = false })
	end
	column(t, "Base", X, 0, Z, 4, 9, TERRA, Enum.Material.Brick)
	column(t, "Coluna", X, 4, Z, H - 4, 6, WALL, Enum.Material.Concrete)
	column(t, "Anel", X, 16, Z, 1, 6.4, TERRA, Enum.Material.SmoothPlastic)
	column(t, "Varanda", X, H, Z, 1, 13, CONCRETE, Enum.Material.Concrete)
	column(t, "Cabine", X, H + 1, Z, 7, 9, GLASS, Enum.Material.SmoothPlastic, { Transparency = 0.45 })
	for k = 0, 7 do
		local a = k * math.pi / 4
		box(t, "Montante", 0.6, 7, 0.6, X + math.cos(a) * 9, H + 1, Z + math.sin(a) * 9, TERRA, Enum.Material.SmoothPlastic)
	end
	for k = 0, 23 do
		local a = k * math.pi / 12
		if k ~= 18 then -- vão na grade em cima da escada
			box(t, "GradeVaranda", 0.3, 3, 0.3, X + math.cos(a) * 12.6, H + 1, Z + math.sin(a) * 12.6, METAL, Enum.Material.Metal)
		end
	end
	column(t, "Telhado", X, H + 8, Z, 1, 11, TERRA, Enum.Material.SmoothPlastic)
	column(t, "Telhado", X, H + 9, Z, 1.4, 7.5, TERRA_DARK, Enum.Material.SmoothPlastic)
	column(t, "Telhado", X, H + 10.4, Z, 1.4, 4, TERRA_DARK, Enum.Material.SmoothPlastic)
	local beacon = column(t, "Farol", X, H + 11.8, Z, 1.6, 1.2, Color3.fromRGB(255, 80, 60), Enum.Material.Neon, { CanCollide = false })
	light(beacon, 16, 0.8, Color3.fromRGB(255, 120, 90))
	-- escada até a varanda (por fora, virada para a entrada)
	part(t, "Escada", Vector3.new(2, H + 2, 2), at(X, (H + 2) / 2, Z - 14), METAL, Enum.Material.Metal, { ClassName = "TrussPart" })
	sign(t, "CONTROLE", 8, 1.6, X, 13, Z - 6.3, Vector3.new(0, 0, -1), WHITE, NAVY)
end


---------------------------------------------------------------------------
-- Lavanderia e Biblioteca (Marco 8.1): prédios pequenos no meio, com estações de tarefa
---------------------------------------------------------------------------

-- Prédio de um andar com porta no meio da frente (-z)
local function smallBuilding(m, name, title, X, Z, W, D, color)
	local b = K.model(name, m)
	local H, T = 11, 1
	local zF, zB = Z - D / 2, Z + D / 2
	box(b, "Piso", W, 0.6, D, X, 0, Z, Color3.fromRGB(232, 228, 220), Enum.Material.SmoothPlastic)
	box(b, "Parede", W, H, T, X, 0, zB - T / 2, WALL, Enum.Material.Concrete)
	for _, s in ipairs({ -1, 1 }) do
		box(b, "Parede", T, H, D, X + s * (W / 2 - T / 2), 0, Z, WALL, Enum.Material.Concrete)
		box(b, "Parede", (W - 8) / 2, H, T, X + s * (W + 8) / 4, 0, zF + T / 2, WALL, Enum.Material.Concrete)
		box(b, "Janela", 6, 4, 0.2, X + s * (W / 4 + 2), 4.5, zF - 0.05, GLASS, Enum.Material.SmoothPlastic, { Transparency = 0.3, CanCollide = false })
	end
	box(b, "Parede", 8, H - 9, T, X, 9, zF + T / 2, WALL, Enum.Material.Concrete)
	band(b, at(X, 0, Z), W, D, 0, 1.4, color)
	box(b, "Teto", W, 0.4, D, X, H, Z, WHITE, Enum.Material.SmoothPlastic)
	box(b, "Laje", W + 1, 0.6, D + 1, X, H + 0.4, Z, ROOF, Enum.Material.Concrete)
	for _, s in ipairs({ -1, 1 }) do
		box(b, "Platibanda", W + 1, 1.8, 0.8, X, H + 0.4, Z + s * (D / 2 + 0.1), color, Enum.Material.SmoothPlastic)
		box(b, "Platibanda", 0.8, 1.8, D + 1, X + s * (W / 2 + 0.1), H + 0.4, Z, color, Enum.Material.SmoothPlastic)
	end
	sign(b, title, 14, 2, X, 10.1, zF - 0.4, Vector3.new(0, 0, -1), WHITE, color)
	for _, dx in ipairs({ -W / 4, W / 4 }) do
		local lamp = box(b, "Luminaria", 6, 0.2, 2, X + dx, H - 0.2, Z, Color3.fromRGB(255, 250, 235), Enum.Material.Neon, { CanCollide = false })
		light(lamp, 20, 0.5)
	end
	return b, zF, zB
end

local function buildLaundry(m)
	local X, Z, W, D = -50, 108, 44, 30
	local b, zF, zB = smallBuilding(m, "Lavanderia", "LAVANDERIA", X, Z, W, D, Color3.fromRGB(60, 150, 190))
	-- máquinas de lavar no fundo (com a portinha redonda de vidro)
	for k = 0, 3 do
		local x = X - 15 + k * 8
		station(box(b, "MaquinaLavar", 5.4, 5, 4, x, 0.6, zB - 3, WHITE, Enum.Material.Metal), "Lav_Maquina", "Máquina de lavar")
		part(b, "PortaMaquina", Vector3.new(0.3, 3, 3), at(x, 3.1, zB - 5.1) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(70, 110, 140), Enum.Material.SmoothPlastic, { Shape = Enum.PartType.Cylinder, Transparency = 0.2, CanCollide = false })
		box(b, "Painel", 4.6, 0.6, 0.2, x, 4.9, zB - 5.05, Color3.fromRGB(60, 150, 190), Enum.Material.SmoothPlastic, { CanCollide = false })
	end
	-- secadoras empilhadas na parede da esquerda
	for k = 0, 1 do
		box(b, "Secadora", 4, 4.6, 5, X - W / 2 + 3, 0.6 + k * 4.7, Z - 4, Color3.fromRGB(225, 228, 232), Enum.Material.Metal)
	end
	-- cestos de roupa suja perto da porta
	for k = 0, 1 do
		local x = X - 14 + k * 4.5
		station(box(b, "CestoRoupa", 3.4, 2.6, 3.4, x, 0.6, zF + 4, Color3.fromRGB(70, 120, 200), Enum.Material.Fabric), "Lav_Cesto", "Cesto de roupa suja")
		box(b, "Roupa", 3, 0.6, 3, x, 3.2, zF + 4, (k == 0) and Color3.fromRGB(235, 120, 30) or WHITE, Enum.Material.Fabric, { CanCollide = false })
	end
	-- varais com roupa laranja e branca (lado direito)
	local CLOTHES = { Color3.fromRGB(235, 120, 30), WHITE, Color3.fromRGB(235, 120, 30), Color3.fromRGB(120, 160, 220) }
	for v = 0, 1 do
		local x = X + 10 + v * 8
		for _, dz in ipairs({ -6, 6 }) do
			box(b, "PosteVaral", 0.4, 7, 0.4, x, 0.6, Z - 1 + dz, METAL, Enum.Material.Metal)
		end
		station(box(b, "CordaVaral", 0.15, 0.15, 12, x, 7.2, Z - 1, WHITE, Enum.Material.SmoothPlastic, { CanCollide = false }), "Lav_Varal", "Varal")
		for k = 0, 3 do
			box(b, "RoupaVaral", 0.2, 2.6, 2, x, 4.6, Z - 5.5 + k * 3, CLOTHES[k + 1], Enum.Material.Fabric, { CanCollide = false })
		end
	end
	box(b, "MesaDobrar", 8, 3.2, 3.4, X - 4, 0.6, Z - 2, Color3.fromRGB(200, 205, 210), Enum.Material.Metal)
	box(b, "RoupaDobrada", 2, 0.8, 1.6, X - 6, 3.8, Z - 2, Color3.fromRGB(235, 120, 30), Enum.Material.Fabric, { CanCollide = false })
	box(b, "RoupaDobrada", 2, 0.6, 1.6, X - 2, 3.8, Z - 2, WHITE, Enum.Material.Fabric, { CanCollide = false })
end

local function buildLibrary(m)
	local X, Z, W, D = 50, 108, 44, 30
	local b, zF, zB = smallBuilding(m, "Biblioteca", "BIBLIOTECA", X, Z, W, D, Color3.fromRGB(130, 80, 160))
	local BOOKS = { Color3.fromRGB(200, 60, 50), Color3.fromRGB(50, 110, 190), Color3.fromRGB(60, 150, 80), Color3.fromRGB(230, 180, 50), Color3.fromRGB(150, 90, 170) }
	local function shelf(x, z, alongX, isStation)
		local sx, sz = alongX and 8 or 1.8, alongX and 1.8 or 8
		local s = box(b, "Estante", sx, 8, sz, x, 0.6, z, WOOD, Enum.Material.Wood)
		for row = 0, 2 do
			for k = 0, 3 do
				local off = -3 + k * 2
				local bxp, bzp = alongX and x + off or x, alongX and z or z + off
				box(b, "Livros", alongX and 1.8 or 1.9, 1.7, alongX and 1.9 or 1.8, bxp, 1.4 + row * 2.4, bzp, BOOKS[(row + k) % #BOOKS + 1], Enum.Material.SmoothPlastic, { CanCollide = false })
			end
		end
		if isStation then
			station(s, "Bib_Estante", "Estante de livros")
		end
	end
	for k = 0, 3 do
		shelf(X - 15 + k * 10, zB - 2, true, k ~= 1)
	end
	for k = 0, 1 do
		shelf(X + W / 2 - 2, Z - 6 + k * 10, false, false)
	end
	-- carrinho de livros devolvidos perto da porta
	station(box(b, "CarrinhoLivros", 4, 3, 2.4, X - 13, 0.6, zF + 5, Color3.fromRGB(120, 125, 135), Enum.Material.Metal), "Bib_Carrinho", "Carrinho de livros")
	for k = 0, 2 do
		box(b, "Livros", 1, 1.4, 1.8, X - 14.2 + k * 1.2, 3.6, zF + 5, BOOKS[k + 1], Enum.Material.SmoothPlastic, { CanCollide = false })
	end
	-- tapete, mesas de leitura com cadeiras (dá para sentar) e uma planta
	box(b, "Tapete", 22, 0.06, 12, X - 2, 0.6, Z - 1, Color3.fromRGB(150, 50, 60), Enum.Material.Fabric, { CanCollide = false })
	for _, tx in ipairs({ X - 8, X + 6 }) do
		box(b, "MesaLeitura", 7, 0.4, 4, tx, 3.2, Z - 1, WOOD, Enum.Material.Wood)
		box(b, "PeMesa", 6, 2.6, 0.6, tx, 0.6, Z - 1, METAL, Enum.Material.Metal)
		for _, d in ipairs({ -1, 1 }) do
			for _, dx in ipairs({ -1.8, 1.8 }) do
				box(b, "Cadeira", 1.8, 2, 1.8, tx + dx, 0.6, Z - 1 + d * 3.2, Color3.fromRGB(130, 80, 160), Enum.Material.SmoothPlastic)
				seat(b, Vector3.new(1.6, 0.3, 1.6), tx + dx, 2.75, Z - 1 + d * 3.2, Vector3.new(0, 0, -d), Color3.fromRGB(130, 80, 160), "Cadeira").Transparency = 1
			end
		end
		box(b, "LivroAberto", 1.6, 0.2, 1.2, tx, 3.6, Z - 1, WHITE, Enum.Material.SmoothPlastic, { CanCollide = false })
	end
	box(b, "Vaso", 2, 2, 2, X + W / 2 - 3, 0.6, zF + 3, TERRA, Enum.Material.SmoothPlastic)
	part(b, "Planta", Vector3.new(3.4, 3.4, 3.4), at(X + W / 2 - 3, 4.2, zF + 3), Color3.fromRGB(70, 150, 70), Enum.Material.Grass, { Shape = Enum.PartType.Ball, CanCollide = false })
end

---------------------------------------------------------------------------
-- Base da PM (Marco 8.1): 2 andares, ao lado da Administração. Só entra quem é Policial
-- (as portas abrem com o cartão). Embaixo: plantão e ARSENAL. Em cima: briefing e escritórios.
-- Visual da foto que o Luís mandou: pedra clara, tijolo, torre de vidro azul e marquise azul-marinho.
---------------------------------------------------------------------------

local PM_X, PM_Z, PM_W, PM_D, PM_F = -113, -151, 84, 48, 12 -- PM_F = altura de cada andar
local STONE = Color3.fromRGB(228, 223, 212)
local BRICK = Color3.fromRGB(150, 80, 60)
local BLUE_GLASS = Color3.fromRGB(70, 135, 205)
local PM_NAVY = Color3.fromRGB(25, 40, 75)
local GOLD = Color3.fromRGB(220, 180, 60)

local function buildPoliceBase(m)
	local p = K.model("BasePM", m)
	local x1, x2 = PM_X - PM_W / 2, PM_X + PM_W / 2 -- -155 .. -71
	local zF, zB = PM_Z - PM_D / 2, PM_Z + PM_D / 2 -- -175 .. -127
	local T = 1
	local TOP = PM_F * 2
	local TX1, TZ2 = x2 - 17, zF + 15 -- torre de vidro no canto da frente (direita)
	local DX, DW = PM_X, 8 -- porta principal
	local MID = -149 -- parede que separa a frente (plantão / briefing) do fundo (arsenal / escritórios)
	local SX1, SX2, SZ1, SZ2 = x1, -146, -172, -150 -- vão da escada (lado esquerdo)
	local F2 = PM_F + 0.6 -- chão do 2º andar
	local STONE_M = Enum.Material.Limestone

	-- pisos e lajes (com o vão da escada)
	box(p, "Piso", PM_W, 0.6, PM_D, PM_X, 0, PM_Z, Color3.fromRGB(205, 205, 210), Enum.Material.Marble)
	box(p, "Laje", x2 - SX2, 0.6, PM_D, (SX2 + x2) / 2, PM_F, PM_Z, Color3.fromRGB(80, 85, 95), Enum.Material.Carpet)
	box(p, "Laje", SX2 - x1, 0.6, zB - SZ2, (x1 + SX2) / 2, PM_F, (SZ2 + zB) / 2, Color3.fromRGB(80, 85, 95), Enum.Material.Carpet)
	box(p, "Laje", SX2 - x1, 0.6, SZ1 - zF, (x1 + SX2) / 2, PM_F, (zF + SZ1) / 2, Color3.fromRGB(80, 85, 95), Enum.Material.Carpet)
	-- forro em 3 pedaços, deixando aberto em cima da escada
	box(p, "Forro", x2 - SX2, 0.3, PM_D, (SX2 + x2) / 2, PM_F - 0.3, PM_Z, WHITE, Enum.Material.SmoothPlastic, { CanCollide = false })
	box(p, "Forro", SX2 - x1, 0.3, zB - SZ2, (x1 + SX2) / 2, PM_F - 0.3, (SZ2 + zB) / 2, WHITE, Enum.Material.SmoothPlastic, { CanCollide = false })
	box(p, "Forro", SX2 - x1, 0.3, SZ1 - zF, (x1 + SX2) / 2, PM_F - 0.3, (zF + SZ1) / 2, WHITE, Enum.Material.SmoothPlastic, { CanCollide = false })
	box(p, "Teto", PM_W, 0.4, PM_D, PM_X, TOP, PM_Z, WHITE, Enum.Material.SmoothPlastic)
	box(p, "Cobertura", PM_W + 1, 0.6, PM_D + 1, PM_X, TOP + 0.4, PM_Z, ROOF, Enum.Material.Concrete)
	for _, s in ipairs({ -1, 1 }) do
		box(p, "Platibanda", PM_W + 1, 2, 0.8, PM_X, TOP + 0.4, PM_Z + s * (PM_D / 2 + 0.1), STONE, STONE_M)
		box(p, "Platibanda", 0.8, 2, PM_D + 1, PM_X + s * (PM_W / 2 + 0.1), TOP + 0.4, PM_Z, STONE, STONE_M)
	end

	-- escada (degraus maciços) subindo de frente para o fundo
	for k = 1, 12 do
		box(p, "Degrau", 7, k, 1.8, -150.5, 0.6, SZ1 + (k - 0.5) * 1.8, Color3.fromRGB(190, 190, 195), Enum.Material.Marble)
	end
	-- guarda-corpo de vidro em volta do vão (2º andar)
	box(p, "GuardaCorpo", 0.3, 3.4, SZ2 - SZ1, SX2, F2, (SZ1 + SZ2) / 2, GLASS, Enum.Material.SmoothPlastic, { Transparency = 0.5 })
	box(p, "GuardaCorpo", SX2 - x1, 3.4, 0.3, (x1 + SX2) / 2, F2, SZ1, GLASS, Enum.Material.SmoothPlastic, { Transparency = 0.5 })
	box(p, "Corrimao", 0.4, 0.3, SZ2 - SZ1, SX2, F2 + 3.4, (SZ1 + SZ2) / 2, STEEL, Enum.Material.Metal)

	-- FACHADA DA FRENTE: tijolo embaixo, pedra e janela em fita em cima, torre de vidro azul no canto
	local zw = zF + T / 2
	box(p, "Parede", (DX - DW / 2) - x1, PM_F, T, (x1 + DX - DW / 2) / 2, 0, zw, BRICK, Enum.Material.Brick)
	box(p, "Parede", TX1 - (DX + DW / 2), PM_F, T, (DX + DW / 2 + TX1) / 2, 0, zw, BRICK, Enum.Material.Brick)
	box(p, "Parede", DW, PM_F - 9.6, T, DX, 9.6, zw, STONE, STONE_M)
	box(p, "Parede", TX1 - x1, 3, T, (x1 + TX1) / 2, PM_F, zw, STONE, STONE_M)
	box(p, "Parede", TX1 - x1, 3, T, (x1 + TX1) / 2, TOP - 3, zw, STONE, STONE_M)
	box(p, "JanelaFita", TX1 - x1, 6, 0.3, (x1 + TX1) / 2, PM_F + 3, zw, BLUE_GLASS, Enum.Material.SmoothPlastic, { Transparency = 0.35 })
	for x = x1 + 6, TX1 - 2, 6 do
		box(p, "Montante", 0.8, 6, T + 0.2, x, PM_F + 3, zw, STONE, STONE_M)
	end
	-- torre de vidro: frente e lado direito, do chão até acima do telhado
	local TH = TOP + 9
	box(p, "TorreVidro", x2 - TX1, TH, 0.4, (TX1 + x2) / 2, 0, zF + 0.2, BLUE_GLASS, Enum.Material.SmoothPlastic, { Transparency = 0.3 })
	box(p, "TorreVidro", 0.4, TH, TZ2 - zF, x2 - 0.2, 0, (zF + TZ2) / 2, BLUE_GLASS, Enum.Material.SmoothPlastic, { Transparency = 0.3 })
	for x = TX1, x2, 3.4 do
		box(p, "MontanteTorre", 0.4, TH, 0.6, x, 0, zF - 0.1, PM_NAVY, Enum.Material.Metal, { CanCollide = false })
	end
	for z = zF, TZ2, 3 do
		box(p, "MontanteTorre", 0.6, TH, 0.4, x2 + 0.1, 0, z, PM_NAVY, Enum.Material.Metal, { CanCollide = false })
	end
	for _, y in ipairs({ PM_F, TOP, TH }) do
		box(p, "FaixaTorre", x2 - TX1 + 0.4, 0.6, 0.8, (TX1 + x2) / 2, y - 0.3, zF - 0.1, PM_NAVY, Enum.Material.Metal, { CanCollide = false })
		box(p, "FaixaTorre", 0.8, 0.6, TZ2 - zF + 0.4, x2 + 0.1, y - 0.3, (zF + TZ2) / 2, PM_NAVY, Enum.Material.Metal, { CanCollide = false })
	end
	-- o pedaço da torre acima do telhado (caixa de vidro com tampa)
	box(p, "TorreVidro", x2 - TX1, TH - TOP - 1, 0.4, (TX1 + x2) / 2, TOP + 1, TZ2 - 0.2, BLUE_GLASS, Enum.Material.SmoothPlastic, { Transparency = 0.3 })
	box(p, "TorreVidro", 0.4, TH - TOP - 1, TZ2 - zF, TX1 + 0.2, TOP + 1, (zF + TZ2) / 2, BLUE_GLASS, Enum.Material.SmoothPlastic, { Transparency = 0.3 })
	box(p, "TampaTorre", x2 - TX1 + 1.4, 1, TZ2 - zF + 1.4, (TX1 + x2) / 2, TH, (zF + TZ2) / 2, PM_NAVY, Enum.Material.Metal)
	sign(p, "POLÍCIA", 12, 2.2, (TX1 + x2) / 2, TH - 2.6, zF - 0.5, Vector3.new(0, 0, -1), WHITE, PM_NAVY)

	-- LADOS E FUNDO: pedra clara, faixa de tijolo embaixo e janelas em fita no 2º andar
	box(p, "Parede", T, TOP, zB - TZ2, x2 - T / 2, 0, (TZ2 + zB) / 2, STONE, STONE_M)
	box(p, "Parede", PM_W, TOP, T, PM_X, 0, zB - T / 2, STONE, STONE_M)
	-- lado esquerdo com a porta para a garagem das viaturas
	local GZ, GW = -138, 6
	box(p, "Parede", T, TOP, (GZ - GW / 2) - zF, x1 + T / 2, 0, (zF + GZ - GW / 2) / 2, STONE, STONE_M)
	box(p, "Parede", T, TOP, zB - (GZ + GW / 2), x1 + T / 2, 0, (GZ + GW / 2 + zB) / 2, STONE, STONE_M)
	box(p, "Parede", T, TOP - 9, GW, x1 + T / 2, 9, GZ, STONE, STONE_M)
	box(p, "Tijolo", 0.3, 4, zB - TZ2, x2 + 0.15, 0, (TZ2 + zB) / 2, BRICK, Enum.Material.Brick, { CanCollide = false })
	box(p, "Tijolo", PM_W, 4, 0.3, PM_X, 0, zB + 0.15, BRICK, Enum.Material.Brick, { CanCollide = false })
	box(p, "JanelaFita", PM_W - 8, 5, 0.3, PM_X, PM_F + 3.5, zB + 0.2, BLUE_GLASS, Enum.Material.SmoothPlastic, { Transparency = 0.2, CanCollide = false })
	box(p, "JanelaFita", 0.3, 5, zB - TZ2 - 6, x2 + 0.2, PM_F + 3.5, (TZ2 + zB) / 2, BLUE_GLASS, Enum.Material.SmoothPlastic, { Transparency = 0.2, CanCollide = false })
	box(p, "JanelaFita", 0.3, 5, PM_D - 8, x1 - 0.2, PM_F + 3.5, PM_Z, BLUE_GLASS, Enum.Material.SmoothPlastic, { Transparency = 0.2, CanCollide = false })

	-- MARQUISE azul-marinho com o letreiro, portas de vidro com cartão
	box(p, "Marquise", 30, 1.2, 9, DX, 10.4, zF - 4.5, PM_NAVY, Enum.Material.Metal)
	for _, s in ipairs({ -1, 1 }) do
		column(p, "PilarMarquise", DX + s * 14, 0, zF - 8.4, 10.4, 0.5, STEEL, Enum.Material.Metal)
	end
	sign(p, "POLÍCIA MILITAR", 26, 1.2, DX, 11, zF - 9.25, Vector3.new(0, 0, -1), WHITE, PM_NAVY)
	local spot = box(p, "LuzMarquise", 20, 0.2, 1, DX, 10.2, zF - 4.5, Color3.fromRGB(255, 250, 235), Enum.Material.Neon, { CanCollide = false })
	light(spot, 16, 0.6)
	for _, s in ipairs({ -1, 1 }) do
		door(p, at(DX + s * DW / 2, 0.6, zF + 0.5).Position, base:VectorToWorldSpace(Vector3.new(-s, 0, 0)), base:VectorToWorldSpace(Vector3.new(0, 0, 1)), DW / 2, 9, "Vidro", "Police", "Base da PM")
	end
	local rp = at(DX - DW / 2 - 1.4, 4.6, zF - 0.15).Position
	cardReader(p, CFrame.lookAt(rp, rp + base:VectorToWorldSpace(Vector3.new(0, 0, -1))))
	rp = at(DX + DW / 2 + 1.4, 4.6, zF + T + 0.15).Position
	cardReader(p, CFrame.lookAt(rp, rp + base:VectorToWorldSpace(Vector3.new(0, 0, 1))))
	for _, s in ipairs({ -1, 1 }) do
		door(p, at(x1 + 0.5, 0.6, GZ + s * GW / 2).Position, base:VectorToWorldSpace(Vector3.new(0, 0, -s)), base:VectorToWorldSpace(Vector3.new(1, 0, 0)), GW / 2, 9, "Vidro", "Police", "Base da PM")
	end
	rp = at(x1 - 0.15, 4.6, GZ - GW / 2 - 1.4).Position
	cardReader(p, CFrame.lookAt(rp, rp + base:VectorToWorldSpace(Vector3.new(-1, 0, 0))))
	rp = at(x1 + T + 0.15, 4.6, GZ + GW / 2 + 1.4).Position
	cardReader(p, CFrame.lookAt(rp, rp + base:VectorToWorldSpace(Vector3.new(1, 0, 0))))
	-- canteiros e mastro na frente
	for _, s in ipairs({ -1, 1 }) do
		box(p, "Canteiro", 10, 1.2, 3, DX + s * 24, 0, zF - 2.5, Color3.fromRGB(90, 95, 105), Enum.Material.Slate)
		for k = -1, 1 do
			part(p, "Arbusto", Vector3.new(2.8, 2.8, 2.8), at(DX + s * 24 + k * 3, 2.2, zF - 2.5), Color3.fromRGB(60, 140, 70), Enum.Material.Grass, { Shape = Enum.PartType.Ball, CanCollide = false })
		end
	end
	column(p, "Mastro", x1 + 6, 0, zF - 12, 26, 0.25, STEEL, Enum.Material.Metal)
	box(p, "BandeiraPM", 5, 3.4, 0.2, x1 + 8.7, 22, zF - 12, PM_NAVY, Enum.Material.Fabric, { CanCollide = false })
	box(p, "EstrelaPM", 1.6, 1.6, 0.24, x1 + 8.7, 22.9, zF - 12, GOLD, Enum.Material.Fabric, { CanCollide = false })

	-- TÉRREO / FRENTE: plantão (balcão), brasão no chão, sofá e troféus
	box(p, "ParedeMeio", (DX - 3) - x1, PM_F, T, (x1 + DX - 3) / 2, 0.6, MID, STONE, STONE_M)
	box(p, "ParedeMeio", x2 - (DX + 3), PM_F, T, (DX + 3 + x2) / 2, 0.6, MID, STONE, STONE_M)
	box(p, "ParedeMeio", 6, PM_F - 9, T, DX, 9.6, MID, STONE, STONE_M)
	sign(p, "ARSENAL", 8, 1.6, DX, 10.6, MID - 0.7, Vector3.new(0, 0, -1), WHITE, Color3.fromRGB(170, 35, 35))
	box(p, "BalcaoPlantao", 14, 4, 3, -96, 0.6, -160, PM_NAVY, Enum.Material.SmoothPlastic)
	box(p, "TampoPlantao", 14.6, 0.4, 3.6, -96, 4.6, -160, WOOD, Enum.Material.Wood)
	sign(p, "PLANTÃO 24H", 10, 1.8, -96, 9.4, -158.2, Vector3.new(0, 0, -1), WHITE, PM_NAVY)
	box(p, "Monitor", 2.4, 1.6, 0.2, -98, 5.6, -159.6, Color3.fromRGB(20, 20, 25), Enum.Material.SmoothPlastic, { CanCollide = false })
	box(p, "Tela", 2.1, 1.3, 0.05, -98, 5.75, -159.75, Color3.fromRGB(80, 160, 255), Enum.Material.Neon, { CanCollide = false })
	column(p, "Brasao", -122, 0.6, -162, 0.06, 5, PM_NAVY, Enum.Material.SmoothPlastic, { CanCollide = false })
	column(p, "Brasao", -122, 0.62, -162, 0.06, 3.6, GOLD, Enum.Material.SmoothPlastic, { CanCollide = false })
	column(p, "Brasao", -122, 0.64, -162, 0.06, 2.8, PM_NAVY, Enum.Material.SmoothPlastic, { CanCollide = false })
	for k = 0, 1 do
		seat(p, Vector3.new(7, 0.6, 2.4), -136 + k * 10, 2, -171.5, Vector3.new(0, 0, 1), Color3.fromRGB(40, 45, 55), "Sofá")
		box(p, "EncostoSofa", 7, 2.6, 0.8, -136 + k * 10, 0.6, -173.6, Color3.fromRGB(40, 45, 55), Enum.Material.Fabric)
	end
	box(p, "Trofeus", 10, 7, 1.6, -122, 0.6, MID - 1.3, WOOD, Enum.Material.Wood)
	for k = 0, 3 do
		column(p, "Trofeu", -125.6 + k * 2.4, 4.2, MID - 1.3, 1.4, 0.4, GOLD, Enum.Material.Metal, { CanCollide = false })
	end
	for _, pos in ipairs({ { -142, -152 }, { -77, -168 } }) do
		box(p, "Vaso", 2, 2, 2, pos[1], 0.6, pos[2], Color3.fromRGB(40, 40, 45), Enum.Material.Slate)
		part(p, "Planta", Vector3.new(3, 3.6, 3), at(pos[1], 4.2, pos[2]), Color3.fromRGB(60, 140, 70), Enum.Material.Grass, { Shape = Enum.PartType.Ball, CanCollide = false })
	end

	-- TÉRREO / FUNDO: ARSENAL (armas nos racks, coletes, escudos, armários e munição)
	local ARMY = Color3.fromRGB(85, 95, 65)
	local GUN = Color3.fromRGB(30, 32, 36)
	for k = 0, 3 do
		local rx = -146 + k * 17
		box(p, "RackArmas", 12, 8, 1, rx, 0.6, zB - 1.6, Color3.fromRGB(60, 64, 72), Enum.Material.Metal)
		for g = 0, 5 do
			local gx = rx - 5 + g * 2
			box(p, "Fuzil", 0.35, 5, 0.5, gx, 2, zB - 2.4, GUN, Enum.Material.Metal, { CanCollide = false })
			box(p, "Coronha", 0.5, 1.2, 0.8, gx, 1.6, zB - 2.4, GUN, Enum.Material.Metal, { CanCollide = false })
			box(p, "Pente", 0.4, 1, 0.6, gx, 4, zB - 2.8, GUN, Enum.Material.Metal, { CanCollide = false })
		end
		sign(p, "ARMAS " .. k + 1, 4, 0.9, rx, 8.4, zB - 2.15, Vector3.new(0, 0, -1), WHITE, Color3.fromRGB(170, 35, 35))
	end
	-- coletes à prova de bala em suportes (parede da direita)
	for k = 0, 3 do
		local vz = -145 + k * 4.5
		column(p, "Suporte", x2 - 3, 0.6, vz, 4, 0.2, STEEL, Enum.Material.Metal)
		box(p, "Colete", 1.4, 3, 2.6, x2 - 3, 4.4, vz, PM_NAVY, Enum.Material.Fabric)
		box(p, "FaixaColete", 1.5, 0.5, 2.7, x2 - 3, 6, vz, WHITE, Enum.Material.SmoothPlastic, { CanCollide = false })
	end
	-- escudos de choque e capacetes na parede do meio (longe da porta lateral)
	for k = 0, 4 do
		local sx = -152 + k * 3.4
		box(p, "Escudo", 2.6, 5, 0.3, sx, 0.8, MID + 1.6, Color3.fromRGB(190, 210, 230), Enum.Material.SmoothPlastic, { Transparency = 0.35 })
		box(p, "Capacete", 1.4, 1, 1.4, sx, 6.4, MID + 2, Color3.fromRGB(30, 30, 35), Enum.Material.SmoothPlastic, { CanCollide = false })
	end
	box(p, "Prateleira", 17, 0.3, 1.6, -145.2, 6.1, MID + 2, Color3.fromRGB(60, 64, 72), Enum.Material.Metal)
	-- armários dos policiais no meio, mesa de manutenção e caixas de munição
	for k = 0, 7 do
		local ax = -147 + k * 3.2
		box(p, "ArmarioPM", 3, 7.4, 2, ax, 0.6, -143, Color3.fromRGB(70, 90, 120), Enum.Material.Metal):SetAttribute("UniformLocker", true)
		box(p, "Placa", 1, 0.4, 0.1, ax, 6, -144.05, WHITE, Enum.Material.SmoothPlastic, { CanCollide = false })
	end
	box(p, "MesaArsenal", 12, 0.5, 5, -96, 3.4, -138, Color3.fromRGB(110, 115, 125), Enum.Material.Metal)
	box(p, "PeMesa", 11, 2.8, 4, -96, 0.6, -138, Color3.fromRGB(60, 64, 72), Enum.Material.Metal)
	for k = 0, 3 do
		box(p, "CaixaMunicao", 2, 1.2, 1.4, -100.5 + k * 3, 3.9, -138, ARMY, Enum.Material.Metal)
	end
	box(p, "Pistola", 1.4, 0.4, 0.3, -98, 4.1, -136.6, GUN, Enum.Material.Metal, { CanCollide = false })
	box(p, "Cofre", 4, 6, 3.4, -80, 0.6, -132, Color3.fromRGB(50, 55, 60), Enum.Material.DiamondPlate)
	column(p, "Volante", -80, 3.6, -133.8, 0.2, 0.9, GOLD, Enum.Material.Metal, { CanCollide = false })
	for _, x in ipairs({ -138, -113, -88 }) do
		local lamp = box(p, "Luminaria", 10, 0.2, 1.2, x, PM_F - 0.5, -138, Color3.fromRGB(255, 250, 240), Enum.Material.Neon, { CanCollide = false })
		light(lamp, 20, 0.6)
		lamp = box(p, "Luminaria", 10, 0.2, 1.2, x, PM_F - 0.5, -162, Color3.fromRGB(255, 250, 240), Enum.Material.Neon, { CanCollide = false })
		light(lamp, 20, 0.6)
	end

	-- 2º ANDAR / FRENTE: sala de briefing (cadeiras viradas para o telão)
	box(p, "ParedeMeio", x2 - (SX2 + 12), PM_F, T, (SX2 + 12 + x2) / 2, F2, MID, STONE, STONE_M)
	box(p, "ParedeMeio", 6, PM_F, T, SX2 + 3, F2, MID, STONE, STONE_M)
	box(p, "ParedeMeio", 6, PM_F - 9, T, SX2 + 9, F2 + 9, MID, STONE, STONE_M)
	box(p, "Telao", 22, 9, 0.4, -105, F2 + 1.8, MID - 0.8, Color3.fromRGB(20, 22, 28), Enum.Material.SmoothPlastic, { CanCollide = false })
	sign(p, "BRIEFING\nOperações da PM", 20, 7.6, -105, F2 + 6.3, MID - 1.1, Vector3.new(0, 0, -1), WHITE, Color3.fromRGB(30, 70, 140))
	box(p, "Palanque", 4, 4, 2.4, -120, F2, MID - 5, WOOD, Enum.Material.Wood)
	for row = 0, 2 do
		for k = 0, 5 do
			local cx, cz = -127 + k * 9, -170 + row * 5
			box(p, "CadeiraBriefing", 2, 2, 2, cx, F2, cz, PM_NAVY, Enum.Material.Fabric)
			box(p, "EncostoBriefing", 2, 2.4, 0.4, cx, F2 + 2, cz - 1.1, PM_NAVY, Enum.Material.Fabric)
			seat(p, Vector3.new(1.8, 0.3, 1.8), cx, F2 + 2.15, cz, Vector3.new(0, 0, 1), PM_NAVY, "Cadeira").Transparency = 1
		end
	end
	for _, x in ipairs({ -128, -100 }) do
		local lamp = box(p, "Luminaria", 10, 0.2, 1.2, x, TOP - 0.5, -162, Color3.fromRGB(255, 250, 240), Enum.Material.Neon, { CanCollide = false })
		light(lamp, 20, 0.6)
	end

	-- 2º ANDAR / FUNDO: escritórios, quadro de PROCURADOS e a sala do comandante (vidro)
	box(p, "QuadroProcurados", 18, 8, 0.3, -125, F2 + 2, zB - 1.2, Color3.fromRGB(150, 110, 70), Enum.Material.Cardboard, { CanCollide = false })
	sign(p, "PROCURADOS", 14, 1.6, -125, F2 + 9, zB - 1.45, Vector3.new(0, 0, -1), WHITE, Color3.fromRGB(170, 35, 35))
	for k = 0, 5 do
		local px, py = -131.5 + (k % 3) * 6.5, F2 + 3.5 + math.floor(k / 3) * 3.4
		box(p, "Cartaz", 3, 2.8, 0.1, px, py, zB - 1.4, Color3.fromRGB(245, 235, 200), Enum.Material.SmoothPlastic, { CanCollide = false })
		box(p, "Rosto", 1.2, 1.4, 0.05, px, py + 0.7, zB - 1.48, Color3.fromRGB(60, 60, 65), Enum.Material.SmoothPlastic, { CanCollide = false })
	end
	for k = 0, 3 do
		local dx = -140 + k * 11
		box(p, "Mesa", 6, 0.4, 3, dx, F2 + 3, -141, WOOD, Enum.Material.Wood)
		box(p, "PeMesa", 5.6, 3, 2.6, dx, F2, -141, Color3.fromRGB(60, 64, 72), Enum.Material.Metal)
		box(p, "Monitor", 2.6, 1.8, 0.2, dx, F2 + 3.4, -141.9, Color3.fromRGB(20, 20, 25), Enum.Material.SmoothPlastic, { CanCollide = false })
		box(p, "Tela", 2.3, 1.5, 0.05, dx, F2 + 3.55, -141.75, Color3.fromRGB(80, 160, 255), Enum.Material.Neon, { CanCollide = false })
		box(p, "CadeiraEscritorio", 2, 2, 2, dx, F2, -138, Color3.fromRGB(30, 30, 35), Enum.Material.Fabric)
		seat(p, Vector3.new(1.8, 0.3, 1.8), dx, F2 + 2.15, -138, Vector3.new(0, 0, -1), Color3.fromRGB(30, 30, 35), "Cadeira").Transparency = 1
	end
	box(p, "MaquinaCafe", 2.4, 4, 2, -150, F2, -132, Color3.fromRGB(40, 40, 45), Enum.Material.Metal)
	box(p, "Bebedouro", 1.6, 4.4, 1.6, -150, F2, -129.5, Color3.fromRGB(200, 220, 240), Enum.Material.SmoothPlastic)
	-- sala do comandante (parede de vidro com porta aberta)
	local CX = -92
	box(p, "VidroComandante", 0.3, PM_F - 0.6, 12, CX, F2, MID + 6.5, GLASS, Enum.Material.SmoothPlastic, { Transparency = 0.5 })
	box(p, "VidroComandante", 0.3, PM_F - 0.6, 4, CX, F2, zB - 3, GLASS, Enum.Material.SmoothPlastic, { Transparency = 0.5 })
	box(p, "MesaComandante", 8, 3.4, 3.4, -80, F2, -138, Color3.fromRGB(110, 70, 45), Enum.Material.Wood)
	seat(p, Vector3.new(2.2, 0.4, 2.2), -80, F2 + 2.2, -134.5, Vector3.new(0, 0, -1), Color3.fromRGB(60, 30, 25), "Cadeira do comandante")
	box(p, "EncostoComandante", 2.4, 3.4, 0.5, -80, F2 + 2.2, -133.2, Color3.fromRGB(60, 30, 25), Enum.Material.Leather)
	sign(p, "COMANDO", 6, 1.2, CX - 0.3, F2 + 9.5, MID + 5, Vector3.new(-1, 0, 0), WHITE, PM_NAVY)
	for _, z in ipairs({ -134, -144 }) do
		column(p, "MastroSala", -73, F2, z, 8, 0.15, GOLD, Enum.Material.Metal)
	end
	box(p, "BandeiraSala", 0.2, 2.4, 3.4, -73, F2 + 5.2, -136, Color3.fromRGB(0, 150, 60), Enum.Material.Fabric, { CanCollide = false })
	box(p, "BandeiraSala", 0.2, 2.4, 3.4, -73, F2 + 5.2, -146, PM_NAVY, Enum.Material.Fabric, { CanCollide = false })
	for _, x in ipairs({ -138, -110, -82 }) do
		local lamp = box(p, "Luminaria", 10, 0.2, 1.2, x, TOP - 0.5, -138, Color3.fromRGB(255, 250, 240), Enum.Material.Neon, { CanCollide = false })
		light(lamp, 20, 0.6)
	end
end

-- Garagem das viaturas: só o Policial tira carro aqui (VehicleService confere o ServiceJob)
local function buildPoliceGarage(m, parent)
	local folder = parent:FindFirstChild("Garages") or m
	local g = K.model("GaragemPolicia", folder)
	g:SetAttribute("ServiceJob", "Policial")
	local Z = -160
	for _, x in ipairs({ -229, -200, -171 }) do
		box(g, "FaixaVaga", 0.5, 0.05, 20, x, 0.3, Z, LINE, Enum.Material.SmoothPlastic, { CanCollide = false })
	end
	for k, x in ipairs({ -215, -185 }) do
		box(g, "Vaga" .. k, 1, 1, 1, x, 0.3, Z, WHITE, Enum.Material.SmoothPlastic, { Transparency = 1, CanCollide = false })
		box(g, "Numero", 6, 0.05, 3, x, 0.31, Z + 7, Color3.fromRGB(250, 250, 250), Enum.Material.SmoothPlastic, { CanCollide = false })
	end
	-- cobertura em cima das vagas (alta, para a viatura caber)
	box(g, "Cobertura", 64, 0.8, 26, -200, 12, Z + 2, PM_NAVY, Enum.Material.Metal)
	box(g, "FaixaCobertura", 64.4, 1, 0.6, -200, 11.6, Z - 11.2, STEEL, Enum.Material.Metal, { CanCollide = false })
	for _, x in ipairs({ -231, -200, -169 }) do
		column(g, "Pilar", x, 0.3, Z + 14, 11.7, 0.5, STEEL, Enum.Material.Metal)
	end
	sign(g, "VIATURAS • SÓ POLICIAIS", 22, 1.6, -200, 13.4, Z - 11.2, Vector3.new(0, 0, -1), WHITE, PM_NAVY)
	-- guarita do balcão (é aqui que abre a garagem)
	box(g, "BaseGuarita", 6, 1, 6, -200, 0.3, -184, CONCRETE, Enum.Material.Concrete)
	local booth = box(g, "Balcao", 4, 3.6, 2, -200, 1.3, -184, PM_NAVY, Enum.Material.SmoothPlastic)
	booth:SetAttribute("Police", true)
	box(g, "TampoGuarita", 4.4, 0.3, 2.4, -200, 4.9, -184, STEEL, Enum.Material.Metal)
	box(g, "TelhadoGuarita", 7, 0.5, 7, -200, 9, -184, PM_NAVY, Enum.Material.Metal)
	for _, sx in ipairs({ -1, 1 }) do
		box(g, "PilarGuarita", 0.5, 7.7, 0.5, -200 + sx * 3, 1.3, -186.8, STEEL, Enum.Material.Metal)
	end
	sign(g, "GARAGEM DA PM", 6.4, 1.2, -200, 8.2, -187.5, Vector3.new(0, 0, -1), WHITE, PM_NAVY)
	local lamp = box(g, "Luz", 1, 0.4, 1, -200, 8.6, -184, Color3.fromRGB(255, 60, 60), Enum.Material.Neon, { CanCollide = false })
	light(lamp, 10, 0.6, Color3.fromRGB(255, 90, 90))
	return g
end

---------------------------------------------------------------------------

function PrisonBuilder.build(parent, cf, kit)
	K = kit
	base = cf
	local m = K.model("Penitenciaria", parent)
	m:SetAttribute("PrisonName", PR.Name)
	m:SetAttribute("Width", PR.Width)
	m:SetAttribute("Depth", PR.Depth)
	-- área de segurança (onde o preso pode andar), em coordenadas da prisão
	m:SetAttribute("SecureMin", Vector3.new(IN_X1 + 1, -20, IN_Z1 + 1))
	m:SetAttribute("SecureMax", Vector3.new(IN_X2 - 1, 120, IN_Z2 - 1))
	buildGrounds(m)
	-- cerca dupla de fora (arame só na de dentro), com a abertura da entrada
	local outer = K.model("CercaExterna", m)
	fenceRect(outer, -HW + 2, -HD + 4, HW - 2, HD - 2, PR.OuterFence, false, { { side = "front", c = 0, w = 30 } })
	fenceRect(outer, -HW + 8, -HD + 10, HW - 8, HD - 8, PR.OuterFence, true, { { side = "front", c = 0, w = 30 } })
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			guardTower(m, sx * (HW - 12), sz * (HD - 12), Vector3.new(-sx, 0, -sz).Unit)
		end
	end
	buildEntrance(m)
	buildAdmin(m)
	buildFrontYard(m)
	buildSecureArea(m)
	buildCanteen(m)
	sideBuilding(m, "Enfermaria", "ENFERMARIA", -1, 82, Color3.fromRGB(200, 45, 45), infirmary)
	sideBuilding(m, "Escola", "ESCOLA E OFICINAS", 1, 82, NAVY, school)
	buildControlTower(m)
	buildLaundry(m)
	buildLibrary(m)
	buildPoliceBase(m)
	buildPoliceGarage(m, parent)
	m.WorldPivot = cf
	return m
end

return PrisonBuilder
