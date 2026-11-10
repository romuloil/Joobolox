-- MapController (ModuleScript)
-- Caminho: StarterPlayer > StarterPlayerScripts > Controllers > MapController
-- Mapa da cidade visto de cima, aberto pelo botão redondo do topo (ícone de mapa) ou pela tecla M.
-- É desenhado a partir do próprio mapa do jogo (ruas, prédios, casas, árvores, parque, prisão).
-- Marco 8.1 (pedido do Luís: "mais bonito e interativo"):
--   * zoom (botões + e −, rodinha do mouse, pinça no celular) e arrastar para andar pelo mapa;
--   * ícones para cada lugar e uma lista ao lado com a distância até cada um;
--   * toque num lugar (no mapa ou na lista) ou em qualquer ponto para marcar um DESTINO:
--     aparece uma linha pontilhada até ele e a distância fica embaixo do botão do mapa;
--   * outros jogadores aparecem como bolinhas com o nome;
--   * o destino do emprego (etapa atual) continua em laranja.
-- Marco 9.9 (GPS igual ao do GTA): o caminho até o destino vai pelas ruas (RouteGraph), desenhado
-- no mapa (Marco 9.10: só no mapa; a faixa no chão fica desligada em GPS_GROUND).
-- Marco 10.12 (pedido do Luís): MINIMAPA igual ao do GTA no canto de cima à direita, no lugar do
-- botão do mapa e da setinha do GPS. Gira com a câmera (para cima = para onde você olha), mostra o
-- caminho do GPS, o destino (rosa), o destino do emprego (laranja; na borda quando está longe),
-- outros jogadores e o "N". Afasta o zoom dentro de veículo. Toque/clique nele abre o mapa grande.
-- Só desenha os pedaços da cidade perto de você (em quadradinhos), para ficar leve no celular.
-- O corte é por ClipsDescendants (quadrado; o CanvasGroup vazava em alguns PCs).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))
local UIScaler = require(script.Parent:WaitForChild("UIScaler"))
local RouteGraph = require(script.Parent:WaitForChild("RouteGraph"))
local CityRoads = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CityRoads"))

local MapController = {}

local player = Players.LocalPlayer
local M = GameConfig.Map
local VIEW = 520 -- tamanho da janela do mapa (px)
local BASE = VIEW -- a cidade inteira cabe na janela no zoom 1
local LIST_W = 230 -- lista de lugares ao lado
local MIN_ZOOM, MAX_ZOOM = 0.2, 8 -- Marco 10: zoom < 1 mostra a rodovia e os bairros longe
local WORLD = M.MapView or M.GroundSize -- studs representados pelo mapa no zoom 1
local RADIAL_START, RADIAL_END = 50, 50 + M.RoadLength
local STUD_M = 0.28 -- 1 stud ≈ 28 cm
local ARRIVE = 25 -- studs: chegou no destino

-- Marco 10.8: mapa "minimalista" escuro (o Luís pediu mais bonito): fundo verde-escuro fosco,
-- ruas claras, casas em cinza-azulado e os pinos coloridos se destacando
local COLORS = {
	Grass = Color3.fromRGB(36, 50, 46),
	GrassDark = Color3.fromRGB(31, 44, 40),
	Tree = Color3.fromRGB(44, 68, 54),
	Road = Color3.fromRGB(150, 158, 174),
	Sidewalk = Color3.fromRGB(70, 80, 94),
	House = Color3.fromRGB(96, 106, 124),
	Building = Color3.fromRGB(84, 98, 128),
	Shop = Color3.fromRGB(40, 110, 220),
	Target = Color3.fromRGB(255, 150, 40),
	Dest = Color3.fromRGB(240, 60, 130),
	Panel = Color3.fromRGB(14, 18, 28),
	Row = Color3.fromRGB(26, 32, 46),
	RowHover = Color3.fromRGB(36, 44, 62),
	Muted = Color3.fromRGB(140, 152, 176),
	Accent = Color3.fromRGB(60, 140, 255),
}

-- Ícone de cada estabelecimento (pela chave do GameConfig.Places)
local PLACE_ICONS = {
	Pizzaria = "🍕", Mercearia = "🛒", Entregas = "📦", PetShop = "🐶", Onibus = "🚌",
	Bombeiros = "🚒", Policia = "🚓", Banco = "🏦", Taxi = "🚕",
}

local gui, panel, viewport, world, worldScale, overlay, listFrame, destLabel, clearButton, zoomLabel
local destCard, destIcon, destSub, searchBox, panelScale -- Marco 10.8
local chipTitle, chipSub, chipBadge -- Marco 10.8: navegação (seta do GPS)
local chip -- distância até o destino, embaixo do botão do mapa (só quando há destino)
local chipArrow -- Marco 9.1: setinha no chip que aponta para o destino (em vez do alfinete)
local isOpen = false
local zoom, center = 1, Vector2.new(BASE / 2, BASE / 2)
local places = {} -- { name, icon, pos, pin, label, row, rowDist, shop }
local pinsByName = {}
local overlayItems = {} -- itens que acompanham o zoom sem crescer: { gui, pos, offset, minZoom }
local playerMarker, playerPointer, playerHalo
local others = {} -- others[Player] = { dot, name }
local targetPlace, targetPos, targetDot
local dest -- { name, pos } escolhido pelo jogador
local destPin, pathDots = nil, {}
local route -- Marco 9.9: { points, color, from, goal } (caminho atual do GPS)
local routeFrames = {} -- linhas do caminho no mapa
local routeParts = {} -- faixa do caminho no chão (só neste aparelho)
local routeFolder
local ROAD_TOP = 0.5 -- altura das ruas (MapBuilder)
local GPS_AHEAD = 700 -- studs de faixa desenhados no chão à frente do jogador
local OFF_ROUTE = 30 -- Marco 10.9: mais longe que isso do caminho = refaz o caminho
local projectOnRoute -- Marco 10.9 (definida no GPS)
local GPS_GROUND = false -- Marco 9.10: o Luís preferiu o caminho só no mapa (true = faixa no chão também)

local function corner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = radius
	c.Parent = parent
	return c
end

local function stroke(parent, color, thickness)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.Parent = parent
	return s
end

local function text(parent, props)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = props.Font or Enum.Font.GothamBold
	l.TextSize = props.TextSize or 12
	l.TextColor3 = props.Color or Color3.new(1, 1, 1)
	l.TextStrokeTransparency = props.Stroke or 1
	l.TextXAlignment = props.Align or Enum.TextXAlignment.Center
	l.AnchorPoint = props.Anchor or Vector2.zero
	l.Size = props.Size or UDim2.fromOffset(100, 14)
	l.Position = props.Position or UDim2.new()
	l.Text = props.Text or ""
	l.ZIndex = props.ZIndex or 1
	l.Parent = parent
	return l
end

local function meters(studs)
	local m = studs * STUD_M
	if m >= 1000 then
		return ("%.1f km"):format(m / 1000)
	end
	return ("%d m"):format(math.floor(m / 5 + 0.5) * 5)
end

---------------------------------------------------------------------------
-- Conversões: mundo (studs) -> mapa (px no zoom 1) -> janela (px com zoom e arrasto)
---------------------------------------------------------------------------

local function toMap(pos)
	return Vector2.new((pos.X / WORLD + 0.5) * BASE, (pos.Z / WORLD + 0.5) * BASE)
end

local function fromMap(p)
	return Vector3.new((p.X / BASE - 0.5) * WORLD, 0, (p.Y / BASE - 0.5) * WORLD)
end

local function toView(pos)
	return (toMap(pos) - center) * zoom + Vector2.new(VIEW / 2, VIEW / 2)
end

local function viewToMap(v)
	return (v - Vector2.new(VIEW / 2, VIEW / 2)) / zoom + center
end

-- Posição do mouse/dedo (tela) -> janela do mapa (px sem a escala do UIScaler)
local function screenToView(screenPos)
	local scale = viewport.AbsoluteSize.X / VIEW
	if scale <= 0 then
		scale = 1
	end
	return (Vector2.new(screenPos.X, screenPos.Y) - viewport.AbsolutePosition) / scale
end

---------------------------------------------------------------------------
-- Desenho fixo (fica dentro de "world", que cresce com o zoom)
---------------------------------------------------------------------------

local function drawLine(a, b, width, color, z)
	local pa, pb = toMap(a), toMap(b)
	local delta = pb - pa
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	f.BackgroundColor3 = color
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Size = UDim2.fromOffset(delta.Magnitude + width, width)
	f.Position = UDim2.fromOffset((pa.X + pb.X) / 2, (pa.Y + pb.Y) / 2)
	f.Rotation = math.deg(math.atan2(delta.Y, delta.X))
	f.ZIndex = z or 2
	f.Parent = world
	return f
end

local function drawCircle(pos, diameterStuds, color, z)
	local p = toMap(pos)
	local d = diameterStuds / WORLD * BASE
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	f.BackgroundColor3 = color
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Size = UDim2.fromOffset(d, d)
	f.Position = UDim2.fromOffset(p.X, p.Y)
	f.ZIndex = z or 2
	f.Parent = world
	corner(f, UDim.new(1, 0))
	return f
end

-- Retângulo girado como no mundo (cf = centro, sx/sz = tamanho em studs)
local function drawRect(cf, sx, sz, color, z, radius)
	local p = toMap(cf.Position)
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	f.BackgroundColor3 = color
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Size = UDim2.fromOffset(math.max(1, sx / WORLD * BASE), math.max(1, sz / WORLD * BASE))
	f.Position = UDim2.fromOffset(p.X, p.Y)
	local _, yaw = cf:ToOrientation()
	f.Rotation = -math.deg(yaw)
	f.ZIndex = z or 3
	f.Parent = world
	if radius then
		corner(f, UDim.new(0, radius))
	end
	return f
end

-- Marco 10.22 (streaming): o servidor anota a caixa e o pivô de cada Model (as peças de longe nem
-- chegam no aparelho). Sem a anotação, mede na hora como antes.
local function boxOf(model)
	local cf, size = model:GetAttribute("MapaBox"), model:GetAttribute("MapaTam")
	if typeof(cf) == "CFrame" and typeof(size) == "Vector3" then
		return true, cf, size
	end
	return pcall(model.GetBoundingBox, model)
end

local function pivotOf(model)
	local cf = model:GetAttribute("MapaPivot")
	if typeof(cf) == "CFrame" then
		return cf
	end
	return model:GetPivot()
end

local function drawModel(model, color, z, radius)
	local ok, cf, size = boxOf(model)
	if ok and cf then
		return drawRect(cf, size.X, size.Z, color, z, radius)
	end
end

local function drawStreets()
	local roadPx = math.max(3, M.RoadWidth / WORLD * BASE)
	local walkPx = roadPx + 2 * M.SidewalkWidth / WORLD * BASE
	local dirs = {}
	for i = 0, 7 do
		table.insert(dirs, CFrame.Angles(0, i * math.pi / 4, 0).LookVector)
	end
	local segments = {}
	local function road(a, b, color)
		table.insert(segments, { a, b, color })
	end
	for _, dir in ipairs(dirs) do
		road(dir * RADIAL_START, dir * RADIAL_END)
	end
	for _, radius in ipairs({ M.InnerRingRadius, RADIAL_END }) do
		for i, dir in ipairs(dirs) do
			road(dir * radius, dirs[(i % #dirs) + 1] * radius)
		end
	end
	local vilaDir = dirs[M.Vila.Dir]
	road(vilaDir * RADIAL_END, vilaDir * (RADIAL_END + M.Vila.Length), Color3.fromRGB(130, 112, 96))
	for _, extra in ipairs({ GameConfig.Park, GameConfig.Prison, GameConfig.PaintShop, GameConfig.BusTerminal, GameConfig.FireStation }) do
		if extra and extra.Dir and extra.RoadLength then
			road(dirs[extra.Dir] * RADIAL_END, dirs[extra.Dir] * (RADIAL_END + extra.RoadLength))
		end
	end
	-- calçada por baixo, asfalto por cima
	for _, s in ipairs(segments) do
		drawLine(s[1], s[2], walkPx, COLORS.Sidewalk, 2)
	end
	drawCircle(Vector3.zero, M.RoundaboutOuterRadius * 2 + M.SidewalkWidth * 2, COLORS.Sidewalk, 2)
	for _, s in ipairs(segments) do
		drawLine(s[1], s[2], roadPx, s[3] or COLORS.Road, 3)
	end
	drawCircle(Vector3.zero, M.RoundaboutOuterRadius * 2, COLORS.Road, 3)
	-- Marco 10: estradas da expansão (CityRoads): rodovia, Rodoanel, saídas e o Bairro Horizonte
	local expansion = CityRoads.get()
	local px = BASE / WORLD
	for _, r in ipairs(expansion.roads) do
		local kind = CityRoads.Kinds[r.Kind]
		local w = math.max(3, r.Width * px)
		for i = 1, #r.Points - 1 do
			local a, b = r.Points[i], r.Points[i + 1]
			if kind.Sidewalk then
				drawLine(a, b, w + 2 * M.SidewalkWidth * px, COLORS.Sidewalk, 2)
			end
			drawLine(a, b, w, r.Kind == "rodovia" and Color3.fromRGB(120, 128, 146) or COLORS.Road, 3)
			if r.Kind == "rodovia" or r.Kind == "boulevard" then
				drawLine(a, b, math.max(1, 6 * px), Color3.fromRGB(52, 80, 62), 3) -- canteiro do meio
			end
		end
	end
	for _, c in ipairs(expansion.circles) do
		drawCircle(c.Center, c.Radius * 2, COLORS.Road, 3)
		drawCircle(c.Center, c.Radius * 0.9, Color3.fromRGB(56, 86, 64), 4)
	end
	drawCircle(Vector3.zero, M.RoundaboutIslandRadius * 2, Color3.fromRGB(56, 86, 64), 4)
	drawCircle(Vector3.zero, 14, Color3.fromRGB(70, 140, 210), 5) -- chafariz

	-- nomes das ruas (ficam por cima, sem crescer com o zoom)
	local function short(name)
		return (name:gsub("^Avenida", "Av."):gsub("^Rua", "R."))
	end
	local function streetLabel(a, b, name)
		local pa, pb = toMap(a), toMap(b)
		local angle = math.deg(math.atan2(pb.Y - pa.Y, pb.X - pa.X))
		if angle > 90 then
			angle -= 180
		elseif angle < -90 then
			angle += 180
		end
		local l = text(overlay, { Text = short(name), TextSize = 10, Stroke = 0.4, Anchor = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(130, 12), ZIndex = 4 })
		l.Rotation = angle
		table.insert(overlayItems, { gui = l, pos = (a + b) / 2, minZoom = 1.3 })
	end
	for i, dir in ipairs(dirs) do
		streetLabel(dir * M.InnerRingRadius, dir * RADIAL_END, M.StreetNames[i])
	end
	streetLabel(dirs[2] * M.InnerRingRadius, dirs[3] * M.InnerRingRadius, M.InnerRingName)
	streetLabel(dirs[6] * RADIAL_END, dirs[7] * RADIAL_END, M.OuterRingName)
	streetLabel(vilaDir * (RADIAL_END + 40), vilaDir * (RADIAL_END + M.Vila.Length), M.Vila.Name)
	-- Marco 10: um nome por estrada da expansão, no trecho mais comprido
	local named = {}
	for _, r in ipairs(CityRoads.get().roads) do
		if not named[r.Name] then
			named[r.Name] = true
			local best, len = 1, 0
			for i = 1, #r.Points - 1 do
				local l = (r.Points[i + 1] - r.Points[i]).Magnitude
				if l > len then
					best, len = i, l
				end
			end
			local label = r.Code and (r.Code .. " " .. r.Name) or r.Name
			streetLabel(r.Points[best], r.Points[best + 1], label)
			if r.Kind == "rodovia" then
				overlayItems[#overlayItems].minZoom = 0.2
			end
		end
	end
	for _, cfg in ipairs({ GameConfig.Prison, GameConfig.BusTerminal, GameConfig.FireStation }) do
		if cfg and cfg.RoadName then
			streetLabel(dirs[cfg.Dir] * RADIAL_END, dirs[cfg.Dir] * (RADIAL_END + cfg.RoadLength), cfg.RoadName)
		end
	end
end

local function drawWorld(map)
	-- chão: grama com "manchas" mais escuras para não ficar chapado
	local rng = Random.new(8)
	for _ = 1, 40 do
		local p = Vector3.new(rng:NextNumber(-0.5, 0.5) * WORLD, 0, rng:NextNumber(-0.5, 0.5) * WORLD)
		local patch = drawCircle(p, rng:NextNumber(120, 320), COLORS.GrassDark, 1)
		patch.BackgroundTransparency = 0.55
	end
	-- árvores
	local nature = map:FindFirstChild("Nature")
	for _, tree in ipairs(nature and nature:GetChildren() or {}) do
		if tree:IsA("Model") and tree.Name == "Tree" then
			drawCircle(pivotOf(tree).Position, 9, COLORS.Tree, 2)
		end
	end
	-- Marco 10.31: Costa do Sol (mar, costão, areia, calçadão, casinhas da orla e o píer)
	local L = GameConfig.Litoral
	if L and map:FindFirstChild("Litoral") then
		local seaDepth = 6000
		drawRect(CFrame.new(0, 0, L.SeaZ + seaDepth / 2), WORLD * 6, seaDepth, Color3.fromRGB(26, 62, 98), 1)
		drawRect(CFrame.new(0, 0, L.SeaZ + 30), WORLD * 6, 60, Color3.fromRGB(34, 78, 118), 1) -- água rasa
		local z0 = L.SandStartZ or L.BikeZ1 -- Marco 10.32: areia e dunas de ponta a ponta
		drawRect(CFrame.new(0, 0, (z0 + L.SeaZ) / 2), WORLD * 6, L.SeaZ - z0, Color3.fromRGB(150, 136, 100), 1) -- areia
		drawRect(CFrame.new(0, 0, (L.WalkZ0 + L.BikeZ1) / 2), 2 * L.BeachHalf, L.BikeZ1 - L.WalkZ0, Color3.fromRGB(118, 116, 108), 2) -- calçadão
		drawRect(CFrame.new(0, 0, (L.WalkZ1 + L.GreenZ1) / 2), 2 * L.BeachHalf, L.GreenZ1 - L.WalkZ1, Color3.fromRGB(56, 86, 64), 2) -- gramado
		drawRect(CFrame.new(0, 0, (L.FrontZ0 + L.WalkZ0) / 2), 2 * (L.BeiraMarHalf - 20), L.WalkZ0 - L.FrontZ0, Color3.fromRGB(128, 104, 118), 3, 2) -- casinhas
		drawRect(CFrame.new(0, 0, (L.FrontZ0 + L.WalkZ0) / 2), 156, L.WalkZ0 - L.FrontZ0, Color3.fromRGB(150, 140, 120), 3) -- praça do píer
		local pier = L.Pier
		drawRect(CFrame.new(0, 0, (pier.Z0 + pier.Z1) / 2), pier.Width, pier.Z1 - pier.Z0, Color3.fromRGB(150, 118, 84), 3) -- píer
		drawRect(CFrame.new(L.ParkCenter), 464, 464, Color3.fromRGB(150, 118, 84), 3, 6) -- plataforma do parque
	end
	drawStreets()
	-- áreas grandes: parque e penitenciária (com os prédios dentro)
	local park = map:FindFirstChild("MigueLandia")
	if park then
		local size = park:GetAttribute("Size") or GameConfig.Park.Size or 440
		drawRect(pivotOf(park), size, size, Color3.fromRGB(92, 64, 90), 3, 8)
		for _, child in ipairs(park:GetChildren()) do
			if child:IsA("Model") then
				drawModel(child, Color3.fromRGB(150, 90, 140), 4, 2)
			end
		end
	end
	-- Marco 10.31: concessionária (lote com o prédio do meio)
	local dealer = map:FindFirstChild("Concessionaria")
	if dealer then
		drawModel(dealer, Color3.fromRGB(70, 66, 58), 3, 6)
		local building = dealer:FindFirstChild("Predio")
		if building then
			drawModel(building, Color3.fromRGB(176, 150, 96), 4, 2)
		end
	end
	local prison = map:FindFirstChild("Penitenciaria")
	if prison then
		local pv = pivotOf(prison)
		drawRect(pv, prison:GetAttribute("Width") or 520, prison:GetAttribute("Depth") or 560, Color3.fromRGB(70, 74, 84), 3, 4)
		local smin, smax = prison:GetAttribute("SecureMin"), prison:GetAttribute("SecureMax")
		if typeof(smin) == "Vector3" and typeof(smax) == "Vector3" then
			local mid = (smin + smax) / 2
			drawRect(pv * CFrame.new(mid.X, 0, mid.Z), smax.X - smin.X, smax.Z - smin.Z, Color3.fromRGB(86, 90, 100), 3)
		end
		for _, d in ipairs(prison:GetDescendants()) do
			if d:IsA("Model") then
				local n = d.Name
				if n:match("^Patio") then
					drawModel(d, Color3.fromRGB(110, 114, 124), 4)
				elseif n:match("^Pavilhao") or n == "Administracao" or n == "Refeitorio" or n == "Enfermaria" or n == "Escola" or n == "Lavanderia" or n == "Biblioteca" then
					drawModel(d, Color3.fromRGB(150, 92, 70), 5, 1)
				elseif n == "BasePM" then
					drawModel(d, Color3.fromRGB(60, 90, 150), 5, 1)
				end
			end
		end
	end
	-- Marco 10.1: favelas (área, patamares do morro e as casas de enfeite; os barracos de morar
	-- estão em Houses, desenhados logo abaixo)
	local favelas = map:FindFirstChild("Favelas")
	local info = map:FindFirstChild("MapaInfo")
	if info then
		-- Marco 10.22: as peças soltas das favelas vêm anotadas pelo servidor (streaming)
		local look = {
			FavelaArea = { Color3.fromRGB(78, 70, 62), 3, 6 },
			Morro = { Color3.fromRGB(92, 82, 70), 3 },
			FavelaCasaModel = { Color3.fromRGB(120, 90, 74), 4 },
			FavelaCasa = { Color3.fromRGB(110, 82, 66), 4 },
		}
		for _, order in ipairs({ "FavelaArea", "Morro", "FavelaCasaModel", "FavelaCasa" }) do
			for _, v in ipairs(info:GetChildren()) do
				local size = v:GetAttribute("Tam")
				if v.Name == order and v:IsA("CFrameValue") and typeof(size) == "Vector3" then
					local l = look[order]
					drawRect(v.Value, size.X, size.Z, l[1], l[2], l[3])
				end
			end
		end
		favelas = nil
	end
	for _, fav in ipairs(favelas and favelas:GetChildren() or {}) do
		local area = fav:FindFirstChild("Area")
		if area then
			drawRect(area.CFrame, area.Size.X, area.Size.Z, Color3.fromRGB(78, 70, 62), 3, 6)
		end
		local chao = fav:FindFirstChild("Chao")
		for _, p in ipairs(chao and chao:GetChildren() or {}) do
			if p.Name == "Morro" then
				drawRect(p.CFrame, p.Size.X, p.Size.Z, Color3.fromRGB(92, 82, 70), 3)
			end
		end
		local casas = fav:FindFirstChild("Casas")
		for _, c in ipairs(casas and casas:GetChildren() or {}) do
			if c:IsA("Model") then
				drawModel(c, Color3.fromRGB(120, 90, 74), 4)
			elseif c:IsA("BasePart") then
				drawRect(c.CFrame, c.Size.X, c.Size.Z, Color3.fromRGB(110, 82, 66), 4)
			end
		end
	end
	-- casas e prédios com o formato de verdade
	local houses = map:FindFirstChild("Houses")
	for _, house in ipairs(houses and houses:GetChildren() or {}) do
		drawModel(house, COLORS.House, 4, 1)
	end
	local buildings = map:FindFirstChild("Buildings")
	for _, building in ipairs(buildings and buildings:GetChildren() or {}) do
		drawModel(building, COLORS.Building, 4, 1)
	end
	local shops = map:FindFirstChild("JobLocations")
	for _, shop in ipairs(shops and shops:GetChildren() or {}) do
		drawModel(shop, Color3.fromRGB(70, 100, 160), 4, 1)
	end
end

---------------------------------------------------------------------------
-- Lugares (ícones no mapa + lista ao lado)
---------------------------------------------------------------------------

local function addPlace(name, icon, pos, color)
	local pin = Instance.new("TextLabel") -- não é botão: o toque passa para o mapa (onTap acha o ícone)
	pin.AnchorPoint = Vector2.new(0.5, 0.5)
	pin.Size = UDim2.fromOffset(24, 24)
	pin.BackgroundColor3 = color or COLORS.Shop
	pin.Font = Enum.Font.GothamBold
	pin.TextSize = 14
	pin.Text = icon
	pin.ZIndex = 6
	pin.Parent = overlay
	corner(pin, UDim.new(1, 0))
	stroke(pin, Color3.fromRGB(14, 18, 28), 2) -- Marco 10.8: contorno escuro (mapa minimalista)
	local label = text(overlay, { Text = name, TextSize = 11, Stroke = 0.35, Anchor = Vector2.new(0.5, 0), Size = UDim2.fromOffset(150, 13), ZIndex = 6 })
	local entry = { name = name, icon = icon, pos = pos, pin = pin, label = label, color = color or COLORS.Shop }
	table.insert(places, entry)
	pinsByName[name] = entry
	table.insert(overlayItems, { gui = pin, pos = pos, entry = entry })
	table.insert(overlayItems, { gui = label, pos = pos, offset = Vector2.new(0, 13), minZoom = 1.6, entry = entry })
	return entry
end

local function collectPlaces(map)
	local iconByName = {}
	for key, placeName in pairs(GameConfig.Places) do
		iconByName[placeName] = PLACE_ICONS[key] or "🏪"
	end
	addPlace("Praça Central", "⛲", Vector3.zero, Color3.fromRGB(60, 150, 90))
	-- Marco 10.4: hospital, escola e praça do Jardim Progresso
	local district = GameConfig.Progresso.District
	local districtIcons = {
		[district.HospitalName] = { "🏥", Color3.fromRGB(200, 50, 55) },
		[district.SchoolName] = { "🏫", Color3.fromRGB(230, 140, 40) },
		[district.PlazaName] = { "⛲", Color3.fromRGB(60, 150, 90) },
	}
	local progresso = map:FindFirstChild("JardimProgresso")
	for _, m in ipairs(progresso and progresso:GetChildren() or {}) do
		local info = m:IsA("Model") and districtIcons[m:GetAttribute("PlaceName") or ""]
		if info then
			addPlace(m:GetAttribute("PlaceName"), info[1], pivotOf(m).Position, info[2])
		end
	end
	local shops = map:FindFirstChild("JobLocations")
	for _, shop in ipairs(shops and shops:GetChildren() or {}) do
		local name = shop:GetAttribute("PlaceName")
		if name then
			addPlace(name, iconByName[name] or "🏪", pivotOf(shop).Position).shop = true
		end
	end
	local garages = map:FindFirstChild("Garages")
	local n = 0
	for _, garage in ipairs(garages and garages:GetChildren() or {}) do
		local booth = garage:FindFirstChild("Balcao", true)
		local pos = booth and booth.Position or pivotOf(garage).Position
		if garage:GetAttribute("Private") or garage:GetAttribute("Retirada") then
			-- Marco 10.6: garagem de mansão (só do dono): não entra no mapa
			-- Marco 10.31: a retirada da concessionária fica no mesmo pino da loja
		elseif garage:GetAttribute("Dealership") then
			addPlace(GameConfig.Dealership.Name, "🚘", garage:GetAttribute("SalesPosition") or pos, Color3.fromRGB(190, 150, 60))
		elseif garage:GetAttribute("ServiceJob") == "Policial" then
			addPlace("Garagem da PM", "🚓", pos, Color3.fromRGB(25, 40, 75))
		elseif garage:GetAttribute("ServiceJob") == "Taxista" then
			addPlace(GameConfig.Places.Taxi, "🚕", pos, Color3.fromRGB(210, 165, 10)) -- Marco 9
		elseif garage:GetAttribute("ServiceJob") == "Motorista" then
			addPlace(GameConfig.Places.Onibus, "🚌", pos, Color3.fromRGB(30, 130, 80)) -- Marco 9: garagem dos ônibus
		elseif garage:GetAttribute("ServiceJob") == "Paramedico" then
			addPlace("Ambulâncias SAMU", "🚑", pos, Color3.fromRGB(200, 20, 30)) -- Marco 10.19: pronto-socorro do hospital
		elseif garage:GetAttribute("ServiceJob") == "Bombeiro" then
			addPlace(GameConfig.Places.Bombeiros, "🚒", pos, Color3.fromRGB(200, 16, 46)) -- Marco 9.9: quartel
		else
			n += 1
			addPlace("Garagem " .. n, "🅿️", pos, Color3.fromRGB(40, 70, 150))
		end
	end
	local paint = map:FindFirstChild("PaintShop")
	if paint then
		addPlace(GameConfig.PaintShop.Name or "Pintura", "🎨", pivotOf(paint).Position, Color3.fromRGB(140, 70, 200))
	end
	local park = map:FindFirstChild("MigueLandia")
	if park then
		addPlace(park:GetAttribute("ParkName") or "Parque", "🎡", pivotOf(park).Position, Color3.fromRGB(230, 90, 150))
	end
	-- Marco 10.31: lugares da Costa do Sol (praia, calçadão, academia, skate, farol...)
	local litoral = map:FindFirstChild("Litoral")
	local lugares = litoral and litoral:FindFirstChild("Lugares")
	for _, m in ipairs(lugares and lugares:GetChildren() or {}) do
		local name = m:GetAttribute("PlaceName")
		if name and not pinsByName[name] then
			local color = m:GetAttribute("IconColor")
			addPlace(name, m:GetAttribute("Icon") or "📍", pivotOf(m).Position, typeof(color) == "Color3" and color or nil)
		end
	end
	local prison = map:FindFirstChild("Penitenciaria")
	if prison then
		addPlace("Penitenciária", "⛓️", pivotOf(prison).Position, Color3.fromRGB(90, 95, 105))
	end
	local vilaDir = CFrame.Angles(0, (M.Vila.Dir - 1) * math.pi / 4, 0).LookVector
	addPlace(M.Vila.Name, "🏘️", vilaDir * (RADIAL_END + M.Vila.Length * 0.6), Color3.fromRGB(150, 120, 90))
	-- Marco 10: Bairro Horizonte, condomínio de mansões e o posto da rodovia
	local HZ = GameConfig.Horizonte
	if map:FindFirstChild("Horizonte") then
		local D = CityRoads.District
		addPlace(HZ.Name, "🏙️", CityRoads.districtPoint(0, D.StreetT[2]), Color3.fromRGB(60, 110, 170))
		addPlace(HZ.CondoName, "🏡", CityRoads.districtPoint(0, (D.Loop.T0 + D.Loop.T1) / 2), Color3.fromRGB(190, 150, 70))
		-- Marco 10.8: joalheria (Rua das Magnólias)
		local joia = map.Horizonte:FindFirstChild("Joalheria")
		if joia then
			addPlace(GameConfig.Jewelry.Name, "💎", pivotOf(joia).Position, Color3.fromRGB(215, 175, 80))
		end
	end
	-- Marco 10.20: Banco Central (Estrada do Vale)
	local banco = game:GetService("CollectionService"):GetTagged("Banco")[1]
	if banco and banco:IsA("Model") then
		addPlace(GameConfig.Bank.Short or GameConfig.Bank.Name, "🏦", pivotOf(banco).Position, Color3.fromRGB(110, 150, 200))
	end
	-- Marco 10.30: obra do Residencial Vale Alto (a perfuratriz do assalto aparece lá)
	local obra = game:GetService("CollectionService"):GetTagged("Obra")[1]
	if obra and obra:IsA("Model") then
		addPlace(obra:GetAttribute("PlaceName") or "Obra", "🏗️", pivotOf(obra).Position, Color3.fromRGB(230, 160, 40))
	end
	local posto = map:FindFirstChild("PostoEstrela", true)
	if posto then
		addPlace(GameConfig.Rodovia.PostoName, "⛽", pivotOf(posto).Position, Color3.fromRGB(200, 60, 50))
	end
	-- Marco 10.1: as 3 comunidades das gangues (o chefe é escondido: não tem pino)
	local favelaIcons = { morro = "⛰️", complexo = "🌑", solar = "☀️" }
	if map:FindFirstChild("Favelas") then
		for _, id in ipairs(GameConfig.Gangs.Order) do
			local g = GameConfig.Gangs.List[id]
			addPlace(g.Community, favelaIcons[g.Style] or "🏚️", g.Center, g.Color)
		end
	end
end

---------------------------------------------------------------------------
-- Destino escolhido pelo jogador
---------------------------------------------------------------------------

local function refreshRows()
	for _, entry in ipairs(places) do
		if entry.row then
			local selected = dest and dest.name == entry.name
			entry.row.BackgroundColor3 = selected and COLORS.Dest or COLORS.Row
			if entry.rowBar then
				entry.rowBar.Visible = selected
			end
		end
	end
end

local function setDestination(name, pos)
	if pos then
		dest = { name = name, pos = Vector3.new(pos.X, 0, pos.Z) }
	else
		dest = nil
	end
	refreshRows()
	MapController.refresh()
end

---------------------------------------------------------------------------
-- Atualização da janela (zoom/arrasto) e das coisas que se mexem
---------------------------------------------------------------------------

local function inView(v, margin)
	margin = margin or 20
	return v.X > -margin and v.Y > -margin and v.X < VIEW + margin and v.Y < VIEW + margin
end

local function placeOverlay(item)
	if item.entry and item.entry.hidden then
		item.gui.Visible = false
		return
	end
	local v = toView(item.pos) + (item.offset or Vector2.zero)
	local show = inView(v) and zoom >= (item.minZoom or 0)
	if item.entry and (item.entry.name == targetPlace or (dest and dest.name == item.entry.name)) then
		show = inView(v) -- nome do destino aparece sempre
	end
	item.gui.Visible = show
	if show then
		item.gui.Position = UDim2.fromOffset(v.X, v.Y)
	end
end

local function applyView()
	zoom = math.clamp(zoom, MIN_ZOOM, MAX_ZOOM)
	-- Marco 10: o arrasto vai até a borda do chão inteiro (a rodovia e os bairros novos ficam
	-- fora do quadrado da cidade); se o chão couber na janela, fica centralizado
	local half = VIEW / 2 / zoom
	local lo, hi = toMap(Vector3.new(-M.GroundSize / 2, 0, 0)).X, toMap(Vector3.new(M.GroundSize / 2, 0, 0)).X
	local function clampAxis(v)
		if hi - lo <= 2 * half then
			return (lo + hi) / 2
		end
		return math.clamp(v, lo + half, hi - half)
	end
	center = Vector2.new(clampAxis(center.X), clampAxis(center.Y))
	worldScale.Scale = zoom
	world.Position = UDim2.fromOffset(VIEW / 2 - center.X * zoom, VIEW / 2 - center.Y * zoom)
	for _, item in ipairs(overlayItems) do
		placeOverlay(item)
	end
	zoomLabel.Text = ("%.1fx"):format(zoom)
end

local function rootPart()
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart")
end

local function dotAt(list, i, color, size)
	local d = list[i]
	if not d then
		d = Instance.new("Frame")
		d.AnchorPoint = Vector2.new(0.5, 0.5)
		d.BorderSizePixel = 0
		d.ZIndex = 5
		d.Parent = overlay
		corner(d, UDim.new(1, 0))
		list[i] = d
	end
	d.BackgroundColor3 = color
	d.Size = UDim2.fromOffset(size, size)
	d.Visible = true
	return d
end

local function updateDynamic()
	local root = rootPart()
	-- você
	if root then
		local v = toView(root.Position)
		playerMarker.Visible = inView(v, 30)
		playerMarker.Position = UDim2.fromOffset(v.X, v.Y)
		local look = root.CFrame.LookVector
		playerPointer.Rotation = math.deg(math.atan2(look.Z, look.X)) + 90
	else
		playerMarker.Visible = false
	end
	-- outros jogadores
	local seen = {}
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player then
			local character = other.Character
			local r = character and character:FindFirstChild("HumanoidRootPart")
			local entry = others[other]
			if r then
				if not entry then
					local dot = Instance.new("Frame")
					dot.AnchorPoint = Vector2.new(0.5, 0.5)
					dot.Size = UDim2.fromOffset(12, 12)
					dot.BackgroundColor3 = Color3.fromRGB(255, 210, 60)
					dot.ZIndex = 7
					dot.Parent = overlay
					corner(dot, UDim.new(1, 0))
					stroke(dot, Color3.fromRGB(60, 40, 0), 2)
					local name = text(overlay, { Text = other.DisplayName, TextSize = 10, Stroke = 0.3, Anchor = Vector2.new(0.5, 1), Size = UDim2.fromOffset(110, 12), ZIndex = 7, Color = Color3.fromRGB(255, 235, 150) })
					entry = { dot = dot, name = name }
					others[other] = entry
				end
				local v = toView(r.Position)
				local show = inView(v)
				entry.dot.Visible = show
				entry.name.Visible = show
				entry.dot.Position = UDim2.fromOffset(v.X, v.Y)
				entry.name.Position = UDim2.fromOffset(v.X, v.Y - 7)
				-- Marco 10.9: bolsa da joalheria com rastreador: a PM vê a pessoa piscando em vermelho
				local tracked = (other:GetAttribute("RastreadorJoias") == true or other:GetAttribute("RastreadorBanco") == true) and player:GetAttribute("Job") == "Policial"
				-- Marco 10.15: o paramédico vê quem está caído (cruz vermelha piscando)
				local downed = other:GetAttribute("Caido") == true and player:GetAttribute("Job") == "Paramedico"
				local mode = downed and "caido" or (tracked and "joias" or nil)
				tracked = tracked or downed
				if mode ~= entry.mode then
					entry.mode = mode
					entry.dot.Size = tracked and UDim2.fromOffset(18, 18) or UDim2.fromOffset(12, 12)
					entry.name.Text = mode == "caido" and ("✚ " .. other.DisplayName .. " (caído)") or (mode == "joias" and ("📡 " .. other.DisplayName .. " (joias)") or other.DisplayName)
					entry.name.TextColor3 = tracked and Color3.fromRGB(255, 120, 120) or Color3.fromRGB(255, 235, 150)
				end
				if tracked then
					entry.dot.BackgroundColor3 = (math.floor(os.clock() * 3) % 2 == 0) and Color3.fromRGB(255, 40, 40) or Color3.fromRGB(255, 200, 200)
				else
					entry.dot.BackgroundColor3 = Color3.fromRGB(255, 210, 60)
				end
				seen[other] = true
			end
		end
	end
	for other, entry in pairs(others) do
		if not seen[other] then
			entry.dot:Destroy()
			entry.name:Destroy()
			others[other] = nil
		end
	end
	-- destino do emprego (bolinha laranja) e destino do jogador (alfinete rosa + linha pontilhada)
	if targetPos then
		local v = toView(targetPos)
		targetDot.Visible = inView(v)
		targetDot.Position = UDim2.fromOffset(v.X, v.Y)
	else
		targetDot.Visible = false
	end
	local used = 0
	if dest then
		local v = toView(dest.pos)
		destPin.Visible = inView(v)
		destPin.Position = UDim2.fromOffset(v.X, v.Y)
	else
		destPin.Visible = false
	end
	for i = used + 1, #pathDots do
		pathDots[i].Visible = false
	end
	-- texto de baixo e distâncias da lista
	-- Marco 10.8: cartão do destino (embaixo do mapa)
	if dest and root then
		local dist = (Vector3.new(root.Position.X, 0, root.Position.Z) - dest.pos).Magnitude
		local entry = pinsByName[dest.name]
		destIcon.Text = entry and entry.icon or "📍"
		destIcon.BackgroundColor3 = COLORS.Dest
		destLabel.Text = dest.name
		destSub.Text = ("%s  •  uns %d min a pé  •  %d min de carro"):format(meters(dist), math.max(1, math.ceil(dist / 16 / 60)), math.max(1, math.ceil(dist / 60 / 60)))
	elseif targetPlace or targetPos then
		destIcon.Text = "💼"
		destIcon.BackgroundColor3 = COLORS.Target
		destLabel.Text = "Destino do trabalho"
		destSub.Text = "O laranja no mapa é para onde o seu trabalho manda. Toque em outro lugar para marcar."
	else
		destIcon.Text = "👆"
		destIcon.BackgroundColor3 = COLORS.Row
		destLabel.Text = "Nenhum destino"
		destSub.Text = "Toque num lugar da lista ou em qualquer ponto do mapa."
	end
	clearButton.Visible = dest ~= nil
	if root then
		local q = searchBox and searchBox.Text:lower() or ""
		for _, entry in ipairs(places) do
			local d = (root.Position * Vector3.new(1, 0, 1) - entry.pos * Vector3.new(1, 0, 1)).Magnitude
			if entry.row then
				local match = q == "" or entry.name:lower():find(q, 1, true) ~= nil
				entry.row.Visible = not entry.hidden and match
				entry.row.LayoutOrder = 10 + math.floor(d / 10) -- Marco 10.8: mais perto primeiro
			end
			if entry.rowDist then
				entry.rowDist.Text = meters(d)
			end
		end
	end
end

function MapController.refresh()
	if not panel then
		return
	end
	for name, entry in pairs(pinsByName) do
		local isTarget = name == targetPlace
		local isDest = dest and dest.name == name
		entry.pin.BackgroundColor3 = isTarget and COLORS.Target or (isDest and COLORS.Dest or entry.color)
		entry.pin.Size = UDim2.fromOffset((isTarget or isDest) and 30 or 24, (isTarget or isDest) and 30 or 24)
		entry.label.TextColor3 = isTarget and Color3.fromRGB(255, 220, 150) or (isDest and Color3.fromRGB(255, 190, 220) or Color3.new(1, 1, 1))
	end
	applyView()
	updateDynamic()
end

---------------------------------------------------------------------------
-- Marco 9.9: GPS (caminho pelas ruas, no mapa e no chão)
---------------------------------------------------------------------------

-- Para onde o GPS leva: destino marcado no mapa; senão o do emprego (ponto ou lugar laranja)
local function routeGoal()
	if dest then
		return dest.pos, COLORS.Dest
	end
	if targetPos then
		return Vector3.new(targetPos.X, 0, targetPos.Z), COLORS.Target
	end
	local entry = targetPlace and pinsByName[targetPlace]
	if entry then
		return Vector3.new(entry.pos.X, 0, entry.pos.Z), COLORS.Target
	end
	return nil
end

local function drawRouteOnMap()
	for _, f in ipairs(routeFrames) do
		f:Destroy()
	end
	routeFrames = {}
	if not world or not route then
		return
	end
	local pts = route.points
	for i = 1, #pts - 1 do
		local outline = drawLine(pts[i], pts[i + 1], 4, Color3.new(1, 1, 1), 4)
		local line = drawLine(pts[i], pts[i + 1], 2.4, route.color, 5)
		table.insert(routeFrames, outline)
		table.insert(routeFrames, line)
	end
end

local function routePart(i)
	local p = routeParts[i]
	if not p then
		if not routeFolder then
			routeFolder = Instance.new("Folder")
			routeFolder.Name = "RotaGPS"
			routeFolder.Parent = Workspace
		end
		p = Instance.new("Part")
		p.Name = "Rota"
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Material = Enum.Material.Neon
		p.Transparency = 0.35
		p.Parent = routeFolder
		routeParts[i] = p
	end
	return p
end

-- Faixa no chão: começa um pouco à frente do jogador (não fica embaixo do carro) e vai até
-- GPS_AHEAD studs pelo caminho
local function drawRouteOnGround()
	local used = 0
	if route and GPS_GROUND then
		local left = GPS_AHEAD
		local skip = 8
		local pts = route.points
		for i = 1, #pts - 1 do
			local a, b = pts[i], pts[i + 1]
			local len = (b - a).Magnitude
			if len > 0.1 and left > 0 then
				local dir = (b - a) / len
				local s0 = math.min(skip, len)
				skip -= s0
				local s1 = math.min(len, s0 + left)
				if s1 - s0 > 0.5 then
					left -= s1 - s0
					used += 1
					local p = routePart(used)
					local mid = a + dir * ((s0 + s1) / 2) + Vector3.new(0, ROAD_TOP + 0.07, 0)
					p.Size = Vector3.new(1.8, 0.05, s1 - s0 + 1.8) -- +1.8: as pontas se encontram nas curvas
					p.CFrame = CFrame.lookAt(mid, mid + dir)
					p.Color = route.color
					p.Transparency = 0.35
				end
			end
		end
	end
	for i = used + 1, #routeParts do
		routeParts[i].Transparency = 1
		routeParts[i].Size = Vector3.new(0.1, 0.1, 0.1)
	end
end

local drawMiniRoute -- Marco 10.12 (minimapa, definida embaixo)

local function updateRoute()
	local root = rootPart()
	local goal, color = routeGoal()
	local here = root and Vector3.new(root.Position.X, 0, root.Position.Z)
	if not goal or not here or (here - goal).Magnitude < ARRIVE then
		if route then
			route = nil
			drawRouteOnMap()
			drawRouteOnGround()
			if drawMiniRoute then
				drawMiniRoute()
			end
		end
		return
	end
	if route and route.goal == goal and route.color == color and (route.from - here).Magnitude < 4 then
		return -- nada mudou
	end
	-- Marco 10.9: enquanto você segue o caminho, ele NÃO é recalculado (antes ele mudava a cada
	-- passo e a seta ficava "atualizando"). Só refaz se sair do caminho (OFF_ROUTE) ou mudar o destino.
	if route and route.goal == goal and route.color == color and route.points and #route.points >= 2 then
		local _, off = projectOnRoute(here)
		if off and off < OFF_ROUTE then
			route.from = here
			return
		end
	end
	local changedGoal = not route or route.goal ~= goal
	route = { points = RouteGraph.route(here, goal), color = color, from = here, goal = goal }
	drawRouteOnGround()
	if drawMiniRoute then
		drawMiniRoute()
	end
	if isOpen or changedGoal then
		drawRouteOnMap()
	end
end

-- Marco 9.1: para onde a setinha aponta. O destino escolhido no mapa vem primeiro; sem ele,
-- vale o destino do emprego fora da loja (passageiro do táxi, casa da entrega).
local function goalPos()
	if dest then
		return dest.pos
	end
	return targetPos and Vector3.new(targetPos.X, 0, targetPos.Z) or nil
end

-- Marco 10.9: posição no caminho. projectOnRoute(p) devolve quantos studs do caminho você já
-- andou (o ponto do caminho mais perto de você) e a distância até ele.
projectOnRoute = function(p)
	local pts = route and route.points
	if not pts or #pts < 2 then
		return nil, nil
	end
	local best, bestS, walked = math.huge, 0, 0
	for i = 1, #pts - 1 do
		local a = Vector3.new(pts[i].X, 0, pts[i].Z)
		local b = Vector3.new(pts[i + 1].X, 0, pts[i + 1].Z)
		local ab = b - a
		local len = ab.Magnitude
		if len > 0.01 then
			local t = math.clamp((p - a):Dot(ab) / (len * len), 0, 1)
			local d = (a + ab * t - p).Magnitude
			if d < best then
				best, bestS = d, walked + t * len
			end
			walked += len
		end
	end
	route.length = walked
	return bestS, best
end

-- ponto do caminho a s studs do começo
local function pointAlong(s)
	local pts = route.points
	local walked = 0
	for i = 1, #pts - 1 do
		local a = Vector3.new(pts[i].X, 0, pts[i].Z)
		local b = Vector3.new(pts[i + 1].X, 0, pts[i + 1].Z)
		local len = (b - a).Magnitude
		if walked + len >= s and len > 0.01 then
			return a + (b - a) * ((s - walked) / len)
		end
		walked += len
	end
	local last = pts[#pts]
	return Vector3.new(last.X, 0, last.Z)
end

-- Próxima curva do caminho depois de "progress": distância até ela e o ângulo (+ direita, - esquerda).
-- O ângulo compara a direção 20 studs antes do ponto com a de 25 studs depois (assim a rotatória,
-- que é feita de retinhas, conta como uma curva só).
local function nextTurn(progress)
	local pts = route.points
	local walked = 0
	for i = 1, #pts - 2 do
		local a = Vector3.new(pts[i].X, 0, pts[i].Z)
		local b = Vector3.new(pts[i + 1].X, 0, pts[i + 1].Z)
		walked += (b - a).Magnitude
		if walked > progress + 2 then
			local before = (b - pointAlong(math.max(0, walked - 20)))
			local after = (pointAlong(walked + 25) - b)
			if before.Magnitude > 1 and after.Magnitude > 1 then
				local i1, i2 = before.Unit, after.Unit
				local ang = math.deg(math.atan2(i1:Cross(i2).Y * -1, i1:Dot(i2)))
				if math.abs(ang) > 35 then
					return walked - progress, ang
				end
			end
		end
	end
	return nil, nil
end

local function chipShow(title, sub, color)
	chipTitle.Text = title
	chipSub.Text = sub or ""
	chipSub.Visible = sub ~= nil
	chipTitle.Position = sub and UDim2.fromOffset(46, 5) or UDim2.fromOffset(46, 12)
	if color then
		chipBadge.BackgroundColor3 = color
	end
	chip.Visible = true
end

-- Marco 10.9: o que o painel mostra (calculado no updateChip, desenhado todo quadro no updateArrow)
local nav = { name = "", remaining = 0 }
local arrowAngle = 0 -- ângulo que a seta mostra (vai suavizando até o certo)
local wrongSince -- desde quando você está indo ao contrário

-- Painel de navegação embaixo dos botões do topo: seta + o que fazer + distância
local function updateChip()
	if not chip then
		return
	end
	local root = rootPart()
	local goal = goalPos()
	if not goal or not root then
		chip.Visible = false
		return
	end
	local here = Vector3.new(root.Position.X, 0, root.Position.Z)
	local dist = (here - goal).Magnitude
	nav.name = dest and dest.name or "Destino do trabalho"
	nav.remaining = dist
	if route and route.points and #route.points >= 2 then
		local progress, off = projectOnRoute(here)
		if progress then
			nav.remaining = math.max(dist, (route.length or 0) - progress + (off or 0))
		end
	end
	if not dest then
		-- destino do emprego: some quando chega (a tarefa mostra o que fazer)
		chipArrow.Visible = true
		if dist < ARRIVE then
			chip.Visible = false
			return
		end
		chip.Visible = true
		return
	end
	if dist < ARRIVE then
		chipArrow.Visible = false
		chipShow("Você chegou!", dest.name, Color3.fromRGB(60, 180, 100))
		chip:SetAttribute("Chegou", true)
		dest = nil
		refreshRows()
		task.delay(3, function()
			if not dest then
				chip.Visible = false
			end
		end)
		if panel then
			MapController.refresh()
		end
		return
	end
	chipArrow.Visible = true
	chip.Visible = true
end

-- Todo quadro: a seta aponta para um ponto do caminho uns 30 studs à frente (para cima = para onde
-- a câmera olha) e gira suave; a frase vem das curvas do caminho, igual GPS de verdade:
-- "Siga em frente", "Vire à direita em 80 m", "Vire à esquerda agora", "Faça o retorno".
-- "Dê a volta" só aparece se você ficar indo ao contrário por mais de 1,5 s.
local function updateArrow(dt)
	if not chip or not chip.Visible or not chipArrow.Visible then
		return
	end
	local root = rootPart()
	local camera = Workspace.CurrentCamera
	local goal = goalPos()
	if not root or not camera or not goal then
		return
	end
	local here = Vector3.new(root.Position.X, 0, root.Position.Z)
	local target, turnDist, turnAng = goal, nil, nil
	if route and route.points and #route.points >= 2 then
		local progress = projectOnRoute(here)
		if progress then
			target = pointAlong(progress + 30)
			turnDist, turnAng = nextTurn(progress)
		end
	end
	local look = camera.CFrame.LookVector
	local flatLook = Vector3.new(look.X, 0, look.Z)
	local toTarget = target - here
	if flatLook.Magnitude < 0.01 or toTarget.Magnitude < 0.01 then
		return
	end
	local rel = CFrame.lookAt(Vector3.zero, flatLook):VectorToObjectSpace(toTarget)
	local want = math.deg(math.atan2(rel.X, -rel.Z))
	local diff = (want - arrowAngle + 180) % 360 - 180
	arrowAngle += diff * math.min(1, (dt or 0.016) * 10)
	chipArrow.Rotation = arrowAngle

	local now = os.clock()
	if math.abs(want) > 140 then
		wrongSince = wrongSince or now
	else
		wrongSince = nil
	end
	local destColor = dest and COLORS.Dest or COLORS.Target
	local title, color
	if wrongSince and now - wrongSince > 1.5 then
		title, color = "Dê a volta", Color3.fromRGB(220, 80, 60)
	elseif turnDist and turnDist < 220 then
		local side = turnAng > 0 and "direita" or "esquerda"
		if math.abs(turnAng) > 140 then
			title = turnDist < 25 and "Faça o retorno agora" or ("Retorno em " .. meters(turnDist))
		else
			title = turnDist < 25 and ("Vire à " .. side .. " agora") or ("Vire à " .. side .. " em " .. meters(turnDist))
		end
		color = destColor
	else
		title, color = "Siga em frente", Color3.fromRGB(60, 180, 100)
	end
	local sub = meters(nav.remaining) .. "  •  " .. nav.name
	if chipTitle.Text ~= title or chipSub.Text ~= sub then
		chipShow(title, sub, nil)
	end
	chipBadge.BackgroundColor3 = chipBadge.BackgroundColor3:Lerp(color, math.min(1, (dt or 0.016) * 6))
end

---------------------------------------------------------------------------
-- Interface
---------------------------------------------------------------------------

local function buildPlayerMarker()
	playerMarker = Instance.new("Frame")
	playerMarker.Name = "Voce"
	playerMarker.BackgroundTransparency = 1
	playerMarker.AnchorPoint = Vector2.new(0.5, 0.5)
	playerMarker.Size = UDim2.fromOffset(44, 44)
	playerMarker.ZIndex = 8
	playerMarker.Parent = overlay

	playerHalo = Instance.new("Frame")
	playerHalo.AnchorPoint = Vector2.new(0.5, 0.5)
	playerHalo.Position = UDim2.fromScale(0.5, 0.5)
	playerHalo.Size = UDim2.fromOffset(26, 26)
	playerHalo.BackgroundColor3 = Color3.fromRGB(40, 140, 255)
	playerHalo.BackgroundTransparency = 0.55
	playerHalo.ZIndex = 8
	playerHalo.Parent = playerMarker
	corner(playerHalo, UDim.new(1, 0))

	playerPointer = Instance.new("Frame")
	playerPointer.AnchorPoint = Vector2.new(0.5, 0.5)
	playerPointer.Position = UDim2.fromScale(0.5, 0.5)
	playerPointer.Size = UDim2.fromOffset(40, 40)
	playerPointer.BackgroundTransparency = 1
	playerPointer.ZIndex = 9
	playerPointer.Parent = playerMarker
	local tip = text(playerPointer, { Text = "▲", TextSize = 14, Font = Enum.Font.GothamBlack, Anchor = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 6), Size = UDim2.fromOffset(16, 12), ZIndex = 10 })
	tip.TextStrokeColor3 = Color3.fromRGB(20, 60, 140)
	tip.TextStrokeTransparency = 0

	local dot = Instance.new("Frame")
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Position = UDim2.fromScale(0.5, 0.5)
	dot.Size = UDim2.fromOffset(18, 18)
	dot.BackgroundColor3 = Color3.fromRGB(30, 120, 255)
	dot.ZIndex = 11
	dot.Parent = playerMarker
	corner(dot, UDim.new(1, 0))
	stroke(dot, Color3.new(1, 1, 1), 3)

	local tag = text(playerMarker, { Text = "VOCÊ", TextSize = 10, Font = Enum.Font.GothamBlack, Anchor = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, -4), Size = UDim2.fromOffset(40, 15), ZIndex = 11 })
	tag.BackgroundTransparency = 0
	tag.BackgroundColor3 = Color3.fromRGB(30, 120, 255)
	corner(tag, UDim.new(0, 6))

	task.spawn(function()
		local t = 0
		while playerMarker.Parent do
			t += 0.05
			local k = (t % 1.2) / 1.2
			playerHalo.Size = UDim2.fromOffset(20 + 22 * k, 20 + 22 * k)
			playerHalo.BackgroundTransparency = 0.4 + 0.6 * k
			task.wait(0.05)
		end
	end)
end

local function smallButton(parent, label, pos, color)
	-- Marco 10.8: botões redondos e discretos no canto do mapa
	local b = Instance.new("TextButton")
	b.AnchorPoint = Vector2.new(1, 0)
	b.Position = pos
	b.Size = UDim2.fromOffset(34, 34)
	b.BackgroundColor3 = color or COLORS.Panel
	b.BackgroundTransparency = color and 0 or 0.15
	b.Font = Enum.Font.GothamBold
	b.TextSize = 18
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Text = label
	b.ZIndex = 20
	b.AutoButtonColor = true
	b.Parent = parent
	corner(b, UDim.new(1, 0))
	local st = stroke(b, Color3.new(1, 1, 1), 1)
	st.Transparency = 0.85
	return b
end

local function zoomAt(viewPoint, factor)
	local before = viewToMap(viewPoint)
	zoom = math.clamp(zoom * factor, MIN_ZOOM, MAX_ZOOM)
	-- mantém o ponto embaixo do mouse/dedo no mesmo lugar
	center = before - (viewPoint - Vector2.new(VIEW / 2, VIEW / 2)) / zoom
	applyView()
	updateDynamic()
end

local function centerOnPlayer()
	local root = rootPart()
	if root then
		center = toMap(root.Position)
		if zoom < 2.5 then
			zoom = 2.5
		end
		applyView()
		updateDynamic()
	end
end

-- Marco 8.3: botão da casinha (topo): abre o mapa na sua casa e marca ela como destino
function MapController.showHome()
	local pos = player:GetAttribute("HomePosition")
	if not panel or typeof(pos) ~= "Vector3" then
		return false
	end
	setDestination("Sua casa", pos)
	MapController.toggle(true)
	center = toMap(pos)
	if zoom < 2.5 then
		zoom = 2.5
	end
	applyView()
	updateDynamic()
	return true
end

-- Toque/clique sem arrastar: escolhe o lugar mais perto (ícone) ou marca o ponto
local function onTap(viewPoint)
	local best, bestDist = nil, 22
	for _, entry in ipairs(places) do
		if entry.pin.Visible and not entry.hidden then
			local d = (toView(entry.pos) - viewPoint).Magnitude
			if d < bestDist then
				best, bestDist = entry, d
			end
		end
	end
	if best then
		setDestination(best.name, best.pos)
	else
		setDestination("Ponto marcado", fromMap(viewToMap(viewPoint)))
	end
end

local function buildInput()
	local dragging, dragStart, centerStart, moved = false, nil, nil, false
	viewport.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			moved = false
			dragStart = screenToView(input.Position)
			centerStart = center
		end
	end)
	viewport.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseWheel then
			zoomAt(screenToView(input.Position), input.Position.Z > 0 and 1.25 or 0.8)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if not dragging or not isOpen then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
			local delta = screenToView(input.Position) - dragStart
			if delta.Magnitude > 6 then
				moved = true
			end
			if moved then
				center = centerStart - delta / zoom
				applyView()
				updateDynamic()
			end
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if not dragging then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
			if not moved and isOpen then
				onTap(screenToView(input.Position))
			end
		end
	end)
	-- pinça no celular
	local pinchStart
	UserInputService.TouchPinch:Connect(function(positions, scale, _, state)
		if not isOpen then
			return
		end
		if state == Enum.UserInputState.Begin then
			pinchStart = zoom
			dragging = false
		elseif pinchStart then
			-- zoom em volta do ponto entre os dois dedos
			local mid = positions[1] and positions[2] and (positions[1] + positions[2]) / 2
			local point = mid and screenToView(mid) or Vector2.new(VIEW / 2, VIEW / 2)
			zoomAt(point, math.clamp(pinchStart * scale, MIN_ZOOM, MAX_ZOOM) / zoom)
			if state == Enum.UserInputState.End then
				pinchStart = nil
			end
		end
	end)
end

local function buildList()
	-- Marco 10.8: busca em cima e lugares do mais perto para o mais longe
	local side = Instance.new("Frame")
	side.Name = "Lado"
	side.Position = UDim2.fromOffset(VIEW + 22, 52)
	side.Size = UDim2.fromOffset(LIST_W, VIEW)
	side.BackgroundTransparency = 1
	side.Parent = panel

	local searchHolder = Instance.new("Frame")
	searchHolder.Size = UDim2.new(1, 0, 0, 34)
	searchHolder.BackgroundColor3 = COLORS.Row
	searchHolder.Parent = side
	corner(searchHolder, UDim.new(0, 10))
	text(searchHolder, { Text = "🔎", TextSize = 14, Position = UDim2.fromOffset(6, 0), Size = UDim2.fromOffset(24, 34) })
	searchBox = Instance.new("TextBox")
	searchBox.BackgroundTransparency = 1
	searchBox.Position = UDim2.fromOffset(32, 0)
	searchBox.Size = UDim2.new(1, -38, 1, 0)
	searchBox.Font = Enum.Font.GothamMedium
	searchBox.TextSize = 13
	searchBox.TextColor3 = Color3.new(1, 1, 1)
	searchBox.PlaceholderText = "Buscar lugar..."
	searchBox.PlaceholderColor3 = COLORS.Muted
	searchBox.TextXAlignment = Enum.TextXAlignment.Left
	searchBox.ClearTextOnFocus = false
	searchBox.Text = ""
	searchBox.Parent = searchHolder
	searchBox:GetPropertyChangedSignal("Text"):Connect(function()
		updateDynamic()
	end)

	listFrame = Instance.new("ScrollingFrame")
	listFrame.Name = "Lugares"
	listFrame.Position = UDim2.fromOffset(0, 42)
	listFrame.Size = UDim2.new(1, 0, 1, -42)
	listFrame.BackgroundTransparency = 1
	listFrame.BorderSizePixel = 0
	listFrame.ScrollBarThickness = 4
	listFrame.ScrollBarImageColor3 = COLORS.Muted
	listFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	listFrame.CanvasSize = UDim2.new()
	listFrame.Parent = side
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 4)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = listFrame
	local pad = Instance.new("UIPadding")
	pad.PaddingRight = UDim.new(0, 8)
	pad.Parent = listFrame
	for i, entry in ipairs(places) do
		local row = Instance.new("TextButton")
		row.AutoButtonColor = true
		row.Size = UDim2.new(1, 0, 0, 40)
		row.BackgroundColor3 = COLORS.Row
		row.Text = ""
		row.LayoutOrder = i
		row.Parent = listFrame
		corner(row, UDim.new(0, 10))
		local icon = text(row, { Text = entry.icon, TextSize = 15, Anchor = Vector2.new(0, 0.5), Position = UDim2.new(0, 6, 0.5, 0), Size = UDim2.fromOffset(28, 28) })
		icon.BackgroundTransparency = 0
		icon.BackgroundColor3 = entry.color
		corner(icon, UDim.new(1, 0))
		local nameLabel = text(row, { Text = entry.name, TextSize = 13, Font = Enum.Font.GothamBold, Align = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(42, 5), Size = UDim2.new(1, -48, 0, 16) })
		nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
		entry.rowDist = text(row, { Text = "", TextSize = 11, Font = Enum.Font.Gotham, Align = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(42, 21), Size = UDim2.new(1, -48, 0, 13), Color = COLORS.Muted })
		local bar = Instance.new("Frame")
		bar.Size = UDim2.new(0, 3, 1, -12)
		bar.Position = UDim2.new(1, -6, 0, 6)
		bar.BackgroundColor3 = Color3.new(1, 1, 1)
		bar.BorderSizePixel = 0
		bar.Visible = false
		bar.Parent = row
		corner(bar, UDim.new(1, 0))
		entry.rowBar = bar
		entry.row = row
		row.MouseEnter:Connect(function()
			if not (dest and dest.name == entry.name) then
				row.BackgroundColor3 = COLORS.RowHover
			end
		end)
		row.MouseLeave:Connect(refreshRows)
		row.Activated:Connect(function()
			setDestination(entry.name, entry.pos)
			center = toMap(entry.pos)
			if zoom < 2.5 then
				zoom = 2.5
			end
			MapController.refresh()
		end)
	end
end

local function build(map)
	gui = Instance.new("ScreenGui")
	gui.Name = "MapUI"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 5
	gui.Parent = player:WaitForChild("PlayerGui")

	panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(VIEW + LIST_W + 34, VIEW + 124)
	panel.BackgroundColor3 = COLORS.Panel
	panel.BackgroundTransparency = 0.04
	panel.Visible = false
	panel.Parent = gui
	corner(panel, UDim.new(0, 20))
	local panelStroke = stroke(panel, Color3.new(1, 1, 1), 1)
	panelStroke.Transparency = 0.88
	UIScaler.attach(panel)
	panelScale = Instance.new("UIScale") -- Marco 10.8: abre com um "pulinho"
	panelScale.Parent = panel

	-- Marco 10.8: cabeçalho limpo (nome da cidade + dica pequena)
	text(panel, { Text = GameConfig.CityName, TextSize = 19, Font = Enum.Font.GothamBlack, Align = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(18, 10), Size = UDim2.new(1, -80, 0, 22) })
	text(panel, { Text = "Toque num lugar para marcar o destino  •  arraste e use a rodinha para o zoom", TextSize = 11, Font = Enum.Font.Gotham, Align = Enum.TextXAlignment.Left, Color = COLORS.Muted, Position = UDim2.fromOffset(18, 31), Size = UDim2.new(1, -80, 0, 14) })
	local close = Instance.new("TextButton")
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -12, 0, 10)
	close.Size = UDim2.fromOffset(32, 32)
	close.BackgroundColor3 = COLORS.Row
	close.Font = Enum.Font.GothamBold
	close.TextSize = 16
	close.TextColor3 = Color3.new(1, 1, 1)
	close.Text = "✕"
	close.Parent = panel
	corner(close, UDim.new(1, 0))
	close.Activated:Connect(function()
		MapController.toggle(false)
	end)

	viewport = Instance.new("Frame")
	viewport.Name = "Canvas"
	viewport.Position = UDim2.fromOffset(12, 52)
	viewport.Size = UDim2.fromOffset(VIEW, VIEW)
	viewport.BackgroundColor3 = COLORS.Grass
	viewport.ClipsDescendants = true
	viewport.Active = true
	viewport.Parent = panel
	corner(viewport, UDim.new(0, 14))

	world = Instance.new("Frame")
	world.Name = "World"
	world.BackgroundTransparency = 1
	world.Size = UDim2.fromOffset(BASE, BASE)
	world.Parent = viewport
	worldScale = Instance.new("UIScale")
	worldScale.Parent = world

	overlay = Instance.new("Frame")
	overlay.Name = "Overlay"
	overlay.BackgroundTransparency = 1
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.ZIndex = 5
	overlay.Parent = viewport

	drawWorld(map)
	collectPlaces(map)

	targetDot = Instance.new("Frame")
	targetDot.AnchorPoint = Vector2.new(0.5, 0.5)
	targetDot.Size = UDim2.fromOffset(16, 16)
	targetDot.BackgroundColor3 = COLORS.Target
	targetDot.ZIndex = 7
	targetDot.Visible = false
	targetDot.Parent = overlay
	corner(targetDot, UDim.new(1, 0))
	stroke(targetDot, Color3.new(1, 1, 1), 2)

	destPin = text(overlay, { Text = "📍", TextSize = 26, Anchor = Vector2.new(0.5, 0.9), Size = UDim2.fromOffset(30, 30), ZIndex = 9 })
	destPin.Visible = false

	-- sua casa
	local home = addPlace("Sua casa", "🏠", Vector3.zero, Color3.fromRGB(60, 190, 90))
	local function placeHome()
		local pos = player:GetAttribute("HomePosition")
		local ok = typeof(pos) == "Vector3"
		home.hidden = not ok
		if ok then
			home.pos = pos
			for _, item in ipairs(overlayItems) do
				if item.gui == home.pin or item.gui == home.label then
					item.pos = pos
				end
			end
		end
	end
	placeHome()
	player:GetAttributeChangedSignal("HomePosition"):Connect(function()
		placeHome()
		MapController.refresh()
	end)

	-- Marco 10.1: as outras casas do jogador (barraco, casas compradas): um pino para cada
	local MASC = { Sobrado = true, Apartamento = true, Barraco = true }
	local extras = {}
	for i = 1, 8 do
		local e = addPlace("Outra casa " .. i, "🏠", Vector3.zero, Color3.fromRGB(60, 190, 90))
		e.hidden = true
		extras[i] = e
	end
	local function placeExtras()
		local main = player:GetAttribute("HomePosition")
		local list = tostring(player:GetAttribute("HomePositions") or "")
		local used = 0
		for label, x, z in list:gmatch("([^:;]+):(%-?%d+):(%-?%d+)") do
			local pos = Vector3.new(tonumber(x), 0, tonumber(z))
			local isMain = typeof(main) == "Vector3" and (Vector3.new(main.X, 0, main.Z) - pos).Magnitude < 3
			if not isMain and used < #extras then
				used += 1
				local e = extras[used]
				e.hidden = false
				e.pos = pos
				e.name = (MASC[label] and "Seu " or "Sua ") .. label:lower()
				e.label.Text = e.name
				e.pin.Text = label == "Barraco" and "🏚️" or "🏠"
				for _, item in ipairs(overlayItems) do
					if item.gui == e.pin or item.gui == e.label then
						item.pos = pos
					end
				end
			end
		end
		for k = used + 1, #extras do
			extras[k].hidden = true
		end
	end
	placeExtras()
	player:GetAttributeChangedSignal("HomePositions"):Connect(function()
		placeExtras()
		MapController.refresh()
	end)

	buildPlayerMarker()

	-- bússola e botões de zoom (canto da janela)
	local north = text(viewport, { Text = "N", TextSize = 13, Font = Enum.Font.GothamBlack, Position = UDim2.fromOffset(10, 10), Size = UDim2.fromOffset(28, 28), ZIndex = 20 })
	north.BackgroundTransparency = 0.15
	north.BackgroundColor3 = COLORS.Panel
	corner(north, UDim.new(1, 0))
	smallButton(viewport, "+", UDim2.new(1, -8, 0, 8)).Activated:Connect(function()
		zoomAt(Vector2.new(VIEW / 2, VIEW / 2), 1.5)
	end)
	smallButton(viewport, "−", UDim2.new(1, -8, 0, 48)).Activated:Connect(function()
		zoomAt(Vector2.new(VIEW / 2, VIEW / 2), 1 / 1.5)
	end)
	smallButton(viewport, "◎", UDim2.new(1, -8, 0, 88), COLORS.Accent).Activated:Connect(centerOnPlayer)
	zoomLabel = text(viewport, { Text = "", TextSize = 10, Stroke = 0.5, Color = COLORS.Muted, Anchor = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 126), Size = UDim2.fromOffset(34, 14), ZIndex = 20 })

	-- barra de baixo: destino e botão de limpar
	-- Marco 10.8: cartão do destino
	destCard = Instance.new("Frame")
	destCard.Position = UDim2.fromOffset(12, VIEW + 62)
	destCard.Size = UDim2.new(1, -24, 0, 52)
	destCard.BackgroundColor3 = COLORS.Row
	destCard.Parent = panel
	corner(destCard, UDim.new(0, 14))
	destIcon = text(destCard, { Text = "📍", TextSize = 18, Anchor = Vector2.new(0, 0.5), Position = UDim2.new(0, 10, 0.5, 0), Size = UDim2.fromOffset(34, 34) })
	destIcon.BackgroundTransparency = 0
	destIcon.BackgroundColor3 = COLORS.Dest
	corner(destIcon, UDim.new(1, 0))
	destLabel = text(destCard, { Text = "", TextSize = 14, Font = Enum.Font.GothamBlack, Align = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(54, 8), Size = UDim2.new(1, -190, 0, 18) })
	destLabel.TextTruncate = Enum.TextTruncate.AtEnd
	destSub = text(destCard, { Text = "", TextSize = 11, Font = Enum.Font.Gotham, Align = Enum.TextXAlignment.Left, Color = COLORS.Muted, Position = UDim2.fromOffset(54, 27), Size = UDim2.new(1, -190, 0, 16) })
	destSub.TextTruncate = Enum.TextTruncate.AtEnd
	clearButton = Instance.new("TextButton")
	clearButton.AnchorPoint = Vector2.new(1, 0.5)
	clearButton.Position = UDim2.new(1, -10, 0.5, 0)
	clearButton.Size = UDim2.fromOffset(120, 34)
	clearButton.BackgroundColor3 = COLORS.Dest
	clearButton.Font = Enum.Font.GothamBold
	clearButton.TextSize = 13
	clearButton.TextColor3 = Color3.new(1, 1, 1)
	clearButton.Text = "Tirar destino"
	clearButton.Visible = false
	clearButton.Parent = destCard
	corner(clearButton, UDim.new(1, 0))
	clearButton.Activated:Connect(function()
		setDestination(nil, nil)
	end)

	buildList()
	buildInput()
	MapController.refresh()
end

function MapController.toggle(open)
	if not panel then
		return
	end
	if open == nil then
		open = not isOpen
	end
	isOpen = open
	panel.Visible = open
	if open and panelScale then
		panelScale.Scale = 0.94
		TweenService:Create(panelScale, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
	if open then
		drawRouteOnMap() -- Marco 9.9: caminho atualizado ao abrir
		MapController.refresh()
	end
end

-- Destino da etapa do emprego: placeName (o ícone do lugar fica laranja) e/ou worldPos
-- (bolinha laranja, usada nas entregas em casas). Passe nil para limpar.
function MapController.setTarget(placeName, worldPos)
	targetPlace = placeName
	targetPos = typeof(worldPos) == "Vector3" and worldPos or nil
	if panel then
		MapController.refresh()
	end
end

---------------------------------------------------------------------------
-- Botão do mapa (topo, no meio) e o chip de distância à esquerda dele
-- (à direita fica o botão da casinha)
---------------------------------------------------------------------------

local function drawMapIcon(parent)
	local holder = Instance.new("Frame")
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.5)
	holder.Size = UDim2.fromOffset(22, 18)
	holder.BackgroundTransparency = 1
	holder.Parent = parent
	local shades = { Color3.fromRGB(235, 235, 225), Color3.fromRGB(190, 215, 170), Color3.fromRGB(235, 235, 225) }
	for i = 1, 3 do
		local strip = Instance.new("Frame")
		strip.Size = UDim2.new(1 / 3, 0, 1, 0)
		strip.Position = UDim2.new((i - 1) / 3, 0, 0, i == 2 and 2 or 0)
		strip.BackgroundColor3 = shades[i]
		strip.BorderSizePixel = 0
		strip.Parent = holder
	end
	local pin = Instance.new("Frame")
	pin.AnchorPoint = Vector2.new(0.5, 0.5)
	pin.Position = UDim2.fromScale(0.5, 0.45)
	pin.Size = UDim2.fromOffset(8, 8)
	pin.BackgroundColor3 = Color3.fromRGB(240, 120, 30)
	pin.BorderSizePixel = 0
	pin.Parent = holder
	corner(pin, UDim.new(1, 0))
end

local function buildButton()
	local buttonGui = Instance.new("ScreenGui")
	buttonGui.Name = "MapButtonUI"
	buttonGui.ResetOnSpawn = false
	buttonGui.IgnoreGuiInset = true -- permite usar a faixa do topo
	buttonGui.DisplayOrder = 4
	buttonGui.Parent = player:WaitForChild("PlayerGui")

	local size = 40
	local topbar = GuiService:GetGuiInset().Y
	local top = math.max(4, (topbar - size) / 2)
	local button = Instance.new("ImageButton")
	button.Name = "MapButton"
	button.AnchorPoint = Vector2.new(0.5, 0)
	button.Position = UDim2.new(0.5, 0, 0, top)
	button.Size = UDim2.fromOffset(size, size)
	button.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	button.BackgroundTransparency = 0.35
	button.Image = ""
	button.Parent = buttonGui
	corner(button, UDim.new(1, 0))
	drawMapIcon(button)
	button.Activated:Connect(function()
		MapController.toggle()
	end)

	-- Marco 10.8: painel de navegação (embaixo dos botões do topo, no meio): seta grande que segue
	-- as ruas do GPS, a frase do que fazer e a distância
	chip = Instance.new("Frame")
	chip.Name = "Navegacao"
	chip.AnchorPoint = Vector2.new(0.5, 0)
	chip.Position = UDim2.new(0.5, 0, 0, top + size + 8)
	chip.Size = UDim2.fromOffset(230, 40) -- Marco 10.9: menor
	chip.BackgroundColor3 = COLORS.Panel
	chip.BackgroundTransparency = 0.12
	chip.Visible = false
	chip.Parent = buttonGui
	corner(chip, UDim.new(0, 20))
	local chipStroke = stroke(chip, Color3.new(1, 1, 1), 1)
	chipStroke.Transparency = 0.85
	chipBadge = Instance.new("Frame")
	chipBadge.AnchorPoint = Vector2.new(0, 0.5)
	chipBadge.Position = UDim2.new(0, 4, 0.5, 0)
	chipBadge.Size = UDim2.fromOffset(32, 32)
	chipBadge.BackgroundColor3 = COLORS.Dest
	chipBadge.Parent = chip
	corner(chipBadge, UDim.new(1, 0))
	-- Marco 10.9: setinha de verdade (ponta em V fechando na ponta + haste), dentro de um quadro que gira
	chipArrow = Instance.new("Frame")
	chipArrow.Name = "Seta"
	chipArrow.AnchorPoint = Vector2.new(0.5, 0.5)
	chipArrow.Position = UDim2.fromScale(0.5, 0.5)
	chipArrow.Size = UDim2.fromOffset(22, 22)
	chipArrow.BackgroundTransparency = 1
	chipArrow.Parent = chipBadge
	local function bar(px, py, w, h, rot)
		local f = Instance.new("Frame")
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Position = UDim2.fromOffset(px, py)
		f.Size = UDim2.fromOffset(w, h)
		f.Rotation = rot
		f.BackgroundColor3 = Color3.new(1, 1, 1)
		f.BorderSizePixel = 0
		f.Parent = chipArrow
		corner(f, UDim.new(1, 0))
	end
	-- ponta em (11, 3): cada traço tem 11 de comprimento e desce 45 graus para um lado
	bar(11, 12.5, 4, 16, 0) -- haste
	bar(7.4, 6.6, 4, 11, 45) -- traço da esquerda
	bar(14.6, 6.6, 4, 11, -45) -- traço da direita
	chipTitle = text(chip, { Text = "", TextSize = 14, Font = Enum.Font.GothamBlack, Align = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(46, 5), Size = UDim2.new(1, -56, 0, 16) })
	chipSub = text(chip, { Text = "", TextSize = 11, Font = Enum.Font.GothamMedium, Align = Enum.TextXAlignment.Left, Color = COLORS.Muted, Position = UDim2.fromOffset(46, 21), Size = UDim2.new(1, -56, 0, 13) })
	chipSub.TextTruncate = Enum.TextTruncate.AtEnd
	chipTitle.TextTruncate = Enum.TextTruncate.AtEnd
	RunService.RenderStepped:Connect(updateArrow)
end

---------------------------------------------------------------------------
-- Marco 10.12: minimapa (canto de cima à direita, embaixo dele ficam as barras de vida/stamina)
---------------------------------------------------------------------------

local MINI_SIZE = 150 -- px (o UIScaler encolhe no celular); igual StatusController.MAP_SIZE
local MINI_TOP = 6
local MINI_ZOOM_FOOT = 1.9 -- a pé: uns 400 studs de lado a lado
local MINI_ZOOM_CAR = 1.15 -- em veículo: vê mais longe
local TILE = 60 -- px do mapa (zoom 1) por quadradinho = 300 studs
local mini = {} -- partes do minimapa
local miniZoom = MINI_ZOOM_FOOT
local miniRot = 0
local arrivedUntil = 0

local function tileKey(x, y)
	return math.floor(x / TILE) .. ":" .. math.floor(y / TILE)
end

-- Copia o desenho do mapa grande em quadradinhos (só os de perto ficam visíveis)
local function buildMiniWorld()
	local skip = {}
	for _, f in ipairs(routeFrames) do
		skip[f] = true
	end
	mini.tiles = {}
	mini.always = Instance.new("Frame")
	mini.always.Name = "Grandes"
	mini.always.BackgroundTransparency = 1
	mini.always.Size = UDim2.fromScale(1, 1)
	mini.always.Parent = mini.world
	for _, child in ipairs(world:GetChildren()) do
		if child:IsA("GuiObject") and not skip[child] then
			local size = child.Size
			local big = math.max(size.X.Offset, size.Y.Offset) > TILE * 1.2
			local copy = child:Clone()
			if big then
				copy.Parent = mini.always
			else
				local pos = child.Position
				local key = tileKey(pos.X.Offset, pos.Y.Offset)
				local tile = mini.tiles[key]
				if not tile then
					tile = Instance.new("Frame")
					tile.Name = "Q" .. key
					tile.BackgroundTransparency = 1
					tile.Size = UDim2.fromScale(1, 1)
					tile.Visible = false
					tile.Parent = mini.world
					mini.tiles[key] = tile
				end
				copy.Parent = tile
			end
		end
	end
	mini.routeLayer = Instance.new("Frame")
	mini.routeLayer.Name = "Rota"
	mini.routeLayer.BackgroundTransparency = 1
	mini.routeLayer.Size = UDim2.fromScale(1, 1)
	mini.routeLayer.ZIndex = 6
	mini.routeLayer.Parent = mini.world
end

local function miniLine(a, b, width, color, z)
	local pa, pb = toMap(a), toMap(b)
	local delta = pb - pa
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	f.BackgroundColor3 = color
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Size = UDim2.fromOffset(delta.Magnitude + width, width)
	f.Position = UDim2.fromOffset((pa.X + pb.X) / 2, (pa.Y + pb.Y) / 2)
	f.Rotation = math.deg(math.atan2(delta.Y, delta.X))
	f.ZIndex = z
	f.Parent = mini.routeLayer
	corner(f, UDim.new(1, 0))
end

drawMiniRoute = function()
	if not mini.routeLayer then
		return
	end
	mini.routeLayer:ClearAllChildren()
	if not route or not route.points then
		return
	end
	local pts = route.points
	for i = 1, #pts - 1 do
		miniLine(pts[i], pts[i + 1], 3.2, Color3.new(1, 1, 1), 6)
		miniLine(pts[i], pts[i + 1], 2, route.color, 7)
	end
end

local function blip(name, size, color, z, text)
	local b = Instance.new("Frame")
	b.Name = name
	b.AnchorPoint = Vector2.new(0.5, 0.5)
	b.Size = UDim2.fromOffset(size, size)
	b.BackgroundColor3 = color
	b.BorderSizePixel = 0
	b.ZIndex = z or 10
	b.Visible = false
	b.Parent = mini.blips
	corner(b, UDim.new(1, 0))
	local st = stroke(b, Color3.new(0, 0, 0), 1.5)
	st.Transparency = 0.3
	if text then
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.Size = UDim2.fromScale(1, 1)
		t.Font = Enum.Font.GothamBlack
		t.TextSize = size - 5
		t.TextColor3 = Color3.new(1, 1, 1)
		t.Text = text
		t.ZIndex = b.ZIndex + 1
		t.Parent = b
	end
	return b
end

local function buildMini(map)
	local miniGui = Instance.new("ScreenGui")
	miniGui.Name = "MiniMapUI"
	miniGui.ResetOnSpawn = false
	miniGui.DisplayOrder = 3
	-- Marco 10.14: usa a faixa do topo (o canto direito dela é livre), só fugindo do entalhe da tela
	miniGui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	miniGui.Parent = player:WaitForChild("PlayerGui")

	local button = Instance.new("TextButton")
	button.Name = "MiniMapa"
	button.AnchorPoint = Vector2.new(1, 0)
	button.Size = UDim2.fromOffset(MINI_SIZE, MINI_SIZE)
	button.BackgroundTransparency = 1
	button.Text = ""
	button.AutoButtonColor = false
	button.Parent = miniGui
	UIScaler.attach(button)
	UIScaler.onChanged(function(sc)
		button.Position = UDim2.new(1, -6, 0, MINI_TOP * sc)
	end)
	button.Activated:Connect(function()
		MapController.toggle(true)
	end)
	mini.button = button

	-- Marco 10.12 (teste do Luís): o CanvasGroup não cortou o desenho em alguns PCs e o mapa vazava
	-- pela tela; um Frame com ClipsDescendants corta sempre (ele mesmo não gira, só o de dentro)
	local canvas = Instance.new("Frame")
	canvas.Name = "Tela"
	canvas.Size = UDim2.fromScale(1, 1)
	canvas.BackgroundColor3 = COLORS.Grass
	canvas.BorderSizePixel = 0
	canvas.ClipsDescendants = true
	canvas.Parent = button
	mini.canvas = canvas

	local rot = Instance.new("Frame")
	rot.Name = "Gira"
	rot.AnchorPoint = Vector2.new(0.5, 0.5)
	rot.Position = UDim2.fromScale(0.5, 0.5)
	rot.Size = UDim2.fromOffset(0, 0)
	rot.BackgroundTransparency = 1
	rot.Parent = canvas
	mini.rot = rot

	local w = Instance.new("Frame")
	w.Name = "Mundo"
	w.BackgroundTransparency = 1
	w.Size = UDim2.fromOffset(BASE, BASE)
	w.Parent = rot
	mini.world = w
	mini.scale = Instance.new("UIScale")
	mini.scale.Scale = miniZoom
	mini.scale.Parent = w
	buildMiniWorld()

	-- bolinhas (destino, emprego, jogadores, N) ficam por cima, sem girar
	local blips = Instance.new("Frame")
	blips.Name = "Pontos"
	blips.BackgroundTransparency = 1
	blips.Size = UDim2.fromScale(1, 1)
	blips.ZIndex = 9
	blips.Parent = canvas
	mini.blips = blips
	mini.dest = blip("Destino", 12, COLORS.Dest, 11)
	mini.target = blip("Trabalho", 12, COLORS.Target, 11)
	mini.north = blip("Norte", 16, Color3.fromRGB(30, 34, 44), 12, "N")
	mini.others = {}

	-- você: setinha branca no meio
	local me = Instance.new("Frame")
	me.Name = "Voce"
	me.AnchorPoint = Vector2.new(0.5, 0.5)
	me.Position = UDim2.fromScale(0.5, 0.5)
	me.Size = UDim2.fromOffset(16, 16)
	me.BackgroundTransparency = 1
	me.ZIndex = 13
	me.Parent = canvas
	local function bar(px, py, wd, h, r)
		local f = Instance.new("Frame")
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Position = UDim2.fromOffset(px, py)
		f.Size = UDim2.fromOffset(wd, h)
		f.Rotation = r
		f.BackgroundColor3 = Color3.new(1, 1, 1)
		f.BorderSizePixel = 0
		f.ZIndex = 13
		f.Parent = me
		corner(f, UDim.new(1, 0))
		local st = stroke(f, Color3.new(0, 0, 0), 1)
		st.Transparency = 0.4
	end
	bar(5, 8, 3.5, 13, 28)
	bar(11, 8, 3.5, 13, -28)
	mini.me = me

	-- borda e textinho de distância embaixo
	local border = Instance.new("Frame")
	border.Size = UDim2.fromScale(1, 1)
	border.BackgroundTransparency = 1
	border.ZIndex = 14
	border.Parent = button
	local bs = stroke(border, Color3.new(0, 0, 0), 2)
	bs.Transparency = 0.35
	mini.info = text(button, { Text = "", TextSize = 11, Font = Enum.Font.GothamBold, Anchor = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -4), Size = UDim2.new(1, -12, 0, 14), Stroke = 0.4, ZIndex = 15 })
	mini.info.TextTruncate = Enum.TextTruncate.AtEnd
	drawMiniRoute()
end

-- posição de um ponto do mundo no minimapa (px, a partir do centro, já girado)
local function miniOffset(pos, here)
	local d = (toMap(pos) - here) * miniZoom
	local r = math.rad(miniRot)
	local c, sn = math.cos(r), math.sin(r)
	return Vector2.new(d.X * c - d.Y * sn, d.X * sn + d.Y * c)
end

local function placeBlip(b, v, clampEdge)
	local half = MINI_SIZE / 2 - 9
	if math.abs(v.X) > half or math.abs(v.Y) > half then
		if not clampEdge then
			b.Visible = false
			return
		end
		local k = half / math.max(math.abs(v.X), math.abs(v.Y))
		v = v * k
	end
	b.Position = UDim2.new(0.5, v.X, 0.5, v.Y)
	b.Visible = true
end

local lastTiles = 0
local function updateMini(dt)
	if not mini.world then
		return
	end
	local root = rootPart()
	local camera = Workspace.CurrentCamera
	if not root or not camera then
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local inVehicle = humanoid and humanoid.SeatPart ~= nil
	local wantZoom = inVehicle and MINI_ZOOM_CAR or MINI_ZOOM_FOOT
	miniZoom += (wantZoom - miniZoom) * math.min(1, dt * 3)
	mini.scale.Scale = miniZoom
	-- gira: para cima = para onde a câmera olha
	local look = camera.CFrame.LookVector
	if Vector2.new(look.X, look.Z).Magnitude > 0.01 then
		miniRot = -90 - math.deg(math.atan2(look.Z, look.X))
	end
	mini.rot.Rotation = miniRot
	local here = toMap(root.Position)
	mini.world.Position = UDim2.fromOffset(-here.X * miniZoom, -here.Y * miniZoom)
	local face = root.CFrame.LookVector
	mini.me.Rotation = math.deg(math.atan2(face.Z, face.X)) + miniRot + 90
	-- quadradinhos perto (10 vezes por segundo basta)
	local now = os.clock()
	if now - lastTiles > 0.1 then
		lastTiles = now
		local reach = (MINI_SIZE * 0.75) / miniZoom + TILE * 0.5
		local tx, ty = math.floor(here.X / TILE), math.floor(here.Y / TILE)
		local n = math.ceil(reach / TILE)
		local show = {}
		for x = tx - n, tx + n do
			for y = ty - n, ty + n do
				show[x .. ":" .. y] = true
			end
		end
		for key, tile in pairs(mini.tiles) do
			local v = show[key] == true
			if tile.Visible ~= v then
				tile.Visible = v
			end
		end
	end
	-- destino escolhido e do emprego (presos na borda quando estão longe)
	if dest then
		placeBlip(mini.dest, miniOffset(dest.pos, here), true)
	else
		mini.dest.Visible = false
	end
	local tpos = targetPos
	if not tpos and targetPlace and pinsByName[targetPlace] then
		tpos = pinsByName[targetPlace].pos
	end
	if tpos then
		placeBlip(mini.target, miniOffset(tpos, here), true)
	else
		mini.target.Visible = false
	end
	-- norte (sempre na borda)
	local northDir = Vector2.new(0, -1)
	local r = math.rad(miniRot)
	local nv = Vector2.new(northDir.X * math.cos(r) - northDir.Y * math.sin(r), northDir.X * math.sin(r) + northDir.Y * math.cos(r)) * MINI_SIZE
	placeBlip(mini.north, nv, true)
	-- outros jogadores (só dentro do minimapa)
	local seen = {}
	for _, other in ipairs(Players:GetPlayers()) do
		local r2 = other ~= player and other.Character and other.Character:FindFirstChild("HumanoidRootPart")
		if r2 then
			local b = mini.others[other]
			if not b then
				b = blip("J_" .. other.Name, 8, Color3.fromRGB(255, 210, 60), 10)
				mini.others[other] = b
			end
			local tracked = (other:GetAttribute("RastreadorJoias") == true or other:GetAttribute("RastreadorBanco") == true) and player:GetAttribute("Job") == "Policial"
			tracked = tracked or (other:GetAttribute("Caido") == true and player:GetAttribute("Job") == "Paramedico")
			if tracked then
				b.BackgroundColor3 = (math.floor(os.clock() * 3) % 2 == 0) and Color3.fromRGB(255, 40, 40) or Color3.fromRGB(255, 200, 200)
			else
				b.BackgroundColor3 = Color3.fromRGB(255, 210, 60)
			end
			placeBlip(b, miniOffset(r2.Position, here), tracked)
			seen[other] = true
		end
	end
	for other, b in pairs(mini.others) do
		if not seen[other] then
			b:Destroy()
			mini.others[other] = nil
		end
	end
	-- distância embaixo
	local flat = Vector3.new(root.Position.X, 0, root.Position.Z)
	if now < arrivedUntil then
		mini.info.Text = "✅ Você chegou!"
	elseif dest then
		mini.info.Text = "📍 " .. meters((flat - dest.pos).Magnitude)
	elseif tpos then
		mini.info.Text = "💼 " .. meters((flat - Vector3.new(tpos.X, 0, tpos.Z)).Magnitude)
	else
		mini.info.Text = ""
	end
end

-- chegou no destino escolhido: limpa (antes quem fazia isso era o painel da seta)
local function checkArrival()
	local root = rootPart()
	if dest and root then
		local flat = Vector3.new(root.Position.X, 0, root.Position.Z)
		if (flat - dest.pos).Magnitude < ARRIVE then
			dest = nil
			arrivedUntil = os.clock() + 3
			refreshRows()
			if panel then
				MapController.refresh()
			end
		end
	end
end

function MapController.init()
	task.spawn(function()
		local map = Workspace:WaitForChild("Map")
		task.wait(1) -- dá tempo das peças do mapa chegarem ao cliente
		-- Marco 10.22: espera o servidor anotar o mapa (streaming); no máximo 20 s
		local t0 = os.clock()
		while not map:GetAttribute("MapaPronto") and os.clock() - t0 < 20 do
			task.wait(0.25)
		end
		build(map)
		buildMini(map) -- Marco 10.12: minimapa no lugar do botão do mapa e da seta do GPS
		RunService.RenderStepped:Connect(function(dt)
			local ok, err = pcall(updateMini, dt)
			if not ok then
				warn("[MapController] minimapa: " .. tostring(err))
			end
		end)

		UserInputService.InputBegan:Connect(function(input, processed)
			if not processed and input.KeyCode == Enum.KeyCode.M then
				MapController.toggle()
			end
		end)

		local n = 0
		while true do
			if isOpen then
				updateDynamic()
			end
			n += 1
			if n % 5 == 0 then
				checkArrival()
				updateChip()
				local ok, err = pcall(updateRoute) -- Marco 9.9: GPS
				if not ok then
					warn("[MapController] GPS: " .. tostring(err))
				end
			end
			task.wait(0.1)
		end
	end)
end

return MapController
