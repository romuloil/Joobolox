-- DealershipBuilder (ModuleScript)
-- Caminho: ServerScriptService > Services > DealershipBuilder
-- Marco 10.31: concessionária de luxo no quadrado antigo da MigueLândia (fim da Avenida dos Motores,
-- saindo do anel externo, pertinho da cidade). O prédio é o modelo que o Romin achou
-- (ServerStorage > StructureModels > DealershipTemplate > Dealer), inteiro e sem escala. O estacionamento gigante
-- que vinha junto (ParkingLot) saiu: aqui em volta é tudo feito por script, no tamanho do lote:
--   * frente: pista de acesso, praça de granito com tapete vermelho até a porta, 4 carros girando
--     em plataformas (DealershipController gira no aparelho de cada um), totem com o nome;
--   * lado da oficina: 5 vagas de RETIRADA (2 na porta da oficina): o carro comprado sai ali;
--   * outro lado: estacionamento dos clientes com vagas pintadas;
--   * palmeiras, bandeiras, luzes e um consultor no balcão.
-- Se o modelo não estiver no ServerStorage, monta um showroom de vidro simples no lugar.
--
-- Coordenadas do lote (lot): -Z = frente (avenida), +X/-X = lados. Lote de 440 x 440.

local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))
local CarBuilder = require(script.Parent:WaitForChild("CarBuilder"))

local DealershipBuilder = {}

local DC = GameConfig.Dealership
local K
local lot -- CFrame do centro do lote
local HALF = 220

local GOLD = Color3.fromRGB(212, 175, 90)
local BLACK = Color3.fromRGB(22, 22, 26)
local GRANITE = Color3.fromRGB(38, 38, 44)
local MARBLE = Color3.fromRGB(236, 234, 228)
local ASPHALT = Color3.fromRGB(52, 54, 58)
local WHITE = Color3.fromRGB(248, 248, 246)
local RED_CARPET = Color3.fromRGB(150, 20, 30)
local YELLOW = Color3.fromRGB(245, 200, 40)

-- Quadro do modelo do Romin: transforma o chão do prédio importado (o mesmo do arquivo dele)
local SOURCE = CFrame.new(813.3833618164062, 2447.85, 2723.642578125,
	0.8191261887550354, 0.01924167014658451, -0.5732919573783875,
	-0.015500071458518505, 0.9998154044151306, 0.011410599574446678,
	0.573405921459198, -0.00046042288886383176, 0.8192729949951172)
-- No modelo, a fachada fica em +Z (z = 80) e o centro em x = -6.5. Aqui: fachada virada para a
-- avenida (-Z do lote), a 75 studs da frente; o chão do prédio na altura da praça.
local PLACE = CFrame.new(0, 0.75, -65) * CFrame.Angles(0, math.pi, 0) * CFrame.new(6.5, 0, 0)

-- textos em inglês do modelo -> português (e a pichação some)
local TEXTS = {
	["The Gv Gangster Was Here"] = "",
	["NEW STORY COMING AT 10:"] = "NOVIDADES TODA SEMANA",
	["CURRENT TIME:"] = "HORÁRIO:",
	["CAR MEET IN TOWN TONIGHT!"] = "ENCONTRO DE CARROS HOJE À NOITE!",
	["Printer on STANDBY"] = "Impressora em espera",
	["Scanner on STANDBY"] = "Scanner em espera",
}

local function at(x, y, z)
	return lot * CFrame.new(x, y, z)
end

local function P(parent, name, size, cf, color, material, extra)
	local props = { Name = name, Size = size, CFrame = cf, Color = color, Material = material or Enum.Material.SmoothPlastic }
	for k, v in pairs(extra or {}) do
		props[k] = v
	end
	return K.makePart(parent, props)
end

-- retângulo no chão do lote, de (x0, z0) a (x1, z1), topo em y1
local function slab(parent, name, x0, x1, z0, z1, y0, y1, color, material, extra)
	return P(parent, name, Vector3.new(x1 - x0, y1 - y0, z1 - z0), at((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), color, material, extra)
end

local function noCollide(extra)
	extra = extra or {}
	extra.CanCollide = false
	return extra
end

local function signText(part, text, color, bg, font)
	K.addSurfaceText(part, text, color, bg)
	if font then
		local gui = part:FindFirstChildOfClass("SurfaceGui")
		local label = gui and gui:FindFirstChildOfClass("TextLabel")
		if label then
			label.Font = font
		end
	end
end

---------------------------------------------------------------------------
-- Prédio do modelo
---------------------------------------------------------------------------

local function connectDoor(model)
	local panel = model:FindFirstChild("interiordoorpanel")
	local garage = model.Name == "DEALERGARAGE"
	if garage then
		panel = model:FindFirstChildWhichIsA("BasePart")
	end
	if not panel then
		return
	end
	local parts = {}
	for _, p in ipairs(model:GetChildren()) do
		if p:IsA("BasePart") and (garage or p == panel or p:IsA("UnionOperation")) then
			table.insert(parts, { p = p, cf = p.CFrame })
		end
	end
	local origin = panel.CFrame
	local hinge = origin * CFrame.new(0, 0, -panel.Size.Z / 2)
	local openT = garage and CFrame.new(0, math.max(panel.Size.Y, 12) + 1, 0) or hinge * CFrame.Angles(0, math.rad(95), 0) * hinge:Inverse()
	local anchor = Instance.new("Part")
	anchor.Name = "ComandoPorta"
	anchor.Size = Vector3.new(0.3, 0.3, 0.3)
	anchor.CFrame = origin
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanTouch = false
	anchor.CanQuery = false
	anchor.Parent = model
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "PortaConcessionaria"
	prompt.ActionText = "Abrir"
	prompt.ObjectText = garage and "Portão da oficina" or "Porta"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = anchor
	local opened, busy = false, false
	prompt.Triggered:Connect(function(player)
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if busy or not root or (root.Position - anchor.Position).Magnitude > 13 then
			return
		end
		opened = not opened
		busy = true
		prompt.ActionText = opened and "Fechar" or "Abrir"
		for _, e in ipairs(parts) do
			TweenService:Create(e.p, TweenInfo.new(0.65), { CFrame = opened and openT * e.cf or e.cf }):Play()
		end
		task.delay(0.7, function()
			busy = false
		end)
	end)
end

local function placeTemplate(site)
	-- lugar certo: ServerStorage > StructureModels > DealershipTemplate (igual BankModels/CarModels);
	-- se estiver em outra pasta do ServerStorage, acha do mesmo jeito
	local folder = ServerStorage:FindFirstChild("StructureModels")
	local template = (folder and folder:FindFirstChild("DealershipTemplate")) or ServerStorage:FindFirstChild("DealershipTemplate", true)
	local src = template and template:FindFirstChild("Dealer")
	if not src then
		return nil
	end
	local dealer = src:Clone()
	dealer.Name = "Predio"
	-- o estacionamento gigante que veio com o modelo sai (aqui o entorno é feito por script)
	for _, d in ipairs(dealer:GetDescendants()) do
		if d.Name == "ParkingLot" and d.Parent then
			d:Destroy()
		end
	end
	local logos = 0
	local list = dealer:GetDescendants()
	for i, d in ipairs(list) do
		if d:IsA("LuaSourceContainer") or d:IsA("ProximityPrompt") or d:IsA("ClickDetector") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = true
			d.CanTouch = false
			d.AssemblyLinearVelocity = Vector3.zero
		elseif d:IsA("TextLabel") then
			local new = TEXTS[d.Text]
			if new then
				d.Text = new
				if new == "" then
					d.Visible = false
				end
			end
		elseif d:IsA("SurfaceGui") and d.Name == "Logo" then
			-- logotipo da loja original -> nome da nossa
			for _, c in ipairs(d:GetChildren()) do
				if c:IsA("ImageLabel") then
					c.Visible = false
				end
			end
			local label = Instance.new("TextLabel")
			label.Name = "NomeLoja"
			label.Size = UDim2.fromScale(1, 1)
			label.BackgroundTransparency = 1
			label.TextScaled = true
			label.Font = Enum.Font.GothamBlack
			label.TextColor3 = GOLD
			label.Text = string.upper(DC.Name)
			label.Parent = d
			logos += 1
		end
		if i % 800 == 0 then
			task.wait()
		end
	end
	-- leva o prédio para o lote (um movimento só, sem escala)
	local move = lot * PLACE * SOURCE:Inverse()
	dealer:PivotTo(move * dealer:GetPivot())
	dealer.Parent = site
	for _, m in ipairs(dealer:GetDescendants()) do
		if m:IsA("Model") and (m.Name == "door" or m.Name == "DEALERGARAGE") then
			pcall(connectDoor, m)
		end
	end
	-- relógio das TVs: hora do jogo
	local clocks = {}
	for _, d in ipairs(dealer:GetDescendants()) do
		if d:IsA("TextLabel") and d.Text:match("^%d+:%d+ [AP]M$") then
			table.insert(clocks, d)
		end
	end
	if #clocks > 0 then
		task.spawn(function()
			while dealer.Parent do
				local t = Lighting.ClockTime
				local text = ("%02d:%02d"):format(math.floor(t), math.floor((t % 1) * 60))
				for _, c in ipairs(clocks) do
					c.Text = text
				end
				task.wait(20)
			end
		end)
	end
	dealer:SetAttribute("Logos", logos)
	return dealer
end

-- Sem o modelo: showroom de vidro simples no mesmo lugar (o jogo funciona igual)
local function fallbackShowroom(site)
	local f = K.model("Predio", site)
	local W, D, H = 200, 150, 22
	local z0 = -145
	slab(f, "Piso", -W / 2, W / 2, z0, z0 + D, 0, 0.75, MARBLE, Enum.Material.Marble)
	slab(f, "Fundo", -W / 2, W / 2, z0 + D - 2, z0 + D, 0.75, H, WHITE, Enum.Material.Plaster)
	slab(f, "Lado", -W / 2, -W / 2 + 2, z0, z0 + D, 0.75, H, WHITE, Enum.Material.Plaster)
	slab(f, "Lado", W / 2 - 2, W / 2, z0, z0 + D, 0.75, H, WHITE, Enum.Material.Plaster)
	slab(f, "Teto", -W / 2 - 4, W / 2 + 4, z0 - 6, z0 + D, H, H + 2, BLACK, Enum.Material.Metal)
	for x = -W / 2 + 2, W / 2 - 12, 20 do
		if math.abs(x + 10 - 38.5) > 12 then
			slab(f, "Vidro", x, x + 20, z0, z0 + 0.6, 0.75, H, Color3.fromRGB(150, 190, 210), Enum.Material.SmoothPlastic, { Transparency = 0.55 })
		end
		slab(f, "Montante", x - 0.4, x + 0.4, z0 - 0.2, z0 + 0.8, 0.75, H, BLACK, Enum.Material.Metal)
	end
	slab(f, "Balcao", 28, 50, -118, -112, 0.75, 4.2, BLACK, Enum.Material.Granite)
	slab(f, "TampoBalcao", 27, 51, -118.5, -111.5, 4.2, 4.6, GOLD, Enum.Material.Metal)
	-- portão da oficina
	slab(f, "Oficina", -128, -64, z0, z0 + 80, 0.75, 18, Color3.fromRGB(200, 200, 205), Enum.Material.Concrete)
	return f
end

---------------------------------------------------------------------------
-- Entorno
---------------------------------------------------------------------------

local function palmPlanter(parent, x, z, scale)
	slab(parent, "Vaso", x - 3, x + 3, z - 3, z + 3, 0.6, 2.6, BLACK, Enum.Material.Granite)
	slab(parent, "VasoBorda", x - 3.2, x + 3.2, z - 3.2, z + 3.2, 2.6, 2.9, GOLD, Enum.Material.Metal)
	if K.palm then
		K.palm(parent, (at(x, 2.9, z)).Position, scale)
	end
end

local function flag(parent, x, z, color)
	local pole = P(parent, "Mastro", Vector3.new(26, 0.5, 0.5), at(x, 0.6 + 13, z) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(220, 220, 225), Enum.Material.Metal, { Shape = Enum.PartType.Cylinder })
	P(parent, "Bandeira", Vector3.new(0.15, 10, 4.5), at(x, 0.6 + 20, z + 2.4), color, Enum.Material.Fabric, noCollide())
	return pole
end

local function money(n)
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1."):reverse()
	return (out:gsub("^%.", ""))
end

local function turntable(parent, x, z, carId)
	local spec = GameConfig.Cars[carId]
	local center = at(x, 0, z)
	local base = K.flatCylinder(parent, "Plataforma", center.Position + Vector3.new(0, 1, 0), 14, 0.9, GRANITE, Enum.Material.Granite)
	K.flatCylinder(parent, "AneloOuro", center.Position + Vector3.new(0, 0.85, 0), 14.6, 0.5, GOLD, Enum.Material.Metal)
	local glow = K.flatCylinder(parent, "LuzBase", center.Position + Vector3.new(0, 0.7, 0), 15.2, 0.2, Color3.fromRGB(255, 235, 190), Enum.Material.Neon)
	glow.CanCollide = false
	base:SetAttribute("Giratorio", true)
	if not spec then
		return
	end
	local ok, car = pcall(CarBuilder.build, spec, CFrame.new(center.Position + Vector3.new(0, 1.45 + (spec.Hover or 2), 0)) * lot.Rotation * CFrame.Angles(0, math.rad(30), 0))
	if not ok or not car then
		warn("[Concessionária] Carro de exposição " .. tostring(carId) .. ": " .. tostring(car))
		return
	end
	car.Name = "Exposicao_" .. carId
	for _, d in ipairs(car:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanTouch = false
			if d:IsA("Seat") or d:IsA("VehicleSeat") then
				d.Disabled = true
			end
		elseif d:IsA("ProximityPrompt") or d:IsA("LuaSourceContainer") or d:IsA("Constraint") then
			d:Destroy()
		end
	end
	car:SetAttribute("Exposicao", true)
	car:SetAttribute("Centro", center.Position)
	car:SetAttribute("Velocidade", DC.TurntableSpeed or 0.25)
	car.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	car.Parent = parent
	game:GetService("CollectionService"):AddTag(car, "VitrineGiratoria")
	-- plaquinha com o preço
	local plate = P(parent, "Preco", Vector3.new(12, 2.2, 0.3), at(x, 2.2, z - 16.5) * CFrame.Angles(math.rad(-15), 0, 0), BLACK, Enum.Material.SmoothPlastic, noCollide())
	signText(plate, ("%s  •  %s%s"):format(tostring(spec.Name or carId), GameConfig.Economy.CurrencySymbol, money(spec.Price or 0)), GOLD, BLACK)
	slab(parent, "PePlaca", x - 0.2, x + 0.2, z - 16.6, z - 16.4, 0, 1.2, GOLD, Enum.Material.Metal)
end

local function bay(parent, garage, k, x, z, label)
	-- caixa amarela pintada e número; o marcador VagaN fica no meio (carro de frente para a avenida)
	for _, sx in ipairs({ -6, 6 }) do
		slab(parent, "FaixaVaga", x + sx - 0.25, x + sx + 0.25, z - 11, z + 11, 0.62, 0.66, YELLOW, nil, noCollide())
	end
	slab(parent, "FaixaVaga", x - 6, x + 6, z + 10.75, z + 11.25, 0.62, 0.66, YELLOW, nil, noCollide())
	local num = P(parent, "NumeroVaga", Vector3.new(6, 0.05, 3), at(x, 0.67, z + 7), YELLOW, nil, noCollide())
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 30
	gui.Parent = num
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.Text = label
	t.TextScaled = true
	t.Font = Enum.Font.GothamBlack
	t.TextColor3 = BLACK
	t.Rotation = 180
	t.Parent = gui
	local marker = K.makePart(garage, { Name = "Vaga" .. k, Size = Vector3.new(1, 1, 1), CFrame = at(x, 1.3, z), Transparency = 1, CanCollide = false })
	marker.CanQuery = false
	marker.CanTouch = false
end

-- lot = { lot = CFrame do centro (frente -Z para a avenida), size, roadEnd, dir }
function DealershipBuilder.build(map, info, helpers)
	K = helpers
	lot = info.lot
	HALF = (info.size or 440) / 2
	local site = K.model("Concessionaria", map)
	site:SetAttribute("PlaceName", DC.Name)
	local curbPos = (at(-26, 0.8, -HALF - 10)).Position
	site:SetAttribute("Curb", CFrame.lookAt(curbPos, curbPos + lot.RightVector))

	-- piso: pista de acesso, área de retirada, praça de granito e estacionamento dos clientes
	local ground = K.model("Piso", site)
	slab(ground, "PistaAcesso", -HALF, HALF, -HALF, -198, 0, 0.6, ASPHALT, Enum.Material.Asphalt)
	slab(ground, "AreaRetirada", -HALF, -60, -198, -140, 0, 0.6, ASPHALT, Enum.Material.Asphalt)
	slab(ground, "Praca", -60, HALF, -198, -145, 0, 0.62, GRANITE, Enum.Material.Granite)
	slab(ground, "BordaPraca", -60, HALF, -198.6, -197.4, 0.62, 0.9, MARBLE, Enum.Material.Marble)
	slab(ground, "Tapete", 32.5, 44.5, -197.4, -145, 0.62, 0.68, RED_CARPET, Enum.Material.Carpet)
	slab(ground, "LadoClientes", 129, HALF, -145, HALF, 0, 0.6, ASPHALT, Enum.Material.Asphalt)
	slab(ground, "LadoOficina", -HALF, -129, -140, HALF, 0, 0.6, ASPHALT, Enum.Material.Asphalt)
	slab(ground, "Fundos", -129, 129, 150, HALF, 0, 0.6, ASPHALT, Enum.Material.Asphalt)
	-- faixa central da pista de acesso e setas
	slab(ground, "Faixa", -HALF + 10, HALF - 10, -209.2, -208.8, 0.6, 0.63, WHITE, nil, noCollide())
	-- vagas dos clientes (dos dois lados do corredor)
	for z = -128, HALF - 16, 13 do
		for _, xs in ipairs({ { 129, 149 }, { HALF - 20, HALF } }) do
			slab(ground, "FaixaCliente", xs[1], xs[2], z - 0.2, z + 0.2, 0.6, 0.63, WHITE, nil, noCollide())
		end
	end
	task.wait()

	-- prédio
	local building = placeTemplate(site)
	if not building then
		warn("[Concessionária] ServerStorage > StructureModels > DealershipTemplate não encontrado: montando um showroom simples. Veja o GUIA do Marco 10.31.")
		fallbackShowroom(site)
	end
	task.wait()

	-- frente: canteiros com palmeiras (abertura só no meio, de frente para a avenida), totem e bandeiras
	local deco = K.model("Fachada", site)
	for x = -HALF + 8, HALF - 8, 28 do
		if math.abs(x) > 24 and x ~= 40 then -- o canteiro do x = 40 vira o totem
			slab(deco, "Canteiro", x - 12, x + 12, -HALF + 1, -HALF + 6, 0.6, 1.6, Color3.fromRGB(60, 130, 60), Enum.Material.Grass)
			slab(deco, "MeioFio", x - 12, x + 12, -HALF + 0.5, -HALF + 1, 0.6, 1.8, MARBLE, Enum.Material.Marble)
			palmPlanter(deco, x, -HALF + 3.5, 1.3)
		end
	end
	local colors = { GOLD, BLACK, WHITE }
	for i, x in ipairs({ -50, -35, 110, 125, 140, 155, 170, 185, 200 }) do
		flag(deco, x, -196, colors[(i - 1) % #colors + 1])
	end
	-- totem
	-- totem na linha dos canteiros (fora da pista de acesso)
	slab(deco, "TotemBase", 32, 48, -219.5, -213.5, 0.6, 2, MARBLE, Enum.Material.Marble)
	local totem = slab(deco, "Totem", 34, 46, -217.5, -215.5, 2, 40, BLACK, Enum.Material.Granite)
	slab(deco, "TotemOuro", 33.6, 46.4, -217.9, -215.1, 39.5, 40.5, GOLD, Enum.Material.Metal)
	for _, sx in ipairs({ 33.6, 46.4 }) do
		slab(deco, "TotemNeon", sx - 0.2, sx + 0.2, -217.9, -215.1, 2, 40, Color3.fromRGB(255, 225, 160), Enum.Material.Neon, noCollide())
	end
	local face = P(deco, "TotemNome", Vector3.new(11, 30, 0.2), at(40, 22, -217.65), BLACK, Enum.Material.SmoothPlastic, noCollide())
	signText(face, string.upper(DC.Name):gsub(" ", "\n"), GOLD, BLACK, Enum.Font.Bodoni)
	totem:SetAttribute("Totem", true)
	-- letreiro grande acima da fachada
	local fascia = P(deco, "Letreiro", Vector3.new(110, 8, 0.6), at(30, 37, -147), BLACK, Enum.Material.Metal, noCollide())
	signText(fascia, string.upper(DC.Name), GOLD, BLACK, Enum.Font.Bodoni)
	slab(deco, "LetreiroBorda", -25.4, 85.4, -147.6, -147.2, 32.6, 41.4, GOLD, Enum.Material.Metal, noCollide())
	-- coluna para o letreiro não flutuar (some atrás da fachada)
	for _, sx in ipairs({ -15, 75 }) do
		slab(deco, "Suporte", sx - 0.4, sx + 0.4, -146.6, -145, 30, 33, BLACK, Enum.Material.Metal)
	end
	-- porta: toldo dourado e postes baixos com corrente
	slab(deco, "Marquise", 26, 51, -160, -145, 12, 12.8, BLACK, Enum.Material.Metal)
	slab(deco, "MarquiseOuro", 26, 51, -160.4, -159.6, 11.6, 13.2, GOLD, Enum.Material.Metal, noCollide())
	for _, sx in ipairs({ 30, 47 }) do
		for _, z in ipairs({ -192, -180, -168 }) do
			slab(deco, "Pilarete", sx - 0.4, sx + 0.4, z - 0.4, z + 0.4, 0.62, 3.6, GOLD, Enum.Material.Metal)
		end
	end
	-- luzes de chão na praça (só algumas acesas: limite de luzes)
	for i, x in ipairs({ -40, 0, 80, 120, 160, 200 }) do
		local up = slab(deco, "Refletor", x - 1, x + 1, -147, -145.5, 0.62, 1.2, BLACK, Enum.Material.Metal)
		if i % 2 == 0 then
			local l = Instance.new("SpotLight")
			l.Face = Enum.NormalId.Top
			l.Angle = 70
			l.Range = 30
			l.Brightness = 2
			l.Color = Color3.fromRGB(255, 230, 190)
			l.Parent = up
		end
	end

	-- carros girando na praça
	local display = K.model("Vitrine", site)
	local spots = { { -20, -172 }, { 88, -172 }, { 144, -172 }, { 198, -172 } }
	for i, s in ipairs(spots) do
		local id = (DC.Display or {})[i]
		if id then
			turntable(display, s[1], s[2], id)
		end
		if i % 2 == 0 then
			task.wait()
		end
	end

	-- garagens: concessionária (balcão = consultor) e retirada (quiosque perto das vagas)
	local garages = map:FindFirstChild("Garages") or K.folder("Garages", map)
	local function makeGarage(name, place, dealership, boothCf)
		local g = K.model(name, garages)
		g:SetAttribute("Garage", true)
		g:SetAttribute("Dealership", dealership)
		g:SetAttribute("PlaceName", place)
		g:SetAttribute("SalesPosition", boothCf.Position)
		g:SetAttribute("Curb", site:GetAttribute("Curb"))
		local booth = K.makePart(g, { Name = "Balcao", Size = Vector3.new(2, 0.4, 2), CFrame = boothCf, Color = GOLD, Material = Enum.Material.Metal, Transparency = 1, CanCollide = false })
		booth.CanQuery = false
		return g
	end
	-- balcão do modelo fica em (38.5, ?, -115) no lote; sem o modelo, no balcão do showroom
	local sales = makeGarage("ConcessionariaPrestige", DC.Name, true, at(38.5, 3.4, -112))
	local pickup = makeGarage("RetiradaPrestige", "Retirada " .. DC.Name, false, at(-56, 3.4, -170))
	pickup:SetAttribute("Retirada", true)
	-- quiosque da retirada
	slab(pickup, "Quiosque", -58, -54, -172, -168, 0.6, 5, BLACK, Enum.Material.Granite)
	local scr = P(pickup, "Tela", Vector3.new(3.6, 2.6, 0.2), at(-56, 6.2, -172.2), Color3.fromRGB(20, 40, 70), Enum.Material.SmoothPlastic, noCollide())
	signText(scr, "RETIRADA\nE GUARDAR", WHITE, Color3.fromRGB(20, 40, 70))
	-- 5 vagas de retirada: 3 no lado da oficina e 2 na porta dela
	local bays = { { -205, -165 }, { -180, -165 }, { -155, -165 }, { -111.5, -162 }, { -86.5, -162 } }
	for k, b in ipairs(bays) do
		bay(ground, sales, k, b[1], b[2], tostring(k))
		local m2 = K.makePart(pickup, { Name = "Vaga" .. k, Size = Vector3.new(1, 1, 1), CFrame = at(b[1], 1.3, b[2]), Transparency = 1, CanCollide = false })
		m2.CanQuery = false
		m2.CanTouch = false
	end
	local rs = P(ground, "PlacaRetirada", Vector3.new(30, 4, 0.4), at(-155, 9, -178), Color3.fromRGB(20, 40, 70), Enum.Material.Metal, noCollide())
	signText(rs, "🔑 RETIRADA DE VEÍCULOS", WHITE, Color3.fromRGB(20, 40, 70))
	for _, sx in ipairs({ -168, -142 }) do
		slab(ground, "PostePlaca", sx - 0.3, sx + 0.3, -178.3, -177.7, 0.6, 9, BLACK, Enum.Material.Metal)
	end

	-- pontos dos NPCs (o LitoralService põe o consultor, a recepcionista e o manobrista)
	local npcSpots = K.model("PontosNPC", site)
	for _, s in ipairs({ { "consultor", 38.5, -108, 0 }, { "recepcao", 52, -190, 0 }, { "manobrista", -70, -185, 90 } }) do
		local p = K.makePart(npcSpots, { Name = s[1], Size = Vector3.new(1, 1, 1), CFrame = at(s[2], 3.6, s[3]) * CFrame.Angles(0, math.rad(s[4]), 0), Transparency = 1, CanCollide = false })
		p.CanQuery = false
		p:SetAttribute("Papel", s[1])
	end
	site:SetAttribute("Template", building ~= nil)
	return site
end

return DealershipBuilder
