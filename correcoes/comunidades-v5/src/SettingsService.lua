-- SettingsService (ModuleScript)
-- Caminho: ServerScriptService > Services > SettingsService
-- Marco 10.8: configurações de cada jogador (por enquanto só a câmera) e limites da câmera.
--   * Zoom: sem 1ª pessoa e afastando pouco (GameConfig.Camera).
--   * data.settings.freeCam vira o atributo "CamLivre" do jogador (o CameraController lê).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))
local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))

local SettingsService = {}
local CAM = GameConfig.Camera

local function applyCamera(player)
	player.CameraMode = Enum.CameraMode.Classic
	player.CameraMinZoomDistance = CAM.MinZoom
	player.CameraMaxZoomDistance = CAM.MaxZoom
end

function SettingsService.init(remotes)
	-- quem nasce depois já vem com os limites (o HomeService usa StarterPlayer.CameraMaxZoomDistance
	-- para devolver o zoom ao sair de casa)
	StarterPlayer.CameraMinZoomDistance = CAM.MinZoom
	StarterPlayer.CameraMaxZoomDistance = CAM.MaxZoom
	StarterPlayer.CameraMode = Enum.CameraMode.Classic
	StarterPlayer.EnableMouseLockOption = false -- a nossa mira travada substitui o shift lock
	for _, player in ipairs(Players:GetPlayers()) do
		applyCamera(player)
	end
	Players.PlayerAdded:Connect(applyCamera)

	PlayerDataService.onLoaded(function(player, data)
		local s = data.settings or {}
		player:SetAttribute("CamLivre", s.freeCam == true)
	end)

	remotes[GameConfig.Remotes.SettingsRequest].OnServerEvent:Connect(function(player, key, value)
		if key == "freeCam" and type(value) == "boolean" then
			local data = PlayerDataService.get(player)
			if data then
				local s = data.settings or {}
				s.freeCam = value
				PlayerDataService.set(player, "settings", s)
			end
			player:SetAttribute("CamLivre", value)
		end
	end)
end

return SettingsService
