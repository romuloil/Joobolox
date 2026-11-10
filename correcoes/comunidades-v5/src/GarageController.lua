-- GarageController (ModuleScript)
-- Caminho: StarterPlayer > StarterPlayerScripts > Controllers > GarageController
-- Marco 6.3: menu da Garagem (guarita azul do mapa, aviso "Abrir garagem" com E).
-- "Retirar" pede ao servidor, que confere se você está perto da guarita e se o veículo é seu, e
-- coloca o veículo numa vaga livre já com você dirigindo. "Guardar" some com o seu veículo da rua.
-- Marco 7: veículo que ainda não é seu mostra o preço; tocar compra (o servidor confere o saldo).
-- Marco 7.1: painel novo. Abas (Carros, Motos e, só no Studio, Serviço), lista de cartões com
-- miniatura 3D à direita e, à esquerda, o veículo escolhido girando, com raridade, barras de
-- velocidade/aceleração/curva e o botão grande de Retirar ou Comprar.
-- As miniaturas vêm de ReplicatedStorage > CarPreviews (o servidor monta uma cópia de cada veículo).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))
local UIScaler = require(script.Parent:WaitForChild("UIScaler"))

local GarageController = {}

local player = Players.LocalPlayer
local vehicleRequest
local gui, panel
local openedAt -- posição do jogador quando abriu (longe disso o menu fecha sozinho)
local spinning -- veículo grande da vitrine, girando devagar
local lastTab = "Carros"

local BG_TOP = Color3.fromRGB(24, 34, 62)
local BG_BOTTOM = Color3.fromRGB(14, 18, 34)
local CARD = Color3.fromRGB(34, 46, 78)
local CARD_ON = Color3.fromRGB(48, 64, 108)
local TEXT_SOFT = Color3.fromRGB(175, 190, 225)
local GREEN = Color3.fromRGB(60, 185, 95)
local ORANGE = Color3.fromRGB(240, 150, 30)
local BLUE = Color3.fromRGB(50, 95, 200)
local RED = Color3.fromRGB(215, 70, 65)
local GRAY = Color3.fromRGB(85, 92, 110)

-- Cor de cada raridade (selo e borda do cartão)
local RARITY = {
	["Comum"] = Color3.fromRGB(160, 168, 180),
	["Incomum"] = Color3.fromRGB(80, 200, 110),
	["Raro"] = Color3.fromRGB(70, 150, 255),
	["Épico"] = Color3.fromRGB(175, 90, 255),
	["Lendário"] = Color3.fromRGB(255, 190, 40),
	["Admin"] = Color3.fromRGB(255, 70, 90), -- Marco 9.16: carros exclusivos dos admins
}
local SERVICE_COLOR = Color3.fromRGB(240, 140, 30)

local function corner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 10)
	c.Parent = parent
	return c
end

local function stroke(parent, color, thickness, transparency)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness or 1
	s.Transparency = transparency or 0
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

local function label(parent, text, size, pos, textSize, color, font, align)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = size
	l.Position = pos
	l.Font = font or Enum.Font.GothamBold
	l.TextSize = textSize or 16
	l.TextXAlignment = align or Enum.TextXAlignment.Left
	l.TextColor3 = color or Color3.new(1, 1, 1)
	l.TextTruncate = Enum.TextTruncate.AtEnd
	l.Text = text
	l.Parent = parent
	return l
end

local function button(parent, text, color, size, pos, textSize)
	local b = Instance.new("TextButton")
	b.Size = size
	b.Position = pos
	b.BackgroundColor3 = color
	b.Font = Enum.Font.GothamBlack
	b.TextSize = textSize or 16
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Text = text
	b.AutoButtonColor = true
	b.Parent = parent
	corner(b, 10)
	return b
end

local function money(n)
	-- 15000 -> "$15.000"
	local s = tostring(math.floor(tonumber(n) or 0))
	local out = s:reverse():gsub("(%d%d%d)", "%1."):reverse()
	if out:sub(1, 1) == "." then
		out = out:sub(2)
	end
	return GameConfig.Economy.CurrencySymbol .. out
end

local function close()
	if panel then
		panel:Destroy()
		panel = nil
	end
	spinning = nil
	openedAt = nil
end

local function send(data)
	vehicleRequest:FireServer("Garage", data)
	close()
end

-- Põe uma cópia do veículo num ViewportFrame. Devolve { aim = função(ângulo) } para girar a câmera.
local function showModel(viewport, id, yaw, zoom)
	local previews = ReplicatedStorage:FindFirstChild("CarPreviews")
	local tpl = previews and previews:FindFirstChild(id)
	if not tpl then
		label(viewport, "🚗", UDim2.fromScale(1, 1), UDim2.new(), 28, TEXT_SOFT, nil, Enum.TextXAlignment.Center)
		return nil
	end
	local world = Instance.new("WorldModel")
	world.Parent = viewport
	local model = tpl:Clone()
	model.Parent = world
	local cf, size = model:GetBoundingBox()
	local center = cf.Position
	local camera = Instance.new("Camera")
	camera.FieldOfView = 30
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	local radius = math.max(size.X, size.Z, size.Y * 1.6) * 0.5
	local dist = radius / math.tan(math.rad(camera.FieldOfView / 2)) * (zoom or 1.05)
	local height = dist * 0.32
	local function aim(angle)
		local offset = Vector3.new(math.sin(angle) * dist, height, math.cos(angle) * dist)
		camera.CFrame = CFrame.lookAt(center + offset, center + Vector3.new(0, size.Y * 0.05, 0))
	end
	aim(yaw or math.rad(-40))
	return { aim = aim }
end

-- Barra de atributo (0 a 1) com nome
local function statBar(parent, name, value, y, color)
	label(parent, name, UDim2.fromOffset(100, 16), UDim2.fromOffset(0, y), 13, TEXT_SOFT)
	local back = Instance.new("Frame")
	back.BackgroundColor3 = Color3.fromRGB(40, 50, 80)
	back.BorderSizePixel = 0
	back.Size = UDim2.new(1, -110, 0, 10)
	back.Position = UDim2.fromOffset(105, y + 3)
	back.Parent = parent
	corner(back, 5)
	local fill = Instance.new("Frame")
	fill.BackgroundColor3 = Color3.new(1, 1, 1)
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(0, 1)
	fill.Parent = back
	corner(fill, 5)
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(color:Lerp(Color3.new(1, 1, 1), 0.3), color)
	g.Parent = fill
	TweenService:Create(fill, TweenInfo.new(0.35, Enum.EasingStyle.Quad), { Size = UDim2.fromScale(math.clamp(value, 0.05, 1), 1) }):Play()
end

function GarageController.open(data)
	close()
	if type(data) ~= "table" or type(data.cars) ~= "table" then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	openedAt = root and root.Position
	local balance = tonumber(data.money) or 0

	-- Os maiores valores entre todos (barra cheia = o melhor veículo naquilo)
	local top = { speed = 1, accel = 1, turn = 0.1 }
	local tabs, byTab = {}, {}
	for _, car in ipairs(data.cars) do
		top.speed = math.max(top.speed, tonumber(car.speed) or 0)
		top.accel = math.max(top.accel, tonumber(car.accel) or 0)
		top.turn = math.max(top.turn, (tonumber(car.turn) or 0) * (tonumber(car.drift) or 1))
		local tab = car.admin and "Admin" or (car.service and "Serviço" or (car.category == "Motos" and "Motos" or "Carros"))
		if not byTab[tab] then
			byTab[tab] = {}
		end
		table.insert(byTab[tab], car)
	end
	for _, t in ipairs({ "Carros", "Motos", "Serviço", "Admin" }) do -- Marco 9.16: "Admin" só aparece para os admins
		if byTab[t] then
			table.insert(tabs, t)
		end
	end
	if not byTab[lastTab] then
		lastTab = tabs[1] or "Carros"
	end

	-- Painel
	panel = Instance.new("Frame")
	panel.Name = "Garagem"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(780, 470)
	panel.BackgroundColor3 = Color3.new(1, 1, 1)
	panel.Parent = gui
	corner(panel, 18)
	stroke(panel, Color3.fromRGB(90, 120, 200), 2, 0.4)
	local bg = Instance.new("UIGradient")
	bg.Color = ColorSequence.new(BG_TOP, BG_BOTTOM)
	bg.Rotation = 90
	bg.Parent = panel
	UIScaler.attach(panel)

	-- Cabeçalho: título, saldo e fechar
	label(panel, data.dealership and "CONCESSIONÁRIA" or "MINHA GARAGEM", UDim2.fromOffset(470, 32), UDim2.fromOffset(22, 14), 23, Color3.new(1, 1, 1), Enum.Font.GothamBlack)
	local chip = Instance.new("Frame")
	chip.BackgroundColor3 = Color3.fromRGB(30, 90, 55)
	chip.Size = UDim2.fromOffset(150, 30)
	chip.Position = UDim2.new(1, -212, 0, 15)
	chip.Parent = panel
	corner(chip, 15)
	stroke(chip, GREEN, 1.5, 0.2)
	label(chip, money(balance), UDim2.fromScale(1, 1), UDim2.new(), 16, Color3.fromRGB(150, 255, 170), Enum.Font.GothamBlack, Enum.TextXAlignment.Center)
	button(panel, "X", RED, UDim2.fromOffset(40, 34), UDim2.new(1, -54, 0, 13), 18).Activated:Connect(close)

	-- Lado esquerdo: vitrine do veículo escolhido
	local show = Instance.new("Frame")
	show.BackgroundColor3 = Color3.fromRGB(12, 16, 30)
	show.BackgroundTransparency = 0.2
	show.Size = UDim2.fromOffset(430, 330)
	show.Position = UDim2.fromOffset(18, 60)
	show.Parent = panel
	corner(show, 14)
	-- "chão" brilhante embaixo do veículo
	local floor = Instance.new("Frame")
	floor.AnchorPoint = Vector2.new(0.5, 0.5)
	floor.BackgroundColor3 = Color3.fromRGB(90, 130, 255)
	floor.BackgroundTransparency = 0.75
	floor.Size = UDim2.fromOffset(300, 34)
	floor.Position = UDim2.new(0.5, 0, 0, 160)
	floor.Parent = show
	corner(floor, 17)
	local stage = Instance.new("ViewportFrame")
	stage.BackgroundTransparency = 1
	stage.Size = UDim2.new(1, 0, 0, 190)
	stage.Ambient = Color3.fromRGB(170, 175, 190)
	stage.LightColor = Color3.fromRGB(255, 250, 240)
	stage.LightDirection = Vector3.new(-1, -2, -1)
	stage.Parent = show

	local info = Instance.new("Frame")
	info.BackgroundTransparency = 1
	info.Size = UDim2.new(1, -32, 0, 136)
	info.Position = UDim2.fromOffset(16, 190)
	info.Parent = show

	-- Lado direito: abas e lista de cartões
	local tabBar = Instance.new("Frame")
	tabBar.BackgroundTransparency = 1
	tabBar.Size = UDim2.fromOffset(300, 34)
	tabBar.Position = UDim2.fromOffset(462, 60)
	tabBar.Parent = panel
	local list = Instance.new("ScrollingFrame")
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Size = UDim2.fromOffset(304, 288)
	list.Position = UDim2.fromOffset(460, 102)
	list.ScrollBarThickness = 6
	list.ScrollBarImageColor3 = Color3.fromRGB(120, 140, 200)
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list

	local cards = {}

	local function select(car)
		for c, card in pairs(cards) do
			local on = c == car
			card.frame.BackgroundColor3 = on and CARD_ON or CARD
			card.stroke.Transparency = on and 0 or 0.65
			card.stroke.Thickness = on and 2.5 or 1.5
		end
		-- vitrine: o veículo girando
		stage:ClearAllChildren()
		spinning = showModel(stage, car.id, math.rad(-40), 1.0)
		if spinning then
			spinning.angle = math.rad(-40)
		end
		-- informações
		info:ClearAllChildren()
		local rarityColor = car.service and SERVICE_COLOR or (RARITY[car.rarity] or RARITY["Comum"])
		label(info, tostring(car.name), UDim2.new(1, -120, 0, 30), UDim2.fromOffset(0, 0), 26, Color3.new(1, 1, 1), Enum.Font.GothamBlack)
		local badge = Instance.new("TextLabel")
		badge.AutomaticSize = Enum.AutomaticSize.X
		badge.Size = UDim2.fromOffset(0, 22)
		badge.AnchorPoint = Vector2.new(1, 0)
		badge.Position = UDim2.new(1, 0, 0, 5)
		badge.BackgroundColor3 = rarityColor
		badge.Font = Enum.Font.GothamBlack
		badge.TextSize = 13
		badge.TextColor3 = Color3.fromRGB(20, 20, 30)
		badge.Text = "  " .. string.upper(car.service and "Serviço" or tostring(car.rarity or "Comum")) .. "  "
		badge.Parent = info
		corner(badge, 11)
		statBar(info, "Velocidade", (tonumber(car.speed) or 0) / top.speed, 38, Color3.fromRGB(255, 200, 60))
		statBar(info, "Aceleração", (tonumber(car.accel) or 0) / top.accel, 58, Color3.fromRGB(255, 120, 70))
		statBar(info, "Curva e drift", (tonumber(car.turn) or 0) * (tonumber(car.drift) or 1) / top.turn, 78, Color3.fromRGB(90, 200, 255))
		-- botão grande
		if car.owned == true then
			local text = data.current == car.id and "Retirar de novo" or "Retirar"
			button(info, text, GREEN, UDim2.new(1, 0, 0, 36), UDim2.fromOffset(0, 100), 18).Activated:Connect(function()
				send({ op = "Car", car = car.id, garage = data.garage })
			end)
		elseif data.dealership then
			local price = tonumber(car.price) or 0
			local canPay = balance >= price
			local text = (canPay and "Comprar por " or "Falta dinheiro: ") .. money(price)
			local buy = button(info, text, canPay and ORANGE or GRAY, UDim2.new(1, 0, 0, 36), UDim2.fromOffset(0, 100), 18)
			if canPay then
				buy.Activated:Connect(function()
					if buy:GetAttribute("Confirmed") then
						send({ op = "Buy", car = car.id, garage = data.garage })
					else
						buy:SetAttribute("Confirmed", true)
						buy.Text = "Confirmar compra: " .. money(price)
					end
				end)
			end
		end
	end

	local function fillList(tab)
		lastTab = tab
		for _, child in ipairs(list:GetChildren()) do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		cards = {}
		for i, car in ipairs(byTab[tab] or {}) do
			local rarityColor = car.service and SERVICE_COLOR or (RARITY[car.rarity] or RARITY["Comum"])
			local frame = Instance.new("TextButton")
			frame.Text = ""
			frame.AutoButtonColor = false
			frame.BackgroundColor3 = CARD
			frame.Size = UDim2.new(1, -10, 0, 70)
			frame.LayoutOrder = i
			frame.Parent = list
			corner(frame, 12)
			local s = stroke(frame, rarityColor, 1.5, 0.65)
			local thumb = Instance.new("ViewportFrame")
			thumb.BackgroundColor3 = Color3.fromRGB(16, 22, 40)
			thumb.Size = UDim2.fromOffset(96, 58)
			thumb.Position = UDim2.fromOffset(6, 6)
			thumb.Ambient = Color3.fromRGB(170, 175, 190)
			thumb.LightDirection = Vector3.new(-1, -2, -1)
			thumb.Parent = frame
			corner(thumb, 9)
			showModel(thumb, car.id, math.rad(-35), 0.95)
			label(frame, tostring(car.name), UDim2.new(1, -116, 0, 22), UDim2.fromOffset(110, 8), 17)
			label(frame, car.service and "Serviço" or tostring(car.rarity or "Comum"), UDim2.new(1, -116, 0, 16), UDim2.fromOffset(110, 30), 13, rarityColor)
			if car.owned == true then
				label(frame, data.current == car.id and "NA RUA" or "SEU", UDim2.new(1, -116, 0, 16), UDim2.fromOffset(110, 48), 13, Color3.fromRGB(120, 230, 140), Enum.Font.GothamBlack)
			else
				local price = tonumber(car.price) or 0
				local color = balance >= price and Color3.fromRGB(255, 200, 90) or Color3.fromRGB(150, 155, 170)
				label(frame, money(price), UDim2.new(1, -116, 0, 16), UDim2.fromOffset(110, 48), 13, color, Enum.Font.GothamBlack)
			end
			cards[car] = { frame = frame, stroke = s }
			frame.Activated:Connect(function()
				select(car)
			end)
		end
		local first = (byTab[tab] or {})[1]
		if first then
			select(first)
		else
			info:ClearAllChildren()
			label(info, ("Você ainda não comprou veículos.\nVisite a %s (🚘 no mapa).\nA bicicleta continua disponível abaixo."):format(GameConfig.Dealership and GameConfig.Dealership.Name or "concessionária"), UDim2.fromScale(1, 1), UDim2.new(), 16, TEXT_SOFT)
		end
	end

	-- Abas
	local tabButtons = {}
	local function paintTabs()
		for t, b in pairs(tabButtons) do
			b.BackgroundColor3 = t == lastTab and BLUE or Color3.fromRGB(36, 46, 74)
			b.TextColor3 = t == lastTab and Color3.new(1, 1, 1) or TEXT_SOFT
		end
	end
	local w = math.floor((300 - (#tabs - 1) * 6) / math.max(#tabs, 1))
	for i, t in ipairs(tabs) do
		local b = button(tabBar, t, BLUE, UDim2.fromOffset(w, 32), UDim2.fromOffset((i - 1) * (w + 6), 0), 15)
		tabButtons[t] = b
		b.Activated:Connect(function()
			fillList(t)
			paintTabs()
		end)
	end
	paintTabs()

	-- Rodapé: bike e guardar
	local bikeText = data.onBike and "Você já está de bike" or "Bicicleta (grátis)"
	local bike = button(panel, bikeText, data.onBike and GRAY or Color3.fromRGB(46, 150, 200), UDim2.fromOffset(212, 46), UDim2.fromOffset(18, 404), 16)
	if not data.onBike then
		bike.Activated:Connect(function()
			send({ op = "Bike", garage = data.garage })
		end)
	end
	local canStore = data.hasCar or data.onBike
	local store = button(panel, "Guardar meu veículo", canStore and BLUE or GRAY, UDim2.fromOffset(212, 46), UDim2.fromOffset(236, 404), 16)
	if canStore then
		store.Activated:Connect(function()
			send({ op = "Store", garage = data.garage })
		end)
	end
	label(panel, data.testMode and "STUDIO: veículos liberados" or (data.dealership and "Compra única • retirada nas vagas" or "Seus veículos • compras na concessionária"), UDim2.fromOffset(300, 46), UDim2.fromOffset(462, 404), 14, TEXT_SOFT, Enum.Font.Gotham, Enum.TextXAlignment.Center)

	fillList(lastTab)
end

function GarageController.init()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	vehicleRequest = remotes:WaitForChild(GameConfig.Remotes.VehicleRequest)
	gui = Instance.new("ScreenGui")
	gui.Name = "GarageUI"
	gui.ResetOnSpawn = false
	gui.Parent = player:WaitForChild("PlayerGui")
	RunService.RenderStepped:Connect(function(dt)
		-- veículo da vitrine girando devagar
		if spinning then
			spinning.angle = (spinning.angle or 0) + dt * 0.6
			spinning.aim(spinning.angle)
		end
		-- andou para longe da guarita: fecha o menu
		if not panel or not openedAt then
			return
		end
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not root or (root.Position - openedAt).Magnitude > 14 then
			close()
		end
	end)
end

return GarageController
