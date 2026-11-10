-- LitoralService (ModuleScript)
-- Caminho: ServerScriptService > Services > LitoralService
-- Marco 10.31: a vida da orla Costa do Sol (LitoralBuilder) e da concessionária (DealershipBuilder).
--   * Barracas de lanche: E = comprar (dinheiro limpo); o lanche vai para a mão e recupera vida.
--   * Academia da praia: E = malhar (o servidor põe o boneco no aparelho e todo mundo vê a pose).
--   * Bolas de vôlei e basquete soltas (voltam para a quadra se forem longe ou caírem no mar).
--   * NPCs: vendedores nas barracas, pescadores no píer, banhistas deitados, turistas andando no
--     calçadão e a equipe da concessionária (consultora, recepcionista, manobrista).
-- Tudo conferido no servidor: distância, dinheiro, frequência.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))
local EconomyService = require(script.Parent:WaitForChild("EconomyService"))
local ParkBuilder = require(script.Parent:WaitForChild("ParkBuilder"))
local NPCKit = require(script.Parent:WaitForChild("NPCKit"))
local RigMeasure = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("RigMeasure"))
local SurfWaves = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SurfWaves"))
local SurfBoards = require(script.Parent:WaitForChild("SurfBoards"))
local CollectionService = game:GetService("CollectionService")

local LitoralService = {}

local L = GameConfig.Litoral
local uiUpdate
local lastUse = {} -- lastUse[player] = os.clock()
local busyStation = {} -- busyStation[estação] = player

local function notice(player, text)
	if uiUpdate then
		uiUpdate:FireClient(player, "Notice", { text = text })
	end
end

local function rootOf(player)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not hum or not root or hum.Health <= 0 then
		return nil
	end
	return root, hum, char
end

local function near(player, part, dist)
	local root = rootOf(player)
	return root and (root.Position - part.Position).Magnitude <= dist
end

local function spam(player, gap)
	local now = os.clock()
	if lastUse[player] and now - lastUse[player] < gap then
		return true
	end
	lastUse[player] = now
	return false
end

local function prompt(parent, action, object, distance, hold)
	local p = Instance.new("ProximityPrompt")
	p.Name = "OrlaPrompt"
	p.ActionText = action
	p.ObjectText = object
	p.KeyboardKeyCode = Enum.KeyCode.E
	p.MaxActivationDistance = distance or 8
	p.HoldDuration = hold or 0
	p.RequiresLineOfSight = false
	p.Parent = parent
	return p
end

---------------------------------------------------------------------------
-- Lanches
---------------------------------------------------------------------------

local function setupSnack(counter)
	local kind = counter:GetAttribute("LitoralSnack")
	local snack = L.Snacks[kind]
	if not snack then
		return
	end
	local p = prompt(counter, ("Comprar ($%d)"):format(snack.Price), snack.Name, 9)
	p.Triggered:Connect(function(player)
		if spam(player, 1) or not near(player, counter, 13) then
			return
		end
		local _, hum, char = rootOf(player)
		if not hum then
			return
		end
		if char:FindFirstChild("CarriedItem") then
			notice(player, "🧺 Larga o que você está carregando antes de pegar um lanche.")
			return
		end
		if not EconomyService.spend(player, snack.Price, "Lanche da orla: " .. snack.Name) then
			notice(player, ("💸 Falta dinheiro: %s custa $%d."):format(snack.Name, snack.Price))
			return
		end
		if not ParkBuilder.giveSnack(player, kind) then
			EconomyService.add(player, snack.Price, "Lanche devolvido")
			return
		end
		hum.Health = math.min(hum.MaxHealth, hum.Health + (snack.Heal or 0))
		notice(player, ("😋 %s! +%d de vida."):format(snack.Name, snack.Heal or 0))
	end)
end

---------------------------------------------------------------------------
-- Academia
---------------------------------------------------------------------------

local GYM_TIME = 6 -- segundos por série
local GYM_TEXT = {
	barra = "💪 Barra fixa: subindo e descendo...",
	argola = "💪 Argolas: segura firme!",
	paralela = "💪 Paralelas: desce e sobe!",
	peso = "🏋️ Supino: empurra!",
}
local series = {} -- series[player] = séries nesta sessão

local function setupStation(spot)
	local kind = spot:GetAttribute("LitoralGym")
	local p = prompt(spot, "Malhar", spot:GetAttribute("GymLabel") or "Aparelho", 7)
	p.Triggered:Connect(function(player)
		if spam(player, L.GymCooldown or 0.6) or not near(player, spot, 11) then
			return
		end
		local holder = busyStation[spot]
		if holder and holder.Parent then
			if holder ~= player then
				notice(player, "⏳ Esse aparelho está ocupado. Tenta outro!")
			end
			return
		end
		local root, hum, char = rootOf(player)
		if not root or hum.Sit then
			return
		end
		busyStation[spot] = player
		p.Enabled = false
		local height = hum.HipHeight + root.Size.Y / 2
		local standing = spot.CFrame + Vector3.new(0, height + 0.15, 0)
		-- Marco 10.32: o boneco vai para o lugar certo do aparelho, medido pelo tamanho dele
		-- (pendurado na barra/argola, apoiado nas paralelas, deitado no supino). As mãos ficam no
		-- aparelho pelo PoseController (cálculo dos braços em todos os aparelhos).
		local alvo = spot:GetAttribute("Alvo")
		local m = RigMeasure.measure(char)
		local place = standing
		if typeof(alvo) == "CFrame" and m and m.rigType == "R15" then
			local arm = m.armL1 + m.armL2
			local shY = m.shoulder.Right.Y
			local look = alvo.LookVector
			if kind == "barra" or kind == "argola" then
				local pos = alvo.Position - Vector3.new(0, shY + arm * 0.97, 0) - look * 0.35
				place = CFrame.lookAt(pos, pos + look)
			elseif kind == "paralela" then
				local pos = alvo.Position + Vector3.new(0, arm * 0.95 - shY, 0)
				place = CFrame.lookAt(pos, pos + look)
			elseif kind == "peso" then
				local torso = char:FindFirstChild("UpperTorso")
				local back = torso and torso.Size.Z / 2 or 0.5
				local pos = alvo.Position - look * 1.2 + Vector3.new(0, back + 0.05, 0)
				place = CFrame.lookAt(pos, pos + Vector3.new(0, 1, 0), look) -- deitado, olhando para cima
			end
			char:SetAttribute("PoseAlvo", alvo)
		end
		char:PivotTo(place)
		root.Anchored = true
		NPCKit.pose(char, kind, GYM_TIME)
		series[player] = (series[player] or 0) + 1
		notice(player, ("%s  (%dª série)"):format(GYM_TEXT[kind] or "💪", series[player]))
		task.delay(GYM_TIME, function()
			if root.Parent then
				char:SetAttribute("PoseAlvo", nil)
				if place ~= standing then
					char:PivotTo(standing) -- desce do aparelho em pé
				end
				root.Anchored = false
			end
			busyStation[spot] = nil
			p.Enabled = true
		end)
	end)
end

---------------------------------------------------------------------------
-- Bolas soltas
---------------------------------------------------------------------------

local function watchBalls(balls)
	for _, ball in ipairs(balls) do
		ball:SetAttribute("Home", ball.CFrame)
		ball.Anchored = false
		ball.CanCollide = true
		if ball.Name == "BolaVolei" then
			ball.CustomPhysicalProperties = PhysicalProperties.new(0.12, 0.3, 0.75, 1, 1)
		else
			ball.CustomPhysicalProperties = PhysicalProperties.new(0.35, 0.4, 0.8, 1, 1)
		end
	end
	if #balls == 0 then
		return
	end
	task.spawn(function()
		while true do
			task.wait(5)
			for _, ball in ipairs(balls) do
				local home = ball:GetAttribute("Home")
				if ball.Parent and typeof(home) == "CFrame" then
					local away = (ball.Position - home.Position) * Vector3.new(1, 0, 1)
					if away.Magnitude > 90 or ball.Position.Y < home.Position.Y - 6 then
						ball.AssemblyLinearVelocity = Vector3.zero
						ball.AssemblyAngularVelocity = Vector3.zero
						ball.CFrame = home
					end
				end
			end
		end
	end)
end

---------------------------------------------------------------------------
-- NPCs
---------------------------------------------------------------------------

---------------------------------------------------------------------------
-- Marco 10.32: Escolinha de Surfe
--   * E numa prancha do cavalete = alugar ($ limpo). Ela vai para as costas do personagem.
--   * Entrou no mar entre as boias: o cliente deita na prancha (remando) e, quando a onda chega,
--     ESPAÇO fica em pé (surfando). O cliente controla o movimento; o servidor só guarda o estado
--     (para todo mundo ver a pose e a prancha no lugar certo) e confere os pontos antes de pagar.
---------------------------------------------------------------------------

local S = GameConfig.Surf
local surfers = {} -- surfers[player] = { state, since, rideStart, validRide, lastPay, changes, window }
local best = {} -- placar: { { name, points } } (as 5 melhores ondas do servidor)
local scoreLabels
local SURF_STATES = { carregando = true, remando = true, surfando = true, caiu = true }

-- onde a prancha fica em relação ao HumanoidRootPart em cada estado (C0 do PranchaMotor)
local function boardC0(state, hum, root)
	if state == "remando" then
		-- deitado de bruços: o HRP olha para baixo e o "em cima" dele aponta para onde ele rema
		return CFrame.new(0, -0.3, -0.7) * CFrame.Angles(math.rad(90), 0, 0)
	elseif state == "surfando" then
		-- em pé, de lado: o bico aponta para a direita do surfista (+X do HRP)
		local feet = (hum and hum.HipHeight or 2) + (root and root.Size.Y / 2 or 1)
		return CFrame.new(0, -feet - 0.16, 0) * CFrame.Angles(0, math.rad(-90), 0)
	elseif state == "caiu" then
		return CFrame.new(2.6, -0.9, 0) * CFrame.Angles(0, math.rad(-90), math.rad(25))
	end
	-- nas costas, bico para cima e as quilhas para fora
	return CFrame.fromMatrix(Vector3.new(0, 0.1, 0.85), Vector3.new(-1, 0, 0), Vector3.new(0, 0, -1), Vector3.new(0, -1, 0))
end

local function setSurfState(player, state)
	local s = surfers[player]
	local root, hum, char = rootOf(player)
	if not s or not char then
		return
	end
	if state == "surfando" and s.state ~= "surfando" then
		-- confere se tem mesmo uma onda passando perto dele
		s.rideStart = os.clock()
		s.validRide = false
		for _, w in ipairs(SurfWaves.active(Workspace:GetServerTimeNow())) do
			if math.abs(root.Position.Z - w.z) < 30 and w.a > 0.6 then
				s.validRide = true
			end
		end
	end
	s.state = state
	s.since = os.clock()
	char:SetAttribute("Surfe", state)
	local board = char:FindFirstChild("PranchaSurfe")
	local motor = board and board:FindFirstChild("PranchaMotor", true)
	if motor then
		motor.C0 = boardC0(state, hum, root)
	end
	if state == "remando" then
		NPCKit.pose(char, "remar")
	elseif state == "surfando" then
		NPCKit.pose(char, "surfar")
	else
		local pose = char:GetAttribute("Pose")
		if pose == "remar" or pose == "surfar" then
			char:SetAttribute("Pose", nil)
		end
	end
end

local function removeBoard(player)
	local char = player.Character
	local board = char and char:FindFirstChild("PranchaSurfe")
	if board then
		board:Destroy()
	end
	if char then
		char:SetAttribute("Prancha", nil)
		char:SetAttribute("Surfe", nil)
		CollectionService:RemoveTag(char, "Surfista")
		local pose = char:GetAttribute("Pose")
		if pose == "remar" or pose == "surfar" then
			char:SetAttribute("Pose", nil)
		end
	end
	surfers[player] = nil
end

local function giveBoard(player, styleIndex, paletteIndex)
	local root, hum, char = rootOf(player)
	if not root then
		return false
	end
	local old = char:FindFirstChild("PranchaSurfe")
	if old then
		old:Destroy()
	end
	local model, style = SurfBoards.build(styleIndex, paletteIndex)
	model.Name = "PranchaSurfe"
	local main = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	if not main then
		model:Destroy()
		return false
	end
	-- a prancha é feita em volta da origem (bico em -Z, deck em +Y), também a do modelo 3D:
	-- o C1 leva a peça principal até esse ponto (Part0 * C0 = Part1 * C1)
	local c1 = main.CFrame:ToObjectSpace(CFrame.identity)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = false
			d.Massless = true
			if d ~= main then
				local w = Instance.new("WeldConstraint")
				w.Part0 = main
				w.Part1 = d
				w.Parent = d
			end
		end
	end
	local motor = Instance.new("Motor6D")
	motor.Name = "PranchaMotor"
	motor.Part0 = root
	motor.Part1 = main
	motor.C0 = boardC0("carregando", hum, root)
	motor.C1 = c1
	model:PivotTo(root.CFrame * motor.C0)
	motor.Parent = main
	model.Parent = char
	char:SetAttribute("Prancha", style.name)
	CollectionService:AddTag(char, "Surfista")
	surfers[player] = { state = "carregando", since = os.clock(), changes = 0, window = os.clock() }
	setSurfState(player, "carregando")
	return true
end

local function refreshScoreboard()
	if not scoreLabels then
		return
	end
	for i, label in ipairs(scoreLabels) do
		local e = best[i]
		label.Text = e and ("%d. %s  —  %d pts"):format(i, e.name, e.points) or ("%d. ---"):format(i)
	end
end

local function addScore(player, points)
	table.insert(best, { name = player.DisplayName, points = points })
	table.sort(best, function(a, b)
		return a.points > b.points
	end)
	while #best > 5 do
		table.remove(best)
	end
	refreshScoreboard()
end

local function buildScoreboard(part)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "PlacarGui"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	gui.Parent = part
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 6)
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.Parent = gui
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 14)
	pad.Parent = gui
	local function line(text, h, color)
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.Size = UDim2.new(0.92, 0, 0, h)
		t.Font = Enum.Font.GothamBold
		t.TextScaled = true
		t.TextColor3 = color
		t.Text = text
		t.Parent = gui
		return t
	end
	line("🏄 MELHORES ONDAS", 44, Color3.fromRGB(255, 210, 70))
	scoreLabels = {}
	for i = 1, 5 do
		local t = line("", 30, Color3.new(1, 1, 1))
		t.TextXAlignment = Enum.TextXAlignment.Left
		scoreLabels[i] = t
	end
	line("$1 a cada " .. S.MoneyPerPoints .. " pontos (até $" .. S.MaxMoneyPerWave .. " por onda)", 22, Color3.fromRGB(160, 220, 255))
	refreshScoreboard()
end

local function talkPrompt(npcModel, speaker, lines, onTalk)
	local head = npcModel and (npcModel:FindFirstChild("Head") or npcModel.PrimaryPart)
	if not head then
		return
	end
	local p = prompt(head, "Conversar", speaker, 9)
	p.Triggered:Connect(function(player)
		if spam(player, 1) or not uiUpdate then
			return
		end
		if onTalk then
			onTalk(player)
		end
		uiUpdate:FireClient(player, "PraiaDialog", { speaker = speaker, lines = lines() })
	end)
end

local SURF_TIPS = {
	{ "Fala, surfista! Aluga uma prancha ali no cavalete por $" .. S.RentPrice .. ".", "Cada prancha é de um jeito: o longboard é estável, a pranchinha é rápida pra manobra." },
	{ "Entra no mar entre as boias amarelas e laranjas. Lá você deita na prancha e rema.", "Quando a onda chegar e te levantar, aperta ESPAÇO (ou o botão de pulo) pra ficar em pé!" },
	{ "Em pé, desce a parede da onda pra ganhar velocidade e sobe pra frear.", "F (ou o botão 🌀) faz a rasgada. ESPAÇO com velocidade é aéreo 360!" },
	{ "Cada onda dá pontos: tempo, velocidade e manobras. Faz combo que multiplica!", "As melhores ondas vão pro placar. E a escolinha paga $1 a cada " .. S.MoneyPerPoints .. " pontos." },
}

local function setupSurf(root)
	local f = root:FindFirstChild("Surfe", true)
	if not f then
		return
	end
	for _, d in ipairs(f:GetDescendants()) do
		if d:IsA("Model") and d.Name == "PranchaAluguel" then
			local main = d.PrimaryPart or d:FindFirstChildWhichIsA("BasePart", true)
			local styleIndex, paletteIndex = d:GetAttribute("Estilo") or 1, d:GetAttribute("Cores") or 1
			local style = SurfBoards.STYLES[styleIndex] or SurfBoards.STYLES[1]
			if main then
				local p = prompt(main, ("Alugar ($%d)"):format(S.RentPrice), style.name, 7)
				p.Triggered:Connect(function(player)
					if spam(player, 1) or not near(player, main, 12) then
						return
					end
					local s = surfers[player]
					if s and (s.state == "remando" or s.state == "surfando") then
						return
					end
					if not EconomyService.spend(player, S.RentPrice, "Aluguel de prancha") then
						notice(player, ("💸 O aluguel da prancha custa $%d (dinheiro limpo)."):format(S.RentPrice))
						return
					end
					if giveBoard(player, styleIndex, paletteIndex) then
						notice(player, ("🏄 %s alugado! Entre no mar entre as boias, deite e reme. Quando a onda chegar: ESPAÇO pra ficar em pé!"):format(style.name))
					else
						EconomyService.add(player, S.RentPrice, "Aluguel de prancha devolvido")
					end
				end)
			end
		elseif d:IsA("BasePart") and d:GetAttribute("SurfeBalcao") then
			local p = prompt(d, "Devolver prancha", "Escolinha de Surfe", 9)
			p.Triggered:Connect(function(player)
				if spam(player, 1) or not near(player, d, 14) then
					return
				end
				if not surfers[player] then
					notice(player, "🏄 Você não está com prancha da escolinha.")
					return
				end
				removeBoard(player)
				notice(player, "🏄 Prancha devolvida. Valeu, volte sempre!")
			end)
		elseif d:IsA("BasePart") and d:GetAttribute("PlacarSurfe") then
			buildScoreboard(d)
		end
	end
end

local function onSurfRequest(player, kind, data)
	local s = surfers[player]
	if not s then
		return
	end
	local root, _, char = rootOf(player)
	if not root or not char:FindFirstChild("PranchaSurfe") then
		return
	end
	-- no máximo 8 mudanças a cada 2 s
	local now = os.clock()
	if now - s.window > 2 then
		s.window, s.changes = now, 0
	end
	s.changes += 1
	if s.changes > 8 then
		return
	end
	if kind == "Surfe" then
		if typeof(data) ~= "string" or not SURF_STATES[data] then
			return
		end
		if (data == "remando" or data == "surfando") and not SurfWaves.inZone(root.Position, 40) then
			return
		end
		if data ~= s.state then
			setSurfState(player, data)
		end
	elseif kind == "Onda" then
		if typeof(data) ~= "table" or not s.rideStart then
			return
		end
		local points, duration, tricks = tonumber(data.pontos), tonumber(data.tempo), tonumber(data.manobras) or 0
		if not points or not duration or points ~= points or duration ~= duration then
			return
		end
		local rode = now - s.rideStart
		local valid = s.validRide
		s.rideStart = nil
		duration = math.clamp(duration, 0, math.min(rode + 1, SurfWaves.life()))
		local cap = math.floor(duration * 50 + math.clamp(tricks, 0, 12) * 300 + 60)
		points = math.clamp(math.floor(points), 0, cap)
		if not valid or points <= 0 then
			return
		end
		addScore(player, points)
		local money = math.min(math.floor(points / S.MoneyPerPoints), S.MaxMoneyPerWave)
		if money > 0 and now - (s.lastPay or 0) >= S.WavePeriod * 0.6 then
			s.lastPay = now
			EconomyService.add(player, money, ("Surfe: onda de %d pontos"):format(points))
			notice(player, ("🌊 Onda de %d pontos! A escolinha te pagou $%d."):format(points, money))
		end
	end
end


local WHITE_SHIRT = Color3.fromRGB(250, 250, 248)
local SWIM = { Color3.fromRGB(230, 60, 80), Color3.fromRGB(40, 140, 220), Color3.fromRGB(250, 200, 40), Color3.fromRGB(40, 180, 120), Color3.fromRGB(240, 120, 40), Color3.fromRGB(150, 70, 200) }
local SKINS = { Color3.fromRGB(255, 220, 190), Color3.fromRGB(230, 180, 140), Color3.fromRGB(190, 130, 90), Color3.fromRGB(140, 90, 60), Color3.fromRGB(100, 65, 45) }
local LINES = {
	vendedor = { "Olha o coco geladinho!", "Açaí na tigela, vem!", "Picolé de fruta!", "Milho quentinho!" },
	pescador = { "Hoje o peixe tá difícil...", "Shhh, não espanta os peixes!", "Pegou um! Ah, não... era alga." },
	turista = { "Que praia linda!", "Bora no píer?", "Ainda dá pra ver o pôr do sol!", "Vamos na MigueLândia!" },
	picole = { "Olha o picolé! Tem de uva, limão e coco!", "Picolééé geladinho!", "Picolé pra refrescar, freguesia!" },
	milho = { "Olha o milho verde quentinho!", "Milho com manteiga, bora?", "Milhoooo!" },
	frescobol = { "Boa!", "Essa foi longe!", "Pega essa!", "Uhul, 50 sem cair!" },
	crianca = { "Meu castelo é o mais alto!", "Mãe, olha o meu castelo!", "Não pisa no castelo!" },
	instrutor = { "Aluga uma prancha e vem pro mar!", "Hoje o mar tá clássico!", "Rema, rema... e fica em pé!", "Quem pegar a maior onda vai pro placar!" },
}

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Include
groundParams.IgnoreWater = true

local function standAt(spot)
	-- os pontos ficam um pouco acima do chão: acha o chão logo abaixo (sem pegar toldo nem telhado)
	local map = Workspace:FindFirstChild("Map")
	groundParams.FilterDescendantsInstances = { map, Workspace.Terrain } -- Marco 10.32: areia é Terrain
	local hit = map and Workspace:Raycast(spot.Position, Vector3.new(0, -20, 0), groundParams)
	local y = hit and hit.Position.Y or spot.Position.Y - 3
	local look = spot.CFrame.LookVector * Vector3.new(1, 0, 1)
	if look.Magnitude < 0.1 then
		look = Vector3.new(0, 0, -1)
	end
	local pos = Vector3.new(spot.Position.X, y, spot.Position.Z)
	return CFrame.lookAt(pos, pos + look.Unit)
end

-- vara de pescar na mão, apontando para o mar
local function fishingRod(npc)
	local hand = npc:FindFirstChild("RightHand") or npc:FindFirstChild("Right Arm")
	if not hand then
		return
	end
	local rod = Instance.new("Part")
	rod.Name = "Vara"
	rod.Size = Vector3.new(0.15, 0.15, 9)
	rod.Color = Color3.fromRGB(70, 50, 30)
	rod.Material = Enum.Material.Wood
	rod.CanCollide = false
	rod.CanQuery = false
	rod.CanTouch = false
	rod.Massless = true
	rod.CFrame = CFrame.new(hand.Position) * npc:GetPivot().Rotation * CFrame.Angles(math.rad(35), 0, 0) * CFrame.new(0, 0, -4.3)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = hand
	weld.Part1 = rod
	weld.Parent = rod
	rod.Parent = npc
end

local function chatter(npc, list, every)
	task.spawn(function()
		task.wait(math.random(5, every))
		while npc.Parent do
			if NPCKit.anyPlayerNear(npc:GetPivot().Position, 40) then
				NPCKit.say(npc, list[math.random(1, #list)], 4)
			end
			task.wait(math.random(every, every * 2))
		end
	end)
end

local function spawnStaff(root)
	local vendors, fishers, bathers = {}, {}, {}
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("BasePart") then
			local role = d:GetAttribute("LitoralSpot")
			if role == "vendedor" then
				table.insert(vendors, d)
			elseif role == "pescador" then
				table.insert(fishers, d)
			elseif role == "banhista" then
				table.insert(bathers, d)
			elseif role == "instrutor" then
				local npc = NPCKit.spawn(standAt(d), { name = "Kauã", shirt = Color3.fromRGB(250, 200, 40), pants = Color3.fromRGB(40, 140, 220), title = "INSTRUTOR DE SURFE", anchored = true, important = true })
				if npc then
					chatter(npc, LINES.instrutor, 22)
					talkPrompt(npc, "Kauã · Instrutor de surfe", function()
						return SURF_TIPS[math.random(1, #SURF_TIPS)]
					end)
				end
			end
		end
	end
	-- vendedores mais perto do píer primeiro (lá passa mais gente)
	table.sort(vendors, function(a, b)
		return math.abs(a.Position.X) < math.abs(b.Position.X)
	end)
	for i, spot in ipairs(vendors) do
		if i > 12 then
			break
		end
		local npc = NPCKit.spawn(standAt(spot), { name = "Vendedor", outfit = "mercado", title = "VENDEDOR", anchored = true, important = true })
		if npc then
			chatter(npc, LINES.vendedor, 25)
		end
		if i % 3 == 0 then
			task.wait()
		end
	end
	for _, spot in ipairs(fishers) do
		local npc = NPCKit.spawn(standAt(spot), { name = "Pescador", shirt = Color3.fromRGB(70, 110, 90), pants = Color3.fromRGB(60, 70, 90), anchored = true, important = true })
		if npc then
			fishingRod(npc)
			chatter(npc, LINES.pescador, 30)
		end
	end
	-- banhistas deitados na canga (no máximo 10, os mais perto do centro)
	table.sort(bathers, function(a, b)
		return math.abs(a.Position.X) < math.abs(b.Position.X)
	end)
	for i, spot in ipairs(bathers) do
		if i > 10 then
			break
		end
		local skin = SKINS[math.random(1, #SKINS)]
		local npc = NPCKit.spawn(standAt(spot), { name = "Banhista", skin = skin, shirt = skin, pants = SWIM[math.random(1, #SWIM)], anchored = true, important = true })
		if npc then
			local cf = standAt(spot)
			npc:PivotTo(cf * CFrame.new(0, 0.55, 0) * CFrame.Angles(math.rad(90), 0, 0)) -- de barriga para cima
		end
	end
end

---------------------------------------------------------------------------
-- Marco 10.32: banhistas andando na areia (com conversa), frescobol, crianças e ambulantes
---------------------------------------------------------------------------

local NAMES_F = { "Bruna", "Camila", "Larissa", "Jéssica", "Thaís", "Fernanda", "Rafaela", "Juliana", "Bia", "Duda" }
local NAMES_M = { "Diego", "Thiago", "Lucas", "Matheus", "Gustavo", "Rodrigo", "Caio", "Leandro", "Pedrinho", "Júnior" }
local HAIR = { Color3.fromRGB(40, 28, 20), Color3.fromRGB(90, 60, 35), Color3.fromRGB(205, 165, 95), Color3.fromRGB(22, 20, 20), Color3.fromRGB(150, 70, 40) }
local CHATS = {
	{ "Opa! A água tá uma delícia hoje.", "Mas não entra de carro no mar, hein! Meu primo afogou o motor ali ontem." },
	{ "Tô tentando pegar um bronze, mas só fico vermelho...", "Passa protetor, viu?" },
	{ "Já foi na MigueLândia? Fica lá no fim do píer.", "A roda-gigante de noite é linda!" },
	{ "Dizem que a escolinha de surfe paga quem pega onda boa.", "Eu só sei cair da prancha, kkkk." },
	{ "Esse calçadão novo ficou top.", "Dá pra entrar em todas as lojas da orla!" },
	{ "Perdi minha chinela! Viu uma azul por aí?", "Deixa pra lá, vou descalço mesmo." },
	{ "Bora uma altinha depois?", "A quadra de vôlei fica perto do píer." },
	{ "O pôr do sol daqui é o mais bonito da cidade.", "Volta mais tarde pra ver!" },
	{ "Meu sonho é morar num desses condomínios com piscina aqui atrás.", "Um dia eu chego lá!" },
	{ "Cuidado com as gaivotas: elas roubam o milho da mão!" },
	{ "Tá vendo o farol lá na ponta? De noite ele gira e dá pra ver de longe." },
	{ "Fui na academia da praia e fiz 20 barras!", "Tá, foram 3. Mas foi bonito." },
	{ "Hoje o mar tá com ondas boas.", "Os surfistas ficam lá entre as boias amarelas." },
	{ "Oi! Desculpa, achei que você era meu amigo.", "Mas já que tá aqui: bom dia!" },
	{ "Água de coco geladinha é a melhor coisa do mundo.", "Tem nas barracas do calçadão." },
	{ "Vi um barco de pesca chegando cedinho, cheio de peixe.", "Os pescadores ficam lá no píer o dia todo." },
}

local function groundY(x, z)
	local map = Workspace:FindFirstChild("Map")
	groundParams.FilterDescendantsInstances = { map, Workspace.Terrain }
	local hit = Workspace:Raycast(Vector3.new(x, 40, z), Vector3.new(0, -80, 0), groundParams)
	return hit and hit.Position.Y or 0.4
end

local function gear(npc, partName, size, offset, color, shape)
	local base = npc:FindFirstChild(partName)
	if not base then
		return nil
	end
	local p = Instance.new("Part")
	p.Name = "Traje"
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	if shape then
		p.Shape = shape
	end
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CollisionGroup = "NPCs"
	p.CFrame = base.CFrame * offset
	local w = Instance.new("WeldConstraint")
	w.Part0 = base
	w.Part1 = p
	w.Parent = p
	p.Parent = npc
	return p
end

-- traje de banho: sunga/bermuda (homem) ou biquíni (mulher), e cabelo
local function swimwear(npc, female, color)
	local lower = npc:FindFirstChild("LowerTorso")
	if lower then
		lower.Color = color
	end
	local ut = npc:FindFirstChild("UpperTorso")
	local head = npc:FindFirstChild("Head")
	local hair = HAIR[math.random(1, #HAIR)]
	if female then
		if ut then
			gear(npc, "UpperTorso", Vector3.new(ut.Size.X * 0.9, ut.Size.Y * 0.26, ut.Size.Z * 1.08), CFrame.new(0, ut.Size.Y * 0.12, 0), color)
		end
		if head then
			local hs = head.Size
			gear(npc, "Head", Vector3.new(hs.X * 1.04, hs.Y * 1.02, hs.Z * 1.04), CFrame.new(0, hs.Y * 0.2, hs.Z * 0.17), hair, Enum.PartType.Ball)
			gear(npc, "Head", Vector3.new(hs.X * 0.8, hs.Y * 1.3, hs.Z * 0.3), CFrame.new(0, -hs.Y * 0.4, hs.Z * 0.46), hair)
		end
	else
		for _, leg in ipairs({ "RightUpperLeg", "LeftUpperLeg" }) do
			local l = npc:FindFirstChild(leg)
			if l and math.random() < 0.6 then -- bermuda (senão é sunga)
				gear(npc, leg, Vector3.new(l.Size.X * 1.1, l.Size.Y * 0.7, l.Size.Z * 1.1), CFrame.new(0, l.Size.Y * 0.15, 0), color)
			end
		end
		if head and math.random() < 0.85 then
			local hs = head.Size
			gear(npc, "Head", Vector3.new(hs.X * 1.04, hs.Y * 0.42, hs.Z * 1.04), CFrame.new(0, hs.Y * 0.36, hs.Z * 0.06), hair)
		end
	end
end

local function sideRange(side)
	if side > 0 then
		return 80, L.BeiraMarHalf + 500
	end
	return -L.BeiraMarHalf - 500, -80
end

local function wander(npc, side, z0, z1, isTalking, lines)
	local lo, hi = sideRange(side)
	task.spawn(function()
		task.wait(math.random(1, 6))
		while npc.Parent do
			if not isTalking() then
				local r = npc:FindFirstChild("HumanoidRootPart")
				local x = r and r.Position.X or (lo + hi) / 2
				local tx = math.clamp(x + math.random(-280, 280), lo, hi)
				NPCKit.walk(npc, { Vector3.new(tx, 0, math.random(z0, z1)) }, nil, function()
					return not isTalking()
				end)
				if lines and npc.Parent and math.random() < 0.3 and NPCKit.anyPlayerNear(npc:GetPivot().Position, 45) then
					NPCKit.say(npc, lines[math.random(1, #lines)], 4)
				end
			end
			task.wait(math.random(2, 7))
		end
	end)
end

local function spawnBeachgoers()
	local n = L.Beachgoers or 12
	for i = 1, n do
		local female = i % 2 == 0
		local side = (i % 4 < 2) and 1 or -1
		local lo, hi = sideRange(side)
		local x = math.random(math.floor(lo), math.floor(hi))
		local z = math.random(3778, 3836)
		local skin = SKINS[math.random(1, #SKINS)]
		local name = female and NAMES_F[math.random(1, #NAMES_F)] or NAMES_M[math.random(1, #NAMES_M)]
		local npc = NPCKit.spawn(CFrame.new(x, groundY(x, z), z), { name = name, skin = skin, shirt = skin, pants = skin, speed = math.random(5, 8), important = true })
		if npc then
			npc:SetAttribute("Banhista", true)
			swimwear(npc, female, SWIM[math.random(1, #SWIM)])
			local talkingUntil = 0
			talkPrompt(npc, name, function()
				return CHATS[math.random(1, #CHATS)]
			end, function(player)
				talkingUntil = os.clock() + 10
				local hum = npc:FindFirstChildOfClass("Humanoid")
				local r = npc:FindFirstChild("HumanoidRootPart")
				local pr = rootOf(player)
				if hum and r then
					hum:MoveTo(r.Position)
					if pr then
						NPCKit.face(npc, pr.Position - r.Position)
					end
				end
			end)
			wander(npc, side, 3778, 3836, function()
				return os.clock() < talkingUntil
			end)
		end
		if i % 3 == 0 then
			task.wait()
		end
	end
end

local function spawnBeachLife(root)
	local life = root:FindFirstChild("VidaNaPraia", true)
	if not life then
		return
	end
	local pairsOf = {}
	for _, d in ipairs(life:GetDescendants()) do
		if d:IsA("BasePart") then
			local role = d:GetAttribute("LitoralSpot")
			if role == "frescobol" then
				local k = d:GetAttribute("Par") or 0
				pairsOf[k] = pairsOf[k] or {}
				table.insert(pairsOf[k], d)
			elseif role == "castelo" then
				local skin = SKINS[math.random(1, #SKINS)]
				local npc = NPCKit.spawn(standAt(d), { name = "Criança", skin = skin, shirt = SWIM[math.random(1, #SWIM)], pants = skin, anchored = true, important = true })
				if npc then
					local lower = npc:FindFirstChild("LowerTorso")
					if lower then
						lower.Color = SWIM[math.random(1, #SWIM)]
					end
					pcall(function()
						npc:ScaleTo(0.65)
					end)
					local hum = npc:FindFirstChildOfClass("Humanoid")
					local r = npc:FindFirstChild("HumanoidRootPart")
					if hum and r then
						npc:PivotTo(standAt(d) + Vector3.new(0, hum.HipHeight + r.Size.Y / 2 + 0.05, 0))
					end
					NPCKit.pose(npc, "castelo")
					chatter(npc, LINES.crianca, 30)
				end
			end
		end
	end
	-- frescobol: os dois de frente, raquete na mão e a bolinha indo e vindo (o cliente anima a bola)
	for _, spots in pairs(pairsOf) do
		if #spots == 2 then
			local hands = {}
			for j, spot in ipairs(spots) do
				local skin = SKINS[math.random(1, #SKINS)]
				local female = j == 2 and math.random() < 0.6
				local npc = NPCKit.spawn(standAt(spot), { name = "Frescobol", skin = skin, shirt = skin, pants = skin, anchored = true, important = true })
				if npc then
					swimwear(npc, female, SWIM[math.random(1, #SWIM)])
					NPCKit.hold(npc, "Raquete", Vector3.new(0.2, 1.7, 1.2), Color3.fromRGB(math.random(40, 240), math.random(40, 200), math.random(40, 240)), Enum.Material.Wood)
					NPCKit.pose(npc, "frescobol")
					if j == 1 then
						chatter(npc, LINES.frescobol, 20)
					end
					local cf = npc:GetPivot()
					hands[j] = (cf * CFrame.new(1.2, 1.4, -1.6)).Position
				end
			end
			if hands[1] and hands[2] then
				local ball = Instance.new("Part")
				ball.Name = "BolaFrescobol"
				ball.Shape = Enum.PartType.Ball
				ball.Size = Vector3.new(0.45, 0.45, 0.45)
				ball.Color = Color3.fromRGB(250, 230, 60)
				ball.Material = Enum.Material.SmoothPlastic
				ball.Anchored = true
				ball.CanCollide = false
				ball.CanQuery = false
				ball.CanTouch = false
				ball.CFrame = CFrame.new(hands[1])
				ball:SetAttribute("PA", hands[1])
				ball:SetAttribute("PB", hands[2])
				CollectionService:AddTag(ball, "BolaFrescobol")
				ball.Parent = life
			end
		end
	end
	-- ambulantes: picolé e milho verde (E no isopor = comprar)
	for i, kind in ipairs({ "Picole", "Milho" }) do
		local side = i == 1 and 1 or -1
		local lo, hi = sideRange(side)
		local x = math.random(math.floor(lo) + 100, math.floor(hi) - 600)
		local z = math.random(3640, 3740)
		local npc = NPCKit.spawn(CFrame.new(x, groundY(x, z), z), { name = kind == "Picole" and "Seu Picolé" or "Dona do Milho", shirt = WHITE_SHIRT, pants = Color3.fromRGB(240, 240, 235), title = kind == "Picole" and "PICOLÉ" or "MILHO VERDE", speed = 5, important = true })
		if npc then
			local cooler = NPCKit.hold(npc, "Isopor", Vector3.new(1.6, 1.4, 1.2), kind == "Picole" and Color3.fromRGB(245, 245, 250) or Color3.fromRGB(250, 200, 40), Enum.Material.SmoothPlastic)
			if cooler then
				cooler:SetAttribute("LitoralSnack", kind)
				setupSnack(cooler)
			end
			wander(npc, side, 3620, 3760, function()
				return false
			end, kind == "Picole" and LINES.picole or LINES.milho)
		end
	end
end

-- turistas andando de um lado para o outro do calçadão
local function spawnTourists()
	local n = L.Tourists or 0
	local zMid = (L.WalkZ0 + L.WalkZ1) / 2
	for i = 1, n do
		local x = math.random(-1400, 1400)
		local z = zMid + math.random(-12, 12)
		local npc = NPCKit.spawn(CFrame.new(x, 0.8, z), { name = "Turista", speed = math.random(6, 9) })
		if not npc then
			break
		end
		task.spawn(function()
			while npc.Parent do
				local tx = math.clamp(x + math.random(-500, 500), -1600, 1600)
				local tz = zMid + math.random(-14, 14)
				NPCKit.walk(npc, { Vector3.new(tx, 0.8, tz) })
				x = tx
				if npc.Parent and math.random() < 0.25 then
					NPCKit.say(npc, LINES.turista[math.random(1, #LINES.turista)], 4)
				end
				task.wait(math.random(3, 9))
			end
		end)
		if i % 4 == 0 then
			task.wait()
		end
	end
end

local function spawnDealershipStaff(map)
	local site = map:FindFirstChild("Concessionaria")
	local spots = site and site:FindFirstChild("PontosNPC")
	if not spots then
		return
	end
	local who = {
		consultor = { name = "Valéria", outfit = "vendedora", title = "CONSULTORA" },
		recepcao = { name = "Recepção", outfit = "gerente", title = "RECEPÇÃO" },
		manobrista = { name = "Manobrista", outfit = "funcionario", title = "MANOBRISTA" },
	}
	for _, spot in ipairs(spots:GetChildren()) do
		local o = who[spot:GetAttribute("Papel")]
		if o and spot:IsA("BasePart") then
			NPCKit.spawn(standAt(spot), { name = o.name, outfit = o.outfit, title = o.title, anchored = true, important = true })
		end
	end
end


---------------------------------------------------------------------------
-- Início
---------------------------------------------------------------------------

function LitoralService.init(remotes)
	uiUpdate = remotes and remotes[GameConfig.Remotes.UIUpdate]
	local map = Workspace:FindFirstChild("Map")
	if not map then
		return
	end
	task.spawn(spawnDealershipStaff, map)
	local root = map:FindFirstChild("Litoral")
	if not root then
		return
	end
	local balls = {}
	for i, d in ipairs(root:GetDescendants()) do
		if d:IsA("BasePart") then
			if d:GetAttribute("LitoralSnack") then
				setupSnack(d)
			elseif d:GetAttribute("LitoralGym") then
				setupStation(d)
			elseif d:GetAttribute("LitoralBall") then
				table.insert(balls, d)
			end
		end
		if i % 2000 == 0 then
			task.wait()
		end
	end
	watchBalls(balls)
	setupSurf(root) -- Marco 10.32
	local litoralRequest = remotes and remotes[GameConfig.Remotes.LitoralRequest]
	if litoralRequest then
		litoralRequest.OnServerEvent:Connect(onSurfRequest)
	end
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function()
			surfers[player] = nil
		end)
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		player.CharacterAdded:Connect(function()
			surfers[player] = nil
		end)
	end
	task.spawn(spawnStaff, root)
	task.delay(8, spawnTourists)
	task.delay(10, spawnBeachgoers) -- Marco 10.32
	task.delay(12, spawnBeachLife, root) -- Marco 10.32
	Players.PlayerRemoving:Connect(function(player)
		lastUse[player] = nil
		series[player] = nil
		surfers[player] = nil
		for spot, holder in pairs(busyStation) do
			if holder == player then
				busyStation[spot] = nil
			end
		end
	end)
end

return LitoralService
