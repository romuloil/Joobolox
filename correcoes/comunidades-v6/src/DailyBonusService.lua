-- DailyBonusService (ModuleScript)
-- Caminho: ServerScriptService > Services > DailyBonusService
-- Regra (documento mestre, seção 12):
--   * o bônus fica disponível até o jogador concluir uma tarefa válida;
--   * ao resgatar, começa um tempo de espera de 24 horas;
--   * quem não entra não perde nada (não existe sequência diária);
--   * sair, trocar de servidor ou reconectar não reinicia nem duplica.
-- A hora do último resgate fica salva no DataStore (os.time(), igual em todos os servidores).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))
local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))
local EconomyService = require(script.Parent:WaitForChild("EconomyService"))

local DailyBonusService = {}

local BONUS = GameConfig.DailyBonus

local function publish(player, lastClaim)
	-- O cliente usa este horário só para mostrar a contagem regressiva
	player:SetAttribute("BonusReadyAt", lastClaim + BONUS.Cooldown)
end

function DailyBonusService.isAvailable(player)
	local data = PlayerDataService.get(player)
	if not data then
		return false
	end
	return os.time() - data.lastBonusClaim >= BONUS.Cooldown
end

-- Chamado pelo MissionService quando uma tarefa válida é concluída.
-- Retorna o valor pago (0 se o bônus não estava disponível).
function DailyBonusService.tryClaim(player)
	if not DailyBonusService.isAvailable(player) then
		return 0
	end
	local now = os.time()
	PlayerDataService.set(player, "lastBonusClaim", now)
	if not EconomyService.add(player, BONUS.Amount, "Bônus diário") then
		return 0
	end
	publish(player, now)
	-- Salva na hora: se o jogador trocar de servidor, o outro já sabe que ele resgatou
	task.spawn(PlayerDataService.save, player)
	return BONUS.Amount
end

function DailyBonusService.init()
	PlayerDataService.onLoaded(function(player, data)
		publish(player, data.lastBonusClaim)
	end)
end

return DailyBonusService
