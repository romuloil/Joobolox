-- MapController (ModuleScript)
-- Caminho: StarterPlayer > StarterPlayerScripts > Controllers > MapController
-- Mapa do bairro visto de cima, aberto pelo botão redondo do topo (ícone de mapa) ou pela tecla M.
-- Mostra ruas, casas, estabelecimentos, onde o jogador está e,
-- quando há etapa de emprego, o destino em laranja (loja ou casa da entrega). É desenhado a partir do próprio mapa do jogo.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))
local UIScaler = require(script.Parent:WaitForChild("UIScaler"))

local MapController = {}

local player = Players.LocalPlayer
local M = GameConfig.Map
local MAP_PX = 420 -- tamanho do desenho do mapa em pixels
local WORLD = M.GroundSize -- studs representados pelo mapa
local RADIAL_START, RADIAL_END = 50, 50 + M.RoadLength

local COLORS = {
	Background = Color3.fromRGB(106, 170, 74),
	Road = Color3.fromRGB(70, 72, 78),
	House = Color3.fromRGB(235, 225, 205),
	Building = Color3.fromRGB(170, 175, 195),
	Shop = Color3.fromRGB(30, 80, 150),
	Target = Color3.fromRGB(240, 140, 30),
	Player = Color3.fromRGB(255, 255, 255),
}

local gui, panel, canvas, playerMarker, playerPointer, playerHalo
local civicRoadLayer, civicMarkerLayer
local shopDots = {} -- shopDots[nome] = { dot, label }
local targetPlace, targetPos, targetDot
local isOpen = false

local function corner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = radius
	c.Parent = parent
end

-- Converte posição do mundo (X, Z) para pixels dentro do canvas
local function toMap(pos)
	return Vector2.new((pos.X / WORLD + 0.5) * MAP_PX, (pos.Z / WORLD + 0.5) * MAP_PX)
end

local function drawLine(a, b, width, color, parent)
	local pa, pb = toMap(a), toMap(b)
	local delta = pb - pa
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	f.BackgroundColor3 = color
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Size = UDim2.fromOffset(delta.Magnitude + width, width)
	f.Position = UDim2.fromOffset((pa.X + pb.X) / 2, (pa.Y + pb.Y) / 2)
	f.Rotation = math.deg(math.atan2(delta.Y, delta.X))
	f.Parent = parent or canvas
	return f
end

local function drawDot(pos, size, color, round, parent)
	local p = toMap(pos)
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	f.BackgroundColor3 = color
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Size = UDim2.fromOffset(size, size)
	f.Position = UDim2.fromOffset(p.X, p.Y)
	f.Parent = parent or canvas
	if round then
		corner(f, UDim.new(1, 0))
	end
	return f
end

local function drawStreets()
	local roadPx = math.max(3, M.RoadWidth / WORLD * MAP_PX)
	local angles = {}
	for i = 0, 7 do
		local dir = CFrame.Angles(0, i * math.pi / 4, 0).LookVector
		table.insert(angles, dir)
		drawLine(dir * RADIAL_START, dir * RADIAL_END, roadPx, COLORS.Road)
	end
	for _, radius in ipairs({ M.InnerRingRadius, RADIAL_END }) do
		for i, dir in ipairs(angles) do
			local nextDir = angles[(i % #angles) + 1]
			drawLine(dir * radius, nextDir * radius, roadPx, COLORS.Road)
		end
	end
	-- Rotatória e praça
	drawDot(Vector3.zero, M.RoundaboutOuterRadius * 2 / WORLD * MAP_PX, COLORS.Road, true)
	drawDot(Vector3.zero, M.RoundaboutIslandRadius * 2 / WORLD * MAP_PX, COLORS.Background, true)

	-- Nomes das ruas (abreviados), escritos ao longo da rua
	local function short(name)
		return (name:gsub("^Avenida", "Av."):gsub("^Rua", "R."))
	end
	local function streetLabel(a, b, name)
		local pa, pb = toMap(a), toMap(b)
		local mid = (pa + pb) / 2
		local angle = math.deg(math.atan2(pb.Y - pa.Y, pb.X - pa.X))
		if angle > 90 then
			angle -= 180
		elseif angle < -90 then
			angle += 180
		end
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.AnchorPoint = Vector2.new(0.5, 0.5)
		l.Position = UDim2.fromOffset(mid.X, mid.Y)
		l.Size = UDim2.fromOffset(120, 12)
		l.Rotation = angle
		l.Font = Enum.Font.GothamBold
		l.TextSize = 10
		l.TextColor3 = Color3.fromRGB(255, 255, 255)
		l.TextStrokeTransparency = 0.5
		l.Text = short(name)
		l.ZIndex = 2
		l.Parent = canvas
	end
	for i, dir in ipairs(angles) do
		streetLabel(dir * M.InnerRingRadius, dir * RADIAL_END, M.StreetNames[i])
	end
	streetLabel(angles[2] * M.InnerRingRadius, angles[3] * M.InnerRingRadius, M.InnerRingName)
	streetLabel(angles[6] * RADIAL_END, angles[7] * RADIAL_END, M.OuterRingName)
end

local function drawBuildings(map)
	local houses = map:FindFirstChild("Houses")
	if houses then
		for _, house in ipairs(houses:GetChildren()) do
			drawDot(house:GetPivot().Position, 4, COLORS.House, false)
		end
	end
	local buildings = map:FindFirstChild("Buildings")
	if buildings then
		for _, building in ipairs(buildings:GetChildren()) do
			drawDot(building:GetPivot().Position, 5, COLORS.Building, false)
		end
	end
	local shops = map:FindFirstChild("JobLocations")
	if shops then
		for _, shop in ipairs(shops:GetChildren()) do
			local name = shop:GetAttribute("PlaceName")
			if name then
				local dot = drawDot(shop:GetPivot().Position, 12, COLORS.Shop, true)
				local stroke = Instance.new("UIStroke")
				stroke.Color = Color3.new(1, 1, 1)
				stroke.Thickness = 2
				stroke.Parent = dot

				-- O nome fica do lado de FORA da rua (longe da loja vizinha do outro lado),
				-- assim duas lojas frente a frente não sobrepõem os nomes.
				local pos = shop:GetPivot().Position
				local flatPos = Vector3.new(pos.X, 0, pos.Z)
				local roadAngle = math.floor(math.atan2(flatPos.X, -flatPos.Z) / (math.pi / 4) + 0.5) * (math.pi / 4)
				local roadDir = Vector3.new(math.sin(roadAngle), 0, -math.cos(roadAngle))
				local side = flatPos - roadDir * flatPos:Dot(roadDir) -- deslocamento lateral em relação à rua
				local label = Instance.new("TextLabel")
				label.BackgroundTransparency = 1
				label.Size = UDim2.fromOffset(110, 14)
				if math.abs(side.X) >= math.abs(side.Z) then
					-- rua vertical no mapa: nome à esquerda ou à direita
					label.TextXAlignment = side.X < 0 and Enum.TextXAlignment.Right or Enum.TextXAlignment.Left
					label.AnchorPoint = Vector2.new(side.X < 0 and 1 or 0, 0.5)
					label.Position = UDim2.new(side.X < 0 and 0 or 1, side.X < 0 and -4 or 4, 0.5, 0)
				else
					-- rua horizontal no mapa: nome acima ou abaixo
					label.AnchorPoint = Vector2.new(0.5, side.Z < 0 and 1 or 0)
					label.Position = UDim2.new(0.5, 0, side.Z < 0 and 0 or 1, side.Z < 0 and -2 or 2)
				end
				label.Font = Enum.Font.GothamBold
				label.TextSize = 12
				label.TextColor3 = Color3.new(1, 1, 1)
				label.TextStrokeTransparency = 0.4
				label.Text = name
				label.Parent = dot
				shopDots[name] = { dot = dot, label = label }
			end
		end
	end
end

-- A estrada e os pontos públicos vêm do mapa construído no servidor.
-- Camadas próprias permitem atualizar a replicação sem refazer o mapa ou o jogador.
local function drawCivic(map)
	if not civicRoadLayer or not civicMarkerLayer then
		return
	end
	civicRoadLayer:ClearAllChildren()
	civicMarkerLayer:ClearAllChildren()
	local roads = map:FindFirstChild("CivicRoads")
	if roads then
		for _, road in ipairs(roads:GetDescendants()) do
			local a, b = road:GetAttribute("RoadStart"), road:GetAttribute("RoadEnd")
			if typeof(a) == "Vector3" and typeof(b) == "Vector3" then
				local line = drawLine(a, b, math.max(3, M.RoadWidth / WORLD * MAP_PX), COLORS.Road, civicRoadLayer)
				line.Name = "CivicRoad"
			end
		end
	end
	local locations = map:FindFirstChild("CivicLocations")
	if not locations then
		return
	end
	for _, location in ipairs(locations:GetChildren()) do
		local pos = location:GetAttribute("MapPosition")
		local name = location:GetAttribute("PlaceName")
		if typeof(pos) == "Vector3" and type(name) == "string" then
			local kind = location:GetAttribute("Kind")
			local color = kind == "Prison" and Color3.fromRGB(178, 103, 45)
				or kind == "Fuel" and Color3.fromRGB(48, 118, 95)
				or kind == "Taxi" and Color3.fromRGB(232, 180, 43)
				or Color3.fromRGB(32, 93, 168)
			local dot = drawDot(pos, kind == "Fuel" and 8 or 12, color, true, civicMarkerLayer)
			dot.Name = name
			dot.ZIndex = 3
			local ring = Instance.new("UIStroke")
			ring.Color = Color3.fromRGB(255, 255, 255)
			ring.Thickness = 2
			ring.Parent = dot

			-- Etiqueta ancorada em pixels para não cortar junto às bordas.
			local p = toMap(pos)
			local label = Instance.new("TextLabel")
			label.Name = "CivicLabel"
			label.AnchorPoint = Vector2.new(0.5, 0.5)
			local labelX = math.clamp(p.X, 65, MAP_PX - 65)
			local labelY = p.Y + (kind == "Prison" and -17 or kind == "Fuel" and 17 or -17)
			label.Position = UDim2.fromOffset(labelX, math.clamp(labelY, 10, MAP_PX - 10))
			label.Size = UDim2.fromOffset(126, 18)
			label.BackgroundColor3 = Color3.fromRGB(20, 30, 50)
			label.BackgroundTransparency = 0.12
			label.BorderSizePixel = 0
			label.Font = Enum.Font.GothamBold
			label.TextSize = 11
			label.TextColor3 = Color3.fromRGB(255, 255, 255)
			label.Text = location:GetAttribute("MapLabel") or name
			label.ZIndex = 4
			label.Parent = civicMarkerLayer
			corner(label, UDim.new(0, 5))
		end
	end
end

local function watchCivic(map)
	local queued = false
	local watched = {}
	local function refreshSoon()
		if queued then
			return
		end
		queued = true
		task.delay(0.15, function()
			queued = false
			if canvas and canvas.Parent then
				drawCivic(map)
			end
		end)
	end
	local function watch(item)
		if watched[item] then
			return
		end
		local parent = item.Parent
		local locations, roads = map:FindFirstChild("CivicLocations"), map:FindFirstChild("CivicRoads")
		if locations and parent == locations then
			watched[item] = true
			for _, attr in ipairs({ "PlaceName", "MapPosition", "MapLabel", "Kind" }) do
				item:GetAttributeChangedSignal(attr):Connect(refreshSoon)
			end
			refreshSoon()
		elseif roads and item:IsA("BasePart") and item:IsDescendantOf(roads) then
			watched[item] = true
			item:GetAttributeChangedSignal("RoadStart"):Connect(refreshSoon)
			item:GetAttributeChangedSignal("RoadEnd"):Connect(refreshSoon)
			refreshSoon()
		end
	end
	map.DescendantAdded:Connect(watch)
	map.DescendantRemoving:Connect(function(item)
		if watched[item] then
			watched[item] = nil
			refreshSoon()
		end
	end)
	map:GetAttributeChangedSignal("CivicReady"):Connect(refreshSoon)
	for _, item in ipairs(map:GetDescendants()) do
		watch(item)
	end
	drawCivic(map)
end

local function refreshTarget()
	if targetDot then
		targetDot.Visible = targetPos ~= nil
		if targetPos then
			local p = toMap(targetPos)
			targetDot.Position = UDim2.fromOffset(p.X, p.Y)
		end
	end
	for name, entry in pairs(shopDots) do
		local isTarget = (name == targetPlace)
		entry.dot.BackgroundColor3 = isTarget and COLORS.Target or COLORS.Shop
		entry.dot.Size = UDim2.fromOffset(isTarget and 16 or 12, isTarget and 16 or 12)
		entry.label.TextColor3 = isTarget and Color3.fromRGB(255, 220, 150) or Color3.new(1, 1, 1)
	end
end

local function updatePlayer()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		playerMarker.Visible = false
		return
	end
	playerMarker.Visible = true
	local p = toMap(root.Position)
	playerMarker.Position = UDim2.fromOffset(p.X, p.Y)
	local look = root.CFrame.LookVector
	-- A seta aponta para cima; gira para a direção em que o personagem olha
	playerPointer.Rotation = math.deg(math.atan2(look.Z, look.X)) + 90
end

-- Marcador do jogador: bolinha azul com borda branca, seta da direção, onda pulsando e "VOCÊ"
local function buildPlayerMarker()
	playerMarker = Instance.new("Frame")
	playerMarker.Name = "Voce"
	playerMarker.BackgroundTransparency = 1
	playerMarker.AnchorPoint = Vector2.new(0.5, 0.5)
	playerMarker.Size = UDim2.fromOffset(44, 44)
	playerMarker.ZIndex = 6
	playerMarker.Parent = canvas

	playerHalo = Instance.new("Frame")
	playerHalo.AnchorPoint = Vector2.new(0.5, 0.5)
	playerHalo.Position = UDim2.fromScale(0.5, 0.5)
	playerHalo.Size = UDim2.fromOffset(26, 26)
	playerHalo.BackgroundColor3 = Color3.fromRGB(40, 140, 255)
	playerHalo.BackgroundTransparency = 0.55
	playerHalo.ZIndex = 6
	playerHalo.Parent = playerMarker
	corner(playerHalo, UDim.new(1, 0))

	playerPointer = Instance.new("Frame")
	playerPointer.AnchorPoint = Vector2.new(0.5, 0.5)
	playerPointer.Position = UDim2.fromScale(0.5, 0.5)
	playerPointer.Size = UDim2.fromOffset(40, 40)
	playerPointer.BackgroundTransparency = 1
	playerPointer.ZIndex = 7
	playerPointer.Parent = playerMarker
	-- seta branca na frente da bolinha (fica girando com o jogador)
	local tip = Instance.new("TextLabel")
	tip.BackgroundTransparency = 1
	tip.AnchorPoint = Vector2.new(0.5, 0.5)
	tip.Position = UDim2.new(0.5, 0, 0, 6)
	tip.Size = UDim2.fromOffset(16, 12)
	tip.Font = Enum.Font.GothamBlack
	tip.TextSize = 14
	tip.TextColor3 = Color3.new(1, 1, 1)
	tip.TextStrokeColor3 = Color3.fromRGB(20, 60, 140)
	tip.TextStrokeTransparency = 0
	tip.Text = "▲"
	tip.ZIndex = 8
	tip.Parent = playerPointer

	local dot = Instance.new("Frame")
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Position = UDim2.fromScale(0.5, 0.5)
	dot.Size = UDim2.fromOffset(18, 18)
	dot.BackgroundColor3 = Color3.fromRGB(30, 120, 255)
	dot.ZIndex = 9
	dot.Parent = playerMarker
	corner(dot, UDim.new(1, 0))
	local ring = Instance.new("UIStroke")
	ring.Color = Color3.new(1, 1, 1)
	ring.Thickness = 3
	ring.Parent = dot

	local tag = Instance.new("TextLabel")
	tag.BackgroundColor3 = Color3.fromRGB(30, 120, 255)
	tag.AnchorPoint = Vector2.new(0.5, 0)
	tag.Position = UDim2.new(0.5, 0, 1, -4)
	tag.Size = UDim2.fromOffset(40, 15)
	tag.Font = Enum.Font.GothamBlack
	tag.TextSize = 10
	tag.TextColor3 = Color3.new(1, 1, 1)
	tag.Text = "VOCÊ"
	tag.ZIndex = 9
	tag.Parent = playerMarker
	corner(tag, UDim.new(0, 6))

	-- onda pulsando para achar o marcador rápido
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
	panel.Size = UDim2.fromOffset(MAP_PX + 20, MAP_PX + 56)
	panel.BackgroundColor3 = Color3.fromRGB(20, 30, 50)
	panel.Visible = false
	panel.Parent = gui
	corner(panel, UDim.new(0, 16))
	UIScaler.attach(panel)

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(14, 8)
	title.Size = UDim2.new(1, -70, 0, 28)
	title.Font = Enum.Font.GothamBold
	title.TextSize = 18
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = Color3.new(1, 1, 1)
	title.Text = GameConfig.CityName
	title.Parent = panel

	local close = Instance.new("TextButton")
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -8, 0, 6)
	close.Size = UDim2.fromOffset(36, 32)
	close.BackgroundColor3 = Color3.fromRGB(200, 90, 60)
	close.Font = Enum.Font.GothamBold
	close.TextSize = 18
	close.TextColor3 = Color3.new(1, 1, 1)
	close.Text = "X"
	close.Parent = panel
	corner(close, UDim.new(0, 8))
	close.Activated:Connect(function()
		MapController.toggle(false)
	end)

	canvas = Instance.new("Frame")
	canvas.Name = "Canvas"
	canvas.Position = UDim2.fromOffset(10, 46)
	canvas.Size = UDim2.fromOffset(MAP_PX, MAP_PX)
	canvas.BackgroundColor3 = COLORS.Background
	canvas.ClipsDescendants = true
	canvas.Parent = panel
	corner(canvas, UDim.new(0, 10))

	drawStreets()
	drawBuildings(map)
	civicRoadLayer = Instance.new("Folder")
	civicRoadLayer.Name = "CivicRoads"
	civicRoadLayer.Parent = canvas
	civicMarkerLayer = Instance.new("Folder")
	civicMarkerLayer.Name = "CivicMarkers"
	civicMarkerLayer.Parent = canvas
	watchCivic(map)

	targetDot = drawDot(Vector3.zero, 14, COLORS.Target, true)
	targetDot.ZIndex = 4
	local ring = Instance.new("UIStroke")
	ring.Color = Color3.new(1, 1, 1)
	ring.Thickness = 2
	ring.Parent = targetDot
	targetDot.Visible = false

	buildPlayerMarker()

	refreshTarget()
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
	if open then
		updatePlayer()
	end
end

-- Destino da etapa atual: placeName (loja fica laranja) e/ou worldPos (bolinha laranja,
-- usada nas entregas em casas). Passe nil para limpar.
function MapController.setTarget(placeName, worldPos)
	targetPlace = placeName
	targetPos = typeof(worldPos) == "Vector3" and worldPos or nil
	if panel then
		refreshTarget()
	end
end

-- Botão "Mapa" pequeno no topo, no centro da tela
-- Ícone de mapa dobrado (3 faixas) com um alfinete laranja, feito só de Frames
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

-- Botão redondo pequeno no limite de cima da tela, na mesma faixa dos botões do Roblox
local function buildButton()
	local buttonGui = Instance.new("ScreenGui")
	buttonGui.Name = "MapButtonUI"
	buttonGui.ResetOnSpawn = false
	buttonGui.IgnoreGuiInset = true -- permite usar a faixa do topo
	buttonGui.DisplayOrder = 4
	buttonGui.Parent = player:WaitForChild("PlayerGui")

	local size = 40
	local topbar = GuiService:GetGuiInset().Y
	local button = Instance.new("ImageButton")
	button.Name = "MapButton"
	button.AnchorPoint = Vector2.new(0.5, 0)
	button.Position = UDim2.new(0.5, 0, 0, math.max(4, (topbar - size) / 2))
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
end

function MapController.init()
	task.spawn(function()
		local map = Workspace:WaitForChild("Map")
		task.wait(1) -- dá tempo das peças do mapa chegarem ao cliente
		build(map)
		buildButton()

		UserInputService.InputBegan:Connect(function(input, processed)
			if not processed and input.KeyCode == Enum.KeyCode.M then
				MapController.toggle()
			end
		end)

		while true do
			if isOpen then
				updatePlayer()
			end
			task.wait(0.1)
		end
	end)
end

return MapController
