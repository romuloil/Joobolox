-- ServerBootstrap (Script)
-- Caminho: ServerScriptService > ServerBootstrap
-- Ponto de partida do servidor. Cria os RemoteEvents, monta o mapa
-- e liga os serviços na ordem certa.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))
local Services = script.Parent:WaitForChild("Services")

local MapBuilder = require(Services:WaitForChild("MapBuilder"))
local VehicleService = require(Services:WaitForChild("VehicleService"))
local PlayerDataService = require(Services:WaitForChild("PlayerDataService"))
local NPCService = require(Services:WaitForChild("NPCService"))
local TutorialService = require(Services:WaitForChild("TutorialService"))
local EconomyService = require(Services:WaitForChild("EconomyService"))
local DailyBonusService = require(Services:WaitForChild("DailyBonusService"))
local JobService = require(Services:WaitForChild("JobService")) -- liga também o MissionService
local ZoneService = require(Services:WaitForChild("ZoneService"))
local SeatService = require(Services:WaitForChild("SeatService"))
local HomeService = require(Services:WaitForChild("HomeService"))
local PetService = require(Services:WaitForChild("PetService"))
local PrisonService = require(Services:WaitForChild("PrisonService"))
local UniformService = require(Services:WaitForChild("UniformService"))
local GangService = require(Services:WaitForChild("GangService"))
local PropService = require(Services:WaitForChild("PropService"))
local WeaponService = require(Services:WaitForChild("WeaponService"))
local InventoryService = require(Services:WaitForChild("InventoryService"))
local CrimeService = require(Services:WaitForChild("CrimeService"))
local SettingsService = require(Services:WaitForChild("SettingsService"))
local JewelryService = require(Services:WaitForChild("JewelryService"))
local BankService = require(Services:WaitForChild("BankService"))
local FerramentasAssaltoService = require(Services:WaitForChild("FerramentasAssaltoService")) -- Marco 10.30
local CareerService = require(Services:WaitForChild("CareerService"))
local DownedService = require(Services:WaitForChild("DownedService"))
local LitoralService = require(Services:WaitForChild("LitoralService")) -- Marco 10.31

-- Segura o nascimento dos jogadores até o mapa existir
Players.CharacterAutoLoads = false

-- 1. RemoteEvents (sempre criados pelo servidor, com nomes do GameConfig)
local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
if not remotesFolder then
	remotesFolder = Instance.new("Folder")
	remotesFolder.Name = "Remotes"
	remotesFolder.Parent = ReplicatedStorage
end

local remotes = {}
for _, remoteName in pairs(GameConfig.Remotes) do
	local remote = remotesFolder:FindFirstChild(remoteName)
	if not remote then
		remote = Instance.new("RemoteEvent")
		remote.Name = remoteName
		remote.Parent = remotesFolder
	end
	remotes[remoteName] = remote
end

-- 2. Mapa
local ok, err = pcall(MapBuilder.build)
task.wait()
if not ok then
	warn("[ServerBootstrap] Erro ao montar o mapa: " .. tostring(err))
end

-- 3. Serviços (os dados primeiro, porque outros serviços dependem deles)
task.wait() -- Marco 10.21: pausa entre serviços (Script timeout)
PlayerDataService.init()
task.wait() -- Marco 10.21: pausa entre serviços (Script timeout)
EconomyService.init()
task.wait() -- Marco 10.21: pausa entre serviços (Script timeout)
DailyBonusService.init()
task.wait() -- Marco 10.21: pausa entre serviços (Script timeout)
TutorialService.init(remotes)
task.wait() -- Marco 10.21: pausa entre serviços (Script timeout)
ZoneService.init() -- locais de trabalho protegidos (precisa do mapa pronto)
task.wait() -- Marco 10.21: pausa entre serviços (Script timeout)
VehicleService.init(remotes)
task.wait() -- Marco 10.21: pausa entre serviços (Script timeout)
NPCService.init(remotes)
task.wait() -- Marco 10.21: pausa entre serviços (Script timeout)
JobService.init(remotes)
task.wait() -- Marco 10.21: pausa entre serviços (Script timeout)
SeatService.init(VehicleService.dismount) -- bancos: sentar com E (depois que lojas e praça existem)
task.wait() -- Marco 10.21: pausa entre serviços (Script timeout)
HomeService.init(remotes, VehicleService.dismount) -- Marco 6: casa de cada jogador
task.wait() -- Marco 10.21: pausa entre serviços (Script timeout)
PetService.init(remotes) -- Marco 7: pets (adoção no Duto Pet Shop)
task.wait() -- Marco 10.21: pausa entre serviços (Script timeout)
PrisonService.init(remotes) -- Marco 8.1: portas da Penitenciária e presos (depois do JobService)
task.wait() -- Marco 10.21: pausa entre serviços (Script timeout)
UniformService.init(remotes) -- Marco 8.4: farda da PM nos armários do arsenal
task.wait() -- Marco 10.21: pausa entre serviços (Script timeout)
GangService.init(remotes) -- Marco 10.1: chefes das gangues, bar, paredão e bolas das favelas
task.wait() -- Marco 10.21: pausa entre serviços (Script timeout)
PropService.init() -- Marco 10.2: TV, luzes, lareira e chuveiro das casas; sentar nos móveis
task.wait() -- Marco 10.21: pausa entre serviços (Script timeout)
WeaponService.init(remotes) -- Marco 10.5: armas (tiro com zonas seguras)
task.wait() -- Marco 10.21: pausa entre serviços (Script timeout)
InventoryService.init(remotes) -- Marco 10.5: mochila, atalhos e baú nos guarda-roupas
task.wait() -- Marco 10.21: pausa entre serviços (Script timeout)
CrimeService.init(remotes) -- Marco 10.5: assaltos, procurados, chamados da PM, taser e algema
task.wait() -- Marco 10.21: pausa entre serviços (Script timeout)
SettingsService.init(remotes) -- Marco 10.8: limites da câmera e configurações do jogador
task.wait() -- Marco 10.21: pausa entre serviços (Script timeout)
JewelryService.init(remotes) -- Marco 10.8: assalto à joalheria do Bairro Horizonte
task.wait() -- Marco 10.21: pausa entre serviços (Script timeout)
BankService.init(remotes) -- Marco 10.20: assalto ao Banco Central (Estrada do Vale)
FerramentasAssaltoService.init(remotes) -- Marco 10.30: perfuratriz escondida na obra do Vale
require(Services:WaitForChild("ObraGuardService")).init(remotes) -- Marco 10.32: seguranças armados na obra
task.wait() -- Marco 10.21: pausa entre serviços (Script timeout)
CareerService.init(remotes) -- Marco 10.15: salário a cada 15 min e cargos (economia nova)
task.wait() -- Marco 10.21: pausa entre serviços (Script timeout)
DownedService.init(remotes) -- Marco 10.15: caído no chão esperando o paramédico
task.wait()
LitoralService.init(remotes) -- Marco 10.31: lanches, academia, bolas e NPCs da orla e da concessionária

task.wait()
-- Marco 10.22: anota posição/tamanho dos lugares para o minimapa funcionar com streaming
local okStamp, errStamp = pcall(MapBuilder.stampMapInfo)
if not okStamp then
	warn("[ServerBootstrap] Erro ao anotar o mapa: " .. tostring(errStamp))
end

-- 4. Libera o nascimento dos jogadores
Players.CharacterAutoLoads = true
for _, player in ipairs(Players:GetPlayers()) do
	if not player.Character then
		player:LoadCharacter()
	end
end

print(("[ServerBootstrap] %s (%s) pronto."):format(GameConfig.GameName, GameConfig.Version))
