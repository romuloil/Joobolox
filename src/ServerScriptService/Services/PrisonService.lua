-- Prisão autoritativa de 60 segundos, com celas individuais e rota fixa de fuga.
-- Não recebe comandos remotos de detenção. PoliceService deve validar
-- papel, evento, imobilização e proximidade ANTES de chamar detain no servidor.
-- Esta etapa não altera dinheiro nem inventa recompensas de assalto.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local CivicConfig = require(Shared:WaitForChild("CivicConfig"))
local Rules = require(Shared:WaitForChild("PrisonRules"))
local SecurityService = require(script.Parent:WaitForChild("SecurityService"))

local PrisonService = {}
local sessions = {}
local cellOwners = {}
local doorTokens = {}
local initialized = false
local sites, hooks, uiUpdate
local WALK_SPEED = GameConfig.WalkSpeed

local function now()
	return Workspace:GetServerTimeNow()
end

local function promptPosition(prompt)
	local parent = prompt and prompt.Parent
	if parent and parent:IsA("BasePart") then
		return parent.Position
	elseif parent and parent:IsA("Attachment") then
		return parent.WorldPosition
	end
	return nil
end

local function descriptorPart(descriptor)
	return descriptor and (descriptor.part or descriptor.door)
end

local function setDoorFrame(descriptor, open)
	local door = descriptorPart(descriptor)
	if not door then return end
	door.CFrame = open and descriptor.open or descriptor.closed
	door.CanCollide = true -- porta física desliza para fora da passagem
	door:SetAttribute("Open", open == true)
	door:SetAttribute("CellDoorOpen", open == true)
end

local function doorwayClear(descriptor)
	if not descriptor or not descriptor.closed then return true end
	for _, player in ipairs(Players:GetPlayers()) do
		local _, _, root = SecurityService.getLivingCharacter(player)
		if root and Rules.isFinitePoint(root.Position)
			and (root.Position - descriptor.closed.Position).Magnitude < 5 then
			return false
		end
	end
	return true
end

-- Nunca fecha a folha em cima de um personagem. Um novo uso cancela a tentativa
-- anterior pelo token; portas livres são verificadas novamente em meio segundo.
local function closeWhenClear(descriptor, permitted)
	local part = descriptorPart(descriptor)
	if not part then return end
	local token = (doorTokens[part] or 0) + 1
	doorTokens[part] = token
	local function attempt()
		if doorTokens[part] ~= token or not part.Parent or (permitted and not permitted()) then
			return
		end
		if doorwayClear(descriptor) then
			setDoorFrame(descriptor, false)
		else
			task.delay(0.5, attempt)
		end
	end
	attempt()
end

local function openDoor(descriptor, closeAfter)
	local part = descriptorPart(descriptor)
	if not part then return end
	local token = (doorTokens[part] or 0) + 1
	doorTokens[part] = token
	setDoorFrame(descriptor, true)
	if closeAfter then
		task.delay(closeAfter, function()
			if doorTokens[part] == token then closeWhenClear(descriptor) end
		end)
	end
end

local function freeCell(player, session)
	local cell = session and session.cell
	if cell and cellOwners[cell] == player then
		cellOwners[cell] = nil
		closeWhenClear(cell, function() return cellOwners[cell] == nil end)
	end
end

local function insideBounds(position, bounds)
	if not bounds then return true end
	local p = bounds.cf:PointToObjectSpace(position)
	local half = bounds.half
	return math.abs(p.X) <= half.X and math.abs(p.Y) <= half.Y and math.abs(p.Z) <= half.Z
end

local function nextHint(session)
	if session.cell and not session.cellOpened then
		return ("Cela %s: aguarde a abertura para o pátio."):format(session.cell.id)
	end
	local prompt = sites.escapeSteps[session.completed + 1]
	if prompt and prompt.ObjectText ~= "" then
		return prompt.ObjectText
	end
	return "Siga a passagem de manutenção para tentar fugir."
end

local function sendState(player, session, customHint)
	local hint = customHint or nextHint(session)
	player:SetAttribute("Detained", true)
	player:SetAttribute("PrisonEndsAt", session.endsAt)
	player:SetAttribute("PrisonStep", session.completed)
	player:SetAttribute("PrisonSteps", #sites.escapeSteps)
	player:SetAttribute("PrisonHint", hint)
	player:SetAttribute("PrisonCell", session.cell and session.cell.id or nil)
	player:SetAttribute("PrisonCellOpensAt", session.cellOpensAt)
	uiUpdate:FireClient(player, "PrisonState", {
		active = true,
		endsAt = session.endsAt,
		step = session.completed,
		steps = #sites.escapeSteps,
		hint = hint,
		cellId = session.cell and session.cell.id or nil,
		cellOpensAt = session.cellOpensAt,
	})
end

local function clearAttributes(player)
	player:SetAttribute("Detained", false)
	player:SetAttribute("PrisonEndsAt", nil)
	player:SetAttribute("PrisonStep", nil)
	player:SetAttribute("PrisonSteps", nil)
	player:SetAttribute("PrisonHint", nil)
	player:SetAttribute("PrisonCell", nil)
	player:SetAttribute("PrisonCellOpensAt", nil)
end

local function moveCharacter(character, humanoid, root, target)
	-- Sit=false pode deixar SeatWeld vivo até o próximo passo de física. Solta
	-- apenas a junta deste personagem antes de mover, sem arrastar banco/carro.
	local seat = humanoid.SeatPart
	local seatWeld = seat and seat:FindFirstChild("SeatWeld")
	if seatWeld and seatWeld:IsA("Weld") then
		local p0, p1 = seatWeld.Part0, seatWeld.Part1
		if (p0 and p0:IsDescendantOf(character)) or (p1 and p1:IsDescendantOf(character)) then
			seatWeld:Destroy()
		end
	end
	humanoid.Sit = false
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	character:PivotTo(target.CFrame)
end

local function placeInPrison(player, session)
	local character, humanoid, root = SecurityService.getLivingCharacter(player)
	if not character then
		return
	end
	if session.humanoid ~= humanoid then
		session.humanoid = humanoid
		-- Uma captura pode chegar com o Humanoid imobilizado pelo jato de água.
		-- Velocidade temporária zero não deve voltar depois de cumprir a pena.
		session.previousWalkSpeed = Rules.isFinite(humanoid.WalkSpeed) and humanoid.WalkSpeed > 0
			and humanoid.WalkSpeed or WALK_SPEED
	end
	humanoid.WalkSpeed = WALK_SPEED
	moveCharacter(character, humanoid, root, session.cell and session.cell.spawn or sites.prisonSpawn)
	session.completed = 0
	session.lastStepAt = now()
	session.lastStepPosition = root.Position
	session.lastMotionAt = session.lastStepAt
	session.lastMotionPosition = root.Position
	sendState(player, session)
end

function PrisonService.isDetained(player)
	return sessions[player] ~= nil
end

-- Somente para outros serviços do servidor. PoliceService confere profissão e
-- proximidade do terminal antes de chamar estas operações; não há remote aqui.
function PrisonService.getCellControls()
	local result = {}
	local time = now()
	for _, cell in ipairs(sites and sites.prisonCells or {}) do
		local owner = cellOwners[cell]
		local session = owner and sessions[owner]
		local door = descriptorPart(cell)
		table.insert(result, {
			id = cell.id,
			name = "Cela " .. cell.id,
			open = door and door:GetAttribute("Open") == true or false,
			occupied = session ~= nil,
			lockedUntil = session and time < session.cellOpensAt and session.cellOpensAt or 0,
		})
	end
	return result
end

function PrisonService.setCellDoor(cellId, open)
	if not initialized or type(cellId) ~= "string" or #cellId == 0 or #cellId > 16
		or type(open) ~= "boolean" then
		return false, "argument"
	end
	local cell
	for _, candidate in ipairs(sites.prisonCells or {}) do
		if candidate.id == cellId then cell = candidate; break end
	end
	if not cell then return false, "cell" end
	local owner = cellOwners[cell]
	local session = owner and sessions[owner]
	if open and session and now() < session.cellOpensAt then
		return false, "locked"
	end
	if session and not session.cellOpened and now() >= session.cellOpensAt then
		-- Resolve também a pequena janela antes do próximo tick: uma ordem
		-- manual após os 15 s não deve ser desfeita pela abertura automática.
		session.cellOpened = true
		sendState(owner, session)
	end
	local part = descriptorPart(cell)
	if (part:GetAttribute("Open") == true) == open then return true end
	if open then
		openDoor(cell)
	else
		if not doorwayClear(cell) then return false, "blocked" end
		-- Um fechamento manual cancela apenas ações antigas desta porta. O prazo
		-- da pena e a soltura automática do ocupante permanecem os mesmos.
		doorTokens[part] = (doorTokens[part] or 0) + 1
		setDoorFrame(cell, false)
	end
	return true
end

function PrisonService.release(player, escaped)
	escaped = escaped == true
	local session = sessions[player]
	if not session then
		return false
	end
	-- Retira primeiro: timeout e último prompt no mesmo frame só resolvem uma vez.
	sessions[player] = nil
	clearAttributes(player)
	local character, humanoid, root = SecurityService.getLivingCharacter(player)
	if humanoid then
		if session.humanoid == humanoid and Rules.isFinite(session.previousWalkSpeed) then
			humanoid.WalkSpeed = session.previousWalkSpeed
		else
			humanoid.WalkSpeed = WALK_SPEED
		end
		if not escaped then
			moveCharacter(character, humanoid, root, sites.prisonRelease)
		end
	end
	freeCell(player, session)
	if player.Parent == Players then
		uiUpdate:FireClient(player, "PrisonState", { active = false, escaped = escaped == true })
		uiUpdate:FireClient(player, "Notice", {
			text = escaped and "Você concluiu a rota de fuga e está livre!"
				or "Tempo cumprido. Você está livre!",
		})
	end
	return true
end

function PrisonService.detain(player, reason)
	if not initialized or player.Parent ~= Players then
		return false, "unavailable"
	end
	if sessions[player] then
		return false, "already_detained"
	end
	local character = SecurityService.getLivingCharacter(player)
	if not character then
		return false, "character"
	end
	local cell
	if sites.prisonCells then
		for _, candidate in ipairs(sites.prisonCells) do
			if not cellOwners[candidate] and doorwayClear(candidate) then
				cell = candidate
				break
			end
		end
		if not cell then return false, "capacity" end
	end
	local time = now()
	local duration = CivicConfig.SentenceSeconds or 60
	local deadline = Rules.deadline(time, duration)
	if not deadline then
		return false, "duration"
	end
	local session = {
		endsAt = deadline, completed = 0, reason = reason, cell = cell,
		cellOpensAt = cell and time + math.min(CivicConfig.CellLockSeconds or 15, duration - 1) or nil,
		cellOpened = cell == nil,
	}
	if cell then
		cellOwners[cell] = player
		local part = descriptorPart(cell)
		doorTokens[part] = (doorTokens[part] or 0) + 1
		setDoorFrame(cell, false)
	end
	sessions[player] = session
	-- Bloqueia novas ações antes de remover o veículo e encerrar a profissão.
	player:SetAttribute("Detained", true)
	if hooks.beforeDetain then
		local ok, err = pcall(hooks.beforeDetain, player)
		if not ok then
			sessions[player] = nil
			clearAttributes(player)
			freeCell(player, session)
			warn("[PrisonService] Falha ao preparar detenção: " .. tostring(err))
			return false, "prepare"
		end
	end
	if sessions[player] ~= session or player.Parent ~= Players then
		freeCell(player, session)
		return false, "cancelled"
	end
	placeInPrison(player, session)
	return true
end

local function positionAllowed(root, session, time)
	local position = root.Position
	if not Rules.isFinitePoint(position) then
		return false
	end
	if not insideBounds(position, sites.prisonBounds) then
		return false
	end
	if session.cell and time < session.cellOpensAt and not insideBounds(position, session.cell.bounds) then
		return false
	end
	return not session.lastMotionPosition or Rules.movementAllowed(
		(position - session.lastMotionPosition).Magnitude, time - session.lastMotionAt, WALK_SPEED)
end

local function tryStep(player, index, prompt)
	local session = sessions[player]
	if not session or not SecurityService.checkRate(player, "PrisonStep", 0.35) then
		return
	end
	local time = now()
	if Rules.remaining(session.endsAt, time) <= 0 then
		PrisonService.release(player, false)
		return
	end
	if session.cell and time < session.cellOpensAt then return end
	local _, _, root = SecurityService.getLivingCharacter(player)
	local target = promptPosition(prompt)
	if not root or not Rules.isFinitePoint(root.Position) or not Rules.isFinitePoint(target)
		or not session.lastStepPosition then
		return
	end
	-- Verifica também no próprio evento: um teleporte seguido de Triggered não
	-- pode aproveitar a janela entre duas amostras do monitor periódico.
	if not positionAllowed(root, session, time) then
		placeInPrison(player, session)
		return
	end
	local allowed = Rules.canAdvance(session.completed + 1, index,
		(root.Position - target).Magnitude, time - session.lastStepAt,
		(session.lastStepPosition - target).Magnitude, WALK_SPEED, true)
	if not allowed then
		return
	end
	session.completed = index
	session.lastStepAt = time
	session.lastStepPosition = root.Position
	local routeDoor = sites.escapeDoors and sites.escapeDoors[index]
	-- A passagem permanece aberta por uma pena inteira, para não prender quem
	-- já validou o acesso antes de atravessar. Cada preso valida sua própria rota.
	if routeDoor then openDoor(routeDoor, CivicConfig.SentenceSeconds or 60) end
	if index == #sites.escapeSteps then
		PrisonService.release(player, true)
	else
		sendState(player, session)
	end
end

local function watchPlayer(player)
	player.CharacterAdded:Connect(function(character)
		-- Pena e prazo pertencem ao Player: resetar o personagem não libera o preso.
		task.spawn(function()
			local humanoid = character:WaitForChild("Humanoid", 10)
			local root = character:WaitForChild("HumanoidRootPart", 10)
			local session = sessions[player]
			if not humanoid or not root or not session or player.Character ~= character then
				return
			end
			if Rules.remaining(session.endsAt, now()) <= 0 then
				PrisonService.release(player, false)
			else
				placeInPrison(player, session)
			end
		end)
	end)
end

local function updateSession(player, session, time)
	if Rules.remaining(session.endsAt, time) <= 0 then
		PrisonService.release(player, false)
		return
	end
	if session.cell and not session.cellOpened and time >= session.cellOpensAt then
		session.cellOpened = true
		openDoor(session.cell)
		sendState(player, session)
	end
	local _, humanoid, root = SecurityService.getLivingCharacter(player)
	if not root then
		session.lastMotionPosition = nil
		return
	end
	humanoid.WalkSpeed = WALK_SPEED
	if not positionAllowed(root, session, time) then
		-- Recomeça só a rota, nunca reinicia nem acrescenta tempo à pena original.
		placeInPrison(player, session)
		return
	end
	session.lastMotionPosition = root.Position
	session.lastMotionAt = time
end

function PrisonService.init(remotes, civicSites, options)
	if initialized then
		return
	end
	assert(civicSites and civicSites.prisonSpawn and civicSites.prisonRelease
		and civicSites.intakePrompt and civicSites.prisonBounds
		and #civicSites.escapeSteps > 0, "[PrisonService] Pontos da prisão incompletos")
	sites = civicSites
	hooks = options or {}
	uiUpdate = assert(remotes[GameConfig.Remotes.UIUpdate], "UIUpdate ausente")
	for _, cell in ipairs(sites.prisonCells or {}) do
		assert(cell.spawn and cell.door and cell.closed and cell.open and cell.id and cell.bounds,
			"[PrisonService] Cela incompleta")
		setDoorFrame(cell, false)
	end
	for _, door in pairs(sites.escapeDoors or {}) do setDoorFrame(door, false) end
	initialized = true
	for index, prompt in ipairs(sites.escapeSteps) do
		prompt.Enabled = true -- o construtor entrega prompts desligados até os serviços estarem prontos
		prompt.Triggered:Connect(function(player)
			tryStep(player, index, prompt)
		end)
	end
	-- Entrada voluntária de validação; não existe como ferramenta de prisão no jogo publicado.
	sites.intakePrompt.Enabled = RunService:IsStudio()
	sites.intakePrompt.Triggered:Connect(function(player)
		if not RunService:IsStudio() or not SecurityService.checkRate(player, "PrisonIntake", 1) then
			return
		end
		local _, _, root = SecurityService.getLivingCharacter(player)
		local position = promptPosition(sites.intakePrompt)
		if root and position and Rules.isFinitePoint(root.Position)
			and (root.Position - position).Magnitude <= 10 then
			PrisonService.detain(player, "studio_test")
		end
	end)
	Players.PlayerAdded:Connect(watchPlayer)
	for _, player in ipairs(Players:GetPlayers()) do
		watchPlayer(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		freeCell(player, sessions[player])
		sessions[player] = nil -- prisão é estado da sessão, não é gravada no DataStore
	end)
	task.spawn(function()
		while true do
			local time = now()
			for player, session in pairs(sessions) do
				updateSession(player, session, time)
			end
			task.wait(0.2)
		end
	end)
end

return PrisonService
