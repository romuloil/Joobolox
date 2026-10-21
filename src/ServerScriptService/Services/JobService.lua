-- JobService (ModuleScript)
-- Caminho: ServerScriptService > Services > JobService
-- Quadro de empregos e vagas (documento mestre, seção 7):
--   * o jogador ESCOLHE a profissão no quadro da praça (nada é automático);
--   * cada profissão tem um limite de vagas; lotada = escolher outra;
--   * a vaga é liberada ao sair do emprego ou ao desconectar (sem vaga presa).
-- Profissão atual é estado da sessão: não fica salva.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local JobConfig = require(Shared:WaitForChild("JobConfig"))
local SecurityService = require(script.Parent:WaitForChild("SecurityService"))
local MissionService = require(script.Parent:WaitForChild("MissionService"))
local JobSiteBuilder = require(script.Parent:WaitForChild("JobSiteBuilder"))
local MarketService = require(script.Parent:WaitForChild("MarketService"))
local CityNPCService = require(script.Parent:WaitForChild("CityNPCService"))
local WorkRoleService = require(script.Parent:WaitForChild("WorkRoleService"))

local JobService = {}

local uiUpdate
local jobOf = {} -- jobOf[player] = id da profissão
local counts = {} -- counts[id] = vagas ocupadas

for id in pairs(JobConfig.Jobs) do
	counts[id] = 0
end

local function broadcastSlots()
	uiUpdate:FireAllClients("JobSlots", { counts = counts })
end

local function isNearBoard(player)
	local _, _, root = SecurityService.getLivingCharacter(player)
	local board = JobSiteBuilder.board
	return root and board and (root.Position - board.Position).Magnitude <= JobConfig.BoardDistance
end

function JobService.getJob(player)
	return jobOf[player]
end

-- Libera a vaga. notify = false quando o jogador está saindo do jogo.
function JobService.leave(player, notify)
	local id = jobOf[player]
	if not id then
		return
	end
	jobOf[player] = nil
	WorkRoleService.clear(player, id)
	counts[id] = math.max(0, counts[id] - 1)
	MissionService.stopJob(player)
	if notify ~= false then
		player:SetAttribute("Job", nil)
		uiUpdate:FireClient(player, "JobChanged", { job = nil })
	end
	print(("[JobService] %s saiu de %s. Vagas: %d/%d"):format(player.Name, id, counts[id], JobConfig.Jobs[id].Slots))
	broadcastSlots()
end

function JobService.join(player, id)
	if player:GetAttribute("TaxiDuty") then
		uiUpdate:FireClient(player, "Notice", { text = "Encerre o turno na LXR Táxis antes de escolher outro emprego." })
		return
	end
	if player:GetAttribute("PoliceDuty") then
		uiUpdate:FireClient(player, "Notice", { text = "Encerre o plantão policial antes de escolher outro emprego." })
		return
	end
	if player:GetAttribute("Detained") then
		uiUpdate:FireClient(player, "Notice", { text = "Aguarde sua liberação para escolher um emprego." })
		return
	end
	local job = JobConfig.Jobs[id]
	if not job or jobOf[player] == id then
		return
	end
	if not isNearBoard(player) then
		uiUpdate:FireClient(player, "JobRefused", { reason = "far" })
		return
	end
	if counts[id] >= job.Slots then
		uiUpdate:FireClient(player, "JobRefused", { reason = "full", job = id })
		return
	end
	-- Trocar de profissão libera a vaga antiga primeiro
	if jobOf[player] then
		JobService.leave(player)
	end
	local assigned = WorkRoleService.assign(player, id)
	if not assigned then
		uiUpdate:FireClient(player, "Notice", { text = "Encerre seu outro emprego antes de assumir esta vaga." })
		return
	end
	jobOf[player] = id
	counts[id] += 1
	player:SetAttribute("Job", id)
	uiUpdate:FireClient(player, "JobChanged", { job = id })
	print(("[JobService] %s virou %s. Vagas: %d/%d"):format(player.Name, id, counts[id], job.Slots))
	broadcastSlots()
	MissionService.startJob(player, id)
end

local function onJobRequest(player, action, id)
	if not SecurityService.checkRate(player, "JobRequest", 0.5) then
		return
	end
	if not SecurityService.isShortString(action, 16) then
		return
	end
	if action == "Join" and SecurityService.isShortString(id, 32) then
		JobService.join(player, id)
	elseif action == "Leave" then
		JobService.leave(player)
	end
end

function JobService.init(remotes)
	uiUpdate = remotes[GameConfig.Remotes.UIUpdate]

	local ok, boardPrompt = pcall(JobSiteBuilder.build)
	if not ok then
		warn("[JobService] Erro ao montar os locais de trabalho: " .. tostring(boardPrompt))
		return
	end
	MissionService.init(remotes, JobSiteBuilder)
	MarketService.init(MissionService, JobSiteBuilder) -- clientes NPC e prateleiras do Minas Market
	CityNPCService.init(MissionService, JobSiteBuilder) -- Marco 5: funcionários, clientes, moradores e praça

	boardPrompt.Triggered:Connect(function(player)
		if not SecurityService.checkRate(player, "JobBoard", 0.5) or not isNearBoard(player) then
			return
		end
		uiUpdate:FireClient(player, "JobBoard", { counts = counts, current = jobOf[player] })
	end)
	remotes[GameConfig.Remotes.JobRequest].OnServerEvent:Connect(onJobRequest)

	Players.PlayerRemoving:Connect(function(player)
		JobService.leave(player, false) -- desconectou: vaga liberada na hora
		jobOf[player] = nil
	end)
end

return JobService
