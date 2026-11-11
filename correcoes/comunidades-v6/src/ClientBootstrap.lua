-- ClientBootstrap (LocalScript)
-- Caminho: StarterPlayer > StarterPlayerScripts > ClientBootstrap
-- Interface básica:
--   * mensagem de boas-vindas
--   * bike e carro saem da Garagem (GarageController, Marco 6.3); os botões só aparecem
--     para descer da bike (B) e sair do carro (V); V perto do seu carro entra nele
--   * animação da bicicleta (BikeAnimator)
--   * tutorial e conversa com o Seu Bento, empregos, casa (Controllers)
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
local MobileButtons = require(Controllers:WaitForChild("MobileButtons"))
local DownedController = require(Controllers:WaitForChild("DownedController"))
local FireController = require(Controllers:WaitForChild("FireController"))
local HomeController = require(Controllers:WaitForChild("HomeController"))
local GarageController = require(Controllers:WaitForChild("GarageController"))
local PaintController = require(Controllers:WaitForChild("PaintController"))
local PetController = require(Controllers:WaitForChild("PetController"))
local ParkController = require(Controllers:WaitForChild("ParkController"))
local LightingController = require(Controllers:WaitForChild("LightingController"))
local PrisonController = require(Controllers:WaitForChild("PrisonController"))
local AmbienceController = require(Controllers:WaitForChild("AmbienceController"))
local GangController = require(Controllers:WaitForChild("GangController"))
local InventoryController = require(Controllers:WaitForChild("InventoryController"))
local WeaponController = require(Controllers:WaitForChild("WeaponController"))
local CrimeController = require(Controllers:WaitForChild("CrimeController"))
local CameraController = require(Controllers:WaitForChild("CameraController"))
local JewelryController = require(Controllers:WaitForChild("JewelryController"))
local BankController = require(Controllers:WaitForChild("BankController"))
local UIScaler = require(Controllers:WaitForChild("UIScaler"))
local WeaponPose = require(Controllers:WaitForChild("WeaponPose"))
local StatusController = require(Controllers:WaitForChild("StatusController"))

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

-- Marco 10.14: no celular "Sair do carro"/"Descer da bike" vira um botão redondo em volta do pulo
local mountedNow, drivingNow = false, false
local function refreshVehicleButton()
	if not MobileButtons.enabled then
		return
	end
	bikeButton.Visible = false
	MobileButtons.show("veiculo", mountedNow or drivingNow)
	if drivingNow then
		MobileButtons.setTitle("veiculo", "Sair", "🚗")
	else
		MobileButtons.setTitle("veiculo", "Descer", "🚲")
	end
end

local function setBikeText(mounted)
	local suffix = touch and "" or " [B]"
	bikeButton.Visible = mounted -- pegar a bike é na garagem
	if mounted then
		bikeButton.Text = "Descer da bike" .. suffix
		bikeButton.BackgroundColor3 = Color3.fromRGB(200, 90, 60)
	else
		bikeButton.Text = "Bicicleta" .. suffix
		bikeButton.BackgroundColor3 = GREEN
	end
	mountedNow = mounted
	refreshVehicleButton()
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
	carButton.Visible = driving -- pegar o carro é na garagem
	if driving then
		carButton.Text = "Sair do carro" .. suffix
		carButton.BackgroundColor3 = Color3.fromRGB(200, 90, 60)
	else
		carButton.Text = "Carro" .. suffix
		carButton.BackgroundColor3 = Color3.fromRGB(40, 90, 170)
	end
	drivingNow = driving
	if MobileButtons.enabled then
		carButton.Visible = false
	end
	refreshVehicleButton()
end
setCarText(false)

local function requestCar()
	vehicleRequest:FireServer("ToggleCar")
end
carButton.Activated:Connect(requestCar)

MobileButtons.add("veiculo", {
	icon = "🚗",
	title = "Sair",
	slots = { 3, 5 },
	onPress = function()
		if drivingNow then
			requestCar()
		elseif mountedNow then
			requestBike()
		end
	end,
})
refreshVehicleButton()

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
HomeController.init()
GarageController.init()
PaintController.init()
PetController.init()
ParkController.init() -- Marco 7.4: camas elásticas e luzinhas do parque
LightingController.init() -- Marco 7.4: luz dentro das casas
PrisonController.init() -- Marco 8.1: tempo de pena do Presidiário
AmbienceController.init() -- Marco 9.12: sons de ambiente da cidade
GangController.init() -- Marco 10.1: conversa com os chefes das gangues e pipas das favelas
InventoryController.init() -- Marco 10.5: atalhos, mochila e baú
WeaponController.init() -- Marco 10.5: atirar, taser e algema
CrimeController.init() -- Marco 10.5: assaltos, estrelas, chamados da PM
CameraController.init() -- Marco 10.8: mira travada e câmera padrão (Marco 10.29: seletor no topo, sem ⚙)
JewelryController.init() -- Marco 10.8: assalto à joalheria (reconhecimento, painel, fuga)
BankController.init() -- Marco 10.20: assalto ao banco (painel, botões, eventos, fuga)
require(Controllers:WaitForChild("MochilaController")).init() -- Marco 10.26: mochila do assalto
require(Controllers:WaitForChild("PoseController")).init() -- Marco 10.26: animações feitas por código
require(Controllers:WaitForChild("DealershipController")).init() -- Marco 10.31: carros girando na concessionária
require(Controllers:WaitForChild("LitoralController")).init() -- Marco 10.32: ondas, surfe, boias e conversas da praia
WeaponPose.init() -- Marco 10.12: pose das armas (fuzil com as duas mãos, mirando)
require(Controllers:WaitForChild("FerramentasController")).init() -- Marco 10.30: perfuratriz no cofre e explosão da C4
StatusController.init() -- Marco 10.12: barras de vida e stamina, correr
DownedController.init() -- Marco 10.15: caído no chão (esperando o paramédico)
FireController.init() -- Marco 10.16: fogo do incêndio da equipe (só bombeiros veem)

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
	elseif kind == "GarageOpen" then
		GarageController.open(data)
	elseif kind == "PaintOpen" then
		PaintController.open(data)
	elseif kind == "PetShopOpen" then
		PetController.openShop(data)
	elseif kind == "PetLove" then
		PetController.love(data)
	elseif kind == "GangDialog" then
		GangController.handle(kind, data)	elseif kind == "Inventory" or kind == "Chest" then
		InventoryController.handle(kind, data)
	elseif kind == "Shot" or kind == "HitMark" or kind == "CrimeZap" then
		WeaponController.handle(kind, data)
	elseif kind:sub(1, 5) == "Crime" then
		CrimeController.handle(kind, data)
	elseif kind:sub(1, 4) == "Joia" then
		JewelryController.handle(kind, data)
	elseif kind:sub(1, 5) == "Banco" then
		BankController.handle(kind, data)
	elseif kind:sub(1, 4) == "Home" then
		HomeController.handle(kind, data)
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
welcome.Text = "Bem-vindo a " .. GameConfig.CityName .. "! Pegue sua bike ou um carro na Garagem (guarita azul) e explore a cidade."
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
