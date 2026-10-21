-- DialogController (ModuleScript)
-- Caminho: StarterPlayer > StarterPlayerScripts > Controllers > DialogController
-- Caixa de diálogo na parte de baixo da tela, com botões grandes (bons para celular).
--
-- Uso:
--   local escolha = DialogController.show("Seu Bento", {"fala 1", "fala 2"},
--       { {id = "sim", text = "Sim"}, {id = "nao", text = "Não"} }, true)
-- A função espera o jogador e devolve o id do botão escolhido,
-- ou "skip" se ele apertou "Pular" (quando allowSkip = true).

local Players = game:GetService("Players")

local UIScaler = require(script.Parent:WaitForChild("UIScaler"))

local DialogController = {}

local BLUE = Color3.fromRGB(20, 45, 90)
local GREEN = Color3.fromRGB(60, 170, 80)

local player = Players.LocalPlayer
local gui, panel, nameLabel, textLabel, buttonRow, skipButton
local activeEvent -- BindableEvent do diálogo aberto (nil se nenhum)

local function corner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "DialogUI"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 10
	gui.Parent = player:WaitForChild("PlayerGui")

	panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 1)
	panel.Position = UDim2.new(0.5, 0, 1, -20)
	panel.Size = UDim2.new(0.92, 0, 0, 190)
	panel.BackgroundColor3 = BLUE
	panel.BackgroundTransparency = 0.05
	panel.Visible = false
	panel.Parent = gui
	corner(panel, 16)

	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(760, 190)
	limit.Parent = panel
	UIScaler.attach(panel)

	nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, -24, 0, 30)
	nameLabel.Position = UDim2.fromOffset(12, 8)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.GothamBlack
	nameLabel.TextSize = 22
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextColor3 = Color3.fromRGB(255, 210, 90)
	nameLabel.Parent = panel

	textLabel = Instance.new("TextLabel")
	textLabel.Size = UDim2.new(1, -24, 0, 80)
	textLabel.Position = UDim2.fromOffset(12, 40)
	textLabel.BackgroundTransparency = 1
	textLabel.Font = Enum.Font.Gotham
	textLabel.TextSize = 20
	textLabel.TextWrapped = true
	textLabel.TextXAlignment = Enum.TextXAlignment.Left
	textLabel.TextYAlignment = Enum.TextYAlignment.Top
	textLabel.TextColor3 = Color3.new(1, 1, 1)
	textLabel.Parent = panel

	buttonRow = Instance.new("Frame")
	buttonRow.Size = UDim2.new(1, -24, 0, 50)
	buttonRow.Position = UDim2.new(0, 12, 1, -60)
	buttonRow.BackgroundTransparency = 1
	buttonRow.Parent = panel

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	layout.Padding = UDim.new(0, 10)
	layout.Parent = buttonRow

	skipButton = Instance.new("TextButton")
	skipButton.Name = "Skip"
	skipButton.AnchorPoint = Vector2.new(1, 0)
	skipButton.Position = UDim2.new(1, -16, 0, 16)
	skipButton.Size = UDim2.fromOffset(110, 44)
	skipButton.BackgroundColor3 = Color3.fromRGB(90, 90, 100)
	skipButton.Font = Enum.Font.GothamBold
	skipButton.TextSize = 18
	skipButton.TextColor3 = Color3.new(1, 1, 1)
	skipButton.Text = "Pular"
	skipButton.Visible = false
	skipButton.Parent = gui
	corner(skipButton, 12)
	UIScaler.attach(skipButton)

	skipButton.Activated:Connect(function()
		if activeEvent then
			activeEvent:Fire("skip")
		end
	end)
end

local function setButtons(options)
	for _, child in ipairs(buttonRow:GetChildren()) do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end
	for i, option in ipairs(options) do
		local b = Instance.new("TextButton")
		b.Name = option.id
		b.LayoutOrder = i
		b.Size = UDim2.fromOffset(#options >= 3 and 150 or 170, 50)
		b.BackgroundColor3 = (i == 1) and GREEN or Color3.fromRGB(70, 90, 140)
		b.Font = Enum.Font.GothamBold
		b.TextSize = 20
		b.TextColor3 = Color3.new(1, 1, 1)
		b.Text = option.text
		b.Parent = buttonRow
		corner(b, 12)
		b.Activated:Connect(function()
			if activeEvent then
				activeEvent:Fire(option.id)
			end
		end)
	end
end

function DialogController.isOpen()
	return activeEvent ~= nil
end

function DialogController.show(speaker, lines, options, allowSkip)
	if not gui then
		build()
	end
	if activeEvent then
		return nil -- já existe um diálogo aberto
	end
	local event = Instance.new("BindableEvent")
	activeEvent = event
	panel.Visible = true
	skipButton.Visible = allowSkip == true
	nameLabel.Text = speaker

	local result = "next"
	for i, line in ipairs(lines) do
		textLabel.Text = line
		local isLast = (i == #lines)
		if isLast and options and #options > 0 then
			setButtons(options)
		else
			setButtons({ { id = "next", text = "Continuar" } })
		end
		local choice = event.Event:Wait()
		if choice == "skip" or isLast then
			result = choice
			break
		end
	end

	activeEvent = nil
	event:Destroy()
	panel.Visible = false
	skipButton.Visible = false
	return result
end

return DialogController
