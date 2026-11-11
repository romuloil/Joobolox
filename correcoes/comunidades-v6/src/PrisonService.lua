-- PrisonService (ModuleScript)
-- Caminho: ServerScriptService > Services > PrisonService
-- Marco 8.1: a Penitenciária funcionando.
--   * Portas que abrem e fecham com E: grades das celas e portões dos pavilhões (qualquer um),
--     e as portas de vidro da PM (só quem é Policial tem o cartão; fecham sozinhas).
--   * Presidiário: quem é preso vai para uma cela, vira "Presidiário" e cumpre a pena.
--     A pena só conta enquanto a pessoa está no jogo. Tarefas pela prisão diminuem a pena.
--     Sair do jogo NÃO solta: a pena fica salva e a pessoa volta presa (data.prison).
--   * Preso que sai da área de segurança volta para a cela (a rota de fuga vem depois).
--   * Bolas dos pátios voltam para o lugar se forem parar longe.
-- Regras PROVISÓRIAS (GameConfig.Prison): pena, tarefas, redução e o teste de prisão no Studio.
-- Por enquanto, a única forma de ser preso é o teste na recepção (só no Studio).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))
local SecurityService = require(script.Parent:WaitForChild("SecurityService"))
local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))
local JobService = require(script.Parent:WaitForChild("JobService"))
local MissionService = require(script.Parent:WaitForChild("MissionService"))
local VehicleService = require(script.Parent:WaitForChild("VehicleService"))

local PrisonService = {}

local PR = GameConfig.Prison
local JOB = "Presidiario"
local POLICE_JOB = "Policial"

local uiUpdate
local prison -- Model "Penitenciaria"
local cells = {} -- peças "CelaSpawn"
local exitPart
local secureMin, secureMax
local state = {} -- state[player] = { left = segundos, tasks = feitas, need = quantas para diminuir, cell = peça }
local rng = Random.new()

local function notice(player, text)
	uiUpdate:FireClient(player, "Notice", { text = text })
end

---------------------------------------------------------------------------
-- Portas
---------------------------------------------------------------------------

local function setupDoor(door)
	local panel = door:FindFirstChild("Painel")
	if not door.PrimaryPart or not panel then
		return
	end
	local police = door:GetAttribute("Access") == "Police"
	local closed = door:GetPivot()
	local open = closed * CFrame.Angles(0, math.rad(door:GetAttribute("OpenAngle") or 90), 0)
	local value = Instance.new("CFrameValue")
	value.Value = closed
	value.Changed:Connect(function(cf)
		door:PivotTo(cf)
	end)
	local info = TweenInfo.new(PR.DoorOpenTime or 1.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "DoorPrompt"
	prompt.ObjectText = door:GetAttribute("Label") or "Porta"
	prompt.ActionText = police and "Usar cartão" or "Abrir"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.MaxActivationDistance = 8
	prompt.RequiresLineOfSight = false
	prompt.Parent = panel

	local isOpen = false
	local token
	local function setOpen(v)
		isOpen = v
		prompt.ActionText = v and "Fechar" or (police and "Usar cartão" or "Abrir")
		TweenService:Create(value, info, { Value = v and open or closed }):Play()
	end

	prompt.Triggered:Connect(function(player)
		if not SecurityService.checkRate(player, "Door", 0.4) then
			return
		end
		local _, _, root = SecurityService.getLivingCharacter(player)
		if not root or (root.Position - panel.Position).Magnitude > 14 then
			return
		end
		if police and player:GetAttribute("Job") ~= POLICE_JOB then
			return notice(player, "Porta da PM: só policiais têm o cartão de acesso.")
		end
		setOpen(not isOpen)
		if police and isOpen then
			-- porta com cartão fecha sozinha depois de alguns segundos
			local mine = {}
			token = mine
			task.delay(PR.PoliceDoorOpenTime or 5, function()
				if token == mine and isOpen then
					setOpen(false)
				end
			end)
		end
	end)
end

---------------------------------------------------------------------------
-- Presos
---------------------------------------------------------------------------

local function toLocal(pos)
	return prison.WorldPivot:PointToObjectSpace(pos)
end

local function insideSecure(pos)
	if not secureMin then
		return true
	end
	local p = toLocal(pos)
	return p.X >= secureMin.X and p.X <= secureMax.X and p.Y >= secureMin.Y and p.Y <= secureMax.Y and p.Z >= secureMin.Z and p.Z <= secureMax.Z
end

local function teleport(player, cf)
	local character, humanoid, root = SecurityService.getLivingCharacter(player)
	if not character then
		return false
	end
	local seat = humanoid.SeatPart
	if seat then
		local weld = seat:FindFirstChild("SeatWeld")
		if weld then
			weld:Destroy()
		end
		humanoid.Sit = false
	end
	root.AssemblyLinearVelocity = Vector3.zero
	character:PivotTo(cf + Vector3.new(0, humanoid.HipHeight + root.Size.Y / 2 + 0.3, 0))
	return true
end

-- Cela de cada preso: sorteia uma que ninguém está usando (se der)
local function cellFor(player)
	local st = state[player]
	if st.cell and st.cell.Parent then
		return st.cell
	end
	local used = {}
	for _, other in pairs(state) do
		if other.cell then
			used[other.cell] = true
		end
	end
	local free = {}
	for _, c in ipairs(cells) do
		if not used[c] then
			table.insert(free, c)
		end
	end
	local pool = #free > 0 and free or cells
	st.cell = pool[rng:NextInteger(1, #pool)]
	return st.cell
end

local function sendToCell(player)
	if #cells == 0 or not state[player] then
		return
	end
	local cell = cellFor(player)
	teleport(player, CFrame.new(cell.Position) * prison.WorldPivot.Rotation)
	player:SetAttribute("PrisonCell", cell:GetAttribute("Cell"))
end

local function newNeed()
	return rng:NextInteger(PR.TasksMin, math.max(PR.TasksMin, PR.TasksMax))
end

-- Atributos que a tela do jogador (PrisonController) mostra, e a cópia que fica salva
local function publish(player)
	local st = state[player]
	if not st then
		return
	end
	player:SetAttribute("PrisonLeft", math.max(0, math.ceil(st.left)))
	player:SetAttribute("PrisonTasks", st.tasks)
	player:SetAttribute("PrisonNeed", st.need)
	PlayerDataService.set(player, "prison", { left = math.ceil(st.left), tasks = st.tasks, need = st.need })
end

local function startServing(player, isNew)
	local st = state[player]
	player:SetAttribute("Preso", true)
	publish(player)
	VehicleService.removeVehicles(player)
	JobService.suspend(player, JOB)
	sendToCell(player)
	if isNew then
		notice(player, ("Você foi preso! Pena: %d min. Faça tarefas pela prisão para diminuir."):format(math.ceil(st.left / 60)))
	else
		notice(player, "Você ainda está preso. Cumpra o resto da pena!")
	end
end

local function release(player)
	state[player] = nil
	PlayerDataService.set(player, "prison", nil)
	task.spawn(PlayerDataService.save, player)
	for _, key in ipairs({ "Preso", "PrisonLeft", "PrisonTasks", "PrisonNeed", "PrisonCell" }) do
		player:SetAttribute(key, nil)
	end
	JobService.resume(player)
	if exitPart then
		teleport(player, CFrame.new(exitPart.Position) * prison.WorldPivot.Rotation * CFrame.Angles(0, math.pi, 0))
	end
	notice(player, "Você está livre! Cumpriu a pena.")
end

-- Prende o jogador (seconds = pena; padrão do GameConfig). Usado pelo teste e, depois, pela polícia.
function PrisonService.arrest(player, seconds)
	if not prison or state[player] or #cells == 0 then
		return false
	end
	state[player] = { left = seconds or PR.Sentence, tasks = 0, need = newNeed() }
	startServing(player, true)
	task.spawn(PlayerDataService.save, player) -- salva na hora: sair do jogo não solta
	return true
end

function PrisonService.isPrisoner(player)
	return state[player] ~= nil
end

-- Tarefa do Presidiário concluída (MissionService chama no fim de cada tarefa)
local function onTaskDone(player)
	local st = state[player]
	if not st then
		return
	end
	st.tasks += 1
	if st.tasks >= st.need then
		st.tasks = 0
		st.need = newNeed()
		st.left = math.max(1, st.left - PR.TaskReduction)
		notice(player, ("Muito bem! Sua pena diminuiu %d segundos."):format(PR.TaskReduction))
	end
	publish(player)
end

local function tick()
	for player, st in pairs(state) do
		if player.Parent then
			st.left -= 1
			if st.left <= 0 then
				release(player)
			else
				publish(player)
				local _, _, root = SecurityService.getLivingCharacter(player)
				if root and not insideSecure(root.Position) then
					sendToCell(player)
					notice(player, "Presos não podem sair da área de segurança!")
				end
			end
		end
	end
end

---------------------------------------------------------------------------
-- Bolas dos pátios
---------------------------------------------------------------------------

local function watchBalls()
	local balls = {}
	for _, d in ipairs(prison:GetDescendants()) do
		if d:IsA("BasePart") and d:GetAttribute("Ball") then
			table.insert(balls, d)
		end
	end
	while true do
		task.wait(5)
		for _, ball in ipairs(balls) do
			local home = ball:GetAttribute("BallHome")
			if ball.Parent and typeof(home) == "Vector3" and (ball.Position - home).Magnitude > 70 then
				ball.AssemblyLinearVelocity = Vector3.zero
				ball.AssemblyAngularVelocity = Vector3.zero
				ball.CFrame = CFrame.new(home)
			end
		end
	end
end

---------------------------------------------------------------------------

function PrisonService.init(remotes)
	uiUpdate = remotes[GameConfig.Remotes.UIUpdate]
	local map = Workspace:FindFirstChild("Map")
	prison = map and map:FindFirstChild("Penitenciaria")
	if not prison then
		warn("[PrisonService] Penitenciária não encontrada no mapa.")
		return
	end
	secureMin, secureMax = prison:GetAttribute("SecureMin"), prison:GetAttribute("SecureMax")
	exitPart = prison:FindFirstChild("SaidaPrisao", true)

	local doors = 0
	for _, d in ipairs(prison:GetDescendants()) do
		if d:IsA("BasePart") and d.Name == "CelaSpawn" then
			table.insert(cells, d)
		end
	end
	for _, d in ipairs(prison:GetDescendants()) do
		if d:IsA("Model") and d:GetAttribute("PrisonDoor") then
			setupDoor(d)
			doors += 1
		end
	end

	MissionService.registerHook("prisonTaskDone", onTaskDone)

	-- Voltou ao jogo ainda com pena: continua preso
	PlayerDataService.onLoaded(function(player, data)
		local saved = type(data.prison) == "table" and data.prison
		if saved and type(saved.left) == "number" and saved.left > 0 and not state[player] then
			state[player] = {
				left = saved.left,
				tasks = tonumber(saved.tasks) or 0,
				need = tonumber(saved.need) or newNeed(),
			}
			startServing(player, false)
		end
	end)

	local function watch(player)
		player.CharacterAdded:Connect(function(character)
			if state[player] then
				character:WaitForChild("HumanoidRootPart", 10)
				task.wait(0.2)
				sendToCell(player) -- renasceu: volta para a cela
			end
		end)
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in ipairs(Players:GetPlayers()) do
		watch(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		state[player] = nil -- a pena já está em data.prison (atualizada a cada segundo)
	end)

	-- Teste no Studio: placa na recepção da Administração para ser preso
	local test = prison:FindFirstChild("TestePrisao", true)
	if test and PR.TestInStudio and RunService:IsStudio() then
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "TestPrompt"
		prompt.ActionText = "Ser preso (teste)"
		prompt.ObjectText = "Teste do Studio"
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.HoldDuration = 1
		prompt.MaxActivationDistance = 10
		prompt.RequiresLineOfSight = false
		prompt.Parent = test
		prompt.Triggered:Connect(function(player)
			if SecurityService.checkRate(player, "PrisonTest", 2) then
				PrisonService.arrest(player)
			end
		end)
	end

	task.spawn(function()
		while true do
			task.wait(1)
			tick()
		end
	end)
	task.spawn(watchBalls)
	print(("[PrisonService] %d portas, %d celas."):format(doors, #cells))
end

return PrisonService
