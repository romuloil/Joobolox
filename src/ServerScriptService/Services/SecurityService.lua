-- SecurityService (ModuleScript)
-- Caminho: ServerScriptService > Services > SecurityService
-- Ferramentas de segurança usadas por todos os serviços:
-- limite de frequência (rate limit) por jogador e checagem do personagem.
-- Regra do projeto: o cliente só pede; o servidor decide.

local Players = game:GetService("Players")

local SecurityService = {}

-- lastCall[player][chave] = horário do último pedido aceito
local lastCall = {}

-- Retorna true se o jogador pode fazer a ação "key" agora.
-- interval = segundos mínimos entre dois pedidos aceitos.
function SecurityService.checkRate(player, key, interval)
	local now = workspace:GetServerTimeNow()
	local calls = lastCall[player]
	if not calls then
		calls = {}
		lastCall[player] = calls
	end
	local last = calls[key]
	if last and now - last < interval then
		return false
	end
	calls[key] = now
	return true
end

-- Retorna character, humanoid e rootPart se o personagem estiver vivo; senão nil.
function SecurityService.getLivingCharacter(player)
	local character = player.Character
	if not character then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or humanoid.Health <= 0 then
		return nil
	end
	return character, humanoid, root
end

-- Texto curto e de tamanho limitado (para argumentos vindos do cliente)
function SecurityService.isShortString(value, maxLength)
	return type(value) == "string" and #value > 0 and #value <= (maxLength or 32)
end

Players.PlayerRemoving:Connect(function(player)
	lastCall[player] = nil
end)

return SecurityService
