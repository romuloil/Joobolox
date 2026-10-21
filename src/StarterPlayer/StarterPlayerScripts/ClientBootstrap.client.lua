-- ClientBootstrap (LocalScript)
-- Caminho: StarterPlayer > StarterPlayerScripts > ClientBootstrap
-- Interface básica:
--   * mensagem de boas-vindas
--   * botão grande da bicicleta (toque no celular, clique ou tecla B no PC)
--   * botão do carro (tecla V): chama o carro, entra e sai (CarController dirige)
--   * animação da bicicleta (BikeAnimator)
--   * tutorial e conversa com o Seu Bento, empregos (Controllers)
-- O cliente só PEDE para montar; quem decide é o servidor.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local vehicleRequest = remotes:WaitForChild(GameConfig.Remotes.VehicleRequest)
local uiUpdate = remotes:WaitForChild(GameConfig.Remotes.UIUpdate)
local tutorialRequest = remotes:WaitForChild(GameConfig.Remotes.TutorialRequest)

local Controllers = script.Parent:WaitForChild("Controllers")
local TutorialController = require(Controllers:WaitForChild("TutorialController"))
local HudController = require(Controllers:WaitForChild("HudController"))
local BikeAnimator = require(Controllers:WaitForChild("BikeAnimator"))
local JobController = require(Controllers:WaitForChild("JobController"))
local CarController = require(Controllers:WaitForChild("CarController"))
local UIScaler = require(Controllers:WaitForChild("UIScaler"))
local PrisonController = require(Controllers:WaitForChild("PrisonController"))
local PoliceController = require(Controllers:WaitForChild("PoliceController"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local BLUE = Color3.fromRGB(20, 45, 90)
local GREEN = Color3.fromRGB(60, 170, 80)

local function corner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

-- Tela principal
local gui = Instance.new("ScreenGui")
gui.Name = "GameUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.Parent = playerGui

-- Botão da bicicleta (canto inferior direito, grande para o polegar)
local bikeButton = Instance.new("TextButton")
bikeButton.Name = "BikeButton"
bikeButton.AnchorPoint = Vector2.new(1, 1)
bikeButton.Size = UDim2.fromOffset(150, 64)
bikeButton.Position = UDim2.new(1, -16, 1, -150) -- acima do botão de pulo no celular
bikeButton.BackgroundColor3 = GREEN
bikeButton.Font = Enum.Font.GothamBold
bikeButton.TextScaled = true
bikeButton.TextColor3 = Color3.new(1, 1, 1)
bikeButton.AutoButtonColor = true
bikeButton.Parent = gui
corner(bikeButton, 14)
UIScaler.attach(bikeButton)

local pad = Instance.new("UIPadding")
pad.PaddingLeft = UDim.new(0, 10)
pad.PaddingRight = UDim.new(0, 10)
pad.PaddingTop = UDim.new(0, 8)
pad.PaddingBottom = UDim.new(0, 8)
pad.Parent = bikeButton

local touch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

local function setBikeText(mounted)
	local suffix = touch and "" or " [B]"
	if mounted then
		bikeButton.Text = "Descer da bike" .. suffix
		bikeButton.BackgroundColor3 = Color3.fromRGB(200, 90, 60)
	else
		bikeButton.Text = "Bicicleta" .. suffix
		bikeButton.BackgroundColor3 = GREEN
	end
end
setBikeText(false)

local function requestBike()
	vehicleRequest:FireServer("ToggleBike")
end

bikeButton.Activated:Connect(requestBike)

-- Botão do carro, logo acima do da bike
local carButton = bikeButton:Clone()
carButton.Name = "CarButton"
carButton.Position = UDim2.new(1, -16, 1, -222)
local copiedScale = carButton:FindFirstChildOfClass("UIScale")
if copiedScale then
	copiedScale:Destroy() -- a cópia ganha a sua própria escala logo abaixo
end
carButton.Parent = gui
UIScaler.attach(carButton)

local function setCarText(driving)
	local suffix = touch and "" or " [V]"
	if driving then
		carButton.Text = "Sair do carro" .. suffix
		carButton.BackgroundColor3 = Color3.fromRGB(200, 90, 60)
	else
		carButton.Text = "Carro" .. suffix
		carButton.BackgroundColor3 = Color3.fromRGB(40, 90, 170)
	end
end
setCarText(false)

local function requestCar()
	vehicleRequest:FireServer("ToggleCar")
end
carButton.Activated:Connect(requestCar)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return -- o jogador está digitando no chat, por exemplo
	end
	if input.KeyCode == Enum.KeyCode.B then
		requestBike()
	elseif input.KeyCode == Enum.KeyCode.V then
		requestCar()
	end
end)

HudController.init()
BikeAnimator.init()
JobController.init()
CarController.init()
PrisonController.init()
PoliceController.init()

-- Respostas do servidor
uiUpdate.OnClientEvent:Connect(function(kind, data)
	if type(data) ~= "table" then
		return
	end
	if kind == "BikeState" then
		setBikeText(data.mounted == true)
	elseif kind == "CarState" then
		setCarText(data.driving == true)
	elseif kind == "Notice" then
		HudController.toast(tostring(data.text or ""), Color3.fromRGB(200, 90, 60))
	elseif kind == "StartTutorial" then
		task.spawn(TutorialController.run, true)
	elseif kind == "GuideDialog" then
		task.spawn(TutorialController.run, false)
	elseif kind == "PrisonState" then
		PrisonController.handle(data)
	elseif kind == "PoliceState" or kind == "PolicePanel" or kind == "PoliceReports" then
		PoliceController.handle(kind, data)
	elseif kind:sub(1, 3) == "Job" then
		JobController.handle(kind, data)
	end
end)

-- Mensagem de boas-vindas que some sozinha
local welcome = Instance.new("TextLabel")
welcome.Name = "Welcome"
welcome.AnchorPoint = Vector2.new(0.5, 0)
welcome.Size = UDim2.new(0.8, 0, 0, 70)
welcome.Position = UDim2.new(0.5, 0, 0, 90)
welcome.BackgroundColor3 = BLUE
welcome.BackgroundTransparency = 0.1
welcome.Font = Enum.Font.GothamBold
welcome.TextScaled = true
welcome.TextColor3 = Color3.new(1, 1, 1)
welcome.Text = "Bem-vindo a " .. GameConfig.CityName .. "! Pegue sua bicicleta e explore o bairro."
welcome.Parent = gui
corner(welcome, 14)
UIScaler.attach(welcome)

local sizeLimit = Instance.new("UISizeConstraint")
sizeLimit.MaxSize = Vector2.new(640, 70)
sizeLimit.Parent = welcome

-- Avisa o servidor que a interface está pronta (ele decide se mostra o tutorial)
task.spawn(function()
	if not player.Character then
		player.CharacterAdded:Wait()
	end
	task.wait(1)
	tutorialRequest:FireServer("Ready")
end)

task.delay(6, function()
	local fade = TweenInfo.new(1)
	TweenService:Create(welcome, fade, { BackgroundTransparency = 1, TextTransparency = 1 }):Play()
	task.wait(1.1)
	welcome:Destroy()
end)
