-- HudController (ModuleScript)
-- Caminho: StarterPlayer > StarterPlayerScripts > Controllers > HudController
-- Mostra saldo, estado do bônus diário, a etapa do emprego e avisos de pagamento.
-- Só MOSTRA o que o servidor mandou; nunca decide valores.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
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
	missionFrame.Size = UDim2.fromOffset(460, 70)
	missionFrame.BackgroundColor3 = Color3.fromRGB(240, 140, 30)
	missionFrame.Visible = false
	missionFrame.Parent = gui
	corner(missionFrame, 12)
	UIScaler.attach(missionFrame)
	missionLabel = label(missionFrame, {
		Size = UDim2.new(1, -86, 1, -8),
		Position = UDim2.fromOffset(10, 4),
		Align = Enum.TextXAlignment.Left,
	})
	local leave = Instance.new("TextButton")
	leave.Name = "Leave"
	leave.AnchorPoint = Vector2.new(1, 0.5)
	leave.Position = UDim2.new(1, -8, 0.5, 0)
	leave.Size = UDim2.fromOffset(66, 40)
	leave.BackgroundColor3 = Color3.fromRGB(160, 60, 40)
	leave.Font = Enum.Font.GothamBold
	leave.TextSize = 15
	leave.TextColor3 = Color3.new(1, 1, 1)
	leave.Text = "Sair"
	leave.Parent = missionFrame
	corner(leave, 10)
	leave.Activated:Connect(function()
		if leaveCallback then
			leaveCallback()
		end
	end)

	-- Avisos de pagamento (meio da tela)
	toastHolder = Instance.new("Frame")
	toastHolder.Name = "Toasts"
	toastHolder.AnchorPoint = Vector2.new(0.5, 0)
	toastHolder.Position = UDim2.new(0.5, 0, 0, 120)
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
	cardFrame.Position = UDim2.new(1, -12, 0, 90) -- canto direito (o chat do Roblox fica à esquerda)
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

-- Mostra o texto da tarefa no topo (nil esconde)
function HudController.setTask(text)
	missionFrame.Visible = text ~= nil
	missionLabel.Text = text or ""
end

-- fn é chamada quando o jogador toca em "Sair" na faixa da tarefa
function HudController.onLeaveJob(fn)
	leaveCallback = fn
end

function HudController.init()
	build()
	MapController.init()
end

return HudController
