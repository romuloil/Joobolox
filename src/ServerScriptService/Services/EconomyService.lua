-- EconomyService (ModuleScript)
-- Caminho: ServerScriptService > Services > EconomyService
-- Único lugar que mexe no dinheiro dos jogadores.
-- O dinheiro aparece na lista de jogadores (leaderstats) e no atributo "Money",
-- que a interface do cliente só LÊ.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))
local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))

local EconomyService = {}

local ECON = GameConfig.Economy

local function isValidAmount(amount)
	return type(amount) == "number" and amount == amount and amount > 0 and amount <= ECON.MaxMoney and math.floor(amount) == amount
end

local function publish(player, money)
	player:SetAttribute("Money", money)
	local stats = player:FindFirstChild("leaderstats")
	local value = stats and stats:FindFirstChild("Dinheiro")
	if value then
		value.Value = money
	end
end

function EconomyService.getMoney(player)
	local data = PlayerDataService.get(player)
	return data and data.money or nil
end

-- Dá dinheiro ao jogador. reason é só para o log. Retorna true se pagou.
function EconomyService.add(player, amount, reason)
	if not isValidAmount(amount) then
		warn(("[EconomyService] Valor inválido para %s: %s"):format(player.Name, tostring(amount)))
		return false
	end
	local data = PlayerDataService.get(player)
	if not data then
		return false -- dados ainda não carregaram: não paga
	end
	local newMoney = math.min(data.money + amount, ECON.MaxMoney)
	PlayerDataService.set(player, "money", newMoney)
	publish(player, newMoney)
	print(("[EconomyService] +%d para %s (%s). Saldo: %d"):format(amount, player.Name, tostring(reason), newMoney))
	return true
end

-- Tira dinheiro (compras, no futuro). Retorna false se não tiver saldo.
function EconomyService.spend(player, amount, reason)
	if not isValidAmount(amount) then
		return false
	end
	local data = PlayerDataService.get(player)
	if not data or data.money < amount then
		return false
	end
	local newMoney = data.money - amount
	PlayerDataService.set(player, "money", newMoney)
	publish(player, newMoney)
	print(("[EconomyService] -%d de %s (%s). Saldo: %d"):format(amount, player.Name, tostring(reason), newMoney))
	return true
end

function EconomyService.init()
	local function setupStats(player)
		if player:FindFirstChild("leaderstats") then
			return
		end
		local stats = Instance.new("Folder")
		stats.Name = "leaderstats" -- nome obrigatório para aparecer na lista de jogadores
		local value = Instance.new("IntValue")
		value.Name = "Dinheiro"
		value.Parent = stats
		stats.Parent = player
	end
	Players.PlayerAdded:Connect(setupStats)
	for _, player in ipairs(Players:GetPlayers()) do
		setupStats(player)
	end

	PlayerDataService.onLoaded(function(player, data)
		setupStats(player)
		publish(player, data.money)
	end)
end

return EconomyService
