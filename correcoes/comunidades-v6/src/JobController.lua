-- JobController (ModuleScript)
-- Caminho: StarterPlayer > StarterPlayerScripts > Controllers > JobController
-- Lado do cliente dos empregos:
--   * painel do quadro de empregos (vagas, pagamento, botão Trabalhar);
--   * etapa atual: liga o botão de interação SÓ da estação certa e destaca o objeto;
--   * faixa da tarefa no topo, destino no mapa e avisos de pagamento.
-- O cliente só mostra e pede; vagas, etapas e pagamentos são decididos pelo servidor.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local JobConfig = require(Shared:WaitForChild("JobConfig"))
local UIScaler = require(script.Parent:WaitForChild("UIScaler"))
local HudController = require(script.Parent:WaitForChild("HudController"))
local MapController = require(script.Parent:WaitForChild("MapController"))

local JobController = {}

local player = Players.LocalPlayer
local jobRequest = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild(GameConfig.Remotes.JobRequest)

local BLUE = Color3.fromRGB(20, 45, 90)
local GREEN = Color3.fromRGB(60, 170, 80)
local GRAY = Color3.fromRGB(110, 110, 120)
local RED = Color3.fromRGB(200, 90, 60)
local SYMBOL = GameConfig.Economy.CurrencySymbol

local gui, panel, rows, leaveButton
local counts = {}
local currentJob
local currentStep -- dados da etapa atual vindos do servidor
local activePrompts, activeHighlights = {}, {}
local activeConns = {} -- Marco 9.9: mangueira do Bombeiro
local hoseFx
local stepToken = 0 -- muda a cada etapa (cancela contagens antigas)

local function corner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function text(parent, props)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = props.Font or Enum.Font.GothamBold
	l.TextColor3 = props.Color or Color3.new(1, 1, 1)
	l.TextSize = props.TextSize or 16
	l.TextWrapped = true
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextYAlignment = props.YAlign or Enum.TextYAlignment.Center
	l.Size = props.Size
	l.Position = props.Position or UDim2.new()
	l.Text = props.Text or ""
	l.Parent = parent
	return l
end

---------------------------------------------------------------------------
-- Painel do quadro de empregos
---------------------------------------------------------------------------

-- Marco 9.14: quadro de empregos refeito (o Luís pediu algo mais bonito e organizado): cada
-- emprego é um cartão com ícone, lugar, pagamento, barra de vagas e botão; a lista rola; o
-- emprego atual fica destacado em cima, e o cartão acende quando o mouse passa.
local CARD = Color3.fromRGB(32, 46, 76)
local CARD_HOVER = Color3.fromRGB(42, 60, 96)
local CARD_MINE = Color3.fromRGB(28, 62, 70)

local function refreshBoard()
	if not panel then
		return
	end
	local jobName
	for id, row in pairs(rows) do
		local job = JobConfig.Jobs[id]
		local used = counts[id] or 0
		local full = used >= job.Slots
		local mine = currentJob == id
		row.slots.Text = ("%d/%d vagas"):format(used, job.Slots)
		row.slots.TextColor3 = full and Color3.fromRGB(255, 160, 150) or Color3.fromRGB(255, 220, 150)
		row.bar.Size = UDim2.new(job.Slots > 0 and math.clamp(used / job.Slots, 0, 1) or 0, 0, 1, 0)
		row.bar.BackgroundColor3 = full and Color3.fromRGB(210, 90, 80) or Color3.fromRGB(90, 200, 120)
		row.base = mine and CARD_MINE or CARD
		row.card.BackgroundColor3 = row.hovering and CARD_HOVER or row.base
		row.tag.Visible = mine
		local button = row.button
		if mine then
			jobName = job.Name
			button.Text = "Seu emprego"
			button.BackgroundColor3 = BLUE
			button.AutoButtonColor = false
		elseif full then
			button.Text = "Lotado"
			button.BackgroundColor3 = GRAY
			button.AutoButtonColor = false
		else
			button.Text = currentJob and "Trocar" or "Trabalhar"
			button.BackgroundColor3 = GREEN
			button.AutoButtonColor = true
		end
	end
	leaveButton.Visible = currentJob ~= nil
	panel.Rodape.Size = UDim2.new(1, 0, 0, currentJob and 58 or 14)
	panel.Cabecalho.Resumo.Text = jobName and ("Você é " .. jobName) or "Escolha um emprego para começar a ganhar"
end

local function buildBoard()
	gui = Instance.new("ScreenGui")
	gui.Name = "JobBoardUI"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 6
	gui.Parent = player:WaitForChild("PlayerGui")

	panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(470, 560)
	panel.BackgroundColor3 = Color3.fromRGB(18, 27, 45)
	panel.Visible = false
	panel.Parent = gui
	corner(panel, 18)
	UIScaler.attach(panel)
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(70, 95, 150)
	stroke.Thickness = 2
	stroke.Parent = panel

	-- cabeçalho
	local head = Instance.new("Frame")
	head.Name = "Cabecalho"
	head.Size = UDim2.new(1, 0, 0, 74)
	head.BackgroundColor3 = Color3.fromRGB(26, 38, 64)
	head.BorderSizePixel = 0
	head.Parent = panel
	corner(head, 18)
	local headFill = Instance.new("Frame") -- tapa o canto arredondado de baixo
	headFill.Size = UDim2.new(1, 0, 0, 18)
	headFill.Position = UDim2.new(0, 0, 1, -18)
	headFill.BackgroundColor3 = head.BackgroundColor3
	headFill.BorderSizePixel = 0
	headFill.Parent = head

	text(head, { Text = "💼  Quadro de empregos", Font = Enum.Font.GothamBlack, TextSize = 21, Size = UDim2.new(1, -70, 0, 26), Position = UDim2.fromOffset(18, 12) })
	local resumo = text(head, { Text = "", Font = Enum.Font.Gotham, TextSize = 14, Color = Color3.fromRGB(170, 195, 235), Size = UDim2.new(1, -70, 0, 20), Position = UDim2.fromOffset(18, 40) })
	resumo.Name = "Resumo"

	local close = Instance.new("TextButton")
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -12, 0, 12)
	close.Size = UDim2.fromOffset(36, 32)
	close.BackgroundColor3 = RED
	close.Font = Enum.Font.GothamBold
	close.TextSize = 18
	close.TextColor3 = Color3.new(1, 1, 1)
	close.Text = "X"
	close.Parent = head
	corner(close, 8)
	close.Activated:Connect(function()
		panel.Visible = false
	end)

	-- rodapé (botão de sair), que some quando o jogador não tem emprego
	local foot = Instance.new("Frame")
	foot.Name = "Rodape"
	foot.AnchorPoint = Vector2.new(0, 1)
	foot.Position = UDim2.fromScale(0, 1)
	foot.Size = UDim2.new(1, 0, 0, 58)
	foot.BackgroundTransparency = 1
	foot.Parent = panel

	leaveButton = Instance.new("TextButton")
	leaveButton.AnchorPoint = Vector2.new(0.5, 1)
	leaveButton.Position = UDim2.new(0.5, 0, 1, -12)
	leaveButton.Size = UDim2.fromOffset(220, 38)
	leaveButton.BackgroundColor3 = RED
	leaveButton.Font = Enum.Font.GothamBold
	leaveButton.TextSize = 16
	leaveButton.TextColor3 = Color3.new(1, 1, 1)
	leaveButton.Text = "Sair do emprego"
	leaveButton.Parent = foot
	corner(leaveButton, 10)
	leaveButton.Activated:Connect(function()
		jobRequest:FireServer("Leave")
	end)

	-- lista que rola
	local list = Instance.new("ScrollingFrame")
	list.Name = "Lista"
	list.Position = UDim2.fromOffset(0, 78)
	list.Size = UDim2.new(1, 0, 1, -78 - 58)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 5
	list.ScrollBarImageColor3 = Color3.fromRGB(90, 120, 180)
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 12)
	pad.PaddingRight = UDim.new(0, 12)
	pad.PaddingBottom = UDim.new(0, 10)
	pad.Parent = list

	rows = {}
	for i, id in ipairs(JobConfig.Order) do
		local job = JobConfig.Jobs[id]
		local card = Instance.new("Frame")
		card.Name = id
		card.LayoutOrder = i
		card.Size = UDim2.new(1, 0, 0, 96)
		card.BackgroundColor3 = CARD
		card.Parent = list
		corner(card, 14)

		local stripe = Instance.new("Frame")
		stripe.Size = UDim2.new(0, 6, 1, -16)
		stripe.Position = UDim2.fromOffset(0, 8)
		stripe.BackgroundColor3 = job.Color
		stripe.BorderSizePixel = 0
		stripe.Parent = card
		corner(stripe, 3)

		-- bolinha com o ícone da profissão
		local badge = Instance.new("Frame")
		badge.Size = UDim2.fromOffset(46, 46)
		badge.Position = UDim2.fromOffset(16, 14)
		badge.BackgroundColor3 = job.Color
		badge.Parent = card
		corner(badge, 23)
		local icon = text(badge, { Text = job.Icon or "💼", TextSize = 24, Size = UDim2.fromScale(1, 1) })
		icon.TextXAlignment = Enum.TextXAlignment.Center

		text(card, { Text = job.Name, Font = Enum.Font.GothamBlack, TextSize = 17, Size = UDim2.new(1, -200, 0, 20), Position = UDim2.fromOffset(72, 12) })
		local tag = text(card, { Text = "SEU EMPREGO", Font = Enum.Font.GothamBold, TextSize = 11, Color = Color3.fromRGB(120, 230, 190), Size = UDim2.fromOffset(100, 14), Position = UDim2.fromOffset(72, 32) })
		tag.Name = "Tag"
		tag.Visible = false
		text(card, { Text = job.Description, Font = Enum.Font.Gotham, TextSize = 12.5, Color = Color3.fromRGB(190, 206, 235), Size = UDim2.new(1, -210, 0, 30), Position = UDim2.fromOffset(72, 32), YAlign = Enum.TextYAlignment.Top })
		local info = text(card, { Font = Enum.Font.GothamBold, TextSize = 12.5, Color = Color3.fromRGB(140, 230, 140), Size = UDim2.new(1, -90, 0, 16), Position = UDim2.fromOffset(72, 66) })
		info.Text = ("%s  ·  📍 %s"):format(job.PayText, job.Place)

		-- vagas: texto e barrinha
		local slots = text(card, { TextSize = 12.5, Color = Color3.fromRGB(255, 220, 150), Size = UDim2.fromOffset(110, 16), Position = UDim2.new(1, -124, 0, 12) })
		slots.TextXAlignment = Enum.TextXAlignment.Right
		local track = Instance.new("Frame")
		track.Size = UDim2.fromOffset(104, 5)
		track.Position = UDim2.new(1, -118, 0, 30)
		track.BackgroundColor3 = Color3.fromRGB(20, 30, 48)
		track.BorderSizePixel = 0
		track.Parent = card
		corner(track, 3)
		local bar = Instance.new("Frame")
		bar.Size = UDim2.new(0, 0, 1, 0)
		bar.BackgroundColor3 = Color3.fromRGB(90, 200, 120)
		bar.BorderSizePixel = 0
		bar.Parent = track
		corner(bar, 3)

		local button = Instance.new("TextButton")
		button.AnchorPoint = Vector2.new(1, 1)
		button.Position = UDim2.new(1, -14, 1, -12)
		button.Size = UDim2.fromOffset(112, 36)
		button.Font = Enum.Font.GothamBold
		button.TextSize = 16
		button.TextColor3 = Color3.new(1, 1, 1)
		button.Parent = card
		corner(button, 10)
		button.Activated:Connect(function()
			if currentJob ~= id and (counts[id] or 0) < job.Slots then
				jobRequest:FireServer("Join", id)
			end
		end)

		local row = { slots = slots, button = button, card = card, bar = bar, tag = tag, base = CARD }
		rows[id] = row
		card.MouseEnter:Connect(function()
			row.hovering = true
			card.BackgroundColor3 = CARD_HOVER
		end)
		card.MouseLeave:Connect(function()
			row.hovering = false
			card.BackgroundColor3 = row.base
		end)
	end
end

---------------------------------------------------------------------------
-- Etapa atual
---------------------------------------------------------------------------

local function clearStep()
	stepToken += 1
	for _, prompt in ipairs(activePrompts) do
		prompt.Enabled = false -- só na tela deste jogador
	end
	for _, h in ipairs(activeHighlights) do
		h:Destroy()
	end
	activePrompts, activeHighlights = {}, {}
	for _, c in ipairs(activeConns) do
		c:Disconnect()
	end
	activeConns = {}
	if hoseFx then
		hoseFx:Destroy()
		hoseFx = nil
	end
	currentStep = nil
end

-- Marco 9.9: jato de água da mangueira (só visual, na tela deste jogador) enquanto segura o E
local function startHose(target)
	if hoseFx then
		hoseFx:Destroy()
	end
	local character = player.Character
	local hand = character and (character:FindFirstChild("RightHand") or character:FindFirstChild("HumanoidRootPart"))
	if not hand then
		return
	end
	local nozzle = Instance.new("Part")
	nozzle.Name = "Mangueira"
	nozzle.Size = Vector3.new(0.3, 0.3, 1.2)
	nozzle.Color = Color3.fromRGB(200, 30, 30)
	nozzle.Material = Enum.Material.SmoothPlastic
	nozzle.CanCollide = false
	nozzle.CanQuery = false
	nozzle.CanTouch = false
	nozzle.Massless = true
	nozzle.Anchored = true
	nozzle.Parent = Workspace
	hoseFx = nozzle
	local water = Instance.new("ParticleEmitter")
	water.EmissionDirection = Enum.NormalId.Front
	water.Color = ColorSequence.new(Color3.fromRGB(170, 215, 255))
	water.LightEmission = 0.2
	water.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1.6) })
	water.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 0.9) })
	water.Lifetime = NumberRange.new(0.7, 0.9)
	water.Speed = NumberRange.new(38, 44)
	water.SpreadAngle = Vector2.new(3, 3)
	water.Acceleration = Vector3.new(0, -30, 0)
	water.Rate = 120
	water.Parent = nozzle
	task.spawn(function()
		while hoseFx == nozzle and hand.Parent do
			local from = hand.Position
			local aim = target.Position + Vector3.new(0, 6, 0) -- mira um pouco acima (o jato cai)
			nozzle.CFrame = CFrame.lookAt(from, aim)
			task.wait()
		end
	end)
end

local function stopHose()
	if hoseFx then
		hoseFx:Destroy()
		hoseFx = nil
	end
end

local function findPoint(name)
	local stations = Workspace:FindFirstChild("JobStations")
	local found = stations and stations:FindFirstChild(name, true)
	if not found then
		-- Marco 9.8: as paradas de ônibus ficam no mapa (Map > PontosOnibus), não em JobStations.
		-- Sem isso o aviso "Abrir as portas" nunca aparecia e o ônibus não terminava a parada.
		local map = Workspace:FindFirstChild("Map")
		local stops = map and map:FindFirstChild("PontosOnibus")
		found = stops and stops:FindFirstChild(name, true)
	end
	return found
end

-- Marco 10.23: dados do painel de tarefa (HudController.showTask)
local function taskInfo(data, waiting)
	local job = JobConfig.Jobs[data.job]
	local targets, action = {}, nil
	for _, entry in ipairs(type(data.points) == "table" and data.points or {}) do
		if typeof(entry.pos) == "Vector3" then
			table.insert(targets, entry.pos)
		end
		action = action or entry.action
	end
	return {
		head = ("%s · %s · etapa %d de %d"):format(job and job.Name or data.job, data.title or "", data.step, data.total),
		step = data.step,
		total = data.total,
		steps = data.steps,
		text = data.text,
		next = type(data.steps) == "table" and data.steps[data.step + 1] or nil,
		action = #targets <= 1 and action or nil,
		hold = data.hold,
		waiting = waiting,
		targets = targets,
	}
end

-- Marco 10.23: marcador no mundo em cima de cada ponto da etapa (some quando a etapa muda). Fica numa
-- peça só deste aparelho, então funciona com o ponto longe e fora do streaming.
local function addMarker(pos, action)
	table.insert(activeHighlights, HudController.newMarker(pos, action))
end

local function showStep(data)
	clearStep()
	currentStep = data
	local token = stepToken
	local prompts = {}
	local isHouse = false
	for _, entry in ipairs(type(data.points) == "table" and data.points or {}) do
		local point = type(entry.point) == "string" and findPoint(entry.point)
		local prompt = point and point:FindFirstChild("JobPrompt")
		local visualRef = point and point:FindFirstChild("Visual")
		if visualRef and visualRef.Value then
			highlight(visualRef.Value)
		end
		if prompt then
			prompt.ActionText = tostring(entry.action or "Usar")
			prompt.HoldDuration = data.hold or 0
			if type(data.reach) == "number" then
				prompt.MaxActivationDistance = data.reach -- Marco 9: táxi para na rua, longe do ponto
			end
			table.insert(prompts, prompt)
			if entry.point:find("^Bombeiro_Casa_") then
				table.insert(activeConns, prompt.PromptButtonHoldBegan:Connect(function()
					startHose(point)
				end))
				table.insert(activeConns, prompt.PromptButtonHoldEnded:Connect(stopHose))
				table.insert(activeConns, prompt.Triggered:Connect(function()
					task.delay(1.5, stopHose)
				end))
			end
		end
		if type(entry.point) == "string" and (entry.point:find("_Casa_") or entry.point:find("^Taxista_") or entry.point:find("^Motorista_") or entry.point:find("^Bombeiro_")) then
			isHouse = true -- destino é um ponto da cidade (casa, calçada do táxi, parada de ônibus), não a loja
		end
	end
	activePrompts = prompts
	-- Marco 10.22 (streaming): o ponto longe só chega no aparelho quando o jogador se aproxima
	-- (e volta como peça nova se saiu e entrou de novo). Quando o botão dele chega, monta a etapa de novo.
	local wanted = {}
	for _, entry in ipairs(type(data.points) == "table" and data.points or {}) do
		if type(entry.point) == "string" then
			wanted[entry.point] = true
		end
	end
	if next(wanted) then
		table.insert(activeConns, Workspace.DescendantAdded:Connect(function(d)
			if d.Name == "JobPrompt" and d:IsA("ProximityPrompt") and d.Parent and wanted[d.Parent.Name] then
				task.defer(function()
					if token == stepToken and currentStep == data then
						showStep(data)
					end
				end)
			end
		end))
	end
	HudController.showCard(data.card) -- comanda da pizza (só aparece no Pizzaiolo)
	local marked = 0
	for _, entry in ipairs(type(data.points) == "table" and data.points or {}) do
		if typeof(entry.pos) == "Vector3" and marked < 8 then
			marked += 1
			addMarker(entry.pos, entry.action)
		end
	end

	-- Entrega em casa: destino no mapa é a casa; senão, a loja
	MapController.setTarget(not isHouse and data.place or nil, isHouse and data.targetPos or nil)

	-- Espera (ex.: pizza assando) com contagem na faixa
	task.spawn(function()
		while token == stepToken do
			local left = (data.readyAt or 0) - Workspace:GetServerTimeNow()
			if left <= 0 then
				break
			end
			local waitText = type(data.waitText) == "string" and data.waitText or "pronto em"
			HudController.showTask(taskInfo(data, ("%s %ds"):format(waitText, math.ceil(left))))
			task.wait(0.25)
		end
		if token == stepToken then
			HudController.showTask(taskInfo(data))
			for _, prompt in ipairs(prompts) do
				prompt.Enabled = true
			end
		end
	end)
end

---------------------------------------------------------------------------
-- Mensagens do servidor (chamado pelo ClientBootstrap)
---------------------------------------------------------------------------

function JobController.handle(kind, data)
	if kind == "JobBoard" then
		counts = type(data.counts) == "table" and data.counts or counts
		currentJob = data.current
		refreshBoard()
		panel.Visible = true
	elseif kind == "JobSlots" then
		counts = type(data.counts) == "table" and data.counts or counts
		refreshBoard()
	elseif kind == "JobChanged" then
		currentJob = data.job
		refreshBoard()
		if currentJob then
			panel.Visible = false
			local job = JobConfig.Jobs[currentJob]
			HudController.toast("Você agora é " .. (job and job.Name or currentJob) .. "!", BLUE)
		else
			clearStep()
			HudController.setTask(nil)
			HudController.showCard(nil)
			MapController.setTarget(nil)
			HudController.toast("Você saiu do emprego.", GRAY)
		end
	elseif kind == "JobPaused" then
		-- Marco 8.2: entrou/saiu da prisão: some o pedido que estava na tela
		clearStep()
		HudController.setTask(nil)
		HudController.showCard(nil)
		MapController.setTarget(nil)
	elseif kind == "JobStep" then
		showStep(data)
	elseif kind == "JobPaid" then
		clearStep()
		HudController.showCard(nil)
		if data.job == "Presidiario" then
			HudController.setTask("Tarefa concluída! Próxima tarefa chegando...")
			HudController.toast(("Tarefa concluída: %s"):format(tostring(data.title or "")), Color3.fromRGB(235, 120, 30))
			return
		end
		HudController.setTask("Pedido concluído! Próximo pedido chegando...")
		if type(data.reward) == "number" and data.reward > 0 then
			HudController.toast(("+%s %d  %s concluído!"):format(SYMBOL, data.reward, tostring(data.title or "Pedido")))
		end
		if type(data.tip) == "number" and data.tip > 0 then
			HudController.toast(("+%s %d  Gorjeta pela rapidez!"):format(SYMBOL, data.tip), Color3.fromRGB(40, 150, 200))
		end
		if type(data.bonus) == "number" and data.bonus > 0 then
			HudController.toast(("+%s %d  Bônus diário!"):format(SYMBOL, data.bonus), Color3.fromRGB(230, 170, 30))
		end
	elseif kind == "JobHint" then
		HudController.toast(tostring(data.text or ""), data.bad and RED or BLUE)
	elseif kind == "JobRefused" then
		if data.reason == "full" then
			HudController.toast("Essa vaga lotou. Escolha outra profissão!", RED)
		elseif data.reason == "far" then
			HudController.toast("Chegue mais perto do quadro de empregos.", RED)
		end
	end
end

function JobController.init()
	buildBoard()
	refreshBoard()
	HudController.onLeaveJob(function()
		jobRequest:FireServer("Leave")
	end)
end

return JobController
