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

local function refreshBoard()
	if not panel then
		return
	end
	for id, row in pairs(rows) do
		local job = JobConfig.Jobs[id]
		local used = counts[id] or 0
		row.slots.Text = ("Vagas: %d/%d"):format(used, job.Slots)
		local button = row.button
		if currentJob == id then
			button.Text = "Seu emprego"
			button.BackgroundColor3 = BLUE
			button.AutoButtonColor = false
		elseif used >= job.Slots then
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
end

local function buildBoard()
	gui = Instance.new("ScreenGui")
	gui.Name = "JobBoardUI"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 6
	gui.Parent = player:WaitForChild("PlayerGui")

	local rowHeight, padding = 84, 8
	local height = 52 + #JobConfig.Order * (rowHeight + padding) + 56
	panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(440, height)
	panel.BackgroundColor3 = Color3.fromRGB(20, 30, 50)
	panel.Visible = false
	panel.Parent = gui
	corner(panel, 16)
	UIScaler.attach(panel)

	text(panel, { Text = "Quadro de empregos", Font = Enum.Font.GothamBlack, TextSize = 20, Size = UDim2.new(1, -70, 0, 30), Position = UDim2.fromOffset(14, 10) })

	local close = Instance.new("TextButton")
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -8, 0, 8)
	close.Size = UDim2.fromOffset(36, 32)
	close.BackgroundColor3 = RED
	close.Font = Enum.Font.GothamBold
	close.TextSize = 18
	close.TextColor3 = Color3.new(1, 1, 1)
	close.Text = "X"
	close.Parent = panel
	corner(close, 8)
	close.Activated:Connect(function()
		panel.Visible = false
	end)

	rows = {}
	for i, id in ipairs(JobConfig.Order) do
		local job = JobConfig.Jobs[id]
		local row = Instance.new("Frame")
		row.Position = UDim2.fromOffset(10, 52 + (i - 1) * (rowHeight + padding))
		row.Size = UDim2.new(1, -20, 0, rowHeight)
		row.BackgroundColor3 = Color3.fromRGB(35, 50, 80)
		row.Parent = panel
		corner(row, 12)

		local stripe = Instance.new("Frame")
		stripe.Size = UDim2.new(0, 8, 1, 0)
		stripe.BackgroundColor3 = job.Color
		stripe.BorderSizePixel = 0
		stripe.Parent = row
		corner(stripe, 4)

		text(row, { Text = job.Name, Font = Enum.Font.GothamBlack, TextSize = 18, Size = UDim2.new(1, -150, 0, 22), Position = UDim2.fromOffset(18, 6) })
		text(row, { Text = job.Description, Font = Enum.Font.Gotham, TextSize = 13, Color = Color3.fromRGB(200, 215, 240), Size = UDim2.new(1, -150, 0, 34), Position = UDim2.fromOffset(18, 28), YAlign = Enum.TextYAlignment.Top })
		local info = text(row, { Font = Enum.Font.GothamBold, TextSize = 13, Color = Color3.fromRGB(140, 230, 140), Size = UDim2.new(1, -150, 0, 16), Position = UDim2.fromOffset(18, 64) })
		info.Text = ("%s · %s"):format(job.PayText, job.Place)

		local slots = text(row, { TextSize = 13, Color = Color3.fromRGB(255, 220, 150), Size = UDim2.fromOffset(120, 18), Position = UDim2.new(1, -128, 0, 8) })
		slots.TextXAlignment = Enum.TextXAlignment.Center

		local button = Instance.new("TextButton")
		button.AnchorPoint = Vector2.new(1, 1)
		button.Position = UDim2.new(1, -8, 1, -8)
		button.Size = UDim2.fromOffset(120, 44)
		button.Font = Enum.Font.GothamBold
		button.TextSize = 17
		button.TextColor3 = Color3.new(1, 1, 1)
		button.Parent = row
		corner(button, 10)
		button.Activated:Connect(function()
			if currentJob ~= id and (counts[id] or 0) < job.Slots then
				jobRequest:FireServer("Join", id)
			end
		end)
		rows[id] = { slots = slots, button = button }
	end

	leaveButton = Instance.new("TextButton")
	leaveButton.AnchorPoint = Vector2.new(0.5, 1)
	leaveButton.Position = UDim2.new(0.5, 0, 1, -10)
	leaveButton.Size = UDim2.fromOffset(200, 40)
	leaveButton.BackgroundColor3 = RED
	leaveButton.Font = Enum.Font.GothamBold
	leaveButton.TextSize = 17
	leaveButton.TextColor3 = Color3.new(1, 1, 1)
	leaveButton.Text = "Sair do emprego"
	leaveButton.Parent = panel
	corner(leaveButton, 10)
	leaveButton.Activated:Connect(function()
		jobRequest:FireServer("Leave")
	end)
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
	currentStep = nil
end

local function findPoint(name)
	local stations = Workspace:FindFirstChild("JobStations")
	return stations and stations:FindFirstChild(name, true)
end

local function bannerText(data, extra)
	local job = JobConfig.Jobs[data.job]
	local header = ("%s · %s · %d/%d"):format(job and job.Name or data.job, data.title or "", data.step, data.total)
	return header .. "\n" .. data.text .. (extra or "")
end

-- Contorno discreto só nos objetos desta etapa
local function highlight(visual)
	local h = Instance.new("Highlight")
	h.Name = "JobHighlight"
	h.FillColor = Color3.fromRGB(255, 170, 60)
	h.FillTransparency = 0.85
	h.OutlineColor = Color3.fromRGB(255, 170, 60)
	h.DepthMode = Enum.HighlightDepthMode.Occluded
	h.Adornee = visual
	h.Parent = visual
	table.insert(activeHighlights, h)
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
			table.insert(prompts, prompt)
		end
		if type(entry.point) == "string" and entry.point:find("_Casa_") then
			isHouse = true
		end
	end
	activePrompts = prompts
	HudController.showCard(data.card) -- comanda da pizza (só aparece no Pizzaiolo)

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
			HudController.setTask(bannerText(data, ("  (%s %ds)"):format(waitText, math.ceil(left))))
			task.wait(0.25)
		end
		if token == stepToken then
			HudController.setTask(bannerText(data))
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
	elseif kind == "JobStep" then
		showStep(data)
	elseif kind == "JobPaid" then
		clearStep()
		HudController.showCard(nil)
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
