-- PlayerDataService (ModuleScript)
-- Caminho: ServerScriptService > Services > PlayerDataService
-- Carrega e salva os dados de cada jogador com DataStoreService.
--
-- Regras de segurança dos dados:
--   * Se o carregamento FALHAR, o jogador joga com dados padrão, mas NADA é salvo
--     nessa sessão. Assim nunca escrevemos dados vazios por cima de dados bons.
--   * Só o servidor muda os dados. O cliente nunca envia valores para salvar.
--
-- Para funcionar no Studio: publique o jogo e ligue
-- Configurações do jogo > Segurança > "Permitir acesso do Studio aos serviços de API".

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))

local PlayerDataService = {}

local CFG = GameConfig.Data

-- Formato dos dados salvos. Campos novos entram aqui com valor padrão.
local DEFAULT_DATA = {
	version = 1,
	tutorialDone = false,
	money = GameConfig.Economy.StartingMoney,
	lastBonusClaim = 0, -- os.time() do último resgate do bônus diário (0 = nunca)
	home = nil, -- Marco 6: casa do jogador (Marco 10.1: virou "homes"; o HomeService converte)
	homes = nil, -- Marco 10.1: casas do jogador por nível (homes.basica, homes.media, homes.barraco...)
	gang = nil, -- Marco 10.1: gangue ("CDA", "TDE", "CDS") ou nil
	ownedCars = {}, -- Marco 7: carros comprados (ownedCars.L5 = true)
	pet = nil, -- Marco 7: pet adotado ({ kind = "Dog", color = 1 })
	carColors = {}, -- Marco 6.4: cor de cada carro pintado na loja de pintura (carColors.L5 = {r, g, b})
	carPlates = {}, -- Marco 7.5: placa de cada carro (carPlates.L5 = "LUIS123"), escolhida na loja de pintura
	settings = nil, -- Marco 10.8: { freeCam = true } = câmera livre do Roblox em vez da mira travada
	prison = nil, -- Marco 8.1: pena que falta ({ left = segundos, tasks, need }); nil = livre
	career = nil, -- Marco 10.15: tarefas feitas em cada profissão ({ Pizzaiolo = 12 }) = cargo
	econV = 2, -- Marco 10.15: versão da economia (1 = antiga; o EconomyService multiplica por 10 uma vez)
}

local store -- DataStore (nil se o serviço não estiver disponível)
local profiles = {} -- profiles[player] = { data = {...}, canSave = bool, dirty = bool }
local loadedCallbacks = {}

-- Cópia completa (tabelas dentro de tabelas também), para jogadores não dividirem a mesma tabela
local function deepCopy(value)
	if type(value) ~= "table" then
		return value
	end
	local t = {}
	for k, v in pairs(value) do
		t[k] = deepCopy(v)
	end
	return t
end

local function copyDefaults()
	return deepCopy(DEFAULT_DATA)
end

local function keyFor(player)
	return "Player_" .. player.UserId
end

-- Tenta uma função várias vezes, esperando um pouco mais a cada falha
local function withRetries(fn)
	local lastErr
	for attempt = 1, CFG.Retries do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		lastErr = result
		task.wait(attempt * 2)
	end
	return false, lastErr
end

local function loadPlayer(player)
	local profile = { data = copyDefaults(), canSave = false, dirty = false }

	if store then
		local ok, saved = withRetries(function()
			return store:GetAsync(keyFor(player))
		end)
		if ok then
			if type(saved) == "table" then
				for k, v in pairs(saved) do
					profile.data[k] = v
				end
				if saved.econV == nil then
					profile.data.econV = 1 -- salvo antes da economia nova
				end
			end
			profile.canSave = true
		else
			warn(("[PlayerDataService] Falha ao carregar %s: %s. Progresso desta sessão NÃO será salvo."):format(player.Name, tostring(saved)))
		end
	end

	if not player.Parent then
		return -- saiu enquanto carregava
	end
	profiles[player] = profile
	for _, callback in ipairs(loadedCallbacks) do
		task.spawn(callback, player, profile.data)
	end
end

function PlayerDataService.save(player)
	local profile = profiles[player]
	if not profile or not profile.canSave or not store then
		return false
	end
	local data = profile.data
	local ok, err = withRetries(function()
		store:UpdateAsync(keyFor(player), function()
			return data
		end)
	end)
	if ok then
		profile.dirty = false
	else
		warn(("[PlayerDataService] Falha ao salvar %s: %s"):format(player.Name, tostring(err)))
	end
	return ok
end

-- Dados do jogador (nil se ainda não carregou). Só use no servidor.
function PlayerDataService.get(player)
	local profile = profiles[player]
	return profile and profile.data
end

function PlayerDataService.canPersist(player)
	local profile = profiles[player]
	return profile ~= nil and profile.canSave == true and store ~= nil
end

-- Muda um campo e marca para salvar
function PlayerDataService.set(player, key, value)
	local profile = profiles[player]
	if not profile then
		return false
	end
	profile.data[key] = value
	profile.dirty = true
	return true
end

-- Chama callback(player, data) quando os dados de um jogador terminarem de carregar
function PlayerDataService.onLoaded(callback)
	table.insert(loadedCallbacks, callback)
	for player, profile in pairs(profiles) do
		task.spawn(callback, player, profile.data)
	end
end

function PlayerDataService.init()
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(CFG.StoreName)
	end)
	if ok then
		store = result
	else
		warn("[PlayerDataService] DataStore indisponível (jogo não publicado ou acesso de API desligado). Nada será salvo: " .. tostring(result))
	end

	Players.PlayerAdded:Connect(loadPlayer)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(loadPlayer, player)
	end

	Players.PlayerRemoving:Connect(function(player)
		PlayerDataService.save(player)
		profiles[player] = nil
	end)

	-- Salvamento automático só de quem mudou algo
	task.spawn(function()
		while true do
			task.wait(CFG.AutosaveInterval)
			for player, profile in pairs(profiles) do
				if profile.dirty then
					task.spawn(PlayerDataService.save, player)
				end
			end
		end
	end)

	-- Servidor fechando: salva todo mundo antes
	game:BindToClose(function()
		local pending = 0
		for player in pairs(profiles) do
			pending += 1
			task.spawn(function()
				PlayerDataService.save(player)
				pending -= 1
			end)
		end
		local start = os.clock()
		while pending > 0 and os.clock() - start < 25 do
			task.wait(0.2)
		end
	end)
end

return PlayerDataService
