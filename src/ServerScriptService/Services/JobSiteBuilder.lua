-- JobSiteBuilder (ModuleScript)
-- Caminho: ServerScriptService > Services > JobSiteBuilder
-- Monta os lugares de trabalho do Marco 4, separados do mapa (pasta Workspace > JobStations):
--   * quadro de empregos na praça;
--   * interior decorado de cada loja, com as estações de trabalho (bancada, forno, prateleiras, caixa...);
--   * pontos de entrega na porta de cada casa (Entregador Sherlex).
-- Cada estação tem um ProximityPrompt DESLIGADO no servidor; o cliente liga só a
-- estação da etapa atual de quem está trabalhando. Quem valida tudo é o MissionService.
-- As lojas são ocas (MapBuilder); aqui entram os móveis, a decoração e as estações de dentro.

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local JobConfig = require(Shared:WaitForChild("JobConfig"))
local PizzaArt = require(Shared:WaitForChild("PizzaArt"))

local JobSiteBuilder = {}

local WOOD = Color3.fromRGB(150, 105, 65)
local STEEL = Color3.fromRGB(185, 190, 195)
local CARDBOARD = Color3.fromRGB(200, 160, 110)
local DARK = Color3.fromRGB(45, 45, 50)

-- points[nome] = { part, prompt, visual, job, station }
-- groups[job][station] = lista de nomes de pontos (ex.: 3 prateleiras)
JobSiteBuilder.points = {}
JobSiteBuilder.groups = {}
JobSiteBuilder.houses = {} -- pontos de entrega nas casas: { point = nome, address = "Rua das Flores, 12" }
JobSiteBuilder.market = nil -- dados do Minas Market para o MarketService (caixas, porta, prateleiras)
JobSiteBuilder.board = nil -- peça do quadro de empregos
-- Lugares dos NPCs em cada loja (Marco 5): shops[jobId] = { base, door = {fora, dentro}, staff, customers }
-- staff = onde o funcionário NPC fica atrás do balcão; customers = onde o cliente NPC espera
JobSiteBuilder.shops = {}

-- Posições na planta de cada loja (x, z no chão da loja; -Z é o lado da porta)
local SHOP_SPOTS = {
	Pizzaiolo = { staff = { -12.5, -6.6 }, customers = { { -14.5, -12 }, { -10.5, -12 } } },
	Atendente = { staff = { 8, -7.4 } },
	Entregador = { staff = { 0, -0.6 } },
	PetShop = { staff = { 13, -6.6 } },
}

local function part(parent, props)
	local p = Instance.new(props.ClassName or "Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = props.Material or Enum.Material.SmoothPlastic
	p.Color = props.Color or Color3.new(1, 1, 1)
	p.Size = props.Size
	p.CFrame = props.CFrame
	p.Name = props.Name or "Part"
	if props.Shape then
		p.Shape = props.Shape
	end
	if props.Transparency then
		p.Transparency = props.Transparency
	end
	if props.CanCollide ~= nil then
		p.CanCollide = props.CanCollide
	end
	p.Parent = parent
	return p
end

local function signText(target, text, color)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	gui.Parent = target
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextColor3 = color or DARK
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.Text = text
	label.Parent = gui
	return label
end

local function addPrompt(target, objectText)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "JobPrompt"
	prompt.ObjectText = objectText
	prompt.ActionText = "Usar"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.MaxActivationDistance = 8
	prompt.RequiresLineOfSight = false
	prompt.Enabled = false -- o cliente liga só para quem está nesta etapa
	prompt.Parent = target
	return prompt
end

local function register(name, jobId, station, target, visual, objectText, reach)
	local prompt = addPrompt(target, objectText)
	if reach then
		prompt.MaxActivationDistance = reach -- estações coladas (ex.: potes de ingredientes)
	end
	local visualRef = Instance.new("ObjectValue")
	visualRef.Name = "Visual"
	visualRef.Value = visual
	visualRef.Parent = target
	JobSiteBuilder.points[name] = { part = target, prompt = prompt, visual = visual, job = jobId, station = station }
	local byJob = JobSiteBuilder.groups[jobId] or {}
	JobSiteBuilder.groups[jobId] = byJob
	byJob[station] = byJob[station] or {}
	table.insert(byJob[station], name)
	target.Name = name
	return prompt
end

-- Balcão fechado (caixa sólida com tampo colorido). Devolve o corpo.
local function counter(m, cf, size, bodyColor, topColor)
	local body = part(m, { Name = "Body", Size = Vector3.new(size.X, size.Y - 0.3, size.Z), CFrame = cf * CFrame.new(0, (size.Y - 0.3) / 2, 0), Color = bodyColor })
	part(m, { Name = "Top", Size = Vector3.new(size.X + 0.2, 0.3, size.Z + 0.2), CFrame = cf * CFrame.new(0, size.Y - 0.15, 0), Color = topColor })
	return body
end

local function crate(m, cf, s)
	return part(m, { Name = "Box", Size = Vector3.new(s, s, s), CFrame = cf, Color = CARDBOARD, Material = Enum.Material.Cardboard })
end

---------------------------------------------------------------------------
-- Móveis de decoração (sem interação)
---------------------------------------------------------------------------

local function model(name, parent)
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end

-- Piso quadriculado sobre o chão da loja (não colide, só visual)
local function tiles(parent, base, w, d, size, c1, c2)
	local f = model("Piso", parent)
	local nx, nz = math.floor(w / size), math.floor(d / size)
	for i = 0, nx - 1 do
		for k = 0, nz - 1 do
			local p = part(f, {
				Name = "Tile",
				Size = Vector3.new(size, 0.05, size),
				CFrame = base * CFrame.new(-w / 2 + size / 2 + i * size, 0.03, -d / 2 + size / 2 + k * size),
				Color = ((i + k) % 2 == 0) and c1 or c2,
				CanCollide = false,
			})
			p.CanQuery = false
			p.CastShadow = false
		end
	end
end

local function stool(parent, cf, color)
	-- Assento de verdade (o jogador fica virado para o -Z do cf). Senta apertando E (SeatService).
	local m = model("Banco", parent)
	part(m, { ClassName = "Seat", Name = "Seat", Size = Vector3.new(1.6, 0.3, 1.6), CFrame = cf * CFrame.new(0, 2, 0), Color = color })
	part(m, { Name = "Cushion", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.35, 1.8, 1.8), CFrame = cf * CFrame.new(0, 2.05, 0) * CFrame.Angles(0, 0, math.rad(90)), Color = color, CanCollide = false })
	part(m, { Name = "Leg", Size = Vector3.new(0.3, 1.9, 0.3), CFrame = cf * CFrame.new(0, 0.95, 0), Color = DARK, Material = Enum.Material.Metal })
end

local function diningTable(parent, cf, topColor, seatColor)
	local m = model("MesaCliente", parent)
	part(m, { Name = "Top", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 3.4, 3.4), CFrame = cf * CFrame.new(0, 3, 0) * CFrame.Angles(0, 0, math.rad(90)), Color = topColor })
	part(m, { Name = "Leg", Size = Vector3.new(0.4, 2.85, 0.4), CFrame = cf * CFrame.new(0, 1.43, 0), Color = DARK, Material = Enum.Material.Metal })
	for _, x in ipairs({ -2.4, 2.4 }) do
		-- cada banco olha para a mesa
		stool(parent, cf * CFrame.new(x, 0, 0) * CFrame.Angles(0, x < 0 and -math.pi / 2 or math.pi / 2, 0), seatColor)
	end
end

local function plant(parent, cf)
	local m = model("Planta", parent)
	part(m, { Name = "Pot", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.6, 1.6, 1.6), CFrame = cf * CFrame.new(0, 0.8, 0) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(170, 90, 60), Material = Enum.Material.Slate })
	part(m, { Name = "Leaves", Shape = Enum.PartType.Ball, Size = Vector3.new(2.4, 2.8, 2.4), CFrame = cf * CFrame.new(0, 2.8, 0), Color = Color3.fromRGB(70, 150, 60), Material = Enum.Material.Grass, CanCollide = false })
end

-- Prateleira de parede com objetos coloridos (potes, latas, pacotes)
local function wallShelf(parent, cf, width, colors, levels)
	local m = model("PrateleiraParede", parent)
	for level = 0, (levels or 2) - 1 do
		local shelfCf = cf * CFrame.new(0, 4.5 + level * 2, 0)
		part(m, { Name = "Board", Size = Vector3.new(width, 0.2, 1.2), CFrame = shelfCf, Color = WOOD, Material = Enum.Material.Wood })
		local n = math.floor(width / 1.1)
		for k = 0, n - 1 do
			part(m, {
				Name = "Item",
				Size = Vector3.new(0.7, 0.9, 0.7),
				CFrame = shelfCf * CFrame.new(-width / 2 + 0.6 + k * 1.1, 0.55, 0),
				Color = colors[((k + level) % #colors) + 1],
				CanCollide = false,
			})
		end
	end
end

local function wallSign(parent, cf, size, text, textColor, bgColor)
	local p = part(parent, { Name = "Quadro", Size = size, CFrame = cf, Color = bgColor })
	signText(p, text, textColor)
	return p
end

-- Etiqueta do pote: desenho do ingrediente + nome
local function ingredientLabel(target, ing)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.LightInfluence = 0
	gui.Parent = target
	local icon = Instance.new("Frame")
	icon.BackgroundTransparency = 1
	icon.Position = UDim2.fromScale(0.02, 0.05)
	icon.Size = UDim2.fromScale(0.36, 0.9)
	icon.Parent = gui
	PizzaArt.ingredient(icon, ing.id)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Position = UDim2.fromScale(0.38, 0)
	label.Size = UDim2.fromScale(0.6, 1)
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = DARK
	label.Text = ing.label
	label.Parent = gui
end

-- Cardápio da parede: um desenho de cada pizza, com o nome e o preço embaixo
local function menuBoard(parent, cf, size)
	local board = part(parent, { Name = "Cardapio", Size = size, CFrame = cf, Color = Color3.fromRGB(40, 35, 30) })
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	gui.Parent = board
	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.fromScale(1, 0.17)
	title.Position = UDim2.fromScale(0, 0.02)
	title.Font = Enum.Font.GothamBlack
	title.TextScaled = true
	title.TextColor3 = Color3.fromRGB(255, 220, 120)
	title.Text = "CARDÁPIO"
	title.Parent = gui
	local n = #JobConfig.Flavors
	for i, flavor in ipairs(JobConfig.Flavors) do
		local col = Instance.new("Frame")
		col.BackgroundTransparency = 1
		col.Position = UDim2.fromScale((i - 1) / n, 0.2)
		col.Size = UDim2.fromScale(1 / n, 0.8)
		col.Parent = gui
		local art = Instance.new("Frame")
		art.BackgroundTransparency = 1
		art.Position = UDim2.fromScale(0.1, 0)
		art.Size = UDim2.fromScale(0.8, 0.72)
		art.Parent = col
		PizzaArt.pizza(art, flavor.ingredients)
		local name = Instance.new("TextLabel")
		name.BackgroundTransparency = 1
		name.Position = UDim2.fromScale(0, 0.74)
		name.Size = UDim2.fromScale(1, 0.2)
		name.Font = Enum.Font.GothamBold
		name.TextScaled = true
		name.TextColor3 = Color3.new(1, 1, 1)
		name.Text = flavor.label
		name.Parent = col
	end
	return board
end

---------------------------------------------------------------------------
-- Interior de cada loja. base = chão de dentro, olhando para a rua (-Z).
-- Dentro: x de -21 a 21, z de -17 (vitrine/porta) a 17 (fundo).
-- O corredor da porta (x entre -4 e 4, perto da frente) fica livre.
---------------------------------------------------------------------------

local function buildPizzaria(folder, base)
	local job = "Pizzaiolo"
	local function at(x, z)
		return base * CFrame.new(x, 0, z)
	end
	local RED = Color3.fromRGB(200, 50, 45)
	local CREAM = Color3.fromRGB(245, 235, 215)
	local decor = model("Decoracao", folder)
	tiles(decor, base, 42, 34, 3.5, Color3.fromRGB(240, 240, 235), Color3.fromRGB(190, 60, 55))

	-- Fundo da cozinha: massas, mesa de montagem, forno, lixo e caixas de pizza
	local m = model("Massa", folder)
	local body = counter(m, at(-17, 14.5), Vector3.new(5, 3.4, 3), CREAM, WOOD)
	part(m, { Name = "Tray", Size = Vector3.new(4, 0.3, 2.4), CFrame = body.CFrame * CFrame.new(0, 1.85, 0), Color = STEEL, Material = Enum.Material.Metal })
	for i = 0, 5 do
		part(m, { Name = "Dough", Shape = Enum.PartType.Ball, Size = Vector3.new(0.9, 0.9, 0.9), CFrame = body.CFrame * CFrame.new(-1.4 + (i % 3) * 1.4, 2.3, -0.5 + math.floor(i / 3) * 1), Color = Color3.fromRGB(245, 230, 200) })
	end
	register("Pizzaiolo_Massa_1", job, "Massa", body, m, "Massas")

	m = model("MesaMontagem", folder)
	body = counter(m, at(-10.5, 14.5), Vector3.new(6, 3.4, 3), STEEL, STEEL)
	part(m, { Name = "Board", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.15, 2.4, 2.4), CFrame = body.CFrame * CFrame.new(0, 1.93, 0) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(190, 140, 90), Material = Enum.Material.Wood })
	part(m, { Name = "RollingPin", Shape = Enum.PartType.Cylinder, Size = Vector3.new(2, 0.4, 0.4), CFrame = body.CFrame * CFrame.new(2.2, 2.05, 0) * CFrame.Angles(0, math.rad(90), 0), Color = WOOD })
	register("Pizzaiolo_MesaMontagem_1", job, "MesaMontagem", body, m, "Mesa de montagem")

	m = model("Forno", folder)
	local oven = part(m, { Name = "Oven", Size = Vector3.new(7, 5, 5), CFrame = at(1, 14) * CFrame.new(0, 2.5, 0), Color = Color3.fromRGB(170, 85, 60), Material = Enum.Material.Brick })
	part(m, { Name = "Dome", Shape = Enum.PartType.Ball, Size = Vector3.new(6.6, 3.4, 4.6), CFrame = oven.CFrame * CFrame.new(0, 2.5, 0), Color = Color3.fromRGB(170, 85, 60), Material = Enum.Material.Brick })
	part(m, { Name = "Mouth", Size = Vector3.new(3.2, 2, 0.2), CFrame = oven.CFrame * CFrame.new(0, 0.6, -2.5), Color = Color3.fromRGB(25, 20, 20) })
	local fire = part(m, { Name = "Fire", Size = Vector3.new(2.6, 0.5, 0.2), CFrame = oven.CFrame * CFrame.new(0, -0.1, -2.45), Color = Color3.fromRGB(255, 140, 40), Material = Enum.Material.Neon, CanCollide = false })
	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(255, 150, 60)
	glow.Range = 8
	glow.Brightness = 1.5
	glow.Parent = fire
	part(m, { Name = "Chimney", Size = Vector3.new(1.2, 8, 1.2), CFrame = oven.CFrame * CFrame.new(2, 6.5, 1.5), Color = DARK, Material = Enum.Material.Metal })
	register("Pizzaiolo_Forno_1", job, "Forno", oven, m, "Forno a lenha")

	m = model("Lixo", folder)
	local bin = part(m, { Name = "Bin", Shape = Enum.PartType.Cylinder, Size = Vector3.new(3, 2.2, 2.2), CFrame = at(7, 15) * CFrame.new(0, 1.5, 0) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(70, 80, 75), Material = Enum.Material.Metal })
	part(m, { Name = "Lid", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 2.4, 2.4), CFrame = at(7, 15) * CFrame.new(0, 3.1, 0) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(50, 55, 50), Material = Enum.Material.Metal })
	register("Pizzaiolo_Lixo_1", job, "Lixo", bin, m, "Lixo")

	m = model("Embalagem", folder)
	body = counter(m, at(12.5, 14.5), Vector3.new(6, 3.4, 3), CREAM, RED)
	for i = 0, 5 do
		part(m, { Name = "PizzaBox", Size = Vector3.new(2.4, 0.4, 2.4), CFrame = body.CFrame * CFrame.new(-1.4, 1.95 + i * 0.42, 0) * CFrame.Angles(0, 0.05 * i, 0), Color = Color3.fromRGB(245, 240, 230) })
	end
	part(m, { Name = "OpenBox", Size = Vector3.new(2.4, 0.15, 2.4), CFrame = body.CFrame * CFrame.new(1.5, 1.8, 0), Color = Color3.fromRGB(245, 240, 230) })
	register("Pizzaiolo_Embalagem_1", job, "Embalagem", body, m, "Caixas de pizza")
	part(decor, { Name = "Wood", Size = Vector3.new(2.5, 1.2, 1.2), CFrame = at(18, 15) * CFrame.new(0, 0.6, 0), Color = Color3.fromRGB(120, 80, 45), Material = Enum.Material.Wood })

	-- Bancada de ingredientes: grupo BASE (molho e queijo, vão em todas) e grupo COBERTURAS.
	-- Cada pote tem uma etiqueta com o desenho do ingrediente e o nome.
	local island = model("BancadaIngredientes", decor)
	local spacing = 3
	local xs, x = {}, -18
	local lastBase
	for i, ing in ipairs(JobConfig.Ingredients) do
		if lastBase and not ing.base then
			x += 1.5 -- espaço entre os dois grupos
			lastBase = nil
		end
		xs[i] = x
		if ing.base then
			lastBase = true
		end
		x += spacing
	end
	local left, right = xs[1] - 1.8, xs[#xs] + 1.8
	local islandCf = at((left + right) / 2, 6)
	counter(island, islandCf, Vector3.new(right - left, 3.4, 3), CREAM, STEEL)
	local baseEnd, topStart
	for i, ing in ipairs(JobConfig.Ingredients) do
		local px = xs[i] - (left + right) / 2
		local pm = model("Ing_" .. ing.id, folder)
		local pot = part(pm, { Name = "Pot", Size = Vector3.new(2.2, 0.8, 2.2), CFrame = islandCf * CFrame.new(px, 3.8, 0), Color = STEEL, Material = Enum.Material.Metal })
		part(pm, { Name = "Content", Size = Vector3.new(1.9, 0.2, 1.9), CFrame = islandCf * CFrame.new(px, 4.25, 0), Color = ing.color, CanCollide = false })
		local label = part(pm, { Name = "Label", Size = Vector3.new(2.8, 1.3, 0.1), CFrame = islandCf * CFrame.new(px, 2.3, -1.56), Color = Color3.new(1, 1, 1) })
		ingredientLabel(label, ing)
		register("Pizzaiolo_Ing_" .. ing.id .. "_1", job, "Ing_" .. ing.id, pot, pm, ing.label, 4)
		if ing.base then
			baseEnd = px
		elseif not topStart then
			topStart = px
		end
	end
	-- Plaquinhas dos grupos, atrás dos potes
	local baseStart = xs[1] - (left + right) / 2
	local topEnd = xs[#xs] - (left + right) / 2
	local groupSign = part(island, { Name = "Grupo", Size = Vector3.new(baseEnd - baseStart + 2.4, 0.9, 0.15), CFrame = islandCf * CFrame.new((baseStart + baseEnd) / 2, 5.2, 1.2), Color = RED })
	signText(groupSign, "BASE (vai em todas)", Color3.new(1, 1, 1))
	groupSign = part(island, { Name = "Grupo", Size = Vector3.new(topEnd - topStart + 2.4, 0.9, 0.15), CFrame = islandCf * CFrame.new((topStart + topEnd) / 2, 5.2, 1.2), Color = Color3.fromRGB(60, 120, 60) })
	signText(groupSign, "COBERTURAS (veja a comanda)", Color3.new(1, 1, 1))

	-- Balcão de retirada (pedido e entrega) perto da porta
	m = model("BalcaoPizza", folder)
	body = counter(m, at(-12.5, -9), Vector3.new(9, 3.6, 2.5), CREAM, RED)
	local tag = part(m, { Name = "Tag", Size = Vector3.new(4, 0.9, 0.1), CFrame = body.CFrame * CFrame.new(0, 0.6, -1.3), Color = Color3.new(1, 1, 1) })
	signText(tag, "PEDIDOS", RED)
	part(m, { Name = "Register", Size = Vector3.new(1.4, 0.9, 1.2), CFrame = body.CFrame * CFrame.new(3, 2.3, 0.3), Color = DARK })
	part(m, { Name = "Ticket", Size = Vector3.new(0.8, 1.1, 0.05), CFrame = body.CFrame * CFrame.new(-2.5, 2.4, 0.4) * CFrame.Angles(math.rad(-15), 0, 0), Color = Color3.new(1, 1, 1) })
	register("Pizzaiolo_BalcaoPizza_1", job, "BalcaoPizza", body, m, "Balcão de pedidos")

	-- Salão: mesas com bancos de sentar, cardápio, prateleiras e plantas
	for _, pos in ipairs({ { 9, -12 }, { 16, -12 }, { 9, -4 }, { 16, -4 } }) do
		diningTable(decor, at(pos[1], pos[2]), CREAM, RED)
	end
	menuBoard(decor, base * CFrame.new(-7, 10.5, 16.9), Vector3.new(16, 6.5, 0.2))
	wallShelf(decor, base * CFrame.new(20.3, 1.5, 6) * CFrame.Angles(0, math.pi / 2, 0), 8, { Color3.fromRGB(110, 60, 40), Color3.fromRGB(230, 200, 120), RED }, 2)
	wallShelf(decor, base * CFrame.new(-20.3, 1.5, -2) * CFrame.Angles(0, -math.pi / 2, 0), 10, { Color3.fromRGB(80, 150, 60), Color3.fromRGB(245, 235, 215) }, 2)
	plant(decor, at(-19, -15))
	plant(decor, at(19, -15))
	plant(decor, at(19, 9))
end

local function buildMarket(folder, base)
	local job = "Atendente"
	local function at(x, z)
		return base * CFrame.new(x, 0, z)
	end
	local GREEN = Color3.fromRGB(40, 140, 70)
	local LIGHT = Color3.fromRGB(235, 240, 220)
	local decor = model("Decoracao", folder)
	tiles(decor, base, 42, 34, 4, Color3.fromRGB(235, 235, 230), Color3.fromRGB(215, 225, 215))

	-- Estoque no fundo: uma pilha de caixas de cada tipo, com etiqueta
	part(decor, { Name = "Pallet", Size = Vector3.new(12, 0.5, 4), CFrame = at(14.7, 14) * CFrame.new(0, 0.25, 0), Color = WOOD, Material = Enum.Material.WoodPlanks })
	for i, cat in ipairs(JobConfig.Categories) do
		local x = 10.5 + (i - 1) * 2.8
		local m = model("Caixa_" .. cat.id, folder)
		local box = part(m, { Name = "Box", Size = Vector3.new(2.2, 2, 2.2), CFrame = at(x, 14) * CFrame.new(0, 1.5, 0), Color = cat.color, Material = Enum.Material.Cardboard })
		part(m, { Name = "Box2", Size = Vector3.new(2, 1.8, 2), CFrame = at(x, 14) * CFrame.new(0, 3.4, 0) * CFrame.Angles(0, 0.15 * i, 0), Color = cat.color, Material = Enum.Material.Cardboard })
		local label = part(m, { Name = "Label", Size = Vector3.new(2, 0.7, 0.1), CFrame = box.CFrame * CFrame.new(0, 0, -1.16), Color = Color3.new(1, 1, 1) })
		signText(label, cat.label, DARK)
		register("Atendente_Caixa_" .. cat.id .. "_1", job, "Caixa_" .. cat.id, box, m, "Caixa de " .. cat.label, 4)
	end
	wallSign(decor, base * CFrame.new(14.7, 8, 16.9), Vector3.new(8, 1.4, 0.2), "ESTOQUE", Color3.new(1, 1, 1), GREEN)

	local m = model("Reciclagem", folder)
	local bin = part(m, { Name = "Bin", Size = Vector3.new(2.6, 3, 2.2), CFrame = at(6.5, 15) * CFrame.new(0, 1.5, 0), Color = Color3.fromRGB(50, 150, 80) })
	local tag = part(m, { Name = "Tag", Size = Vector3.new(2.2, 0.7, 0.1), CFrame = bin.CFrame * CFrame.new(0, 0.6, -1.16), Color = Color3.new(1, 1, 1) })
	signText(tag, "RECICLE", Color3.fromRGB(50, 150, 80))
	register("Atendente_Reciclagem_1", job, "Reciclagem", bin, m, "Reciclagem")

	-- Gôndolas: uma por tipo de produto, com placa em cima
	local function gondola(parent, cf, colors, title)
		local g = model("Prateleira", parent)
		local back = part(g, { Name = "Back", Size = Vector3.new(7, 6, 0.3), CFrame = cf * CFrame.new(0, 3, 0.7), Color = LIGHT })
		for level = 0, 3 do
			local shelfCf = cf * CFrame.new(0, 0.5 + level * 1.5, 0)
			part(g, { Name = "Shelf", Size = Vector3.new(7, 0.2, 1.4), CFrame = shelfCf, Color = GREEN })
			for k = 0, 5 do
				part(g, { Name = "Product", Size = Vector3.new(0.8, 0.9, 0.8), CFrame = shelfCf * CFrame.new(-2.9 + k * 1.15, 0.55, 0), Color = colors[((k + level) % #colors) + 1], CanCollide = false })
			end
		end
		if title then
			local sign = part(g, { Name = "Title", Size = Vector3.new(5, 1, 0.2), CFrame = cf * CFrame.new(0, 7, 0.6), Color = GREEN })
			signText(sign, title, Color3.new(1, 1, 1))
		end
		return g, back
	end
	local shades = function(c)
		return { c, c:Lerp(Color3.new(1, 1, 1), 0.35), c:Lerp(Color3.new(0, 0, 0), 0.25) }
	end
	local shelves = {}
	for i, cat in ipairs(JobConfig.Categories) do
		local x = ({ -15, -6, 6, 15 })[i]
		local g, back = gondola(folder, at(x, 2), shades(cat.color), cat.label)
		g.Name = "Prateleira_" .. cat.id
		register("Atendente_Prateleira_" .. cat.id .. "_1", job, "Prateleira_" .. cat.id, back, g, "Prateleira de " .. cat.label)
		local products = {}
		for _, child in ipairs(g:GetChildren()) do
			if child.Name == "Product" then
				table.insert(products, child)
			end
		end
		shelves[cat.id] = products
	end
	gondola(decor, at(-15, 12), shades(Color3.fromRGB(250, 200, 60)))
	gondola(decor, at(-6, 12), shades(Color3.fromRGB(240, 240, 240)))

	-- Dois caixas (um para cada atendente). O cliente NPC fica do lado da porta (-Z),
	-- o atendente atrás do balcão. Na esteira aparecem as compras do cliente.
	local lanes = {}
	for lane, laneX in ipairs({ 8, 16 }) do
		local cm = model("Caixa" .. lane, folder)
		local body = counter(cm, at(laneX, -10), Vector3.new(6, 3.4, 3), LIGHT, GREEN)
		part(cm, { Name = "Belt", Size = Vector3.new(3.6, 0.1, 1.4), CFrame = body.CFrame * CFrame.new(-1.1, 1.6, -0.5), Color = DARK, Material = Enum.Material.Rubber })
		part(cm, { Name = "Register", Size = Vector3.new(1.4, 0.9, 1.1), CFrame = body.CFrame * CFrame.new(1.2, 2.3, 0.8), Color = DARK })
		part(cm, { Name = "Screen", Size = Vector3.new(1, 0.6, 0.1), CFrame = body.CFrame * CFrame.new(1.2, 3.05, 0.6) * CFrame.Angles(math.rad(-20), 0, 0), Color = Color3.fromRGB(120, 220, 140), Material = Enum.Material.Neon })
		local scanner = part(cm, { Name = "Scanner", Size = Vector3.new(0.9, 0.12, 1), CFrame = body.CFrame * CFrame.new(1, 1.66, -0.5), Color = Color3.fromRGB(255, 60, 60), Material = Enum.Material.Neon, CanCollide = false })
		local post = part(cm, { Name = "Post", Size = Vector3.new(0.3, 5, 0.3), CFrame = body.CFrame * CFrame.new(-2.7, 4.2, 0.9), Color = DARK, Material = Enum.Material.Metal })
		local laneSign = part(cm, { Name = "LaneSign", Size = Vector3.new(2.6, 1.1, 0.2), CFrame = post.CFrame * CFrame.new(0, 2.6, 0), Color = GREEN })
		signText(laneSign, "CAIXA " .. lane, Color3.new(1, 1, 1))
		register("Atendente_Checkout" .. lane, job, "Checkout" .. lane, body, cm, "Caixa " .. lane)

		-- Sacolas na ponta do balcão
		local bm = model("Sacolas" .. lane, folder)
		local holder = part(bm, { Name = "Holder", Size = Vector3.new(1.4, 0.2, 1.2), CFrame = body.CFrame * CFrame.new(2.4, 1.7, -0.5), Color = Color3.fromRGB(200, 200, 200), Material = Enum.Material.Metal })
		for k = 0, 1 do
			part(bm, { Name = "Bag", Size = Vector3.new(0.6, 0.9, 0.5), CFrame = holder.CFrame * CFrame.new(-0.3 + k * 0.6, 0.55, 0), Color = Color3.fromRGB(240, 240, 235), Material = Enum.Material.Fabric, CanCollide = false })
		end
		register("Atendente_Bag" .. lane, job, "Bag" .. lane, holder, bm, "Sacolas")

		-- Lugares das compras na esteira (ficam invisíveis até o cliente chegar)
		local slots = {}
		for k = 1, 6 do
			local item = part(folder, {
				Name = "Produto",
				Size = Vector3.new(0.45, 0.7, 0.45),
				CFrame = body.CFrame * CFrame.new(-2.65 + (k - 1) * 0.55, 2.0, -0.5),
				Color = Color3.new(1, 1, 1),
				Transparency = 1,
				CanCollide = false,
			})
			register(("Atendente_Esteira%d_%d"):format(lane, k), job, ("Esteira%d_%d"):format(lane, k), item, item, "Produto", 5)
			slots[k] = item
		end
		lanes[lane] = {
			customerSpot = at(laneX, -13.4), -- onde o cliente para, de frente para o balcão
			scanner = scanner,
			bag = holder,
			slots = slots,
		}
	end

	-- Limpeza: balde com esfregão e 3 lugares onde a sujeira pode aparecer
	m = model("Esfregao", folder)
	local bucket = part(m, { Name = "Bucket", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.6, 1.8, 1.8), CFrame = at(-19, 14.5) * CFrame.new(0, 0.8, 0) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(240, 200, 40) })
	part(m, { Name = "Handle", Size = Vector3.new(0.25, 4.5, 0.25), CFrame = at(-19, 14.5) * CFrame.new(0.3, 2.6, 0) * CFrame.Angles(0, 0, math.rad(8)), Color = Color3.fromRGB(150, 110, 70), Material = Enum.Material.Wood })
	register("Atendente_Esfregao_1", job, "Esfregao", bucket, m, "Esfregão")
	for i, pos in ipairs({ { -10.5, -3 }, { 0, 8 }, { 10.5, 6 } }) do
		local spill = part(folder, {
			Name = "Sujeira",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.08, 4.5, 4.5),
			CFrame = at(pos[1], pos[2]) * CFrame.new(0, 0.1, 0) * CFrame.Angles(0, 0, math.rad(90)),
			Color = Color3.fromRGB(240, 150, 40),
			Material = Enum.Material.Glass,
			Transparency = 1, -- aparece só quando alguém precisa limpar
			CanCollide = false,
		})
		register("Atendente_Sujeira_" .. i, job, "Sujeira_" .. i, spill, spill, "Sujeira")
	end

	-- Banca de frutas, geladeira e plantas
	for i, x in ipairs({ -15, -9 }) do
		local stand = model("BancaFrutas", decor)
		local crateTop = part(stand, { Name = "Stand", Size = Vector3.new(4.5, 2.2, 3), CFrame = at(x, -12) * CFrame.new(0, 1.1, 0) * CFrame.Angles(math.rad(-12), 0, 0), Color = WOOD, Material = Enum.Material.WoodPlanks })
		local fruit = i == 1 and Color3.fromRGB(230, 60, 50) or Color3.fromRGB(250, 170, 40)
		for k = 0, 5 do
			part(stand, { Name = "Fruit", Shape = Enum.PartType.Ball, Size = Vector3.new(0.9, 0.9, 0.9), CFrame = crateTop.CFrame * CFrame.new(-1.6 + (k % 3) * 1.6, 1.4, -0.6 + math.floor(k / 3) * 1.2), Color = fruit, CanCollide = false })
		end
	end
	local fridge = part(decor, { Name = "Geladeira", Size = Vector3.new(2.5, 7, 10), CFrame = at(-19.6, -5) * CFrame.new(0, 3.5, 0), Color = Color3.fromRGB(150, 210, 240), Material = Enum.Material.Glass, Transparency = 0.3 })
	local cold = Instance.new("PointLight")
	cold.Color = Color3.fromRGB(150, 210, 255)
	cold.Range = 8
	cold.Parent = fridge
	plant(decor, at(-19.5, -15.5))
	wallSign(decor, base * CFrame.new(-8, 10.5, 16.9), Vector3.new(16, 3, 0.2), "Produtos fresquinhos de Minas!", Color3.new(1, 1, 1), GREEN)

	JobSiteBuilder.market = {
		base = base,
		door = { base * CFrame.new(0, 0, -24), base * CFrame.new(0, 0, -14) }, -- fora da porta -> logo depois da porta
		lanes = lanes,
		shelves = shelves,
	}
end

local function buildSherlex(folder, base)
	local job = "Entregador"
	local function at(x, z)
		return base * CFrame.new(x, 0, z)
	end
	local ORANGE = Color3.fromRGB(240, 140, 30)
	local decor = model("Decoracao", folder)
	tiles(decor, base, 42, 34, 6, Color3.fromRGB(205, 205, 210), Color3.fromRGB(190, 190, 198))

	-- Balcão de coleta de frente para a porta
	local m = model("BalcaoPacotes", folder)
	local body = counter(m, at(0, -3), Vector3.new(10, 3.6, 2.5), Color3.fromRGB(235, 235, 240), ORANGE)
	crate(m, body.CFrame * CFrame.new(-3.2, 2.65, 0), 1.4)
	crate(m, body.CFrame * CFrame.new(-1.6, 2.45, 0.2) * CFrame.Angles(0, 0.4, 0), 1)
	crate(m, body.CFrame * CFrame.new(3.2, 2.55, 0) * CFrame.Angles(0, -0.2, 0), 1.2)
	local tag = part(m, { Name = "Tag", Size = Vector3.new(5, 0.9, 0.1), CFrame = body.CFrame * CFrame.new(0, 0.6, -1.3), Color = Color3.new(1, 1, 1) })
	signText(tag, "COLETA", ORANGE)
	register("Entregador_BalcaoPacotes_1", job, "BalcaoPacotes", body, m, "Balcão de pacotes")

	-- Estantes de metal com pacotes no fundo
	for _, x in ipairs({ -14, -4, 6, 15 }) do
		local rack = model("Estante", decor)
		for _, sx in ipairs({ -3.2, 3.2 }) do
			part(rack, { Name = "Post", Size = Vector3.new(0.3, 9, 0.3), CFrame = at(x + sx, 15.5) * CFrame.new(0, 4.5, 0), Color = ORANGE, Material = Enum.Material.Metal })
		end
		for level = 0, 2 do
			local shelfCf = at(x, 15.5) * CFrame.new(0, 1 + level * 3, 0)
			part(rack, { Name = "Shelf", Size = Vector3.new(7, 0.2, 2.4), CFrame = shelfCf, Color = STEEL, Material = Enum.Material.Metal })
			for k = 0, 2 do
				local s = 1 + ((k + level + x) % 3) * 0.3
				crate(rack, shelfCf * CFrame.new(-2.2 + k * 2.2, 0.1 + s / 2, 0) * CFrame.Angles(0, 0.15 * (k - 1), 0), s)
			end
		end
	end

	-- Esteira de pacotes na lateral
	local belt = model("Esteira", decor)
	part(belt, { Name = "Base", Size = Vector3.new(3, 2.6, 16), CFrame = at(-18.5, 0) * CFrame.new(0, 1.3, 0), Color = DARK, Material = Enum.Material.Metal })
	part(belt, { Name = "Belt", Size = Vector3.new(2.6, 0.15, 16), CFrame = at(-18.5, 0) * CFrame.new(0, 2.65, 0), Color = Color3.fromRGB(30, 30, 30), Material = Enum.Material.Rubber })
	for i, z in ipairs({ -5, -1, 4 }) do
		crate(belt, at(-18.5, z) * CFrame.new(0, 3.3, 0) * CFrame.Angles(0, 0.3 * i, 0), 1.2)
	end

	-- Mesa com computador, pilhas de caixas e plantas
	local desk = model("Escritorio", decor)
	part(desk, { Name = "Desk", Size = Vector3.new(6, 0.3, 3), CFrame = at(15, -10) * CFrame.new(0, 3, 0), Color = WOOD, Material = Enum.Material.Wood })
	part(desk, { Name = "Base", Size = Vector3.new(5.6, 2.8, 2.6), CFrame = at(15, -10) * CFrame.new(0, 1.4, 0.1), Color = Color3.fromRGB(230, 230, 235) })
	part(desk, { Name = "Monitor", Size = Vector3.new(2.2, 1.4, 0.2), CFrame = at(15, -10) * CFrame.new(0, 4, 0.6), Color = Color3.fromRGB(120, 180, 240), Material = Enum.Material.Neon })
	stool(decor, at(15, -7.5), ORANGE)
	for i, pos in ipairs({ { 8, 6 }, { 10, 7.5 }, { -9, 7 } }) do
		crate(decor, at(pos[1], pos[2]) * CFrame.new(0, 1.2, 0) * CFrame.Angles(0, 0.4 * i, 0), 2.4)
	end
	wallSign(decor, base * CFrame.new(-2, 12, 16.9), Vector3.new(14, 2.6, 0.2), "SHERLEX ENTREGAS", Color3.new(1, 1, 1), ORANGE)
	plant(decor, at(-19, -15))
	plant(decor, at(19, -15))
end

-- Duto Pet Shop: só decoração por enquanto (a profissão de cuidador chega no Marco 9)
local function buildPetShop(folder, base)
	local function at(x, z)
		return base * CFrame.new(x, 0, z)
	end
	local PURPLE = Color3.fromRGB(130, 80, 200)
	local decor = model("Decoracao", folder)
	tiles(decor, base, 42, 34, 4, Color3.fromRGB(245, 240, 250), Color3.fromRGB(225, 210, 240))
	-- Banheira de banho
	local tub = model("Banheira", decor)
	part(tub, { Name = "Tub", Size = Vector3.new(6, 2.6, 3.5), CFrame = at(-14, 14) * CFrame.new(0, 1.3, 0), Color = Color3.new(1, 1, 1) })
	part(tub, { Name = "Water", Size = Vector3.new(5.4, 0.2, 2.9), CFrame = at(-14, 14) * CFrame.new(0, 2.5, 0), Color = Color3.fromRGB(120, 200, 240), Material = Enum.Material.Glass, Transparency = 0.3, CanCollide = false })
	-- Mesa de tosa
	counter(decor, at(-4, 14.5), Vector3.new(5, 3.2, 3), STEEL, PURPLE)
	-- Caminhas de pet
	for i, x in ipairs({ 6, 11, 16 }) do
		local bed = Color3.fromHSV((0.75 + i * 0.08) % 1, 0.4, 0.95)
		part(decor, { Name = "Caminha", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.8, 3.4, 3.4), CFrame = at(x, 13) * CFrame.new(0, 0.4, 0) * CFrame.Angles(0, 0, math.rad(90)), Color = bed, Material = Enum.Material.Fabric })
	end
	wallShelf(decor, base * CFrame.new(-20.3, 1, 0) * CFrame.Angles(0, -math.pi / 2, 0), 14, { PURPLE, Color3.fromRGB(250, 200, 60), Color3.fromRGB(110, 190, 90) }, 2)
	counter(decor, at(13, -9), Vector3.new(7, 3.6, 2.5), Color3.fromRGB(245, 240, 250), PURPLE)
	wallSign(decor, base * CFrame.new(0, 10.5, 16.9), Vector3.new(16, 3, 0.2), "Banho · Tosa · Carinho", Color3.new(1, 1, 1), PURPLE)
	plant(decor, at(-19, -15))
	plant(decor, at(19, -15))
end

-- Ponto de entrega invisível na frente da porta de cada casa
local function buildHouseDeliveries(folder, houses)
	for _, house in ipairs(houses:GetChildren()) do
		local door = house:FindFirstChild("Door")
		local number = house:GetAttribute("HouseNumber") -- número único da casa (para o nome do ponto)
		local address = house:GetAttribute("Address") or ("Casa " .. tostring(number))
		if door and number then
			local point = part(folder, {
				Name = "Casa",
				Size = Vector3.new(4, 4, 2),
				CFrame = door.CFrame * CFrame.new(0, -1.5, -2.5),
				Transparency = 1,
				CanCollide = false,
			})
			point.CanQuery = false
			point.CanTouch = false
			local name = "Entregador_Casa_" .. number
			register(name, "Entregador", "House", point, door, address)
			table.insert(JobSiteBuilder.houses, { point = name, address = address })
		end
	end
end

local function buildBoard(folder)
	local pos = JobConfig.BoardPosition
	local cf = CFrame.lookAt(Vector3.new(pos.X, 0.9, pos.Z), Vector3.new(0, 0.9, 20))
	local m = Instance.new("Model")
	m.Name = "QuadroDeEmpregos"
	m.Parent = folder
	for _, x in ipairs({ -2.6, 2.6 }) do
		part(m, { Name = "Post", Size = Vector3.new(0.5, 7, 0.5), CFrame = cf * CFrame.new(x, 3.5, 0), Color = WOOD, Material = Enum.Material.Wood })
	end
	local board = part(m, { Name = "Board", Size = Vector3.new(5.6, 3.6, 0.4), CFrame = cf * CFrame.new(0, 4.6, 0), Color = Color3.fromRGB(110, 75, 45), Material = Enum.Material.Wood })
	part(m, { Name = "Roof", Size = Vector3.new(6.6, 0.4, 1.4), CFrame = cf * CFrame.new(0, 6.9, 0), Color = Color3.fromRGB(180, 70, 55) })
	local paper = part(m, { Name = "Paper", Size = Vector3.new(4.8, 2.9, 0.1), CFrame = board.CFrame * CFrame.new(0, 0, -0.25), Color = Color3.fromRGB(250, 245, 230) })
	signText(paper, "EMPREGOS", Color3.fromRGB(30, 80, 150))

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "BoardPrompt"
	prompt.ActionText = "Ver empregos"
	prompt.ObjectText = "Quadro de empregos"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = board
	JobSiteBuilder.board = board
	return prompt
end

local function shopFrame(shops, placeName)
	local shop = shops:WaitForChild(placeName, 10)
	return shop and shop:GetAttribute("BaseCFrame") -- chão de dentro da loja (MapBuilder)
end

-- Devolve o ProximityPrompt do quadro de empregos
function JobSiteBuilder.build()
	local old = Workspace:FindFirstChild("JobStations")
	if old then
		old:Destroy()
	end
	local root = Instance.new("Folder")
	root.Name = "JobStations"

	local boardPrompt = buildBoard(root)

	local map = Workspace:WaitForChild("Map")
	local shops = map:WaitForChild("JobLocations")
	local builders = {
		{ GameConfig.Places.Pizzaria, "Pizzaiolo", buildPizzaria },
		{ GameConfig.Places.Mercearia, "Atendente", buildMarket },
		{ GameConfig.Places.Entregas, "Entregador", buildSherlex },
		{ GameConfig.Places.PetShop, "PetShop", buildPetShop },
	}
	for _, entry in ipairs(builders) do
		local cf = shopFrame(shops, entry[1])
		if cf then
			local folder = Instance.new("Folder")
			folder.Name = entry[2]
			folder.Parent = root
			entry[3](folder, cf)
			local spots = SHOP_SPOTS[entry[2]] or {}
			local shop = { base = cf, door = { cf * CFrame.new(0, 0, -24), cf * CFrame.new(0, 0, -14) }, customers = {} }
			if spots.staff then
				shop.staff = cf * CFrame.new(spots.staff[1], 0, spots.staff[2]) -- olhando para a porta
			end
			for _, c in ipairs(spots.customers or {}) do
				table.insert(shop.customers, cf * CFrame.new(c[1], 0, c[2]) * CFrame.Angles(0, math.pi, 0)) -- olhando para o balcão
			end
			JobSiteBuilder.shops[entry[2]] = shop
		else
			warn("[JobSiteBuilder] Loja não encontrada: " .. entry[1])
		end
	end

	local houses = map:FindFirstChild("Houses")
	if houses then
		local deliveries = Instance.new("Folder")
		deliveries.Name = "Entregas"
		deliveries.Parent = root
		buildHouseDeliveries(deliveries, houses)
	end

	root.Parent = Workspace
	return boardPrompt
end

return JobSiteBuilder
