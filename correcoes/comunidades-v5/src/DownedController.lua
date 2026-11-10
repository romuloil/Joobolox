-- DownedController (ModuleScript)
-- Caminho: StarterPlayer > StarterPlayerScripts > Controllers > DownedController
-- Marco 10.15: tela de quem está CAÍDO (DownedService no servidor): tempo esperando o paramédico,
-- quantos paramédicos estão em serviço e o botão Desistir (renasce na praça sem os itens).
-- Também liga o botão "Reanimar" dos caídos só para quem é Paramédico.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))
local UIScaler = require(script.Parent:WaitForChild("UIScaler"))

local DownedController = {}

local D = GameConfig.Downed
local player = Players.LocalPlayer
local request
local gui, tint, card, timeLabel, medicLabel, giveUpButton
local downedAt -- os.clock() de quando caiu (neste cliente)
local confirming = false

local function setControls(enabled)
	pcall(function()
		local playerModule = require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule"))
		local controls = playerModule:GetControls()
		if enabled then
			controls:Enable()
		else
			controls:Disable()
		end
	end)
end

local function corner(parent, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = parent
end

local function label(parent, y, size, font, color)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Position = UDim2.fromOffset(0, y)
	l.Size = UDim2.new(1, 0, 0, size + 4)
	l.Font = font
	l.TextSize = size
	l.TextColor3 = color
	l.Text = ""
	l.Parent = parent
	return l
end

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "CaidoUI"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 20
	gui.Enabled = false
	gui.Parent = player:WaitForChild("PlayerGui")

	tint = Instance.new("Frame")
	tint.Size = UDim2.fromScale(1, 1)
	tint.BackgroundColor3 = Color3.fromRGB(90, 0, 10)
	tint.BackgroundTransparency = 0.62
	tint.BorderSizePixel = 0
	tint.Active = false
	tint.Parent = gui

	card = Instance.new("Frame")
	card.AnchorPoint = Vector2.new(0.5, 1)
	card.Position = UDim2.new(0.5, 0, 1, -30)
	card.Size = UDim2.fromOffset(330, 150)
	card.BackgroundColor3 = Color3.fromRGB(18, 20, 28)
	card.BackgroundTransparency = 0.12
	card.Parent = gui
	corner(card, 14)
	UIScaler.attach(card)

	label(card, 12, 22, Enum.Font.GothamBlack, Color3.fromRGB(255, 110, 110)).Text = "💔 Você caiu"
	timeLabel = label(card, 42, 16, Enum.Font.GothamBold, Color3.new(1, 1, 1))
	medicLabel = label(card, 66, 13, Enum.Font.Gotham, Color3.fromRGB(200, 210, 230))

	giveUpButton = Instance.new("TextButton")
	giveUpButton.AnchorPoint = Vector2.new(0.5, 0)
	giveUpButton.Position = UDim2.new(0.5, 0, 0, 96)
	giveUpButton.Size = UDim2.fromOffset(250, 38)
	giveUpButton.Font = Enum.Font.GothamBold
	giveUpButton.TextSize = 15
	giveUpButton.TextColor3 = Color3.new(1, 1, 1)
	giveUpButton.AutoButtonColor = true
	giveUpButton.Parent = card
	corner(giveUpButton, 10)
	giveUpButton.Activated:Connect(function()
		if not downedAt or os.clock() - downedAt < D.GiveUpAfter then
			return
		end
		if not confirming then
			confirming = true -- 2º toque confirma (perde os itens!)
			task.delay(3, function()
				confirming = false
			end)
			return
		end
		confirming = false
		request:FireServer("Desistir")
	end)
end

local function medicCount()
	local n = 0
	for _, p in ipairs(Players:GetPlayers()) do
		if p:GetAttribute("Job") == "Paramedico" then
			n += 1
		end
	end
	return n
end

local function refresh()
	if not gui.Enabled then
		return
	end
	local untilT = player:GetAttribute("CaidoAte")
	local left = untilT and math.max(0, math.floor(untilT - Workspace:GetServerTimeNow())) or 0
	timeLabel.Text = ("Esperando um paramédico... %d:%02d"):format(left // 60, left % 60)
	local n = medicCount()
	medicLabel.Text = n > 0 and ("🚑 %d paramédico(s) em serviço: eles veem você no mapa"):format(n) or "🚑 Nenhum paramédico em serviço agora"
	local wait = downedAt and math.ceil(D.GiveUpAfter - (os.clock() - downedAt)) or 0
	if wait > 0 then
		giveUpButton.Text = ("Desistir (%d)"):format(wait)
		giveUpButton.BackgroundColor3 = Color3.fromRGB(70, 72, 82)
	elseif confirming then
		giveUpButton.Text = "Tem certeza? Perde a mochila!"
		giveUpButton.BackgroundColor3 = Color3.fromRGB(220, 60, 50)
	else
		giveUpButton.Text = "Desistir (renasce na praça sem os itens)"
		giveUpButton.BackgroundColor3 = Color3.fromRGB(170, 60, 55)
	end
end

local function setDowned(on)
	if on == gui.Enabled then
		return
	end
	gui.Enabled = on
	confirming = false
	downedAt = on and os.clock() or nil
	setControls(not on)
	refresh()
end

local function prepCharacter(character)
	local hum = character:WaitForChild("Humanoid", 10)
	if hum then
		hum.BreakJointsOnDeath = false
		hum:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
	end
end

function DownedController.handle(kind)
	if kind == "Caiu" then
		setDowned(true)
	elseif kind == "Levantou" then
		setDowned(false)
	end
end

function DownedController.init()
	request = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild(GameConfig.Remotes.DownedRequest)
	build()
	player:GetAttributeChangedSignal("Caido"):Connect(function()
		setDowned(player:GetAttribute("Caido") == true)
	end)
	player.CharacterAdded:Connect(function(character)
		setDowned(false)
		prepCharacter(character)
	end)
	if player.Character then
		task.spawn(prepCharacter, player.Character)
	end
	setDowned(player:GetAttribute("Caido") == true)
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 0.3 then
			return
		end
		acc = 0
		refresh()
		-- botão "Reanimar" só para paramédicos
		local medic = player:GetAttribute("Job") == "Paramedico"
		for _, other in ipairs(Players:GetPlayers()) do
			local root = other ~= player and other.Character and other.Character:FindFirstChild("HumanoidRootPart")
			local prompt = root and root:FindFirstChild("ReanimarPrompt")
			if prompt and prompt.Enabled ~= medic then
				prompt.Enabled = medic
			end
		end
	end)
end

return DownedController
