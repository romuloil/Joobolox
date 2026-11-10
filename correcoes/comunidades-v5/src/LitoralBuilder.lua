-- LitoralBuilder (ModuleScript)
-- Caminho: ServerScriptService > Services > LitoralBuilder
-- Marco 10.31: Costa do Sol, o litoral no fim da Estrada Sul. Inspirado nas orlas da Califórnia
-- (calçadão com barracas, palmeiras altas, píer com parque de diversões, academia na areia, pista de
-- skate, postos de salva-vidas), com um toque brasileiro (calçadão de ondas, água de coco, açaí).
--
-- Organização (de norte para sul, +Z = sul):
--   Rotatória da Costa (portal) -> Avenida Costa do Sol (boulevard) -> bairro (Rua das Gaivotas e 4
--   transversais, prédios, hotéis e casas de praia) -> Avenida Beira-Mar (boulevard) -> casinhas
--   coloridas viradas para o mar -> calçadão de ondas -> gramado com palmeiras -> ciclovia -> areia
--   -> mar (água de Terrain até a borda do mapa). No eixo da avenida, o píer com a MigueLândia.
--
-- Duas etapas, como os outros bairros: plan (reserva os lotes antes do campo) e build (constrói
-- depois de tudo, para os números das casas antigas não mudarem). Sorteio próprio (L.Seed).
-- O que é interativo (lanches, academia, vôlei, turistas) fica no LitoralService, achado pelos
-- atributos das peças (LitoralSnack, LitoralGym, LitoralBall, LitoralSpot).

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))
local HorizonteBuilder = require(script.Parent:WaitForChild("HorizonteBuilder"))
local SurfBoards = require(script.Parent:WaitForChild("SurfBoards"))
local OrlaShops = require(script.Parent:WaitForChild("OrlaShops"))
local CondoBuilder = require(script.Parent:WaitForChild("CondoBuilder"))
local CollectionService = game:GetService("CollectionService")

local LitoralBuilder = {}

local L = GameConfig.Litoral
local M = GameConfig.Map
local K -- ferramentas do MapBuilder
local rng

local BALL, CYL = Enum.PartType.Ball, Enum.PartType.Cylinder
local SAND = Color3.fromRGB(232, 211, 160)
local SAND_WET = Color3.fromRGB(196, 172, 124)
local WALK = Color3.fromRGB(240, 232, 214)
local WAVE = Color3.fromRGB(38, 40, 44)
local WOOD = Color3.fromRGB(158, 122, 82)
local WOOD_DARK = Color3.fromRGB(110, 82, 55)
local WHITE = Color3.fromRGB(248, 248, 244)
local METAL = Color3.fromRGB(70, 76, 84)
local LIFE_BLUE = Color3.fromRGB(110, 190, 220)
local RED = Color3.fromRGB(220, 60, 55)
local YELLOW = Color3.fromRGB(250, 205, 60)
local GRASS = Color3.fromRGB(96, 170, 80)
local PASTELS = {
	Color3.fromRGB(246, 190, 160), Color3.fromRGB(160, 214, 205), Color3.fromRGB(250, 226, 150),
	Color3.fromRGB(190, 175, 225), Color3.fromRGB(240, 160, 170), Color3.fromRGB(170, 205, 240),
	Color3.fromRGB(245, 245, 235), Color3.fromRGB(150, 205, 150),
}
local AWNING = { RED, Color3.fromRGB(40, 120, 200), Color3.fromRGB(30, 150, 110), Color3.fromRGB(240, 130, 40), Color3.fromRGB(150, 70, 180) }
local SHOPS = {
	"Surf Shop", "Sorveteria", "Açaí da Orla", "Bar do Zé", "Óculos & Cia", "Pranchas Sol", "Tatuagem",
	"Pastelaria", "Bike Aluguel", "Moda Praia", "Souvenirs", "Sucos Naturais", "Peixaria", "Café Brisa",
	"Pizza na Areia", "Skate Shop", "Biquínis", "Chapéus", "Artesanato", "Lanchonete Maré",
}

-- Lanches das barracas (ordem em que aparecem no calçadão)
local SNACK_ORDER = { "Coco", "Acai", "Picole", "Milho", "Churros" }
local SNACK_COLORS = {
	Coco = Color3.fromRGB(70, 160, 80), Acai = Color3.fromRGB(110, 40, 120), Picole = Color3.fromRGB(240, 120, 160),
	Milho = Color3.fromRGB(240, 190, 40), Churros = Color3.fromRGB(200, 120, 50),
}

---------------------------------------------------------------------------
-- Básico
---------------------------------------------------------------------------

local function P(parent, name, size, cf, color, material, extra)
	local props = { Name = name, Size = size, CFrame = cf, Color = color, Material = material or Enum.Material.SmoothPlastic }
	for k, v in pairs(extra or {}) do
		props[k] = v
	end
	return K.makePart(parent, props)
end

-- caixa alinhada ao mundo, de (x0, y0, z0) até (x1, y1, z1); peças grandes viram pedaços (máx. 2048)
local function box(parent, name, x0, x1, y0, y1, z0, z1, color, material, extra)
	local w, d = x1 - x0, z1 - z0
	local nx, nz = math.ceil(w / 2000), math.ceil(d / 2000)
	local last
	for i = 0, nx - 1 do
		for j = 0, nz - 1 do
			local a0, a1 = x0 + w * i / nx, x0 + w * (i + 1) / nx
			local b0, b1 = z0 + d * j / nz, z0 + d * (j + 1) / nz
			last = P(parent, name, Vector3.new(a1 - a0, y1 - y0, b1 - b0), CFrame.new((a0 + a1) / 2, (y0 + y1) / 2, (b0 + b1) / 2), color, material, extra)
		end
	end
	return last
end

local function nocollide(extra)
	extra = extra or {}
	extra.CanCollide = false
	return extra
end

-- cilindro em pé (base em pos)
local function column(parent, name, pos, height, radius, color, material, extra)
	return P(parent, name, Vector3.new(height, radius * 2, radius * 2), CFrame.new(pos + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)), color, material, (function()
		local e = { Shape = CYL }
		for k, v in pairs(extra or {}) do
			e[k] = v
		end
		return e
	end)())
end

local function sign(parent, cf, size, text, textColor, bg)
	local p = P(parent, "Placa", size, cf, bg, Enum.Material.SmoothPlastic, nocollide())
	K.addSurfaceText(p, text, textColor, bg)
	return p
end

-- lugar para o mapa/GPS (modelo pequeno com uma peça invisível)
local placesFolder
local function addSpot(name, icon, pos, curbPos, color)
	local m = K.model(name, placesFolder)
	local p = P(m, "Ponto", Vector3.new(1, 1, 1), CFrame.new(pos + Vector3.new(0, 1, 0)), WHITE, nil, { Transparency = 1, CanCollide = false })
	p.CanQuery = false
	p.CanTouch = false
	m:SetAttribute("PlaceName", name)
	m:SetAttribute("Icon", icon)
	m:SetAttribute("IconColor", color)
	if curbPos then
		m:SetAttribute("Curb", CFrame.lookAt(curbPos, curbPos + Vector3.new(0, 0, -1)))
	end
	m.PrimaryPart = p
	return m
end

-- banco de praça virado para lookDir
local function bench(parent, pos, yaw)
	local cf = CFrame.new(pos) * CFrame.Angles(0, yaw, 0)
	local seat = P(parent, "Banco", Vector3.new(5, 0.4, 1.6), cf * CFrame.new(0, 1.6, 0), WOOD, Enum.Material.WoodPlanks, { ClassName = "Seat" })
	seat:SetAttribute("SeatText", "Sentar")
	P(parent, "Encosto", Vector3.new(5, 1.4, 0.3), cf * CFrame.new(0, 2.5, 0.7), WOOD, Enum.Material.WoodPlanks)
	for _, x in ipairs({ -2, 2 }) do
		P(parent, "Pe", Vector3.new(0.4, 1.4, 1.4), cf * CFrame.new(x, 0.8, 0), METAL, Enum.Material.Metal)
	end
end

-- poste do calçadão (dois globos, estilo píer antigo)
local function globeLamp(parent, pos, withLight)
	local lamp = K.model("PosteOrla", parent)
	column(lamp, "Poste", pos, 13, 0.3, METAL, Enum.Material.Metal)
	P(lamp, "Braco", Vector3.new(5, 0.25, 0.25), CFrame.new(pos + Vector3.new(0, 12.6, 0)), METAL, Enum.Material.Metal, nocollide())
	for _, x in ipairs({ -2.4, 2.4 }) do
		local g = P(lamp, "Globo", Vector3.new(1.5, 1.5, 1.5), CFrame.new(pos + Vector3.new(x, 13.4, 0)), Color3.fromRGB(255, 244, 220), Enum.Material.Neon, nocollide({ Shape = BALL }))
		if withLight and x > 0 then
			local light = Instance.new("PointLight")
			light.Range = 22
			light.Brightness = 1
			light.Color = Color3.fromRGB(255, 225, 175)
			light.Parent = g
		end
	end
	return lamp
end

-- palmeira alta da orla (escala grande, tronco fino como as da Califórnia)
local function tallPalm(parent, pos, scale)
	if K.palm then
		return K.palm(parent, pos, scale)
	end
	column(parent, "Tronco", pos, 14 * scale, 0.5 * scale, Color3.fromRGB(150, 115, 75), Enum.Material.Wood)
end

-- Marco 10.31: no píer as árvores do parque viram palmeiras em vasos (chamado na etapa do parque,
-- antes do resto: não usa o sorteio de ninguém)
function LitoralBuilder.pierPlanter(parent, position, scale, makePart, model)
	scale = scale or 1
	local m = model("Palmeira", parent)
	local function p(name, size, cf, color, material, extra)
		local props = { Name = name, Size = size, CFrame = cf, Color = color, Material = material }
		for k, v in pairs(extra or {}) do
			props[k] = v
		end
		return makePart(m, props)
	end
	p("Vaso", Vector3.new(4.5, 2.4, 4.5), CFrame.new(position + Vector3.new(0, 1.2, 0)), Color3.fromRGB(235, 225, 205), Enum.Material.Concrete)
	p("Terra", Vector3.new(4, 0.2, 4), CFrame.new(position + Vector3.new(0, 2.45, 0)), Color3.fromRGB(90, 65, 45), Enum.Material.Ground)
	local h = 12 * scale
	for i = 0, 3 do
		local y = 2.4 + h * (i + 0.5) / 4
		p("Tronco", Vector3.new(0.9 * scale, h / 4 + 0.3, 0.9 * scale), CFrame.new(position + Vector3.new(0, y, 0)), Color3.fromRGB(150, 115, 75), Enum.Material.Wood)
	end
	local top = position + Vector3.new(0, 2.4 + h, 0)
	for k = 0, 5 do
		local a = k * math.pi / 3 + position.X * 0.01
		local frond = CFrame.new(top) * CFrame.Angles(0, a, 0) * CFrame.Angles(math.rad(-25), 0, 0) * CFrame.new(0, 0, -2.8 * scale)
		p("Folha", Vector3.new(1.4 * scale, 0.2, 5.6 * scale), frond, Color3.fromRGB(60, 160, 70), Enum.Material.Grass, { CanCollide = false })
	end
	return m
end

---------------------------------------------------------------------------
-- Etapa 1: reserva (antes do campo e das garagens)
---------------------------------------------------------------------------

local SIDE = M.SidewalkWidth
-- Morros verdes atrás do bairro (fundo bonito para quem olha da praia)
local HILLS = { -- x, z, raio
	{ -2500, 3000, 260 }, { -3400, 3150, 340 }, { 2600, 3000, 280 }, { 3500, 3150, 360 },
	{ -4700, 3250, 420 }, { 4800, 3200, 440 },
}
local BLVD_HALF = 30 -- meia largura do boulevard (2 x 24 + 12)
local RUA_HALF = M.RoadWidth / 2

-- lote ao lado de uma rua reta: frente (-Z do lote) virada para a rua
local function lotAlong(a, b, t, side, depth, half)
	local dir = (b - a).Unit
	local perp = Vector3.new(-dir.Z, 0, dir.X)
	local center = a + dir * t + perp * side * (half + SIDE + 0.6 + depth / 2)
	return CFrame.lookAt(center, center - perp * side)
end

function LitoralBuilder.plan(map, helpers)
	K = helpers
	rng = Random.new(L.Seed)
	local root = K.folder("Litoral", map)
	local plan = { root = root, items = {} }
	local function reserve(kind, lot, w, d, extra)
		local area = K.rect(lot, w, d)
		if not K.isFree(area) then
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

	-- Avenida Beira-Mar, lado norte (vista para o mar): hotéis nas esquinas da avenida e prédios
	local bmA = Vector3.new(-L.BeiraMarHalf, 0, L.BeiraMarZ)
	local bmB = Vector3.new(L.BeiraMarHalf, 0, L.BeiraMarZ)
	local TW, TD = HorizonteBuilder.TOWER_W, HorizonteBuilder.TOWER_D
	local hotels = {
		{ x = -110, cfg = { Name = "Hotel Costa do Sol", Floors = 14, Style = "sacadas", Wall = Color3.fromRGB(245, 240, 228), Accent = Color3.fromRGB(40, 140, 190) } },
		{ x = 110, cfg = { Name = "Residencial Maré Alta", Floors = 12, Style = "vidro", Wall = Color3.fromRGB(200, 225, 235), Accent = Color3.fromRGB(240, 150, 60) } },
		{ x = -1500, cfg = { Name = "Edifício Gaivota", Floors = 9, Style = "sacadas", Wall = Color3.fromRGB(250, 226, 190), Accent = Color3.fromRGB(230, 90, 80) } },
		{ x = 1500, cfg = { Name = "Edifício Coral", Floors = 10, Style = "sacadas", Wall = Color3.fromRGB(250, 200, 190), Accent = Color3.fromRGB(60, 160, 150) } },
	}
	for _, h in ipairs(hotels) do
		local t = h.x + L.BeiraMarHalf
		reserve("torre", lotAlong(bmA, bmB, t, -1, TD, BLVD_HALF), TW, TD, { cfg = h.cfg, street = L.BeiraMarName, t = t, side = -1 })
	end
	-- prédios com lojinha no térreo no resto da Beira-Mar (os dois lados das transversais)
	local LOT_D = 34
	local t = 40
	while t < 2 * L.BeiraMarHalf - 40 do
		local w = rng:NextInteger(34, 44)
		local item = reserve("loja", lotAlong(bmA, bmB, t, -1, LOT_D, BLVD_HALF), w + 2, LOT_D, { street = L.BeiraMarName, t = t, side = -1, lotW = w, floors = rng:NextInteger(3, 6) })
		t += (item and (w / 2 + 24) or 8)
	end
	-- Rua das Gaivotas: casas de praia dos dois lados
	local gA = Vector3.new(-L.TownHalf, 0, L.TownZ)
	local gB = Vector3.new(L.TownHalf, 0, L.TownZ)
	for _, side in ipairs({ -1, 1 }) do
		t = 30
		while t < 2 * L.TownHalf - 30 do
			local variant = rng:NextInteger(1, 3)
			local w = variant == 3 and 46 or rng:NextInteger(34, 38)
			local item = reserve("casa", lotAlong(gA, gB, t, side, 38, RUA_HALF), w + 2, 38, { street = L.TownName, t = t, side = side, lotW = w, variant = variant })
			t += (item and (w / 2 + 26 + (rng:NextNumber() < 0.15 and 30 or 0)) or 6)
		end
	end
	-- transversais: prédios baixos com comércio
	for _, st in ipairs(L.CrossStreets) do
		local a = Vector3.new(st.X, 0, L.TownZ)
		local b = Vector3.new(st.X, 0, L.BeiraMarZ)
		for _, side in ipairs({ -1, 1 }) do
			t = 40
			while t < (b - a).Magnitude - 50 do
				local w = rng:NextInteger(32, 40)
				local item = reserve("loja", lotAlong(a, b, t, side, LOT_D, RUA_HALF), w + 2, LOT_D, { street = st.Name, t = t, side = side, lotW = w, floors = rng:NextInteger(2, 4) })
				t += (item and (w / 2 + 24) or 8)
			end
		end
	end
	-- Marco 10.32: miolo das quadras (entre a Rua das Gaivotas e a Beira-Mar): condomínios
	-- fechados e prédios residenciais. Vêm depois de tudo (não mudam casas, lojas nem números).
	local crng = Random.new(L.Seed + 3210)
	local CZ0, CZ1 = 3141, 3293 -- miolo livre (os hotéis da Beira-Mar entram até ~3297)
	local towerCfgs = {
		{ Name = "Residencial Coqueiros", Floors = 11, Style = "sacadas", Wall = Color3.fromRGB(246, 238, 222), Accent = Color3.fromRGB(40, 150, 140) },
		{ Name = "Edifício Brisa Azul", Floors = 13, Style = "vidro", Wall = Color3.fromRGB(205, 225, 240), Accent = Color3.fromRGB(40, 110, 190) },
		{ Name = "Torre Atlântica", Floors = 15, Style = "vidro", Wall = Color3.fromRGB(225, 232, 236), Accent = Color3.fromRGB(230, 120, 50) },
		{ Name = "Edifício Sol Nascente", Floors = 10, Style = "sacadas", Wall = Color3.fromRGB(250, 222, 190), Accent = Color3.fromRGB(220, 80, 70) },
		{ Name = "Residencial Ilha Bela", Floors = 12, Style = "sacadas", Wall = Color3.fromRGB(235, 245, 230), Accent = Color3.fromRGB(70, 150, 80) },
		{ Name = "Edifício Maresia", Floors = 9, Style = "sacadas", Wall = Color3.fromRGB(240, 215, 220), Accent = Color3.fromRGB(150, 70, 160) },
		{ Name = "Torre Horizonte Azul", Floors = 14, Style = "vidro", Wall = Color3.fromRGB(210, 220, 230), Accent = Color3.fromRGB(240, 170, 40) },
		{ Name = "Edifício Concha Dourada", Floors = 10, Style = "sacadas", Wall = Color3.fromRGB(250, 236, 200), Accent = Color3.fromRGB(200, 140, 60) },
		{ Name = "Residencial Farol Alto", Floors = 12, Style = "vidro", Wall = Color3.fromRGB(230, 236, 242), Accent = Color3.fromRGB(200, 60, 60) },
		{ Name = "Edifício Areia Branca", Floors = 8, Style = "sacadas", Wall = Color3.fromRGB(248, 244, 232), Accent = Color3.fromRGB(60, 140, 200) },
	}
	local condoWalls = { Color3.fromRGB(244, 236, 220), Color3.fromRGB(226, 236, 230), Color3.fromRGB(240, 226, 214), Color3.fromRGB(230, 232, 240) }
	local nTower, nCondo = 0, 0
	local SOUTH = Vector3.new(0, 0, 1)
	for _, side in ipairs({ 1, -1 }) do
		local blocks = {
			-- { x0, x1 (lado positivo), onde fica o condomínio, quantos prédios }
			{ 40, 545, "inicio", 2 }, -- ao lado da Avenida Costa do Sol (portão para a avenida)
			{ 655, 1145, "fim", 2 },
			{ 1256, 1720, "inicio", 1 },
		}
		for bi, blk in ipairs(blocks) do
			local a, b = blk[1], blk[2]
			local CW = 220
			local cx0 = blk[3] == "inicio" and a + 2 or b - CW - 2
			local ccx = side * (cx0 + CW / 2)
			local ccz = (CZ0 + CZ1) / 2
			-- frente do condomínio: para a avenida (quadra do meio) ou para o sul
			local face = (bi == 1) and Vector3.new(-side, 0, 0) or SOUTH
			local lotCF = CFrame.lookAt(Vector3.new(ccx, 0, ccz), Vector3.new(ccx, 0, ccz) + face)
			local W, Dd = (bi == 1) and (CZ1 - CZ0) or CW, (bi == 1) and CW or (CZ1 - CZ0)
			nCondo += 1
			reserve("condominio", lotCF, W + 4, Dd + 4, {
				street = side > 0 and "Alameda das Palmeiras" or "Alameda dos Coqueiros", t = math.abs(ccx), side = 1,
				W = W, D = Dd, name = CondoBuilder.NAMES[(nCondo - 1) % #CondoBuilder.NAMES + 1],
				wall = condoWalls[crng:NextInteger(1, #condoWalls)], accent = AWNING[crng:NextInteger(1, #AWNING)],
			})
			-- prédios no resto da quadra, virados para o mar
			local fx0 = blk[3] == "inicio" and cx0 + CW + 20 or a + 10
			for k = 0, blk[4] - 1 do
				local tcx = fx0 + TW / 2 + k * (TW + 30)
				if tcx + TW / 2 < (blk[3] == "inicio" and b or cx0 - 10) and nTower < #towerCfgs then
					nTower += 1
					local c = Vector3.new(side * tcx, 0, ccz)
					reserve("torre", CFrame.lookAt(c, c + SOUTH), TW, TD, {
						cfg = towerCfgs[nTower], street = side > 0 and "Alameda das Palmeiras" or "Alameda dos Coqueiros", t = tcx, side = 1,
					})
				end
			end
		end
	end

	-- morros (só onde estiver livre) e o portal da avenida
	plan.hills = {}
	for _, h in ipairs(HILLS) do
		local area = K.rect(CFrame.new(h[1], 0, h[2]), h[3] * 1.6, h[3] * 1.6)
		if K.isFree(area) then
			K.occupy(area)
			table.insert(plan.hills, h)
		end
	end
	K.occupy(K.rect(CFrame.new(0, 0, L.EntryZ + L.RoundaboutRadius + 70), 150, 30))
	-- A orla inteira (casinhas, calçadão, areia e mar) fica reservada
	K.occupy(K.rect(CFrame.new(0, 0, (L.FrontZ0 - 2 + M.GroundSize / 2) / 2), M.GroundSize, M.GroundSize / 2 - L.FrontZ0 + 2))
	plan.lotCount = #plan.items
	return plan
end

---------------------------------------------------------------------------
-- Etapa 2: construção
---------------------------------------------------------------------------

-- Mar: água de Terrain da linha do mar até a borda sul do mapa (de ponta a ponta)
local function buildSea()
	local terrain = Workspace.Terrain
	terrain.WaterColor = Color3.fromRGB(28, 126, 150)
	terrain.WaterTransparency = 0.5
	terrain.WaterReflectance = 0.3
	terrain.WaterWaveSize = 0.12
	terrain.WaterWaveSpeed = 8
	local half = M.GroundSize / 2
	local z0 = L.SeaZ - 110
	local depth = L.SeaLevel - L.SeaBottom
	local STEP = 500
	for x = -half, half - 1, STEP do
		for z = z0, half - 1, STEP do
			local w, d = math.min(STEP, half - x), math.min(STEP, half - z)
			terrain:FillBlock(CFrame.new(x + w / 2, L.SeaBottom + depth / 2, z + d / 2), Vector3.new(w, depth, d), Enum.Material.Water)
			terrain:FillBlock(CFrame.new(x + w / 2, L.SeaBottom - 2, z + d / 2), Vector3.new(w, 4, d), Enum.Material.Sand)
		end
		task.wait()
	end
end

-- Marco 10.32: a areia é Terrain de verdade (com o relevo e a textura do Roblox), de ponta a ponta
-- do mapa: na praia é plana (as quadras e a academia ficam em cima), fora do calçadão viram dunas
-- com vegetação de restinga. Depois da areia plana ela desce em rampa até o fundo do mar.
local terrainParams = RaycastParams.new()
terrainParams.FilterType = Enum.RaycastFilterType.Include
terrainParams.IgnoreWater = true

-- altura da areia (Terrain) em (x, z)
local function sandY(x, z)
	terrainParams.FilterDescendantsInstances = { Workspace.Terrain }
	local hit = Workspace:Raycast(Vector3.new(x, 40, z), Vector3.new(0, -80, 0), terrainParams)
	return hit and hit.Position.Y or 0.4
end
LitoralBuilder.sandY = sandY

local SAND_TOP = 0.4
local SLOPE = 250 -- da areia plana até o fundo do mar

-- caixa de areia (Terrain) em pedaços de até 1000 studs
local function sandBlock(x0, x1, z0, z1, y0, y1)
	local terrain = Workspace.Terrain
	local nx, nz = math.ceil((x1 - x0) / 1000), math.ceil((z1 - z0) / 1000)
	for i = 0, nx - 1 do
		for j = 0, nz - 1 do
			local a0, a1 = x0 + (x1 - x0) * i / nx, x0 + (x1 - x0) * (i + 1) / nx
			local b0, b1 = z0 + (z1 - z0) * j / nz, z0 + (z1 - z0) * (j + 1) / nz
			terrain:FillBlock(CFrame.new((a0 + a1) / 2, (y0 + y1) / 2, (b0 + b1) / 2), Vector3.new(a1 - a0, y1 - y0, b1 - b0), Enum.Material.Sand)
		end
	end
end

-- lugares da praia que ficam planos (quadras, academia, píer, postos)
local function busyAt(x, z, pad)
	pad = pad or 0
	if math.abs(x) < L.Pier.Width / 2 + 30 + pad then
		return true
	end
	for _, r in ipairs(LitoralBuilder.FLAT or {}) do
		if x > r[1] - pad and x < r[2] + pad and z > r[3] - pad and z < r[4] + pad then
			return true
		end
	end
	return false
end

-- vegetação de restinga (capim, arbustos e coqueiros) em cima das dunas
local function restinga(parent, x, z)
	local y = sandY(x, z)
	local roll = rng:NextNumber()
	if roll < 0.62 then
		local tuft = K.model("Capim", parent)
		local green = Color3.fromRGB(110 + rng:NextInteger(0, 40), 150 + rng:NextInteger(0, 30), 70)
		for k = 1, 4 do
			local h = rng:NextNumber(1.4, 3)
			P(tuft, "Folha", Vector3.new(0.25, h, 0.6), CFrame.new(x + rng:NextNumber(-1.2, 1.2), y + h / 2 - 0.2, z + rng:NextNumber(-1.2, 1.2)) * CFrame.Angles(rng:NextNumber(-0.4, 0.4), rng:NextNumber(0, 6), rng:NextNumber(-0.4, 0.4)), green, Enum.Material.Grass, nocollide())
		end
	elseif roll < 0.9 then
		local s = rng:NextNumber(2.5, 5)
		P(parent, "Arbusto", Vector3.new(s * 1.4, s * 0.7, s * 1.2), CFrame.new(x, y + s * 0.15, z) * CFrame.Angles(0, rng:NextNumber(0, 6), 0), Color3.fromRGB(70 + rng:NextInteger(0, 30), 120 + rng:NextInteger(0, 30), 60), Enum.Material.Grass, { Shape = BALL, CanCollide = false })
	else
		tallPalm(parent, Vector3.new(x, y - 0.3, z), rng:NextNumber(1.4, 2.2))
	end
end

local function buildBeach(root)
	local f = K.model("Praia", root)
	local terrain = Workspace.Terrain
	terrain:SetMaterialColor(Enum.Material.Sand, Color3.fromRGB(226, 206, 156))
	local half = M.GroundSize / 2
	local W = L.BeiraMarHalf - 20 -- até aqui vai o calçadão
	local bottom = L.SeaBottom - 4
	-- 1. embaixo do calçadão, casinhas e ciclovia (coberto pelas peças)
	sandBlock(-W, W, L.SandStartZ, L.BikeZ1, bottom, -0.6)
	-- 2. areia plana da praia e, dos lados, de onde termina o chão
	sandBlock(-W, W, L.BikeZ1, L.SandFlatZ, bottom, SAND_TOP)
	for _, side in ipairs({ -1, 1 }) do
		sandBlock(math.min(side * W, side * half), math.max(side * W, side * half), L.SandStartZ - 6, L.SandFlatZ, bottom, SAND_TOP)
	end
	task.wait()
	-- 3. rampa até o fundo do mar (faixas de 4 studs)
	for z = L.SandFlatZ, L.SandFlatZ + SLOPE - 4, 4 do
		local t = (z + 2 - L.SandFlatZ) / SLOPE
		local top = SAND_TOP + (L.SeaBottom - SAND_TOP) * t
		if top - bottom > 0.5 then
			sandBlock(-half, half, z, z + 4, bottom, top)
		end
	end
	task.wait()
	-- 4. relevo: na praia, ondinhas baixas (fora das quadras); dos lados do calçadão, dunas com
	-- restinga, mais altas longe do mar e baixando até a areia plana perto da água
	local dunesZ1 = L.SandFlatZ - 70
	for x = -half + 40, half - 40, 46 do
		local outside = math.abs(x) > W + 30
		local z = (outside and L.SandStartZ or L.BikeZ1) + 30
		while z < (outside and dunesZ1 or L.SandFlatZ - 30) do
			local jx, jz = x + rng:NextNumber(-14, 14), z + rng:NextNumber(-12, 12)
			if outside then
				local k = math.clamp((dunesZ1 - jz) / (dunesZ1 - L.SandStartZ), 0, 1)
				local h = rng:NextNumber(1, 2.5) + 5.5 * k
				local r = rng:NextNumber(18, 34)
				terrain:FillBall(Vector3.new(jx, SAND_TOP - r + h, jz), r, Enum.Material.Sand)
			elseif not busyAt(jx, jz, 14) then
				local r = rng:NextNumber(16, 28)
				terrain:FillBall(Vector3.new(jx, SAND_TOP - r + rng:NextNumber(0.4, 1.1), jz), r, Enum.Material.Sand)
			end
			z += rng:NextNumber(40, 60)
		end
		if x % 920 < 46 then
			task.wait()
		end
	end
	-- 5. restinga nas dunas (dos dois lados)
	local veg = K.model("Restinga", f)
	for _, side in ipairs({ -1, 1 }) do
		local x = W + 40
		while x < half - 30 do
			local z = L.SandStartZ + rng:NextNumber(6, 40)
			while z < dunesZ1 - 10 do
				restinga(veg, side * (x + rng:NextNumber(-8, 8)), z)
				z += rng:NextNumber(26, 48) + (z - L.SandStartZ) * 0.25
			end
			x += rng:NextNumber(30, 44)
		end
		-- cerquinha de duna (estacas e corda) separando as dunas da areia da praia
		local zf = dunesZ1 + 12
		x = W + 60
		while x < half - 60 do
			local len = rng:NextInteger(5, 9)
			for k = 0, len do
				local px = side * (x + k * 6)
				local y = sandY(px, zf)
				P(veg, "Estaca", Vector3.new(0.4, 3.4, 0.4), CFrame.new(px, y + 1.5, zf), WOOD_DARK, Enum.Material.Wood)
				if k < len then
					P(veg, "Corda", Vector3.new(6, 0.12, 0.12), CFrame.new(px + side * 3, y + 2.6, zf), Color3.fromRGB(220, 205, 170), Enum.Material.Fabric, nocollide())
				end
			end
			x += len * 6 + rng:NextNumber(30, 70)
		end
		task.wait()
	end
	-- pedras só na ponta do farol (leste)
	for k = 1, 10 do
		local s = rng:NextNumber(14, 30)
		P(f, "Ponta", Vector3.new(s, s * 0.8, s), CFrame.new(L.BeachHalf + rng:NextNumber(20, 140), L.SeaLevel + s * 0.15, L.SandFlatZ + rng:NextNumber(70, 170)) * CFrame.Angles(rng:NextNumber(-0.4, 0.4), rng:NextNumber(0, 6), rng:NextNumber(-0.4, 0.4)), Color3.fromRGB(110, 106, 98), Enum.Material.Rock)
	end
	return f
end

-- Calçadão de ondas, gramado com palmeiras, ciclovia, bancos e postes
local function buildPromenade(root)
	local f = K.model("Calcadao", root)
	local X0, X1 = -L.BeiraMarHalf + 20, L.BeiraMarHalf - 20
	box(f, "Calcadao", X0, X1, -0.2, 0.8, L.WalkZ0, L.WalkZ1, WALK, Enum.Material.Pavement)
	-- faixa de ondas no meio (pedra escura)
	local mid = (L.WalkZ0 + L.WalkZ1) / 2
	local SEG, AMP, PERIOD = 12, 7, 60
	local x = X0
	while x < X1 do
		local xa, xb = x, math.min(x + SEG, X1)
		local za = mid + AMP * math.sin(xa / PERIOD * 2 * math.pi)
		local zb = mid + AMP * math.sin(xb / PERIOD * 2 * math.pi)
		local a, b = Vector3.new(xa, 0.83, za), Vector3.new(xb, 0.83, zb)
		P(f, "Onda", Vector3.new(2.4, 0.06, (b - a).Magnitude + 1.2), CFrame.lookAt((a + b) / 2, b), WAVE, Enum.Material.Basalt, nocollide())
		x = xb
	end
	-- meio-fio do lado do mar
	box(f, "Borda", X0, X1, -0.2, 1.0, L.WalkZ1 - 0.6, L.WalkZ1, Color3.fromRGB(205, 200, 190), Enum.Material.Concrete)
	-- gramado
	box(f, "Gramado", X0, X1, -0.2, 0.55, L.WalkZ1, L.GreenZ1, GRASS, Enum.Material.Grass)
	-- ciclovia
	box(f, "Ciclovia", X0, X1, -0.2, 0.5, L.GreenZ1, L.BikeZ1, Color3.fromRGB(70, 90, 110), Enum.Material.Asphalt)
	box(f, "FaixaCiclovia", X0, X1, 0.5, 0.53, (L.GreenZ1 + L.BikeZ1) / 2 - 0.2, (L.GreenZ1 + L.BikeZ1) / 2 + 0.2, YELLOW, Enum.Material.SmoothPlastic, nocollide())
	-- palmeiras altas no gramado, bancos e postes no calçadão
	local pierHalf = L.Pier.Width / 2 + 6
	local k = 0
	for px = X0 + 20, X1 - 20, 48 do
		if math.abs(px) > pierHalf + 8 then
			k += 1
			tallPalm(f, Vector3.new(px + rng:NextNumber(-4, 4), 0.55, (L.WalkZ1 + L.GreenZ1) / 2), rng:NextNumber(1.5, 2.3))
			if k % 2 == 0 then
				bench(f, Vector3.new(px + 24, 0.8, L.WalkZ1 - 3), math.pi) -- de frente para o mar
			end
			if k % 3 == 0 then
				globeLamp(f, Vector3.new(px + 12, 0.8, L.WalkZ0 + 2.5), k % 6 == 0)
			end
		end
		if k % 40 == 0 then
			task.wait()
		end
	end
	return f
end

-- Barraca do calçadão (toldo colorido); as de lanche ganham balcão com E (LitoralService)
local function buildTent(parent, pos, color, snackKind)
	local t = K.model(snackKind and "BarracaLanche" or "BarracaFeira", parent)
	local cf = CFrame.new(pos) * CFrame.Angles(0, math.pi, 0) -- frente (-Z) virada para o calçadão (norte)
	for _, sx in ipairs({ -4, 4 }) do
		for _, sz in ipairs({ -3.5, 3.5 }) do
			P(t, "Haste", Vector3.new(0.3, 8, 0.3), cf * CFrame.new(sx, 4, sz), WHITE, Enum.Material.Metal)
		end
	end
	P(t, "Toldo", Vector3.new(9.6, 0.4, 8.6), cf * CFrame.new(0, 8.2, 0), color, Enum.Material.Fabric)
	P(t, "Pico", Vector3.new(9.6, 1.6, 4.3), cf * CFrame.new(0, 9.2, -2.15), color, Enum.Material.Fabric, { ClassName = "WedgePart", CanCollide = false })
	P(t, "Pico", Vector3.new(9.6, 1.6, 4.3), cf * CFrame.new(0, 9.2, 2.15) * CFrame.Angles(0, math.pi, 0), WHITE, Enum.Material.Fabric, { ClassName = "WedgePart", CanCollide = false })
	local counter = P(t, "Mesa", Vector3.new(8, 3, 2.4), cf * CFrame.new(0, 1.5 + 0.8, -2.6), snackKind and WHITE or Color3.fromRGB(210, 190, 160), Enum.Material.Wood)
	if snackKind then
		local snack = L.Snacks[snackKind]
		counter:SetAttribute("LitoralSnack", snackKind)
		sign(t, cf * CFrame.new(0, 6.7, -4.3) * CFrame.Angles(0, math.pi, 0), Vector3.new(8, 1.6, 0.2), ("%s  •  $%d"):format(snack.Name, snack.Price), WHITE, color)
		-- produtos de enfeite no balcão
		for i, x in ipairs({ -2.6, 0, 2.6 }) do
			P(t, "Produto", Vector3.new(1, 1, 1), cf * CFrame.new(x, 4.3, -2.6), i == 2 and color or WHITE, Enum.Material.SmoothPlastic, nocollide({ Shape = BALL }))
		end
		-- vendedor (LitoralService põe o NPC aqui)
		local spot = P(t, "Vendedor", Vector3.new(1, 1, 1), cf * CFrame.new(0, 3.8, 1.2) * CFrame.Angles(0, math.pi, 0), WHITE, nil, { Transparency = 1, CanCollide = false })
		spot.CanQuery = false
		spot:SetAttribute("LitoralSpot", "vendedor")
	else
		-- artesanato, quadros e óculos
		for i = -1, 1 do
			P(t, "Artesanato", Vector3.new(1.8, 0.4, 1.4), cf * CFrame.new(i * 2.4, 3.9, -2.6), PASTELS[rng:NextInteger(1, #PASTELS)], Enum.Material.Fabric, nocollide())
		end
		P(t, "Quadro", Vector3.new(3, 2.4, 0.2), cf * CFrame.new(0, 5.4, 3.4), PASTELS[rng:NextInteger(1, #PASTELS)], Enum.Material.SmoothPlastic, nocollide())
	end
	return t
end

local function buildTents(root)
	local f = K.model("Barracas", root)
	local X0, X1 = -L.BeiraMarHalf + 60, L.BeiraMarHalf - 60
	local z = L.WalkZ1 - 4.5
	local k = 0
	local snackIdx = 0
	for x = X0, X1, 96 do
		if math.abs(x) > 90 then
			k += 1
			local food = k % 3 == 1
			local kind
			if food then
				snackIdx += 1
				kind = SNACK_ORDER[(snackIdx - 1) % #SNACK_ORDER + 1]
			end
			buildTent(f, Vector3.new(x, 0.8, z), food and SNACK_COLORS[kind] or AWNING[rng:NextInteger(1, #AWNING)], kind)
		end
	end
	return f
end

-- Casinhas coloridas entre a Beira-Mar e o calçadão (fachada para o mar, estilo Venice)
local function buildFrontRow(root)
	local f = K.model("CasinhasDaOrla", root)
	local z0, z1 = L.FrontZ0 + 2, L.WalkZ0 - 1
	local d = z1 - z0
	box(f, "Passeio", -L.BeiraMarHalf + 20, L.BeiraMarHalf - 20, -0.2, 0.8, L.FrontZ0 - 4, L.WalkZ0, Color3.fromRGB(215, 210, 200), Enum.Material.Pavement)
	local x = -L.BeiraMarHalf + 30
	local lots = 0
	local shopIndex = 0
	local shopsToBuild = {}
	while x < L.BeiraMarHalf - 40 do
		-- praça do píer, estacionamentos e vielas para a areia
		if math.abs(x) < 80 then
			x = 80
		elseif math.abs(math.abs(x) - 700) < 70 then
			-- estacionamento da praia (entra pela Beira-Mar)
			local cx = x < 0 and -700 or 700
			local lot = K.model("EstacionamentoPraia", f)
			box(lot, "Asfalto", cx - 60, cx + 60, 0.8, 0.9, z0, z1, Color3.fromRGB(60, 63, 68), Enum.Material.Asphalt)
			for k = 0, 9 do
				local vx = cx - 54 + k * 12
				P(lot, "Faixa", Vector3.new(0.3, 0.05, 18), CFrame.new(vx, 0.93, z1 - 9), WHITE, nil, nocollide())
			end
			sign(lot, CFrame.new(cx + 50, 6, z0 + 2) * CFrame.Angles(0, math.pi, 0), Vector3.new(10, 3, 0.3), "P  PRAIA", WHITE, Color3.fromRGB(30, 80, 160))
			column(lot, "PostePlaca", Vector3.new(cx + 50, 0.9, z0 + 2.4), 6, 0.2, METAL, Enum.Material.Metal)
			x = cx + 70
		else
			local w = rng:NextInteger(26, 44)
			if x + w > L.BeiraMarHalf - 30 then
				break
			end
			lots += 1
			if lots % 5 == 0 then
				x += 16 -- viela
			else
				local cx = x + w / 2
				local floors = rng:NextInteger(1, 3)
				local h = 10 + (floors - 1) * 8
				local wall = PASTELS[rng:NextInteger(1, #PASTELS)]
				local aw = AWNING[rng:NextInteger(1, #AWNING)]
				local b = K.model("CasinhaOrla", f)
				local bd = d - 6
				local front = z0 + bd
				-- Marco 10.32: loja de verdade (dá para entrar), com interior do tema e fundo bonito
				shopIndex += 1
				local pending = { b = b, lot = { x0 = cx - (w - 2) / 2, x1 = cx + (w - 2) / 2, z0 = z0, z1 = front, h = h, wall = wall, awning = aw, index = shopIndex, vazada = shopIndex % 3 == 1 } }
				table.insert(shopsToBuild, pending)
				-- toldo listrado
				local stripes = math.max(3, math.floor((w - 2) / 3))
				for s = 0, stripes - 1 do
					local sw = (w - 2) / stripes
					P(b, "Toldo", Vector3.new(sw, 0.3, 4), CFrame.new(cx - (w - 2) / 2 + sw * (s + 0.5), 0.8 + 8.4, front + 1.8) * CFrame.Angles(math.rad(16), 0, 0), s % 2 == 0 and aw or WHITE, Enum.Material.Fabric, nocollide())
				end
				local name = SHOPS[rng:NextInteger(1, #SHOPS)]
				pending.lot.name = name
				local plate = sign(b, CFrame.new(cx, 0.8 + 9.9, front + 0.2) * CFrame.Angles(0, math.pi, 0), Vector3.new(math.min(w - 6, 20), 1.6, 0.2), name, aw, WHITE)
				plate.Name = "Sign"
				for fl = 2, floors do
					local y = 0.8 + 10 + (fl - 2) * 8 + 4
					P(b, "Janelas", Vector3.new(w - 8, 3.6, 0.3), CFrame.new(cx, y, front + 0.1), Color3.fromRGB(120, 170, 200), Enum.Material.SmoothPlastic, { Transparency = 0.15, CanCollide = false })
					P(b, "Sacada", Vector3.new(w - 6, 1.2, 1.6), CFrame.new(cx, y - 2, front + 0.9), WHITE, Enum.Material.Concrete)
				end
				P(b, "Platibanda", Vector3.new(w - 1, 1, bd + 1), CFrame.new(cx, 0.8 + h + 0.5, z0 + bd / 2), WHITE, Enum.Material.Concrete)
				b:SetAttribute("Business", name)
				x += w
			end
		end
	end
	-- Marco 10.32: interiores (sorteio próprio, não muda o resto da orla)
	local irng = Random.new(L.Seed + 1032)
	local kit = { P = P, sign = sign, column = column, nocollide = nocollide, snacks = L.Snacks }
	for i, s in ipairs(shopsToBuild) do
		OrlaShops.build(s.b, kit, s.lot, irng)
		if i % 6 == 0 then
			task.wait()
		end
	end
	-- Praça do Píer (liga a avenida ao píer, sem carros)
	local plaza = K.model("PracaDoPier", f)
	box(plaza, "Piso", -78, 78, -0.2, 0.82, L.FrontZ0 - 4, L.WalkZ0, Color3.fromRGB(236, 226, 205), Enum.Material.Pavement)
	for _, sx in ipairs({ -1, 1 }) do
		for i = 0, 6 do
			column(plaza, "Fradinho", Vector3.new(sx * (20 + i * 5), 0.82, L.FrontZ0 - 2), 2.6, 0.5, WHITE, Enum.Material.Concrete)
		end
		tallPalm(plaza, Vector3.new(sx * 50, 0.82, L.FrontZ0 + 26), 2.1)
		tallPalm(plaza, Vector3.new(sx * 66, 0.82, L.FrontZ0 + 14), 1.8)
		bench(plaza, Vector3.new(sx * 34, 0.82, L.FrontZ0 + 40), 0)
	end
	-- chafariz baixo
	K.flatCylinder(plaza, "Chafariz", Vector3.new(0, 1.3, L.FrontZ0 + 26), 12, 1, Color3.fromRGB(210, 205, 195), Enum.Material.Concrete)
	local water = K.flatCylinder(plaza, "Agua", Vector3.new(0, 1.85, L.FrontZ0 + 26), 11, 0.1, Color3.fromRGB(80, 170, 210), Enum.Material.SmoothPlastic)
	water.Transparency = 0.25
	water.CanCollide = false
	return f
end

-- Píer: deck de tábua sobre pilares, guarda-corpo, postes, portal e plataforma da MigueLândia
local function buildPier(root)
	local f = K.model("Pier", root)
	local PR = L.Pier
	local half = PR.Width / 2
	local deckTop = 0.8 -- mesma altura do calçadão
	box(f, "Deck", -half, half, deckTop - 1, deckTop, PR.Z0, PR.Z1, WOOD, Enum.Material.WoodPlanks)
	-- pilares e travessas (a cada 24)
	for z = PR.Z0 + 12, PR.Z1, 24 do
		for _, x in ipairs({ -half + 2, 0, half - 2 }) do
			column(f, "Pilar", Vector3.new(x, L.SeaBottom, z), deckTop - 1 - L.SeaBottom, 0.9, WOOD_DARK, Enum.Material.Wood)
		end
		P(f, "Travessa", Vector3.new(PR.Width, 1, 1.2), CFrame.new(0, deckTop - 1.6, z), WOOD_DARK, Enum.Material.Wood)
	end
	-- guarda-corpo
	for _, sx in ipairs({ -1, 1 }) do
		box(f, "Corrimao", sx * half - 0.3, sx * half + 0.3, deckTop + 3.2, deckTop + 3.6, PR.Z0 + 10, PR.Z1, WHITE, Enum.Material.Wood)
		box(f, "Corrimao", sx * half - 0.25, sx * half + 0.25, deckTop + 1.6, deckTop + 1.9, PR.Z0 + 10, PR.Z1, WHITE, Enum.Material.Wood, nocollide())
		for z = PR.Z0 + 10, PR.Z1, 12 do
			P(f, "Montante", Vector3.new(0.5, 3.6, 0.5), CFrame.new(sx * half, deckTop + 1.8, z), WHITE, Enum.Material.Wood)
		end
		for z = PR.Z0 + 40, PR.Z1 - 20, 60 do
			globeLamp(f, Vector3.new(sx * (half - 1.5), deckTop, z), (z / 60) % 2 < 1)
		end
		-- bancos virados para o mar (lado de dentro do guarda-corpo)
		for z = PR.Z0 + 70, PR.Z1 - 30, 60 do
			bench(f, Vector3.new(sx * (half - 3), deckTop, z), sx > 0 and -math.pi / 2 or math.pi / 2)
		end
	end
	-- deque de pesca dos dois lados
	for _, sx in ipairs({ -1, 1 }) do
		local zc = PR.Z1 - 140
		box(f, "DequePesca", math.min(sx * half, sx * (half + 18)), math.max(sx * half, sx * (half + 18)), deckTop - 1, deckTop, zc - 20, zc + 20, WOOD, Enum.Material.WoodPlanks)
		box(f, "Corrimao", sx * (half + 18) - 0.3, sx * (half + 18) + 0.3, deckTop + 3.2, deckTop + 3.6, zc - 20, zc + 20, WHITE, Enum.Material.Wood)
		for _, z in ipairs({ zc - 20, zc + 20 }) do
			box(f, "Corrimao", math.min(sx * half, sx * (half + 18)), math.max(sx * half, sx * (half + 18)), deckTop + 3.2, deckTop + 3.6, z - 0.3, z + 0.3, WHITE, Enum.Material.Wood)
		end
		column(f, "Pilar", Vector3.new(sx * (half + 16), L.SeaBottom, zc), deckTop - 1 - L.SeaBottom, 0.9, WOOD_DARK, Enum.Material.Wood)
		for _, dz in ipairs({ -10, 10 }) do
			local spot = P(f, "Pescador", Vector3.new(1, 1, 1), CFrame.lookAt(Vector3.new(sx * (half + 14), deckTop + 3, zc + dz), Vector3.new(sx * (half + 40), deckTop + 3, zc + dz)), WHITE, nil, { Transparency = 1, CanCollide = false })
			spot.CanQuery = false
			spot:SetAttribute("LitoralSpot", "pescador")
		end
		P(f, "Balde", Vector3.new(1.4, 1.6, 1.4), CFrame.new(sx * (half + 10), deckTop + 0.8, zc), Color3.fromRGB(60, 120, 200), Enum.Material.SmoothPlastic, { Shape = CYL })
	end
	-- portal na entrada (sobre o calçadão)
	local gate = K.model("PortalPier", f)
	local gz = PR.Z0 + 4
	for _, sx in ipairs({ -1, 1 }) do
		box(gate, "Coluna", sx * (half + 1) - 1.5, sx * (half + 1) + 1.5, 0.3, 24, gz - 1.5, gz + 1.5, WHITE, Enum.Material.Concrete)
		P(gate, "Luz", Vector3.new(3.4, 1, 3.4), CFrame.new(sx * (half + 1), 24.5, gz), YELLOW, Enum.Material.Neon, nocollide())
	end
	local arch = P(gate, "Arco", Vector3.new(PR.Width + 6, 5, 1.2), CFrame.new(0, 22, gz) * CFrame.Angles(0, math.pi, 0), Color3.fromRGB(30, 110, 160), Enum.Material.Metal, nocollide())
	K.addSurfaceText(arch, "PÍER COSTA DO SOL", YELLOW, Color3.fromRGB(30, 110, 160))
	local arch2 = P(gate, "Arco2", Vector3.new(PR.Width + 6, 5, 1.2), CFrame.new(0, 22, gz), Color3.fromRGB(30, 110, 160), Enum.Material.Metal, nocollide())
	K.addSurfaceText(arch2, "VOLTE SEMPRE!", YELLOW, Color3.fromRGB(30, 110, 160))
	local sub = P(gate, "Faixa", Vector3.new(PR.Width - 6, 3, 0.8), CFrame.new(0, 17.5, gz) * CFrame.Angles(0, math.pi, 0), Color3.fromRGB(230, 90, 150), Enum.Material.SmoothPlastic, nocollide())
	K.addSurfaceText(sub, "🎡 MIGUELÂNDIA • DIVERSÃO NO MAR", WHITE, Color3.fromRGB(230, 90, 150))
	-- fradinhos: a pé sim, de carro não
	for x = -half + 3, half - 3, 4.5 do
		column(gate, "Fradinho", Vector3.new(x, 0.3, gz - 4), 3, 0.5, YELLOW, Enum.Material.Metal)
	end

	-- plataforma da MigueLândia (embaixo do chão do parque)
	local pc = L.ParkCenter
	local S = GameConfig.Park.Size + 24
	local plat = K.model("PlataformaParque", f)
	box(plat, "Plataforma", pc.X - S / 2, pc.X + S / 2, -1.6, -0.05, pc.Z - S / 2, pc.Z + S / 2, WOOD_DARK, Enum.Material.WoodPlanks)
	box(plat, "Borda", pc.X - S / 2, pc.X + S / 2, -0.05, 0.3, pc.Z - S / 2, pc.Z + S / 2, WOOD, Enum.Material.WoodPlanks)
	local step = S / 8
	for i = 0, 8 do
		for j = 0, 8 do
			if i == 0 or j == 0 or i == 8 or j == 8 or (i + j) % 2 == 0 then
				column(plat, "Pilar", Vector3.new(pc.X - S / 2 + i * step, L.SeaBottom, pc.Z - S / 2 + j * step), -1.6 - L.SeaBottom, 1.4, WOOD_DARK, Enum.Material.Wood)
			end
		end
	end
	-- guarda-corpo na beira da plataforma (fora do muro do parque), com vão para o píer
	local e = S / 2
	for _, sx in ipairs({ -1, 1 }) do
		box(plat, "Corrimao", pc.X + sx * e - 0.3, pc.X + sx * e + 0.3, 0.3, 3.8, pc.Z - e, pc.Z + e, WHITE, Enum.Material.Wood)
	end
	box(plat, "Corrimao", pc.X - e, pc.X + e, 0.3, 3.8, pc.Z + e - 0.3, pc.Z + e + 0.3, WHITE, Enum.Material.Wood)
	box(plat, "Corrimao", pc.X - e, pc.X - half, 0.3, 3.8, pc.Z - e - 0.3, pc.Z - e + 0.3, WHITE, Enum.Material.Wood)
	box(plat, "Corrimao", pc.X + half, pc.X + e, 0.3, 3.8, pc.Z - e - 0.3, pc.Z - e + 0.3, WHITE, Enum.Material.Wood)
	return f
end

-- Academia na areia (barras, argolas, supino, paralelas): E = malhar (LitoralService)
local function buildGym(root, x0, z0)
	local f = K.model("AcademiaDaPraia", root)
	local W, D = 120, 76
	box(f, "Piso", x0, x0 + W, 0.4, 0.75, z0, z0 + D, Color3.fromRGB(150, 60, 50), Enum.Material.Rubber)
	-- mureta baixa com abertura na frente
	box(f, "Mureta", x0, x0 + W, 0.75, 2.6, z0 - 1, z0, Color3.fromRGB(235, 230, 220), Enum.Material.Concrete)
	box(f, "Mureta", x0, x0 + 1, 0.75, 2.6, z0, z0 + D, Color3.fromRGB(235, 230, 220), Enum.Material.Concrete)
	box(f, "Mureta", x0 + W - 1, x0 + W, 0.75, 2.6, z0, z0 + D, Color3.fromRGB(235, 230, 220), Enum.Material.Concrete)
	box(f, "Mureta", x0, x0 + W / 2 - 8, 0.75, 2.6, z0 + D, z0 + D + 1, Color3.fromRGB(235, 230, 220), Enum.Material.Concrete)
	box(f, "Mureta", x0 + W / 2 + 8, x0 + W, 0.75, 2.6, z0 + D, z0 + D + 1, Color3.fromRGB(235, 230, 220), Enum.Material.Concrete)
	local s = sign(f, CFrame.new(x0 + W / 2, 9, z0 + D + 1) * CFrame.Angles(0, math.pi, 0), Vector3.new(30, 4, 0.4), "💪 ACADEMIA DA PRAIA", WHITE, Color3.fromRGB(150, 60, 50))
	column(f, "PostePlaca", Vector3.new(x0 + W / 2 - 14, 0.75, z0 + D + 1.2), 8, 0.3, METAL, Enum.Material.Metal)
	column(f, "PostePlaca", Vector3.new(x0 + W / 2 + 14, 0.75, z0 + D + 1.2), 8, 0.3, METAL, Enum.Material.Metal)
	s.CanCollide = false
	local y = 0.75
	-- Marco 10.32: "Alvo" = onde as mãos pegam (barra, argolas, paralelas) ou o banco do supino,
	-- virado para onde o boneco olha (LookVector) e com a barra no eixo RightVector
	local function station(kind, label, pos, faceDir, alvo)
		local spot = P(f, "Estacao", Vector3.new(1.5, 0.2, 1.5), CFrame.lookAt(Vector3.new(pos.X, y + 0.1, pos.Z), Vector3.new(pos.X, y + 0.1, pos.Z) + faceDir), Color3.fromRGB(240, 200, 60), Enum.Material.SmoothPlastic, nocollide())
		spot:SetAttribute("LitoralGym", kind)
		spot:SetAttribute("GymLabel", label)
		if alvo then
			spot:SetAttribute("Alvo", alvo)
		end
		return spot
	end
	local AHEAD = Vector3.new(0, 0, -1)
	-- barras fixas (2) e argolas
	for i, bx in ipairs({ x0 + 18, x0 + 38 }) do
		local bz = z0 + 18
		for _, sx in ipairs({ -3, 3 }) do
			column(f, "Coluna", Vector3.new(bx + sx, y, bz), 10, 0.35, METAL, Enum.Material.Metal)
		end
		P(f, "Barra", Vector3.new(6.4, 0.3, 0.3), CFrame.new(bx, y + 9.8, bz), Color3.fromRGB(200, 200, 205), Enum.Material.Metal)
		station("barra", "Barra fixa " .. i, Vector3.new(bx, 0, bz + 1.2), AHEAD, CFrame.lookAt(Vector3.new(bx, y + 9.8, bz), Vector3.new(bx, y + 9.8, bz) + AHEAD))
	end
	do
		local bx, bz = x0 + 62, z0 + 18
		for _, sx in ipairs({ -5, 5 }) do
			column(f, "Coluna", Vector3.new(bx + sx, y, bz), 13, 0.35, METAL, Enum.Material.Metal)
		end
		P(f, "Trave", Vector3.new(10.6, 0.4, 0.4), CFrame.new(bx, y + 12.8, bz), METAL, Enum.Material.Metal)
		for _, sx in ipairs({ -1.2, 1.2 }) do
			P(f, "Corda", Vector3.new(0.12, 3.6, 0.12), CFrame.new(bx + sx, y + 10.9, bz), Color3.fromRGB(230, 225, 210), Enum.Material.Fabric, nocollide())
			P(f, "Argola", Vector3.new(0.25, 1.2, 1.2), CFrame.new(bx + sx, y + 8.6, bz), Color3.fromRGB(200, 170, 110), Enum.Material.Wood, nocollide({ Shape = CYL }))
		end
		station("argola", "Argolas", Vector3.new(bx, 0, bz + 1.2), AHEAD, CFrame.lookAt(Vector3.new(bx, y + 8.2, bz), Vector3.new(bx, y + 8.2, bz) + AHEAD))
	end
	-- paralelas
	do
		local bx, bz = x0 + 88, z0 + 18
		for _, sx in ipairs({ -1.6, 1.6 }) do
			for _, sz in ipairs({ -3, 3 }) do
				column(f, "Pe", Vector3.new(bx + sx, y, bz + sz), 4.4, 0.25, METAL, Enum.Material.Metal)
			end
			P(f, "Paralela", Vector3.new(0.3, 0.3, 7), CFrame.new(bx + sx, y + 4.4, bz), Color3.fromRGB(200, 200, 205), Enum.Material.Metal)
		end
		station("paralela", "Paralelas", Vector3.new(bx, 0, bz + 4.2), AHEAD, CFrame.lookAt(Vector3.new(bx, y + 4.6, bz), Vector3.new(bx, y + 4.6, bz) + AHEAD))
	end
	-- supinos (banco + barra com anilhas) e halteres
	for i, bx in ipairs({ x0 + 24, x0 + 52, x0 + 80 }) do
		local bz = z0 + 50
		P(f, "BancoSupino", Vector3.new(2.4, 0.6, 6), CFrame.new(bx, y + 1.8, bz), Color3.fromRGB(40, 40, 45), Enum.Material.Leather)
		P(f, "PeBanco", Vector3.new(1.4, 1.6, 5), CFrame.new(bx, y + 0.8, bz), METAL, Enum.Material.Metal)
		-- barra com anilhas num modelo só: o PoseController leva ela até as mãos de quem faz supino
		local barbell = K.model("Supino", f)
		for _, sx in ipairs({ -3.5, 3.5 }) do
			column(f, "Suporte", Vector3.new(bx + sx, y, bz - 2.2), 4.9, 0.2, METAL, Enum.Material.Metal)
			P(barbell, "Anilha", Vector3.new(0.5, 2.6, 2.6), CFrame.new(bx + sx * 1.15, y + 5, bz - 2.2), Color3.fromRGB(30, 30, 32), Enum.Material.Metal, nocollide({ Shape = CYL }))
		end
		local bar = P(barbell, "BarraSupino", Vector3.new(9, 0.25, 0.25), CFrame.new(bx, y + 5, bz - 2.2), Color3.fromRGB(200, 200, 205), Enum.Material.Metal, nocollide())
		barbell.PrimaryPart = bar
		barbell:SetAttribute("Home", bar.CFrame)
		game:GetService("CollectionService"):AddTag(barbell, "BarraSupino")
		station("peso", "Supino " .. i, Vector3.new(bx + 2.6, 0, bz + 1), Vector3.new(-1, 0, 0), CFrame.lookAt(Vector3.new(bx, y + 2.1, bz), Vector3.new(bx, y + 2.1, bz) + AHEAD))
	end
	-- rack de halteres
	P(f, "Rack", Vector3.new(14, 2.4, 2.4), CFrame.new(x0 + 104, y + 1.2, z0 + 50), METAL, Enum.Material.Metal)
	for k = 0, 5 do
		P(f, "Halter", Vector3.new(1.8, 0.7, 0.7), CFrame.new(x0 + 98.5 + k * 2.2, y + 2.8, z0 + 50), Color3.fromRGB(40, 40, 44), Enum.Material.Metal, nocollide({ Shape = CYL }))
	end
	return f
end

-- Pista de skate: caixote, corrimãos, quarter pipes e escadinha (dá para andar de BMX)
local function buildSkate(root, x0, z0)
	local f = K.model("PistaDeSkate", root)
	local W, D = 190, 116
	local CON = Color3.fromRGB(196, 196, 192)
	box(f, "Piso", x0, x0 + W, 0.4, 0.8, z0, z0 + D, CON, Enum.Material.Concrete)
	local y = 0.8
	-- quarter pipes nas duas pontas (rampas em degrau curvo)
	for _, side in ipairs({ -1, 1 }) do
		local edge = side < 0 and x0 or x0 + W
		for k = 1, 4 do
			local h = k * 1.6
			local len = 4
			local cx = edge - side * (4 * (4 - k) + len / 2 + 1)
			P(f, "QuarterPipe", Vector3.new(D - 20, h, len), CFrame.new(cx, y + h / 2, z0 + D / 2) * CFrame.Angles(0, side * math.pi / 2, 0), CON, Enum.Material.Concrete, { ClassName = "WedgePart" })
		end
		box(f, "Topo", side < 0 and edge or edge - 4, side < 0 and edge + 4 or edge, y, y + 7, z0 + 10, z0 + D - 10, Color3.fromRGB(170, 170, 168), Enum.Material.Concrete)
	end
	-- caixote central (funbox) com rampas
	local cx, cz = x0 + W / 2, z0 + D / 2
	box(f, "Caixote", cx - 16, cx + 16, y, y + 3, cz - 10, cz + 10, CON, Enum.Material.Concrete)
	for _, side in ipairs({ -1, 1 }) do
		P(f, "Rampa", Vector3.new(20, 3, 12), CFrame.new(cx + side * 22, y + 1.5, cz) * CFrame.Angles(0, side * math.pi / 2, 0), CON, Enum.Material.Concrete, { ClassName = "WedgePart" })
	end
	P(f, "Corrimao", Vector3.new(26, 0.3, 0.3), CFrame.new(cx, y + 4.8, cz), Color3.fromRGB(240, 200, 40), Enum.Material.Metal)
	for _, sx in ipairs({ -12, 12 }) do
		P(f, "PeCorrimao", Vector3.new(0.3, 1.8, 0.3), CFrame.new(cx + sx, y + 3.9, cz), Color3.fromRGB(240, 200, 40), Enum.Material.Metal)
	end
	-- bordas (ledges) coloridas e grafites nas paredes
	for i, lx in ipairs({ x0 + 40, x0 + W - 40 }) do
		box(f, "Borda", lx - 10, lx + 10, y, y + 1.6, z0 + 12, z0 + 16, PASTELS[i + 2], Enum.Material.Concrete)
		box(f, "Borda", lx - 10, lx + 10, y, y + 1.6, z0 + D - 16, z0 + D - 12, PASTELS[i + 4], Enum.Material.Concrete)
	end
	for k = 0, 5 do
		P(f, "Grafite", Vector3.new(0.2, 4, 14), CFrame.new(x0 + 0.2 + (k >= 3 and W - 0.4 or 0), y + 9, z0 + 18 + (k % 3) * 30), AWNING[k % #AWNING + 1], Enum.Material.SmoothPlastic, nocollide())
	end
	sign(f, CFrame.new(x0 + W / 2, 8, z0 + D + 0.5) * CFrame.Angles(0, math.pi, 0), Vector3.new(26, 4, 0.4), "🛹 PISTA DE SKATE", WHITE, Color3.fromRGB(40, 40, 45))
	for _, sx in ipairs({ -12, 12 }) do
		column(f, "PostePlaca", Vector3.new(x0 + W / 2 + sx, 0.8, z0 + D + 0.8), 6, 0.3, METAL, Enum.Material.Metal)
	end
	return f
end

-- Quadra de basquete de rua
local function buildCourt(root, x0, z0)
	local f = K.model("QuadraBasquete", root)
	local W, D = 60, 90
	box(f, "Piso", x0, x0 + W, 0.4, 0.8, z0, z0 + D, Color3.fromRGB(60, 120, 170), Enum.Material.Concrete)
	box(f, "Garrafao", x0 + W / 2 - 8, x0 + W / 2 + 8, 0.8, 0.83, z0, z0 + 18, Color3.fromRGB(220, 110, 60), nil, nocollide())
	box(f, "Garrafao", x0 + W / 2 - 8, x0 + W / 2 + 8, 0.8, 0.83, z0 + D - 18, z0 + D, Color3.fromRGB(220, 110, 60), nil, nocollide())
	box(f, "Meio", x0, x0 + W, 0.8, 0.83, z0 + D / 2 - 0.2, z0 + D / 2 + 0.2, WHITE, nil, nocollide())
	for _, end_ in ipairs({ { z0 + 2, 1 }, { z0 + D - 2, -1 } }) do
		local z, dir = end_[1], end_[2]
		column(f, "Poste", Vector3.new(x0 + W / 2, 0.8, z - dir * 1), 11, 0.35, METAL, Enum.Material.Metal)
		P(f, "Tabela", Vector3.new(7, 4.5, 0.3), CFrame.new(x0 + W / 2, 11, z + dir * 0.5), WHITE, Enum.Material.SmoothPlastic)
		P(f, "Aro", Vector3.new(0.2, 2.6, 2.6), CFrame.new(x0 + W / 2, 9.6, z + dir * 2) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(240, 100, 40), Enum.Material.Metal, nocollide({ Shape = CYL, Transparency = 0.2 }))
	end
	local ball = P(f, "BolaBasquete", Vector3.new(1.8, 1.8, 1.8), CFrame.new(x0 + W / 2, 2.5, z0 + D / 2), Color3.fromRGB(230, 110, 40), Enum.Material.Rubber, { Shape = BALL })
	ball:SetAttribute("LitoralBall", true)
	return f
end

-- Vôlei de praia: rede e bola de verdade (LitoralService devolve a bola se ela sumir)
local function buildVolley(root, cx, cz)
	local f = K.model("QuadraVolei", root)
	local W, D = 30, 58
	local y = 0.4
	-- linhas
	for _, sx in ipairs({ -1, 1 }) do
		box(f, "Linha", cx + sx * W / 2 - 0.25, cx + sx * W / 2 + 0.25, y, y + 0.04, cz - D / 2, cz + D / 2, Color3.fromRGB(40, 110, 200), nil, nocollide())
	end
	for _, sz in ipairs({ -1, 1 }) do
		box(f, "Linha", cx - W / 2, cx + W / 2, y, y + 0.04, cz + sz * D / 2 - 0.25, cz + sz * D / 2 + 0.25, Color3.fromRGB(40, 110, 200), nil, nocollide())
	end
	for _, sx in ipairs({ -1, 1 }) do
		column(f, "PosteRede", Vector3.new(cx + sx * (W / 2 + 2), y, cz), 9, 0.3, WHITE, Enum.Material.Metal)
	end
	P(f, "Rede", Vector3.new(W + 4, 3, 0.15), CFrame.new(cx, y + 7, cz), Color3.fromRGB(30, 30, 34), Enum.Material.Fabric, { Transparency = 0.45 })
	P(f, "FaixaRede", Vector3.new(W + 4, 0.4, 0.2), CFrame.new(cx, y + 8.6, cz), WHITE, Enum.Material.Fabric)
	local ball = P(f, "BolaVolei", Vector3.new(2.2, 2.2, 2.2), CFrame.new(cx, 4, cz - 10), Color3.fromRGB(250, 235, 90), Enum.Material.SmoothPlastic, { Shape = BALL })
	ball:SetAttribute("LitoralBall", true)
	return f
end

-- Posto de salva-vidas (casinha azul sobre pernas, rampa, boia e bandeira)
local function buildLifeguard(root, pos, number)
	local f = K.model("PostoSalvaVidas", root)
	local cf = CFrame.new(pos) * CFrame.Angles(0, math.pi, 0) -- janela grande (-Z) virada para o mar
	for _, sx in ipairs({ -4.5, 4.5 }) do
		for _, sz in ipairs({ -4, 4 }) do
			P(f, "Perna", Vector3.new(0.7, 7, 0.7), cf * CFrame.new(sx, 3.5, sz), WHITE, Enum.Material.Wood)
		end
	end
	P(f, "Piso", Vector3.new(14, 0.6, 12), cf * CFrame.new(0, 7.3, -1), WOOD, Enum.Material.WoodPlanks)
	P(f, "Cabine", Vector3.new(10, 7, 8), cf * CFrame.new(0, 11.1, 0.5), LIFE_BLUE, Enum.Material.WoodPlanks)
	P(f, "Janela", Vector3.new(8, 3, 0.3), cf * CFrame.new(0, 12, -3.6), Color3.fromRGB(40, 60, 80), Enum.Material.SmoothPlastic, { Transparency = 0.3 })
	P(f, "Telhado", Vector3.new(12, 0.6, 10), cf * CFrame.new(0, 14.9, 0.5), WHITE, Enum.Material.WoodPlanks)
	P(f, "Guarda", Vector3.new(14, 2.2, 0.3), cf * CFrame.new(0, 8.7, -7), WHITE, Enum.Material.Wood)
	-- rampa até a areia (atrás)
	local rampLen = 20
	local ang = math.atan2(7, rampLen)
	P(f, "Rampa", Vector3.new(4, 0.5, math.sqrt(rampLen * rampLen + 49)), cf * CFrame.new(0, 7 / 2 + 0.4, 4.4 + rampLen / 2) * CFrame.Angles(ang, 0, 0), WOOD, Enum.Material.WoodPlanks)
	local num = P(f, "Numero", Vector3.new(4, 3, 0.2), cf * CFrame.new(0, 11.5, 4.65) * CFrame.Angles(0, math.pi, 0), LIFE_BLUE, nil, nocollide())
	K.addSurfaceText(num, tostring(number), WHITE, Color3.fromRGB(230, 70, 60))
	P(f, "Boia", Vector3.new(0.6, 3, 3), cf * CFrame.new(5.2, 10, -1) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(240, 70, 50), Enum.Material.SmoothPlastic, nocollide({ Shape = CYL }))
	column(f, "Mastro", (cf * CFrame.new(-6.5, 7.6, -6)).Position, 9, 0.15, WHITE, Enum.Material.Metal)
	P(f, "Bandeira", Vector3.new(0.1, 1.8, 2.8), cf * CFrame.new(-6.5, 15.6, -4.6), Color3.fromRGB(240, 220, 60), Enum.Material.Fabric, nocollide())
	local seat = P(f, "Cadeira", Vector3.new(2.4, 0.5, 2.4), cf * CFrame.new(0, 8.1, -4.6) * CFrame.Angles(0, math.pi, 0), Color3.fromRGB(240, 70, 50), Enum.Material.SmoothPlastic, { ClassName = "Seat" })
	seat:SetAttribute("SeatText", "Vigiar o mar")
	return f
end

-- Guarda-sol, canga e cadeira (sorteados na areia)
local function buildUmbrella(parent, pos, color)
	local u = K.model("GuardaSol", parent)
	column(u, "Haste", pos, 8, 0.15, WHITE, Enum.Material.Metal, { CanCollide = false })
	P(u, "Lona", Vector3.new(0.6, 10, 10), CFrame.new(pos + Vector3.new(0, 8, 0)) * CFrame.Angles(0, 0, math.rad(90)), color, Enum.Material.Fabric, nocollide({ Shape = CYL }))
	P(u, "Topo", Vector3.new(0.8, 0.8, 0.8), CFrame.new(pos + Vector3.new(0, 8.5, 0)), WHITE, nil, nocollide({ Shape = BALL }))
	local yaw = rng:NextNumber(-0.5, 0.5)
	P(u, "Canga", Vector3.new(3.4, 0.05, 6), CFrame.new(pos + Vector3.new(3, 0.03, 1)) * CFrame.Angles(0, yaw, 0), PASTELS[rng:NextInteger(1, #PASTELS)], Enum.Material.Fabric, nocollide())
	if rng:NextNumber() < 0.6 then
		local seat = P(u, "Cadeira", Vector3.new(2.4, 0.4, 2.8), CFrame.new(pos + Vector3.new(-3, 1, 0.5)) * CFrame.Angles(0, math.pi, 0), color, Enum.Material.Fabric, { ClassName = "Seat" })
		seat:SetAttribute("SeatText", "Tomar sol")
		P(u, "Encosto", Vector3.new(2.4, 2.4, 0.3), seat.CFrame * CFrame.new(0, 1.1, 1.3) * CFrame.Angles(math.rad(-20), 0, 0), color, Enum.Material.Fabric)
	end
	if rng:NextNumber() < 0.3 then
		P(u, "Isopor", Vector3.new(2.2, 1.6, 1.4), CFrame.new(pos + Vector3.new(1.5, 0.8, -3)), WHITE, Enum.Material.SmoothPlastic)
	end
	if rng:NextNumber() < 0.35 then
		local spot = P(u, "Banhista", Vector3.new(1, 1, 1), CFrame.new(pos + Vector3.new(3, 0.5, 1)) * CFrame.Angles(0, yaw, 0), WHITE, nil, { Transparency = 1, CanCollide = false })
		spot.CanQuery = false
		spot:SetAttribute("LitoralSpot", "banhista")
	end
	return u
end

-- Marco 10.32: Escolinha de Surfe (aluguel de pranchas, instrutor e placar) e as boias da área
local function buildSurf(root)
	local S = GameConfig.Surf
	local f = K.model("Surfe", root)
	local cx, cz = S.ShopX, S.ShopZ
	local y = 0.45
	local cf = CFrame.new(cx, y, cz) -- frente (+Z) virada para o mar
	-- deck de madeira
	P(f, "Deck", Vector3.new(46, 0.8, 26), cf * CFrame.new(0, 0, 0), WOOD, Enum.Material.WoodPlanks)
	for _, sx in ipairs({ -22, 22 }) do
		for _, sz in ipairs({ -12, 12 }) do
			P(f, "Pe", Vector3.new(0.8, 2, 0.8), cf * CFrame.new(sx, -0.8, sz), WOOD_DARK, Enum.Material.Wood)
		end
	end
	-- quiosque: balcão, telhado de palha e letreiro
	local hut = K.model("Quiosque", f)
	P(hut, "Fundo", Vector3.new(20, 9, 0.6), cf * CFrame.new(-8, 4.9, -10), Color3.fromRGB(70, 170, 190), Enum.Material.WoodPlanks)
	for _, sx in ipairs({ -18, 2 }) do
		P(hut, "Lado", Vector3.new(0.6, 9, 8), cf * CFrame.new(sx, 4.9, -6.3), Color3.fromRGB(70, 170, 190), Enum.Material.WoodPlanks)
		P(hut, "Poste", Vector3.new(0.7, 11, 0.7), cf * CFrame.new(sx, 5.9, -2), WOOD_DARK, Enum.Material.Wood)
	end
	local counter = P(hut, "Balcao", Vector3.new(19, 3.6, 2), cf * CFrame.new(-8, 2.2, -2.4), Color3.fromRGB(245, 240, 225), Enum.Material.WoodPlanks)
	counter:SetAttribute("SurfeBalcao", true)
	P(hut, "TampoBalcao", Vector3.new(19.6, 0.3, 2.6), cf * CFrame.new(-8, 4.15, -2.4), WOOD, Enum.Material.Wood)
	P(hut, "Palha", Vector3.new(24, 1.4, 13), cf * CFrame.new(-8, 11.2, -6) * CFrame.Angles(math.rad(-8), 0, 0), Color3.fromRGB(196, 168, 110), Enum.Material.Grass)
	P(hut, "PalhaBorda", Vector3.new(24.4, 0.9, 0.6), cf * CFrame.new(-8, 10.4, 0.4), Color3.fromRGB(170, 140, 90), Enum.Material.Grass, nocollide())
	sign(hut, cf * CFrame.new(-8, 8.3, -1.9) * CFrame.Angles(0, math.pi, 0), Vector3.new(17, 2.2, 0.3), "🏄 ESCOLINHA DE SURFE • PRANCHAS $" .. S.RentPrice, WHITE, Color3.fromRGB(230, 90, 60))
	-- placar das melhores ondas
	local board = P(f, "Placar", Vector3.new(9, 6.4, 0.4), cf * CFrame.new(16, 5.2, -9) * CFrame.Angles(0, math.pi, 0), Color3.fromRGB(25, 45, 70), Enum.Material.SmoothPlastic)
	board:SetAttribute("PlacarSurfe", true)
	for _, sx in ipairs({ 12, 20 }) do
		P(f, "PostePlacar", Vector3.new(0.4, 8.4, 0.4), cf * CFrame.new(sx, 4.2, -8.6), WOOD_DARK, Enum.Material.Wood)
	end
	-- dois cavaletes com 5 pranchas cada (modelos e cores diferentes)
	local k = 0
	for _, rx in ipairs({ 4, 12 }) do
		P(f, "Cavalete", Vector3.new(7.6, 0.4, 0.5), cf * CFrame.new(rx, 4.6, 3), WOOD_DARK, Enum.Material.Wood)
		for _, sx in ipairs({ -3.6, 3.6 }) do
			P(f, "PeCavalete", Vector3.new(0.4, 4.6, 0.4), cf * CFrame.new(rx + sx, 2.7, 3), WOOD_DARK, Enum.Material.Wood)
		end
		for i = 0, 4 do
			k += 1
			local styleIndex = (k - 1) % #SurfBoards.STYLES + 1
			local paletteIndex = (k * 3 - 1) % #SurfBoards.PALETTES + 1
			local b, style = SurfBoards.build(styleIndex, paletteIndex)
			local h = style.length / 2
			b:PivotTo(cf * CFrame.new(rx - 3 + i * 1.5, 0.4 + h * 0.97, 2.4) * CFrame.Angles(math.rad(-76), 0, 0) * CFrame.Angles(0, 0, math.rad(90)))
			b.Name = "PranchaAluguel"
			b:SetAttribute("Estilo", styleIndex)
			b:SetAttribute("Cores", paletteIndex)
			b.Parent = f
		end
	end
	-- instrutor e bandeiras
	local spot = P(f, "Instrutor", Vector3.new(1, 1, 1), cf * CFrame.new(-8, 0.4 + 0.5, -5) * CFrame.Angles(0, math.pi, 0), WHITE, nil, { Transparency = 1, CanCollide = false })
	spot.CanQuery = false
	spot:SetAttribute("LitoralSpot", "instrutor")
	for i, x in ipairs({ S.X0 + 10, (S.X0 + S.X1) / 2, S.X1 - 10 }) do
		local base = Vector3.new(x, sandY(x, 3790), 3790)
		column(f, "Mastro", base, 12, 0.18, WHITE, Enum.Material.Metal)
		P(f, "Bandeira", Vector3.new(0.12, 2.4, 3.6), CFrame.new(base + Vector3.new(0, 10.8, 1.8)), i == 2 and Color3.fromRGB(230, 60, 50) or Color3.fromRGB(250, 210, 50), Enum.Material.Fabric, nocollide())
	end
	local plate = sign(f, CFrame.new((S.X0 + S.X1) / 2, 6, 3796) * CFrame.Angles(0, math.pi, 0), Vector3.new(26, 3.4, 0.3), "🌊 ÁREA DE SURFE • SÓ COM PRANCHA", WHITE, Color3.fromRGB(30, 110, 170))
	plate.Name = "PlacaSurfe"
	-- boias: dos dois lados e no fundo, com corda entre elas (cada aparelho balança as boias)
	local buoys = K.model("Boias", f)
	local level = L.SeaLevel + 0.5
	local function buoy(x, z, n)
		local b = P(buoys, "Boia", Vector3.new(2.4, 2.4, 2.4), CFrame.new(x, level, z), n % 2 == 0 and Color3.fromRGB(240, 80, 40) or Color3.fromRGB(250, 210, 40), Enum.Material.SmoothPlastic, { Shape = BALL, CanCollide = false })
		b:SetAttribute("Base", b.CFrame)
		CollectionService:AddTag(b, "Boia")
	end
	local n = 0
	for _, x in ipairs({ S.X0, S.X1 }) do
		for z = S.ZShore + 30, S.ZOut, 30 do
			n += 1
			buoy(x, z, n)
		end
		P(buoys, "Corda", Vector3.new(0.15, 0.15, S.ZOut - S.ZShore - 30), CFrame.new(x, level - 0.4, (S.ZShore + 30 + S.ZOut) / 2), Color3.fromRGB(250, 250, 240), Enum.Material.Fabric, nocollide())
	end
	for x = S.X0 + 35, S.X1 - 35, 35 do
		n += 1
		buoy(x, S.ZOut, n)
	end
	P(buoys, "Corda", Vector3.new(S.X1 - S.X0, 0.15, 0.15), CFrame.new((S.X0 + S.X1) / 2, level - 0.4, S.ZOut), Color3.fromRGB(250, 250, 240), Enum.Material.Fabric, nocollide())
	return f
end

-- Marco 10.32: mais vida na areia: castelinhos (com criança), frescobol (pares de NPCs),
-- barcos ancorados balançando no mar e cangas com cooler. Os NPCs são criados pelo LitoralService.
local SAND_DARK = Color3.fromRGB(205, 182, 130)
local function sandcastle(parent, x, z)
	local m = K.model("Castelinho", parent)
	local y = sandY(x, z)
	local base = CFrame.new(x, y, z)
	P(m, "Monte", Vector3.new(7, 1.4, 7), base * CFrame.new(0, 0.5, 0), SAND_DARK, Enum.Material.Sand, nocollide())
	for i, o in ipairs({ { -2, -2 }, { 2, -2 }, { -2, 2 }, { 2, 2 } }) do
		column(m, "Torre", Vector3.new(x + o[1], y + 1, z + o[2]), 2.2 + (i % 2) * 0.6, 0.65, SAND_DARK, Enum.Material.Sand, nocollide())
		P(m, "Ameia", Vector3.new(1.5, 0.6, 1.5), CFrame.new(x + o[1], y + 3.5 + (i % 2) * 0.6, z + o[2]), SAND_DARK, Enum.Material.Sand, nocollide())
	end
	P(m, "Torre", Vector3.new(2.4, 3.6, 2.4), base * CFrame.new(0, 2.6, 0), SAND_DARK, Enum.Material.Sand, nocollide())
	P(m, "Bandeirinha", Vector3.new(0.08, 0.7, 1), base * CFrame.new(0, 5.2, 0.5), Color3.fromRGB(230, 60, 50), Enum.Material.Fabric, nocollide())
	column(m, "Balde", Vector3.new(x + 4.5, y, z + 1), 1.2, 0.6, Color3.fromRGB(250, 200, 40), Enum.Material.SmoothPlastic, nocollide())
	P(m, "Pazinha", Vector3.new(0.3, 0.12, 1.6), CFrame.new(x + 4.2, y + 0.15, z - 1.4) * CFrame.Angles(0, 0.6, 0), Color3.fromRGB(40, 140, 220), Enum.Material.SmoothPlastic, nocollide())
	local spot = P(m, "Crianca", Vector3.new(1, 1, 1), CFrame.lookAt(Vector3.new(x, y + 1, z - 5), Vector3.new(x, y + 1, z)), WHITE, nil, { Transparency = 1, CanCollide = false })
	spot.CanQuery = false
	spot:SetAttribute("LitoralSpot", "castelo")
end

local function boat(parent, pos, yaw, colors, sail)
	local m = K.model(sail and "Veleiro" or "Barco", parent)
	local cf = CFrame.new(pos) * CFrame.Angles(0, yaw, 0)
	local hull, trim = colors[1], colors[2]
	local L0 = sail and 22 or 18
	P(m, "Casco", Vector3.new(6.5, 2.6, L0), cf * CFrame.new(0, 0.6, 0), hull, Enum.Material.WoodPlanks, nocollide())
	P(m, "Proa", Vector3.new(6.5, 2.6, 5), cf * CFrame.new(0, 0.6, -L0 / 2 - 2.5) * CFrame.Angles(0, 0, math.pi), hull, Enum.Material.WoodPlanks, { ClassName = "WedgePart", CanCollide = false })
	P(m, "Faixa", Vector3.new(6.6, 0.5, L0), cf * CFrame.new(0, 1.7, 0), trim, Enum.Material.SmoothPlastic, nocollide())
	P(m, "Convés", Vector3.new(6, 0.3, L0 - 1), cf * CFrame.new(0, 1.95, 0), WOOD, Enum.Material.WoodPlanks, nocollide())
	if sail then
		column(m, "Mastro", (cf * CFrame.new(0, 2, -2)).Position, 22, 0.25, WHITE, Enum.Material.Metal, nocollide())
		P(m, "Vela", Vector3.new(0.12, 18, 9), cf * CFrame.new(0, 12, 2.6) * CFrame.Angles(0, math.pi, 0), WHITE, Enum.Material.Fabric, { ClassName = "WedgePart", CanCollide = false })
	else
		P(m, "Cabine", Vector3.new(4.6, 3.4, 5), cf * CFrame.new(0, 3.8, 3), WHITE, Enum.Material.SmoothPlastic, nocollide())
		P(m, "Teto", Vector3.new(5.2, 0.3, 5.6), cf * CFrame.new(0, 5.6, 3), trim, Enum.Material.SmoothPlastic, nocollide())
		column(m, "Antena", (cf * CFrame.new(0, 5.7, 4)).Position, 5, 0.08, METAL, Enum.Material.Metal, nocollide())
		for _, sx in ipairs({ -1, 1 }) do
			P(m, "Boia", Vector3.new(0.6, 1.4, 1.4), cf * CFrame.new(sx * 3.35, 1, -2), Color3.fromRGB(240, 90, 40), Enum.Material.SmoothPlastic, { Shape = CYL, CanCollide = false })
		end
	end
	m:SetAttribute("Base", m:GetPivot())
	CollectionService:AddTag(m, "Barco")
end

local function towelSpot(parent, x, z, n)
	local y = sandY(x, z)
	local colors = { Color3.fromRGB(230, 60, 80), Color3.fromRGB(40, 140, 220), Color3.fromRGB(250, 200, 40), Color3.fromRGB(40, 180, 120) }
	for i = 1, n do
		local c = colors[(i + math.floor(x)) % #colors + 1]
		P(parent, "Canga", Vector3.new(3.4, 0.08, 6.2), CFrame.new(x + (i - 1) * 4.2, y + 0.05, z) * CFrame.Angles(0, rng:NextNumber(-0.2, 0.2), 0), c, Enum.Material.Fabric, nocollide())
	end
	P(parent, "Cooler", Vector3.new(2.2, 1.6, 1.4), CFrame.new(x - 2.6, y + 0.8, z + 2), Color3.fromRGB(240, 240, 245), Enum.Material.SmoothPlastic)
	P(parent, "TampaCooler", Vector3.new(2.3, 0.3, 1.5), CFrame.new(x - 2.6, y + 1.7, z + 2), Color3.fromRGB(40, 110, 200), Enum.Material.SmoothPlastic)
end

local function buildBeachLife(root)
	local f = K.model("VidaNaPraia", root)
	for _, x in ipairs({ -480, -1450, 1950, -2050 }) do
		sandcastle(f, x, 3758)
	end
	-- frescobol: dois pontos (um de frente para o outro) perto da água
	for i, x in ipairs({ -260, -900, -1600, 1750 }) do
		local z = 3800
		for side = -1, 1, 2 do
			local p = Vector3.new(x + side * 8, sandY(x + side * 8, z) + 1, z)
			local spot = P(f, "Frescobol", Vector3.new(1, 1, 1), CFrame.lookAt(p, Vector3.new(x, p.Y, z)), WHITE, nil, { Transparency = 1, CanCollide = false })
			spot.CanQuery = false
			spot:SetAttribute("LitoralSpot", "frescobol")
			spot:SetAttribute("Par", i)
		end
	end
	-- cangas com cooler espalhadas
	for _, o in ipairs({ { -700, 3735 }, { -1300, 3700 }, { 1300, 3690 }, { 1900, 3725 }, { -1900, 3710 }, { 250, 3745 } }) do
		if not busyAt(o[1], o[2], 6) then
			towelSpot(f, o[1], o[2], rng:NextInteger(2, 3))
		end
	end
	-- barcos ancorados (fora da área de surfe e longe do parque do píer)
	local barcos = K.model("Barcos", f)
	local hulls = {
		{ Color3.fromRGB(40, 110, 200), WHITE }, { Color3.fromRGB(230, 70, 60), Color3.fromRGB(250, 210, 50) },
		{ WHITE, Color3.fromRGB(40, 160, 120) }, { Color3.fromRGB(250, 200, 40), Color3.fromRGB(40, 110, 200) },
	}
	for i, o in ipairs({ { -1900, 4380, 0.4 }, { -1150, 4520, -0.9 }, { 1900, 4400, 1.2 }, { 2350, 4600, -0.3 }, { -2450, 4750, 2.2, true }, { 2700, 4900, 0.8, true } }) do
		boat(barcos, Vector3.new(o[1], L.SeaLevel - 1.2, o[2]), o[3], hulls[(i - 1) % #hulls + 1], o[4])
	end
	return f
end

-- Farol na ponta de pedras do leste
local function buildLighthouse(root, pos)
	local f = K.model("FarolDaCosta", root)
	for k = 1, 10 do
		local s = rng:NextNumber(18, 36)
		P(f, "Rocha", Vector3.new(s, s * 0.7, s), CFrame.new(pos + Vector3.new(rng:NextNumber(-30, 30), -4 + s * 0.1, rng:NextNumber(-30, 30))) * CFrame.Angles(rng:NextNumber(-0.3, 0.3), rng:NextNumber(0, 6), 0), Color3.fromRGB(108, 104, 96), Enum.Material.Rock)
	end
	local base = pos + Vector3.new(0, 4, 0)
	K.flatCylinder(f, "Base", base, 14, 2, Color3.fromRGB(200, 195, 185), Enum.Material.Concrete)
	local H = 54
	for i = 0, 5 do
		local r = 9 - i * 0.6
		P(f, "Torre", Vector3.new(H / 6 + 0.1, r * 2, r * 2), CFrame.new(base + Vector3.new(0, 1 + H / 6 * (i + 0.5), 0)) * CFrame.Angles(0, 0, math.rad(90)), i % 2 == 0 and WHITE or RED, Enum.Material.Concrete, { Shape = CYL })
	end
	local top = base + Vector3.new(0, 1 + H, 0)
	K.flatCylinder(f, "Varanda", top + Vector3.new(0, 0.5, 0), 7.5, 1, METAL, Enum.Material.Metal)
	local lamp = P(f, "Lanterna", Vector3.new(6, 5, 6), CFrame.new(top + Vector3.new(0, 3.5, 0)), Color3.fromRGB(255, 236, 170), Enum.Material.Neon, { Shape = CYL })
	lamp.CFrame = CFrame.new(top + Vector3.new(0, 3.5, 0)) * CFrame.Angles(0, 0, math.rad(90))
	local light = Instance.new("SpotLight")
	light.Name = "Facho"
	light.Range = 60
	light.Angle = 40
	light.Brightness = 3
	light.Face = Enum.NormalId.Top
	light.Color = Color3.fromRGB(255, 236, 170)
	light.Parent = lamp
	lamp:SetAttribute("Farol", true)
	P(f, "Cupula", Vector3.new(7, 3, 7), CFrame.new(top + Vector3.new(0, 7.2, 0)), RED, Enum.Material.Metal, { Shape = BALL })
	return f
end

-- Portal da Rotatória da Costa (entrada da cidade de praia)
local function buildGateway(root)
	local f = K.model("PortalCosta", root)
	local c = Vector3.new(0, 0, L.EntryZ + L.RoundaboutRadius + 70)
	for _, sx in ipairs({ -1, 1 }) do
		box(f, "Torre", sx * 44 - 4, sx * 44 + 4, 0.5, 30, c.Z - 4, c.Z + 4, Color3.fromRGB(245, 235, 210), Enum.Material.Plaster)
		P(f, "Topo", Vector3.new(10, 2, 10), CFrame.new(sx * 44, 31, c.Z), Color3.fromRGB(240, 140, 60), Enum.Material.ClayRoofTiles)
		tallPalm(f, Vector3.new(sx * 56, 0.5, c.Z), 1.9)
		tallPalm(f, Vector3.new(sx * 64, 0.5, c.Z - 10), 1.6)
	end
	local arch = P(f, "Arco", Vector3.new(96, 7, 2), CFrame.new(0, 27, c.Z), Color3.fromRGB(30, 120, 170), Enum.Material.SmoothPlastic, nocollide())
	K.addSurfaceText(arch, "☀ BEM-VINDO À COSTA DO SOL ☀", YELLOW, Color3.fromRGB(30, 120, 170))
	local back = P(f, "ArcoVolta", Vector3.new(96, 7, 2), CFrame.new(0, 27, c.Z) * CFrame.Angles(0, math.pi, 0), Color3.fromRGB(30, 120, 170), Enum.Material.SmoothPlastic, nocollide())
	K.addSurfaceText(back, "VOLTE SEMPRE • CIDADE ↑", YELLOW, Color3.fromRGB(30, 120, 170))
	return f
end

local function buildHills(root, hills)
	local f = K.model("Morros", root)
	for _, h in ipairs(hills) do
		local r = h[3]
		P(f, "Morro", Vector3.new(2 * r, 2 * r, 2 * r), CFrame.new(h[1], -r * 0.62, h[2]), Color3.fromRGB(86 + rng:NextInteger(0, 20), 140 + rng:NextInteger(0, 20), 80), Enum.Material.Grass, { Shape = BALL })
	end
	return f
end

function LitoralBuilder.build(plan, groups, props)
	local root = plan.root
	root:SetAttribute("PlaceName", L.Name)
	placesFolder = K.model("Lugares", root)

	-- Marco 10.32: o que fica em cima da areia plana (sem relevo embaixo)
	LitoralBuilder.FLAT = {
		{ 60, 200, L.BikeZ1, L.BikeZ1 + 100 }, -- academia
		{ -300, -90, L.BikeZ1, L.BikeZ1 + 140 }, -- pista de skate
		{ -410, -330, L.BikeZ1, L.BikeZ1 + 116 }, -- basquete
		{ 300, 430, 3660, 3740 }, -- vôlei
		{ GameConfig.Surf.ShopX - 30, GameConfig.Surf.ShopX + 30, GameConfig.Surf.ShopZ - 20, GameConfig.Surf.ShopZ + 20 }, -- escolinha de surfe
	}
	for _, x in ipairs({ -2200, -1700, -1150, -620, 620, 1150, 1700, 2200 }) do
		table.insert(LitoralBuilder.FLAT, { x - 14, x + 14, 3715, 3775 }) -- postos de salva-vidas
	end
	for _, r in ipairs(LitoralBuilder.EXTRA_FLAT or {}) do
		table.insert(LitoralBuilder.FLAT, r)
	end
	buildSea()
	task.wait()
	buildBeach(root)
	task.wait()
	buildPromenade(root)
	task.wait()
	buildTents(root)
	buildFrontRow(root)
	task.wait()
	buildPier(root)
	task.wait()

	-- na areia, dos dois lados do píer
	local areia = K.model("Areia", root)
	buildGym(areia, 70, L.BikeZ1 + 14)
	buildSkate(areia, -290, L.BikeZ1 + 12)
	buildCourt(areia, -400, L.BikeZ1 + 16)
	buildVolley(areia, 330, 3700)
	buildVolley(areia, 400, 3700)
	for i, x in ipairs({ -2200, -1700, -1150, -620, 620, 1150, 1700, 2200 }) do
		buildLifeguard(areia, Vector3.new(x, 0.4, 3742), i)
	end
	-- duchas na entrada do píer
	for _, sx in ipairs({ -1, 1 }) do
		local p = Vector3.new(sx * 36, 0.4, L.BikeZ1 + 8)
		column(areia, "Ducha", p, 9, 0.25, METAL, Enum.Material.Metal)
		P(areia, "Chuveiro", Vector3.new(1.6, 0.4, 1.6), CFrame.new(p + Vector3.new(0, 9, 0)), METAL, Enum.Material.Metal, nocollide())
		box(areia, "Estrado", p.X - 2.5, p.X + 2.5, 0.4, 0.7, p.Z - 2.5, p.Z + 2.5, WOOD, Enum.Material.WoodPlanks)
	end
	task.wait()
	-- guarda-sóis sorteados (longe das quadras, do píer e da academia)
	local busy = {
		{ -40, 40 }, { 60, 200 }, { -300, -90 }, { -410, -330 }, { 300, 430 }, { GameConfig.Surf.ShopX - 40, GameConfig.Surf.ShopX + 40 },
	}
	local placed = 0
	for _ = 1, 400 do
		if placed >= 70 then
			break
		end
		local x = rng:NextNumber(-L.BeiraMarHalf + 80, L.BeiraMarHalf - 80)
		local z = rng:NextNumber(L.BikeZ1 + 30, L.SandFlatZ - 20)
		local ok = true
		for _, r in ipairs(busy) do
			if x > r[1] - 12 and x < r[2] + 12 and z < L.BikeZ1 + 150 then
				ok = false
			end
		end
		if math.abs(x) < 50 then
			ok = false
		end
		for _, lx in ipairs({ -2200, -1700, -1150, -620, 620, 1150, 1700, 2200 }) do
			if math.abs(x - lx) < 26 and z > 3700 then
				ok = false
			end
		end
		if ok then
			buildUmbrella(areia, Vector3.new(x, sandY(x, z), z), AWNING[rng:NextInteger(1, #AWNING)])
			placed += 1
			if placed % 20 == 0 then
				task.wait()
			end
		end
	end
	buildSurf(areia) -- Marco 10.32
	buildBeachLife(areia) -- Marco 10.32
	buildLighthouse(root, Vector3.new(L.BeachHalf + 90, 0, L.SeaZ + 20))
	buildGateway(root)
	buildHills(root, plan.hills or {})
	task.wait()

	-- bairro: hotéis, prédios e casas de praia (números depois de tudo da cidade)
	local streets = {}
	local function streetOf(name)
		streets[name] = streets[name] or K.newStreet(name)
		return streets[name]
	end
	local numbered = {}
	for _, item in ipairs(plan.items) do
		table.insert(numbered, item)
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
	local counts = { torre = 0, loja = 0, casa = 0, condominio = 0 }
	local condoKit = { P = P, sign = sign, column = column, nocollide = nocollide, palm = tallPalm, bench = bench, text = function(part, text, color, bg)
		K.addSurfaceText(part, text, color, bg)
	end }
	local condoRng = Random.new(L.Seed + 3211)
	for i, item in ipairs(plan.items) do
		local ok, err = pcall(function()
			if item.kind == "torre" then
				local b = HorizonteBuilder.buildTower(groups, item, item.street)
				if b then
					b:SetAttribute("District", L.Name)
				end
			elseif item.kind == "loja" then
				K.withRng(rng, K.buildBuilding, groups.buildings, item.lot, item.lotW, item.floors, { street = item.street, number = item.number })
			elseif item.kind == "casa" then
				K.withRng(rng, K.buildHouse, groups.houses, item.lot, item.lotW, item.variant, { street = item.street, number = item.number })
			elseif item.kind == "condominio" then -- Marco 10.32
				local m = K.model(item.name, groups.buildings)
				m:SetAttribute("PlaceName", item.name)
				m:SetAttribute("District", L.Name)
				CondoBuilder.build(m, condoKit, { cf = item.lot, W = item.W, D = item.D, name = item.name, wall = item.wall, accent = item.accent }, condoRng)
			end
		end)
		if ok then
			counts[item.kind] += 1
		else
			warn(("[Litoral] Erro ao montar %s: %s"):format(item.kind, tostring(err)))
		end
		if i % 12 == 0 then
			task.wait()
		end
	end

	-- lugares para o mapa e o GPS
	local bmZ = L.BeiraMarZ + BLVD_HALF + SIDE * 0.5
	addSpot("Praia da Costa do Sol", "🏖️", Vector3.new(-900, 0.4, 3680), Vector3.new(-900, 0.8, bmZ), Color3.fromRGB(35, 155, 180))
	addSpot("Calçadão da Orla", "🌴", Vector3.new(500, 0.8, (L.WalkZ0 + L.WalkZ1) / 2), Vector3.new(500, 0.8, bmZ), Color3.fromRGB(60, 160, 90))
	addSpot("Academia da Praia", "💪", Vector3.new(130, 0.8, L.BikeZ1 + 50), Vector3.new(130, 0.8, bmZ), Color3.fromRGB(150, 60, 50))
	addSpot("Pista de Skate", "🛹", Vector3.new(-195, 0.8, L.BikeZ1 + 70), Vector3.new(-195, 0.8, bmZ), Color3.fromRGB(70, 70, 80))
	addSpot("Farol da Costa", "🗼", Vector3.new(L.BeachHalf + 90, 0, L.SeaZ + 20), nil, Color3.fromRGB(200, 60, 55))
	root:SetAttribute("Lots", plan.lotCount)
	root:SetAttribute("Towers", counts.torre)
	root:SetAttribute("Shops", counts.loja)
	root:SetAttribute("Houses", counts.casa)
	print(("[Litoral] %s: %d prédios com loja, %d casas de praia e %d hotéis/residenciais."):format(L.Name, counts.loja, counts.casa, counts.torre))
	return root
end

return LitoralBuilder
