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
local CivicBuilder = require(Services:WaitForChild("CivicBuilder"))
local PrisonService = require(Services:WaitForChild("PrisonService"))
local PoliceService = require(Services:WaitForChild("PoliceService"))
local TaxiService = require(Services:WaitForChild("TaxiService"))
local WorkRoleService = require(Services:WaitForChild("WorkRoleService"))
local WorkplaceBuilder = require(Services:WaitForChild("WorkplaceBuilder"))
local StreetNPCService = require(Services:WaitForChild("StreetNPCService"))
local PrisonActivityService = require(Services:WaitForChild("PrisonActivityService"))

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
if not ok then
	warn("[ServerBootstrap] Erro ao montar o mapa: " .. tostring(err))
end

-- 3. Serviços (os dados primeiro, porque outros serviços dependem deles)
PlayerDataService.init()
EconomyService.init()
DailyBonusService.init()
TutorialService.init(remotes)
ZoneService.init() -- locais de trabalho protegidos (precisa do mapa pronto)
VehicleService.init(remotes)
NPCService.init(remotes)
JobService.init(remotes)
local workplaces = WorkplaceBuilder.build(CivicBuilder.sites.workplaces)
WorkRoleService.init(remotes, workplaces)
VehicleService.configureWorkplaces(workplaces, CivicBuilder.sites.personalGarage)
-- Prisão e polícia compartilham apenas APIs internas. O cliente não escolhe
-- quem fica preso; abordagem e algemamento são conferidos pelo servidor.
PrisonService.init(remotes, CivicBuilder.sites, {
	beforeDetain = function(player)
		PrisonActivityService.clearPlayer(player)
		TaxiService.leave(player)
		PoliceService.leave(player)
		JobService.leave(player)
		VehicleService.prepareForDetention(player)
	end,
	afterRelease = function(player, escaped, reason)
		PrisonActivityService.clearPlayer(player)
		PoliceService.handlePrisonRelease(player, escaped, reason)
	end,
	afterReturnToCell = function(player)
		PrisonActivityService.clearPlayer(player)
	end,
})
PoliceService.init(remotes, CivicBuilder.sites, {
	beforeDuty = function(player)
		TaxiService.leave(player)
		JobService.leave(player)
		VehicleService.prepareForDetention(player)
	end,
	beforeStun = VehicleService.prepareForDetention,
	prisonService = PrisonService,
	vehicleService = VehicleService,
	economyService = EconomyService,
})
PrisonActivityService.init(remotes, CivicBuilder.sites, {
	prisonService = PrisonService,
	policeService = PoliceService,
	workRoleService = WorkRoleService,
})
TaxiService.init(remotes, CivicBuilder.sites.taxi, {
	vehicleService = VehicleService,
	workRoleService = WorkRoleService,
	beforeDuty = function(player)
		PoliceService.leave(player)
		JobService.leave(player)
		VehicleService.prepareForDetention(player)
	end,
})
StreetNPCService.init(CivicBuilder.sites)
SeatService.init(VehicleService.dismount) -- bancos: sentar com E (depois que lojas e praça existem)

-- 4. Libera o nascimento dos jogadores
Players.CharacterAutoLoads = true
for _, player in ipairs(Players:GetPlayers()) do
	if not player.Character then
		player:LoadCharacter()
	end
end

print(("[ServerBootstrap] %s (%s) pronto."):format(GameConfig.GameName, GameConfig.Version))
