-- EconomyService (ModuleScript)
-- Caminho: ServerScriptService > Services > EconomyService
-- Único lugar que mexe no dinheiro dos jogadores.
-- O dinheiro aparece na lista de jogadores (leaderstats) e no atributo "Money",
-- que a interface do cliente só LÊ.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

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

-- Marco 10.15: economia nova (Revisão 2, tudo x10). Quem já jogava tem o dinheiro (e o dinheiro
-- sujo) multiplicado por 10 uma vez só, para continuar valendo o mesmo com os preços novos.
local function migrate(player, data)
	if data.econV ~= 1 then
		return
	end
	data.econV = 2
	local money = math.min((tonumber(data.money) or 0) * 10, ECON.MaxMoney)
	PlayerDataService.set(player, "money", math.floor(money))
	if tonumber(data.dirty) then
		PlayerDataService.set(player, "dirty", math.floor(data.dirty * 10))
		player:SetAttribute("DinheiroSujo", math.floor(data.dirty * 10))
	end
	publish(player, math.floor(money))
	print(("[EconomyService] Economia nova: dinheiro de %s x10 (%d)."):format(player.Name, money))
end

function EconomyService.init()
	PlayerDataService.onLoaded(migrate)
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
	-- Marco 9.15: comando de teste SÓ no Studio (no jogo publicado não existe): digite no chat
	-- "/dinheiro" (+10000) ou "/dinheiro 50000". Usa o TextChatCommand do chat novo do Roblox
	-- (o Player.Chatted antigo não chegava) e, por garantia, também o Chatted com "!dinheiro".
	local function giveTest(player, message)
		local amount = string.match(message or "", "^[!/]dinheiro%s*(%d*)")
		if amount then
			amount = tonumber(amount) or 10000
			EconomyService.add(player, math.clamp(math.floor(amount), 1, ECON.MaxMoney), "teste no Studio")
		end
	end
	if RunService:IsStudio() then
		local TextChatService = game:GetService("TextChatService")
		local command = Instance.new("TextChatCommand")
		command.Name = "ComandoDinheiro"
		command.PrimaryAlias = "/dinheiro"
		command.SecondaryAlias = "!dinheiro"
		command.Parent = TextChatService
		command.Triggered:Connect(function(source, text)
			local player = source and Players:GetPlayerByUserId(source.UserId)
			if player then
				giveTest(player, text)
			end
		end)
	end
	local function testCommands(player)
		if RunService:IsStudio() then
			player.Chatted:Connect(function(message)
				giveTest(player, message)
			end)
		end
	end
	Players.PlayerAdded:Connect(function(player)
		setupStats(player)
		testCommands(player)
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		setupStats(player)
		testCommands(player)
	end

	PlayerDataService.onLoaded(function(player, data)
		setupStats(player)
		publish(player, data.money)
	end)
end

return EconomyService
