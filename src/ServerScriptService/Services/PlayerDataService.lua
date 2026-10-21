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
}

local store -- DataStore (nil se o serviço não estiver disponível)
local profiles = {} -- profiles[player] = { data = {...}, canSave = bool, dirty = bool }
local loadedCallbacks = {}

local function copyDefaults()
	local t = {}
	for k, v in pairs(DEFAULT_DATA) do
		t[k] = v
	end
	return t
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
