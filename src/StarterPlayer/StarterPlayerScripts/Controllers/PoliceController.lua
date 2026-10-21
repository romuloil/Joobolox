-- Interface e ferramentas do policial. O cliente aponta e pede; o servidor
-- decide vagas, equipamento, relatórios, acesso, imobilização e captura.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))
local UIScaler = require(script.Parent:WaitForChild("UIScaler"))

local PoliceController = {}
local player = Players.LocalPlayer
local initialized = false
local request, gui, panel, panelTitle, panelSubtitle, content, banner, dutyText, patrolText
local crosshair, aimHint, statusLabel, mobileAction
local currentPanel, panelData = nil, {}
local state = { onDuty = false, count = 0, slots = 3, equipped = false, patrolStep = 0, patrolTotal = 4 }
local reports = {}
local activeTool
local toolConnections, characterConnections, cuffPrompts = {}, {}, {}
local lastActivation = 0
local noticeUntil = 0
local lastPromptRefresh = 0

local BLUE = Color3.fromRGB(27, 71, 119)
local INK = Color3.fromRGB(25, 42, 60)
local PAPER = Color3.fromRGB(244, 241, 230)
local ORANGE = Color3.fromRGB(223, 139, 62)
local MUTED = Color3.fromRGB(96, 112, 125)

local function corner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function text(parent, name, value, size, position, color, font, pixels)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Size, label.Position = size, position or UDim2.new()
	label.Text, label.Font = value, font or Enum.Font.GothamMedium
	label.TextSize, label.TextColor3 = pixels or 14, color or INK
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.TextWrapped = true
	label.Parent = parent
	return label
end

local function send(action, payload)
	if request then
		request:FireServer(action, payload)
	end
end

local function toolKind()
	return activeTool and activeTool.Parent == player.Character and activeTool:GetAttribute("PoliceTool") or nil
end

local function targetOwner(prompt)
	local item = prompt.Parent
	while item and item ~= Workspace do
		if item:IsA("Model") then
			local owner = item:GetAttribute("PoliceTrainingOwner")
			if owner then
				return nil, owner, item
			end
			local target = Players:GetPlayerFromCharacter(item)
			if target then
				return target, nil
			end
		end
		item = item.Parent
	end
	return nil, nil
end

local function refreshCuffPrompts()
	local holdingCuffs = state.onDuty and toolKind() == "Cuff"
	local time = Workspace:GetServerTimeNow()
	for prompt in pairs(cuffPrompts) do
		if not prompt.Parent then
			cuffPrompts[prompt] = nil
		else
			local target, trainingOwner, trainingModel = targetOwner(prompt)
			local trainingStun = trainingModel and trainingModel:GetAttribute("StunnedUntil")
			local valid = trainingOwner == player.UserId and type(trainingStun) == "number" and trainingStun > time
			if target then
				local stunned = target:GetAttribute("StunnedUntil")
				valid = target ~= player and target:GetAttribute("Wanted") == true
					and type(stunned) == "number" and stunned > time
			end
			prompt.Enabled = holdingCuffs and valid
		end
	end
end

local function watchCuffPrompt(item)
	if item:IsA("ProximityPrompt") and item.Name == "PoliceCuffPrompt" then
		cuffPrompts[item] = true
		refreshCuffPrompts()
	end
end

local function notice(value)
	if statusLabel then
		statusLabel.Text = value
		noticeUntil = os.clock() + 3
	end
end

local function refreshAim()
	if not crosshair then return end
	local kind = toolKind()
	crosshair.Visible = state.onDuty and (kind == "Spray" or kind == "Cuff") and not panel.Visible
	if kind == "Spray" then
		aimHint.Text = "LANÇADOR DE ÁGUA\nMire e use a ferramenta para imobilizar."
	elseif kind == "Cuff" then
		aimHint.Text = "ALGEMAS\nAproxime-se do suspeito imobilizado e interaja."
	end
	if mobileAction then
		mobileAction.Visible = state.onDuty and kind ~= nil and not panel.Visible
			and UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
		local names = { Spray = "ÁGUA", Cuff = "ALGEMAR", Flashlight = "LUZ", Radio = "RÁDIO" }
		mobileAction.Text = names[kind] or "USAR"
	end
	refreshCuffPrompts()
end

local function aimRay()
	local camera = Workspace.CurrentCamera
	if not camera then return nil end
	local mobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	if mobile then
		return camera:ViewportPointToRay(camera.ViewportSize.X / 2, camera.ViewportSize.Y / 2)
	end
	return player:GetMouse().UnitRay
end

local function aimResult()
	local ray = aimRay()
	if not ray then return nil end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = player.Character and { player.Character } or {}
	params.IgnoreWater = true
	local hit = Workspace:Raycast(ray.Origin, ray.Direction * 90, params)
	return hit, hit and hit.Position or ray.Origin + ray.Direction * 90
end

local function activate(tool)
	if tool ~= activeTool or not state.onDuty or tool.Parent ~= player.Character or panel.Visible then return end
	local time = os.clock()
	if time - lastActivation < 0.15 then return end
	lastActivation = time
	local kind = tool:GetAttribute("PoliceTool")
	if kind == "Flashlight" then
		send("Flashlight")
	elseif kind == "Radio" then
		send("Radio")
	elseif kind == "Spray" then
		local _, point = aimResult()
		local character = player.Character
		local head = character and (character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart"))
		if head and point then
			local direction = point - head.Position
			if direction.Magnitude > 0.01 then
				send("Spray", { direction = direction.Unit })
			end
		end
	elseif kind == "Cuff" then
		local hit = aimResult()
		local item = hit and hit.Instance
		while item and item ~= Workspace do
			if item:IsA("Model") then
				if item:GetAttribute("PoliceTrainingOwner") == player.UserId then
					send("Cuff", "Training")
					return
				end
				local target = Players:GetPlayerFromCharacter(item)
				if target and target ~= player then
					send("Cuff", target.UserId)
					return
				end
			end
			item = item.Parent
		end
		notice("Mire no alvo ou use o botão de algemar perto dele.")
	end
end

local function disconnectTools()
	for _, connection in ipairs(characterConnections) do connection:Disconnect() end
	table.clear(characterConnections)
	for _, connections in pairs(toolConnections) do
		for _, connection in ipairs(connections) do connection:Disconnect() end
	end
	table.clear(toolConnections)
	activeTool = nil
end

local function watchTool(tool)
	if not tool:IsA("Tool") or not tool:GetAttribute("PoliceTool") or toolConnections[tool] then return end
	toolConnections[tool] = {
		tool.Activated:Connect(function() activate(tool) end),
		tool.Equipped:Connect(function()
			activeTool = tool
			refreshAim()
		end),
		tool.Unequipped:Connect(function()
			if activeTool == tool then activeTool = nil end
			refreshAim()
		end),
		tool.Destroying:Connect(function()
			local connections = toolConnections[tool]
			if connections then
				for _, connection in ipairs(connections) do connection:Disconnect() end
				toolConnections[tool] = nil
			end
			if activeTool == tool then activeTool = nil; refreshAim() end
		end),
	}
	if tool.Parent == player.Character then
		activeTool = tool
		refreshAim()
	end
end

local function watchCharacter(character)
	disconnectTools()
	table.insert(characterConnections, character.ChildAdded:Connect(watchTool))
	table.insert(characterConnections, character.ChildRemoved:Connect(function(tool)
		if activeTool == tool then activeTool = nil; refreshAim() end
	end))
	for _, item in ipairs(character:GetChildren()) do watchTool(item) end
	refreshAim()
end

local function button(parent, value, callback, color)
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(1, 0, 0, 43)
	b.BackgroundColor3 = color or BLUE
	b.BorderSizePixel = 0
	b.Font = Enum.Font.GothamBold
	b.TextSize = 14
	b.TextColor3 = Color3.new(1, 1, 1)
	b.TextWrapped = true
	b.Text = value
	b.Parent = parent
	corner(b, 8)
	b.Activated:Connect(callback)
	return b
end

local function paragraph(value, height, color)
	return text(content, "Info", value, UDim2.new(1, -4, 0, height or 45), nil, color or MUTED, nil, 13)
end

local function refreshBanner()
	if not banner then return end
	banner.Visible = state.onDuty
	dutyText.Text = ("EM SERVIÇO  ·  %d/%d policiais"):format(state.count, state.slots)
	local step = math.clamp(state.patrolStep, 0, state.patrolTotal)
	patrolText.Text = ("Ronda: %d/%d  ·  %s"):format(step, state.patrolTotal,
		state.equipped and "kit retirado" or "retire seu kit no arsenal")
	refreshAim()
end

local function closePanel()
	lastActivation = os.clock() -- fechar uma janela não dispara a ferramenta no mesmo toque
	panel.Visible = false
	currentPanel = nil
	refreshAim()
end

local function renderReports()
	paragraph(panelData.readOnly and "CONSULTA PELO RÁDIO\nPara registrar uma ocorrência, vá ao terminal da equipe."
		or "Registre uma ocorrência no terminal. Os informes ficam disponíveis no rádio da equipe.", 48)
	if not panelData.readOnly then
		for _, category in ipairs({
			{ "Seguranca", "Registrar inspeção de segurança" },
			{ "Patrulha", "Registrar informe de patrulha" },
			{ "Manutencao", "Solicitar manutenção" },
		}) do
			button(content, category[2], function() send("Report", { category = category[1] }) end)
		end
	end
	paragraph("ÚLTIMOS INFORMES", 24, BLUE)
	if #reports == 0 then
		paragraph("Nenhum informe registrado nesta sessão.", 36)
	end
	for index = 1, math.min(#reports, 10) do
		local report = reports[index]
		if type(report) == "table" then
			local time = type(report.at) == "number" and DateTime.fromUnixTimestamp(report.at):FormatLocalTime("HH:mm", "pt-br") or ""
			paragraph(("%s  ·  %s\n%s\n%s"):format(time, tostring(report.officer or "Equipe"),
				tostring(report.text or report.category or "Informe"), tostring(report.location or "")), 75, INK)
		end
	end
end

local function renderPanel()
	if not content or not currentPanel then return end
	for _, child in ipairs(content:GetChildren()) do
		if child:IsA("GuiObject") then child:Destroy() end
	end
	local titles = { duty = "Central de serviço", armory = "Arsenal e equipamentos", reports = "Registro de ocorrências", control = "Controle de acesso", training = "Treinamento policial" }
	panelTitle.Text = titles[currentPanel] or "Centro policial"
	panelSubtitle.Text = "CENTRO POLICIAL  /  LITTLE LITTLE KINDER"
	if currentPanel == "duty" then
		paragraph(("Equipe em serviço: %d de %d vagas ocupadas.\nEntre em serviço para patrulhar e operar a prisão."):format(state.count, state.slots), 58)
		button(content, state.onDuty and "Encerrar meu turno" or "Entrar em serviço", function()
			send("Duty", not state.onDuty)
		end, state.onDuty and ORANGE or BLUE)
		paragraph("Retire o kit no arsenal. O lançador de água imobiliza suspeitos válidos; as algemas exigem aproximação. O policial não pode prender cidadãos inocentes.", 82)
		paragraph("Na prisão: faça a ronda, consulte ocorrências, opere acessos e pratique no setor de treinamento.", 60)
	elseif currentPanel == "armory" then
		paragraph("Kit de serviço: lançador de água, algemas, lanterna e rádio. O equipamento é temporário e só funciona em serviço.", 62)
		button(content, "Retirar / repor meu kit", function() send("Gear") end)
		paragraph("Selecione as ferramentas pela mochila do Roblox. No computador, também use as teclas numéricas. No celular, toque na ferramenta e mire pelo centro da tela.", 78)
		paragraph("Lançador: imobilize o alvo. Algemas: aproxime-se e use a interação. Rádio: consulte a equipe. Lanterna: acenda ou apague ao usar.", 76)
	elseif currentPanel == "reports" then
		renderReports()
	elseif currentPanel == "control" then
		paragraph("Operação local dos portões e portas de serviço. Acesso restrito à equipe em serviço. Mantenha a passagem livre ao fechar.", 58)
		local doors = type(panelData.doors) == "table" and panelData.doors or {}
		for _, door in ipairs(doors) do
			if type(door) == "table" and type(door.id) == "string" then
				local id = door.id
				button(content, (door.open and "Fechar  ·  " or "Abrir  ·  ") .. tostring(door.name or id), function() send("Door", id) end,
					door.open and ORANGE or BLUE)
			end
		end
		if #doors == 0 then paragraph("Nenhum acesso disponível neste terminal.", 40) end
		paragraph("As portas das celas seguem o horário de acesso ao pátio. A pena e a liberação continuam sob controle do servidor.", 60)
	elseif currentPanel == "training" then
		paragraph("Pratique a sequência: lançador de água → aproximação → algemas. O alvo de treinamento é individual e não altera o dinheiro de ninguém.", 76)
		button(content, "Iniciar treinamento", function() send("Training") end)
	end
	content.CanvasPosition = Vector2.zero
	refreshAim()
end

function PoliceController.handle(kind, data)
	if type(data) ~= "table" then return end
	if kind == "PoliceState" then
		state.onDuty = data.onDuty == true
		for _, key in ipairs({ "count", "slots", "patrolStep", "patrolTotal" }) do
			if type(data[key]) == "number" then state[key] = math.max(0, math.floor(data[key])) end
		end
		state.equipped = data.equipped == true
		state.training = data.training == true
		if state.patrolTotal < 1 then state.patrolTotal = 4 end
		refreshBanner()
		if currentPanel == "duty" or currentPanel == "armory" then renderPanel() end
		if not state.onDuty and currentPanel ~= "duty" then closePanel() end
	elseif kind == "PolicePanel" then
		panelData = data
		currentPanel = type(data.panel) == "string" and data.panel or "duty"
		if type(data.reports) == "table" then reports = data.reports end
		if type(data.count) == "number" then state.count = data.count end
		if type(data.slots) == "number" then state.slots = data.slots end
		panel.Visible = true
		renderPanel()
	elseif kind == "PoliceReports" then
		if type(data.reports) == "table" then reports = data.reports end
		if currentPanel == "reports" then renderPanel() end
	end
end

function PoliceController.init()
	if initialized then return end
	initialized = true
	request = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild(GameConfig.Remotes.PoliceRequest or "PoliceRequest")
	gui = Instance.new("ScreenGui")
	gui.Name, gui.ResetOnSpawn, gui.DisplayOrder = "PoliceUI", false, 7
	gui.Parent = player:WaitForChild("PlayerGui")

	banner = Instance.new("Frame")
	banner.Name = "DutyCard"
	banner.Size, banner.Position = UDim2.fromOffset(342, 78), UDim2.fromOffset(16, 112)
	banner.BackgroundColor3, banner.BorderSizePixel, banner.Visible = BLUE, 0, false
	banner.Parent = gui
	corner(banner, 10)
	UIScaler.attach(banner)
	dutyText = text(banner, "Duty", "", UDim2.fromOffset(258, 22), UDim2.fromOffset(12, 8), PAPER, Enum.Font.GothamBold, 12)
	patrolText = text(banner, "Patrol", "", UDim2.fromOffset(318, 32), UDim2.fromOffset(12, 33), PAPER, nil, 12)
	local leave = Instance.new("TextButton")
	leave.Size, leave.Position = UDim2.fromOffset(54, 25), UDim2.new(1, -64, 0, 7)
	leave.Text, leave.TextColor3, leave.Font, leave.TextSize = "Sair", PAPER, Enum.Font.GothamBold, 12
	leave.BackgroundColor3, leave.BorderSizePixel = Color3.fromRGB(53, 95, 139), 0
	leave.Parent = banner
	corner(leave, 6)
	leave.Activated:Connect(function() send("Duty", false) end)

	panel = Instance.new("Frame")
	panel.Name = "PolicePanel"
	panel.AnchorPoint, panel.Position = Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(424, 448)
	panel.BackgroundColor3, panel.BorderSizePixel, panel.Visible = PAPER, 0, false
	panel.Parent = gui
	corner(panel, 14)
	UIScaler.attach(panel)
	panelTitle = text(panel, "Title", "Centro policial", UDim2.new(1, -65, 0, 28), UDim2.fromOffset(18, 15), BLUE, Enum.Font.GothamBold, 21)
	panelSubtitle = text(panel, "Subtitle", "", UDim2.new(1, -36, 0, 22), UDim2.fromOffset(18, 46), MUTED, Enum.Font.GothamBold, 9)
	local close = Instance.new("TextButton")
	close.Size, close.Position = UDim2.fromOffset(32, 32), UDim2.new(1, -45, 0, 13)
	close.Text, close.Font, close.TextSize, close.TextColor3 = "×", Enum.Font.GothamBold, 25, INK
	close.BackgroundColor3, close.BorderSizePixel, close.Modal = Color3.fromRGB(225, 225, 215), 0, true
	close.Parent = panel
	corner(close, 8)
	close.Activated:Connect(closePanel)
	content = Instance.new("ScrollingFrame")
	content.Name = "Content"
	content.Position, content.Size = UDim2.fromOffset(18, 78), UDim2.new(1, -36, 1, -96)
	content.BackgroundTransparency, content.BorderSizePixel, content.ScrollBarThickness = 1, 0, 4
	content.CanvasSize, content.AutomaticCanvasSize = UDim2.new(), Enum.AutomaticSize.Y
	content.ScrollingDirection = Enum.ScrollingDirection.Y
	content.ScrollBarImageColor3 = BLUE
	content.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.Padding, layout.SortOrder, layout.Parent = UDim.new(0, 9), Enum.SortOrder.LayoutOrder, content
	local padding = Instance.new("UIPadding")
	padding.PaddingRight, padding.PaddingBottom, padding.Parent = UDim.new(0, 6), UDim.new(0, 8), content

	crosshair = Instance.new("Frame")
	crosshair.Name = "ToolAim"
	crosshair.AnchorPoint, crosshair.Position, crosshair.Size = Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5), UDim2.fromOffset(24, 24)
	crosshair.BackgroundTransparency, crosshair.Visible, crosshair.Parent = 1, false, gui
	local dot = text(crosshair, "Reticle", "+", UDim2.fromScale(1, 1), nil, Color3.new(1, 1, 1), Enum.Font.GothamBold, 25)
	dot.TextXAlignment, dot.TextStrokeTransparency = Enum.TextXAlignment.Center, 0.25
	aimHint = text(crosshair, "ToolHint", "", UDim2.fromOffset(280, 48), UDim2.fromOffset(-128, 40), PAPER, Enum.Font.GothamBold, 12)
	aimHint.TextXAlignment, aimHint.TextStrokeTransparency = Enum.TextXAlignment.Center, 0.25
	statusLabel = text(gui, "ToolNotice", "", UDim2.fromOffset(320, 36), UDim2.new(0.5, -160, 0.5, 110), PAPER, Enum.Font.GothamBold, 13)
	statusLabel.TextXAlignment, statusLabel.TextStrokeTransparency = Enum.TextXAlignment.Center, 0.25
	mobileAction = Instance.new("TextButton")
	mobileAction.Name = "UsePoliceTool"
	mobileAction.AnchorPoint, mobileAction.Position = Vector2.new(1, 0.5), UDim2.new(1, -20, 0.5, -25)
	mobileAction.Size = UDim2.fromOffset(80, 66)
	mobileAction.BackgroundColor3, mobileAction.BorderSizePixel = BLUE, 0
	mobileAction.Font, mobileAction.TextSize, mobileAction.TextColor3 = Enum.Font.GothamBold, 13, PAPER
	mobileAction.Visible, mobileAction.Parent = false, gui
	corner(mobileAction, 18)
	UIScaler.attach(mobileAction)
	mobileAction.Activated:Connect(function() if activeTool then activate(activeTool) end end)

	player:GetAttributeChangedSignal("PoliceDuty"):Connect(function()
		state.onDuty = player:GetAttribute("PoliceDuty") == true
		refreshBanner()
		if not state.onDuty then closePanel() end
	end)
	state.onDuty = player:GetAttribute("PoliceDuty") == true
	player.CharacterAdded:Connect(watchCharacter)
	if player.Character then watchCharacter(player.Character) end
	local backpack = player:WaitForChild("Backpack")
	backpack.ChildAdded:Connect(watchTool)
	for _, tool in ipairs(backpack:GetChildren()) do watchTool(tool) end
	Workspace.DescendantAdded:Connect(watchCuffPrompt)
	for _, item in ipairs(Workspace:GetDescendants()) do watchCuffPrompt(item) end
	RunService.Heartbeat:Connect(function()
		if crosshair.Visible then
			if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
				crosshair.Position = UDim2.fromScale(0.5, 0.5)
			else
				local mouse = UserInputService:GetMouseLocation()
				local inset = GuiService:GetGuiInset()
				crosshair.Position = UDim2.fromOffset(mouse.X - inset.X, mouse.Y - inset.Y)
			end
		end
		if os.clock() - lastPromptRefresh > 0.2 then
			lastPromptRefresh = os.clock()
			refreshCuffPrompts()
			if statusLabel.Text ~= "" and os.clock() > noticeUntil then statusLabel.Text = "" end
		end
	end)
	refreshBanner()
end

return PoliceController
