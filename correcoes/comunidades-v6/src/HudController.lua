-- HudController (ModuleScript)
-- Caminho: StarterPlayer > StarterPlayerScripts > Controllers > HudController
-- Mostra saldo, estado do bônus diário, a etapa do emprego e avisos de pagamento.
-- Só MOSTRA o que o servidor mandou; nunca decide valores.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))
local JobConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("JobConfig"))
local PizzaArt = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("PizzaArt"))
local UIScaler = require(script.Parent:WaitForChild("UIScaler"))
local MapController = require(script.Parent:WaitForChild("MapController"))

local HudController = {}

local player = Players.LocalPlayer
local BLUE = Color3.fromRGB(20, 45, 90)
local SYMBOL = GameConfig.Economy.CurrencySymbol

local gui, moneyLabel, bonusLabel, missionFrame, missionLabel, toastHolder, cardFrame
local cardFlavor -- sabor desenhado na comanda agora
local buildCard -- definida mais abaixo
local leaveCallback
local TASK_W, TASK_H = 500, 120 -- painel de tarefa (Marco 10.23)
local taskUI = {}
local layoutTask -- definida mais abaixo

local function corner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function label(parent, props)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = props.Font or Enum.Font.GothamBold
	l.TextColor3 = props.Color or Color3.new(1, 1, 1)
	l.TextScaled = true
	l.TextXAlignment = props.Align or Enum.TextXAlignment.Left
	l.Size = props.Size
	l.Position = props.Position or UDim2.new()
	l.Text = props.Text or ""
	l.Parent = parent
	return l
end

local function formatMoney(n)
	local s = tostring(math.floor(n))
	-- separador de milhar: 1234567 -> 1.234.567
	local formatted = s:reverse():gsub("(%d%d%d)", "%1."):reverse()
	if formatted:sub(1, 1) == "." then
		formatted = formatted:sub(2)
	end
	return SYMBOL .. " " .. formatted
end

local function formatTime(seconds)
	seconds = math.max(0, math.floor(seconds))
	local h = math.floor(seconds / 3600)
	local m = math.floor((seconds % 3600) / 60)
	if h > 0 then
		return ("%dh %02dmin"):format(h, m)
	end
	return ("%dmin %02ds"):format(m, seconds % 60)
end

local function updateMoney()
	local money = player:GetAttribute("Money")
	moneyLabel.Text = money and formatMoney(money) or (SYMBOL .. " ...")
end

local function updateBonus()
	local readyAt = player:GetAttribute("BonusReadyAt")
	if not readyAt then
		bonusLabel.Text = "Bônus diário: carregando..."
		return
	end
	local left = readyAt - Workspace:GetServerTimeNow()
	if left <= 0 then
		bonusLabel.Text = ("Bônus diário (%s %d): trabalhe e conclua um pedido!"):format(SYMBOL, GameConfig.DailyBonus.Amount)
		bonusLabel.TextColor3 = Color3.fromRGB(255, 220, 90)
	elseif player:GetAttribute("SalarioEm") then
		-- Marco 10.15: no emprego mostra o cargo e quando cai o próximo salário
		local pay = math.max(0, player:GetAttribute("SalarioEm") - Workspace:GetServerTimeNow())
		bonusLabel.Text = ("💼 %s · salário em %d:%02d"):format(tostring(player:GetAttribute("Cargo") or "Estagiário"), pay // 60, pay % 60)
		bonusLabel.TextColor3 = Color3.fromRGB(200, 240, 200)
	else
		bonusLabel.Text = "Próximo bônus em " .. formatTime(left)
		bonusLabel.TextColor3 = Color3.fromRGB(200, 220, 255)
	end
end

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "HudUI"
	gui.ResetOnSpawn = false
	gui.Parent = player:WaitForChild("PlayerGui")

	-- Saldo e bônus (canto superior esquerdo)
	local wallet = Instance.new("Frame")
	wallet.Name = "Wallet"
	wallet.Size = UDim2.fromOffset(260, 58)
	wallet.Position = UDim2.fromOffset(12, 12)
	wallet.BackgroundColor3 = BLUE
	wallet.BackgroundTransparency = 0.15
	wallet.Parent = gui
	corner(wallet, 12)
	UIScaler.attach(wallet)

	moneyLabel = label(wallet, {
		Size = UDim2.new(1, -16, 0, 30),
		Position = UDim2.fromOffset(8, 4),
		Font = Enum.Font.GothamBlack,
		Color = Color3.fromRGB(140, 230, 140),
	})
	bonusLabel = label(wallet, {
		Size = UDim2.new(1, -16, 0, 18),
		Position = UDim2.fromOffset(8, 36),
		Font = Enum.Font.Gotham,
	})

	-- Tarefa do emprego (topo, centro), com botão para sair do emprego
	missionFrame = Instance.new("Frame")
	missionFrame.Name = "Mission"
	missionFrame.AnchorPoint = Vector2.new(0.5, 0)
	missionFrame.Position = UDim2.new(0.5, 0, 0, 6) -- logo abaixo da faixa do topo (onde fica o botão do mapa)
	missionFrame.Size = UDim2.fromOffset(TASK_W, TASK_H)
	missionFrame.BackgroundColor3 = Color3.fromRGB(24, 32, 58)
	missionFrame.BackgroundTransparency = 0.08
	missionFrame.Visible = false
	missionFrame.Parent = gui
	corner(missionFrame, 12)
	UIScaler.attach(missionFrame)
	taskUI.stroke = Instance.new("UIStroke")
	taskUI.stroke.Color = Color3.fromRGB(240, 160, 50)
	taskUI.stroke.Thickness = 2
	taskUI.stroke.Parent = missionFrame
	taskUI.head = label(missionFrame, { Size = UDim2.new(1, -118, 0, 18), Position = UDim2.fromOffset(12, 6), Color = Color3.fromRGB(255, 205, 110), Font = Enum.Font.GothamBold })
	-- barrinha com um pedaço por etapa
	taskUI.bar = Instance.new("Frame")
	taskUI.bar.BackgroundTransparency = 1
	taskUI.bar.Position = UDim2.fromOffset(12, 27)
	taskUI.bar.Size = UDim2.new(1, -118, 0, 7)
	taskUI.bar.Parent = missionFrame
	local barLayout = Instance.new("UIListLayout")
	barLayout.FillDirection = Enum.FillDirection.Horizontal
	barLayout.Padding = UDim.new(0, 3)
	barLayout.SortOrder = Enum.SortOrder.LayoutOrder
	barLayout.Parent = taskUI.bar
	missionLabel = label(missionFrame, { Size = UDim2.new(1, -118, 0, 36), Position = UDim2.fromOffset(12, 38), Font = Enum.Font.GothamBlack })
	missionLabel.TextWrapped = true
	-- o que fazer agora: seta para o lugar, distância e o botão
	taskUI.arrow = label(missionFrame, { Text = "▲", Size = UDim2.fromOffset(26, 26), Position = UDim2.fromOffset(10, 74), Color = Color3.fromRGB(120, 230, 150), Font = Enum.Font.GothamBlack, Align = Enum.TextXAlignment.Center })
	taskUI.guide = label(missionFrame, { Size = UDim2.new(1, -48, 0, 20), Position = UDim2.fromOffset(40, 77), Color = Color3.fromRGB(150, 235, 170) })
	taskUI.nextLabel = label(missionFrame, { Size = UDim2.new(1, -24, 0, 16), Position = UDim2.fromOffset(12, 99), Color = Color3.fromRGB(170, 180, 210), Font = Enum.Font.Gotham })
	-- lista inteira (abre no botão ▼)
	taskUI.list = Instance.new("Frame")
	taskUI.list.BackgroundTransparency = 1
	taskUI.list.Position = UDim2.fromOffset(12, TASK_H - 2)
	taskUI.list.Size = UDim2.new(1, -24, 0, 0)
	taskUI.list.Visible = false
	taskUI.list.Parent = missionFrame
	local toggle = Instance.new("TextButton")
	toggle.Name = "Etapas"
	toggle.AnchorPoint = Vector2.new(1, 0)
	toggle.Position = UDim2.new(1, -8, 0, 54)
	toggle.Size = UDim2.fromOffset(92, 24)
	toggle.BackgroundColor3 = Color3.fromRGB(60, 74, 120)
	toggle.Font = Enum.Font.GothamBold
	toggle.TextSize = 13
	toggle.TextColor3 = Color3.new(1, 1, 1)
	toggle.Text = "▼ Etapas (T)"
	toggle.Parent = missionFrame
	corner(toggle, 8)
	taskUI.toggle = toggle
	local function toggleList()
		taskUI.open = not taskUI.open
		toggle.Text = taskUI.open and "▲ Fechar (T)" or "▼ Etapas (T)"
		layoutTask()
	end
	toggle.Activated:Connect(toggleList)
	-- com a câmera travada o mouse não clica na tela, então a lista abre também pela tecla T
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Enum.KeyCode.T and missionFrame.Visible and toggle.Visible then
			toggleList()
		end
	end)
	local leave = Instance.new("TextButton")
	leave.Name = "Leave"
	leave.AnchorPoint = Vector2.new(1, 0.5)
	leave.Position = UDim2.new(1, -8, 0, 26)
	leave.Size = UDim2.fromOffset(92, 26)
	leave.BackgroundColor3 = Color3.fromRGB(160, 60, 40)
	leave.Font = Enum.Font.GothamBold
	leave.TextSize = 15
	leave.TextColor3 = Color3.new(1, 1, 1)
	leave.Text = "Sair do emprego"
	leave.TextSize = 11
	leave.Parent = missionFrame
	corner(leave, 10)
	-- Marco 8.1: preso não sai do emprego de Presidiário (o botão some)
	local function showLeave()
		leave.Visible = player:GetAttribute("Preso") ~= true and not taskUI.heist
	end
	taskUI.showLeave = showLeave
	player:GetAttributeChangedSignal("Preso"):Connect(showLeave)
	showLeave()
	leave.Activated:Connect(function()
		if leaveCallback then
			leaveCallback()
		end
	end)

	-- Avisos de pagamento (meio da tela)
	toastHolder = Instance.new("Frame")
	toastHolder.Name = "Toasts"
	toastHolder.AnchorPoint = Vector2.new(0.5, 0)
	toastHolder.Position = UDim2.new(0.5, 0, 0, 132)
	toastHolder.Size = UDim2.fromOffset(360, 200)
	toastHolder.BackgroundTransparency = 1
	toastHolder.Parent = gui
	UIScaler.attach(toastHolder)
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = toastHolder

	buildCard()

	player:GetAttributeChangedSignal("Money"):Connect(updateMoney)
	player:GetAttributeChangedSignal("BonusReadyAt"):Connect(updateBonus)
	updateMoney()
	updateBonus()
	task.spawn(function()
		while true do
			task.wait(1)
			updateBonus()
		end
	end)
end

---------------------------------------------------------------------------
-- Comanda da pizza (canto direito, abaixo do topo): desenho do sabor + ingredientes com ✓
---------------------------------------------------------------------------

function buildCard()
	cardFrame = Instance.new("Frame")
	cardFrame.Name = "Comanda"
	cardFrame.AnchorPoint = Vector2.new(1, 0)
	cardFrame.Position = UDim2.new(1, -12, 0, 206) -- canto direito, embaixo do minimapa e das barras (Marco 10.12)
	UIScaler.onChanged(function(sc)
		cardFrame.Position = UDim2.new(1, -12, 0, 206 * sc)
	end)
	cardFrame.Size = UDim2.fromOffset(180, 250)
	cardFrame.BackgroundColor3 = Color3.fromRGB(255, 250, 235)
	cardFrame.Visible = false
	cardFrame.Parent = gui
	corner(cardFrame, 12)
	UIScaler.attach(cardFrame)
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(200, 50, 45)
	stroke.Thickness = 3
	stroke.Parent = cardFrame
	local content = Instance.new("Frame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.Size = UDim2.fromScale(1, 1)
	content.Parent = cardFrame
end

-- Comanda em lista (mercado): quadradinho colorido, texto, ✓ quando feito e destaque no que é agora
local function showListCard(card)
	cardFlavor = nil
	local content = cardFrame.Content
	content:ClearAllChildren()
	local green = Color3.fromRGB(40, 140, 70)
	label(content, { Text = tostring(card.title or "Tarefa"):upper(), Size = UDim2.new(1, -16, 0, 18), Position = UDim2.fromOffset(8, 6), Color = green, Font = Enum.Font.GothamBlack, Align = Enum.TextXAlignment.Center })
	local y = 30
	for _, row in ipairs(card.rows) do
		local f = Instance.new("Frame")
		f.Position = UDim2.fromOffset(6, y)
		f.Size = UDim2.new(1, -12, 0, 24)
		f.BackgroundColor3 = Color3.fromRGB(255, 230, 150)
		f.BackgroundTransparency = row.now and 0 or 1
		f.Parent = content
		corner(f, 6)
		local chip = Instance.new("Frame")
		chip.Position = UDim2.fromOffset(4, 3)
		chip.Size = UDim2.fromOffset(18, 18)
		chip.BackgroundColor3 = typeof(row.color) == "Color3" and row.color or Color3.fromRGB(200, 200, 200)
		chip.Parent = f
		corner(chip, 5)
		local chipStroke = Instance.new("UIStroke")
		chipStroke.Color = Color3.fromRGB(60, 60, 60)
		chipStroke.Transparency = 0.6
		chipStroke.Parent = chip
		local text = label(f, { Text = tostring(row.label or ""), Size = UDim2.new(1, -56, 1, -6), Position = UDim2.fromOffset(28, 3), Color = row.done and Color3.fromRGB(130, 130, 130) or Color3.fromRGB(40, 35, 30) })
		text.Font = row.now and Enum.Font.GothamBlack or Enum.Font.GothamBold
		label(f, { Text = row.done and "✓" or (row.now and "•" or ""), Size = UDim2.fromOffset(22, 22), Position = UDim2.new(1, -24, 0, 1), Color = row.done and Color3.fromRGB(40, 150, 60) or Color3.fromRGB(230, 120, 30), Font = Enum.Font.GothamBlack, Align = Enum.TextXAlignment.Center })
		y += 26
	end
	if card.footer then
		label(content, { Text = tostring(card.footer), Size = UDim2.new(1, -16, 0, 18), Position = UDim2.fromOffset(8, y + 4), Color = green, Align = Enum.TextXAlignment.Center })
		y += 24
	end
	cardFrame.Size = UDim2.fromOffset(190, y + 8)
	local stroke = cardFrame:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = green
	end
	cardFrame.Visible = true
end

function HudController.showCard(card)
	if not cardFrame then
		return
	end
	if type(card) == "table" and card.kind == "list" and type(card.rows) == "table" then
		showListCard(card)
		return
	end
	if type(card) ~= "table" or type(card.items) ~= "table" then
		cardFrame.Visible = false
		cardFlavor = nil
		return
	end
	local key = tostring(card.flavor)
	if cardFlavor ~= key then
		-- sabor novo: redesenha tudo
		cardFlavor = key
		local content = cardFrame.Content
		content:ClearAllChildren()
		label(content, { Text = "COMANDA", Size = UDim2.new(1, -16, 0, 18), Position = UDim2.fromOffset(8, 6), Color = Color3.fromRGB(200, 50, 45), Font = Enum.Font.GothamBlack, Align = Enum.TextXAlignment.Center })
		label(content, { Text = tostring(card.title or ""), Size = UDim2.new(1, -16, 0, 18), Position = UDim2.fromOffset(8, 24), Color = Color3.fromRGB(40, 35, 30), Align = Enum.TextXAlignment.Center })
		local art = Instance.new("Frame")
		art.BackgroundTransparency = 1
		art.Position = UDim2.fromOffset(50, 46)
		art.Size = UDim2.fromOffset(80, 80)
		art.Parent = content
		local ids = {}
		for _, item in ipairs(card.items) do
			table.insert(ids, item.id)
		end
		PizzaArt.pizza(art, ids)
		local list = Instance.new("Frame")
		list.Name = "Lista"
		list.BackgroundTransparency = 1
		list.Position = UDim2.fromOffset(10, 132)
		list.Size = UDim2.new(1, -20, 0, 112)
		list.Parent = content
		local layout = Instance.new("UIListLayout")
		layout.Padding = UDim.new(0, 2)
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Parent = list
		for i, item in ipairs(card.items) do
			local row = Instance.new("Frame")
			row.Name = tostring(item.id)
			row.LayoutOrder = i
			row.BackgroundTransparency = 1
			row.Size = UDim2.new(1, 0, 0, 24)
			row.Parent = list
			local icon = Instance.new("Frame")
			icon.BackgroundTransparency = 1
			icon.Size = UDim2.fromOffset(22, 22)
			icon.Parent = row
			PizzaArt.ingredient(icon, item.id)
			local ing = JobConfig.ingredientById(item.id)
			label(row, { Text = ing and ing.label or tostring(item.id), Size = UDim2.new(1, -56, 1, -4), Position = UDim2.fromOffset(28, 2), Color = Color3.fromRGB(40, 35, 30) })
			local check = label(row, { Text = "", Size = UDim2.fromOffset(24, 22), Position = UDim2.new(1, -24, 0, 1), Color = Color3.fromRGB(40, 150, 60), Font = Enum.Font.GothamBlack, Align = Enum.TextXAlignment.Center })
			check.Name = "Check"
		end
		cardFrame.Size = UDim2.fromOffset(180, 140 + #card.items * 26)
		local stroke = cardFrame:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = Color3.fromRGB(200, 50, 45)
		end
	end
	-- marca o que já foi colocado
	local list = cardFrame.Content:FindFirstChild("Lista")
	for _, item in ipairs(card.items) do
		local row = list and list:FindFirstChild(tostring(item.id))
		local check = row and row:FindFirstChild("Check")
		if check then
			check.Text = item.done and "✓" or ""
		end
	end
	cardFrame.Visible = true
end

function HudController.toast(text, color)
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromOffset(340, 44)
	t.BackgroundColor3 = color or Color3.fromRGB(60, 170, 80)
	t.Font = Enum.Font.GothamBlack
	t.TextScaled = true
	t.TextColor3 = Color3.new(1, 1, 1)
	t.Text = text
	t.Parent = toastHolder
	corner(t, 12)
	task.delay(3, function()
		TweenService:Create(t, TweenInfo.new(0.6), { BackgroundTransparency = 1, TextTransparency = 1 }):Play()
		task.wait(0.7)
		t:Destroy()
	end)
end

-- Marco 10.23: painel de tarefa. Mostra de quem é o pedido, a barrinha de etapas, O QUE FAZER agora
-- em letra grande, a seta com a distância até o lugar, o botão certo e o que vem depois. O botão
-- "Etapas" abre a lista inteira. Quando a etapa muda, pisca em verde.
function layoutTask()
	local rows = taskUI.rows or {}
	local open = taskUI.open and #rows > 0
	taskUI.list.Visible = open
	missionFrame.Size = UDim2.fromOffset(TASK_W, TASK_H + (open and (#rows * 21 + 4) or 0))
end

local function drawList(steps, step)
	taskUI.list:ClearAllChildren()
	taskUI.rows = {}
	for i, str in ipairs(steps or {}) do
		local done, now = i < step, i == step
		taskUI.rows[i] = label(taskUI.list, {
			Text = (done and "✓  " or (now and "▶  " or "•  ")) .. tostring(str),
			Size = UDim2.new(1, 0, 0, 19),
			Position = UDim2.fromOffset(0, (i - 1) * 21),
			Color = done and Color3.fromRGB(110, 200, 130) or (now and Color3.fromRGB(255, 225, 150) or Color3.fromRGB(170, 180, 210)),
			Font = now and Enum.Font.GothamBold or Enum.Font.Gotham,
		})
	end
end

local function clearBar()
	for _, c in ipairs(taskUI.bar:GetChildren()) do
		if c:IsA("Frame") then
			c:Destroy()
		end
	end
end

local function drawBar(step, total)
	clearBar()
	for i = 1, total do
		local piece = Instance.new("Frame")
		piece.LayoutOrder = i
		piece.BorderSizePixel = 0
		piece.Size = UDim2.new(1 / total, -3, 1, 0)
		piece.BackgroundColor3 = i < step and Color3.fromRGB(90, 200, 120) or (i == step and Color3.fromRGB(245, 170, 60) or Color3.fromRGB(70, 80, 112))
		piece.Parent = taskUI.bar
		corner(piece, 3)
	end
end

local function flashTask()
	taskUI.stroke.Color = Color3.fromRGB(110, 240, 140)
	taskUI.stroke.Thickness = 4
	missionLabel.TextColor3 = Color3.fromRGB(150, 255, 170)
	local info = TweenInfo.new(0.6)
	TweenService:Create(taskUI.stroke, info, { Color = Color3.fromRGB(240, 160, 50), Thickness = 2 }):Play()
	TweenService:Create(missionLabel, info, { TextColor3 = Color3.new(1, 1, 1) }):Play()
end

-- info = { head, step, total, steps, text, next, action, hold, waiting, targets = { Vector3 } }
function HudController.showTask(info)
	if taskUI.heist and not info.isHeist then
		taskUI.saved = { info = info } -- o assalto está na tela: o emprego volta depois
		return
	end
	missionFrame.Visible = true
	taskUI.toggle.Visible = #(info.steps or {}) > 1
	taskUI.head.Text = info.head or ""
	missionLabel.Text = info.text or ""
	taskUI.nextLabel.Text = info.next and ("Depois: " .. info.next) or (info.isHeist and "" or "Última etapa: depois é só receber!")
	taskUI.info = info
	local key = (info.head or "") .. "|" .. tostring(info.step)
	if key ~= taskUI.key then
		local same = taskUI.key ~= nil
		taskUI.key = key
		drawBar(info.step or 1, info.total or 1)
		drawList(info.steps, info.step or 1)
		layoutTask()
		if same then
			flashTask()
		end
	end
end

-- Texto simples no painel ("Próximo pedido chegando..."); nil esconde
function HudController.setTask(text)
	if taskUI.heist then
		taskUI.saved = text and { text = text } or nil
		return
	end
	missionFrame.Visible = text ~= nil
	missionLabel.Text = text or ""
	taskUI.info, taskUI.key, taskUI.rows = nil, nil, nil
	taskUI.open = false
	taskUI.toggle.Text = "▼ Etapas (T)"
	taskUI.toggle.Visible = false
	taskUI.head.Text, taskUI.guide.Text, taskUI.nextLabel.Text = "", "", ""
	taskUI.arrow.Visible = false
	clearBar()
	layoutTask()
end

-- Marco 10.24: assalto em andamento usa o mesmo painel, por cima da tarefa do emprego (nil devolve)
function HudController.setHeistTask(info)
	if info then
		if not taskUI.heist then
			taskUI.heist = true
			taskUI.key = nil
			taskUI.showLeave()
		end
		info.isHeist = true
		HudController.showTask(info)
	elseif taskUI.heist then
		taskUI.heist = false
		taskUI.showLeave()
		local saved = taskUI.saved
		taskUI.saved = nil
		HudController.setTask(saved and saved.text or nil)
		if saved and saved.info then
			HudController.showTask(saved.info)
		end
	end
end

-- Marcador flutuando em cima de um lugar (peça só deste aparelho; quem chama apaga com :Destroy())
function HudController.newMarker(pos, text)
	local part = Instance.new("Part")
	part.Name = "GuiaTarefa"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = Vector3.new(1, 1, 1)
	part.Position = pos
	part.Parent = Workspace
	local board = Instance.new("BillboardGui")
	board.AlwaysOnTop = true
	board.Size = UDim2.fromOffset(170, 44)
	board.StudsOffset = Vector3.new(0, 5, 0)
	board.LightInfluence = 0
	board.Parent = part
	local l = Instance.new("TextLabel")
	l.Size = UDim2.fromScale(1, 1)
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBlack
	l.TextColor3 = Color3.fromRGB(255, 215, 120)
	l.TextStrokeTransparency = 0.3
	l.TextScaled = true
	l.Text = "⬇ " .. tostring(text or "Aqui") .. " ⬇"
	l.Parent = board
	task.spawn(function()
		while part.Parent do
			board.StudsOffset = Vector3.new(0, 5 + math.sin(os.clock() * 3) * 0.5, 0)
			task.wait(0.05)
		end
	end)
	return part
end

-- seta e distância: o lugar mais perto da etapa, em relação para onde a câmera olha
local function updateGuide()
	local info = taskUI.info
	if not info or not missionFrame.Visible then
		return
	end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local camera = Workspace.CurrentCamera
	local best, bestD
	for _, pos in ipairs(info.targets or {}) do
		local d = root and (pos - root.Position).Magnitude
		if d and (not bestD or d < bestD) then
			best, bestD = pos, d
		end
	end
	local button = (UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled) and "o botão" or "E"
	local press = ((info.hold or 0) > 0 and "Segure " or "Aperte ") .. button
	if info.waiting then
		taskUI.arrow.Visible = false
		taskUI.guide.Text = "⏳ " .. info.waiting
	elseif best and bestD > 14 and camera then
		taskUI.arrow.Visible = true
		local look = camera.CFrame.LookVector * Vector3.new(1, 0, 1)
		local dir = (best - root.Position) * Vector3.new(1, 0, 1)
		if look.Magnitude > 0.01 and dir.Magnitude > 0.01 then
			look, dir = look.Unit, dir.Unit
			taskUI.arrow.Rotation = math.deg(math.atan2(look.X * dir.Z - look.Z * dir.X, look.X * dir.X + look.Z * dir.Z))
		end
		taskUI.guide.Text = ("Siga a seta: %d m até lá"):format(math.floor(bestD / 3.5 + 0.5))
	else
		taskUI.arrow.Visible = false
		taskUI.guide.Text = info.hint and ("👉 " .. info.hint) or (info.action and ("👉 %s: %s"):format(press, info.action) or ("👉 Chegou! " .. press))
	end
end

-- fn é chamada quando o jogador toca em "Sair" na faixa da tarefa
function HudController.onLeaveJob(fn)
	leaveCallback = fn
end

function HudController.init()
	build()
	RunService.RenderStepped:Connect(updateGuide)
	MapController.init()
end

return HudController
