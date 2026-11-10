-- TutorialService (ModuleScript)
-- Caminho: ServerScriptService > Services > TutorialService
-- Decide quem vê o tutorial: só quem ainda não concluiu (ou pulou).
-- O tutorial começa quando DUAS coisas aconteceram: os dados carregaram
-- e o cliente avisou que está pronto. Isso evita mandar o aviso cedo demais.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))
local SecurityService = require(script.Parent:WaitForChild("SecurityService"))
local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))

local TutorialService = {}

local uiUpdate
local clientReady = {} -- clientReady[player] = true depois do "Ready"
local started = {} -- started[player] = true quando o tutorial foi enviado

local function tryStart(player)
	if started[player] or not clientReady[player] then
		return
	end
	local data = PlayerDataService.get(player)
	if not data then
		return -- ainda carregando; tenta de novo quando carregar
	end
	if data.tutorialDone then
		return
	end
	started[player] = true
	uiUpdate:FireClient(player, "StartTutorial", {})
end

local function onTutorialRequest(player, action)
	if not SecurityService.checkRate(player, "TutorialRequest", 1) then
		return
	end
	if not SecurityService.isShortString(action, 16) then
		return
	end

	if action == "Ready" then
		clientReady[player] = true
		tryStart(player)
	elseif action == "Finish" then
		-- Só vale se o servidor realmente começou o tutorial para esse jogador
		if not started[player] then
			return
		end
		local data = PlayerDataService.get(player)
		if data and not data.tutorialDone then
			PlayerDataService.set(player, "tutorialDone", true)
			task.spawn(PlayerDataService.save, player)
		end
	end
end

function TutorialService.init(remotes)
	uiUpdate = remotes[GameConfig.Remotes.UIUpdate]
	remotes[GameConfig.Remotes.TutorialRequest].OnServerEvent:Connect(onTutorialRequest)

	PlayerDataService.onLoaded(function(player)
		tryStart(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		clientReady[player] = nil
		started[player] = nil
	end)
end

return TutorialService
