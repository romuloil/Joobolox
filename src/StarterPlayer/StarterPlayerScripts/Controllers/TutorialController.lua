-- TutorialController (ModuleScript)
-- Caminho: StarterPlayer > StarterPlayerScripts > Controllers > TutorialController
-- Tutorial curto e pulável: boas-vindas do Seu Bento, tour de câmera pelos
-- estabelecimentos e dicas finais. Também roda quando o jogador conversa com o Seu Bento.
-- O cliente só avisa o servidor no final ("Finish"); quem salva é o servidor.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local DialogConfig = require(Shared:WaitForChild("DialogConfig"))
local DialogController = require(script.Parent:WaitForChild("DialogController"))

local TutorialController = {}

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local tutorialRequest = remotes:WaitForChild(GameConfig.Remotes.TutorialRequest)
local GUIDE_NAME = GameConfig.Guide.Name
local running = false

-- Liga/desliga o movimento do jogador (para ele não sair andando durante o tour)
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

local function findSign(placeName)
	local map = Workspace:FindFirstChild("Map")
	local jobs = map and map:FindFirstChild("JobLocations")
	local shop = jobs and jobs:FindFirstChild(placeName)
	return shop and shop:FindFirstChild("Sign")
end

local function moveCamera(camera, target)
	local tween = TweenService:Create(camera, TweenInfo.new(1.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { CFrame = target })
	tween:Play()
end

-- Devolve "skip" se o jogador pulou o tour
local function runTour()
	local camera = Workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Scriptable
	setControls(false)

	local result = "done"
	moveCamera(camera, CFrame.lookAt(Vector3.new(170, 170, 170), Vector3.new(0, 0, 0)))
	if DialogController.show(GUIDE_NAME, { DialogConfig.TourIntro }, { { id = "next", text = "Próximo" } }, true) == "skip" then
		result = "skip"
	end

	if result ~= "skip" then
		for _, stop in ipairs(DialogConfig.TourStops) do
			local sign = findSign(stop.place)
			if sign then
				-- A placa olha para a rua (lado -Z); a câmera fica na frente dela
				local camPos = (sign.CFrame * CFrame.new(0, 8, -45)).Position
				moveCamera(camera, CFrame.lookAt(camPos, sign.Position))
			end
			if DialogController.show(GUIDE_NAME, { stop.text }, { { id = "next", text = "Próximo" } }, true) == "skip" then
				result = "skip"
				break
			end
		end
	end

	-- Devolve a câmera para o personagem
	camera.CameraType = Enum.CameraType.Custom
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		camera.CameraSubject = humanoid
	end
	setControls(true)
	return result
end

-- firstTime = true quando o servidor mandou começar o tutorial obrigatório
function TutorialController.run(firstTime)
	if running or DialogController.isOpen() then
		return
	end
	running = true

	local lines = firstTime and DialogConfig.Welcome or DialogConfig.GuideTalk
	local options = { { id = "tour", text = "Ver a cidade" } }
	if not firstTime then
		table.insert(options, { id = "jobs", text = "Empregos" })
	end
	table.insert(options, { id = "no", text = firstTime and "Agora não" or "Tchau" })
	local choice = DialogController.show(GUIDE_NAME, lines, options, firstTime)

	if choice == "jobs" then
		DialogController.show(GUIDE_NAME, DialogConfig.JobsInfo, { { id = "ok", text = "Entendi!" } }, false)
	elseif choice == "tour" then
		runTour()
	end
	if choice ~= "skip" and (firstTime or choice == "tour") then
		DialogController.show(GUIDE_NAME, DialogConfig.Final, { { id = "ok", text = "Vamos lá!" } }, false)
	end

	if firstTime then
		tutorialRequest:FireServer("Finish") -- concluiu ou pulou: não repete
	end
	running = false
end

return TutorialController
