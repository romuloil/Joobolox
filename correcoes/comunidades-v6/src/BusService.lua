-- BusService (ModuleScript)
-- Caminho: ServerScriptService > Services > BusService
-- Marco 9: passageiros do Motorista de ônibus. A volta da Linha Circular é um pedido normal do
-- MissionService (JobConfig: busOrder); aqui ficam as ações especiais das etapas:
--   * busArrive: alguns passageiros NPC esperam na parada (e, se o ônibus está vazio, já entram
--     uns sentados, como diz o documento mestre);
--   * busCheck: só conclui a etapa quem está dirigindo o Ônibus Um Tijo, parado;
--   * busStop: portas abertas: uns descem (vão embora pela calçada), os da parada sobem e sentam.

local Players = game:GetService("Players")

local NPCKit = require(script.Parent:WaitForChild("NPCKit"))
local VehicleService = require(script.Parent:WaitForChild("VehicleService"))
local SecurityService = require(script.Parent:WaitForChild("SecurityService"))

local BusService = {}

local JOB = "Motorista"
local STOP_SPEED = 8 -- acima disso o ônibus ainda está andando
local MAX_RIDERS = 8 -- passageiros NPC no máximo (fica leve; o resto dos bancos é para jogadores)

local sites
local lines = {} -- lines[player] = { riders = { {npc, seat} }, waiting = { npc }, bus = model }

local HELLO = { "Bom dia, motorista!", "Boa tarde!", "Oi, motorista!", "Até que enfim!", "Opa, chegou!" }
local BYE = { "Valeu, motorista!", "Obrigado!", "Até amanhã!", "Tchau!", "É aqui que eu desço!" }

local function pick(list)
	return list[math.random(1, #list)]
end

local function lineOf(player)
	local l = lines[player]
	if not l then
		l = { riders = {}, waiting = {} }
		lines[player] = l
	end
	return l
end

local function clear(player)
	local l = lines[player]
	lines[player] = nil
	if l then
		for _, r in ipairs(l.riders) do
			r.npc:Destroy()
		end
		for _, npc in ipairs(l.waiting) do
			npc:Destroy()
		end
	end
end

-- Ônibus que o jogador está dirigindo agora (nil se não estiver)
local function drivingBus(player)
	local c = VehicleService.getCar(player)
	local _, humanoid = SecurityService.getLivingCharacter(player)
	if not c or not humanoid or c.spec.Service ~= JOB or humanoid.SeatPart ~= c.driver then
		return nil
	end
	return c
end

local function setMassless(npc, value)
	for _, p in ipairs(npc:GetDescendants()) do
		if p:IsA("BasePart") then
			p.Massless = value -- sentado no ônibus não muda o jeito dele andar
		end
	end
end

local function freeSeat(model)
	local list = {}
	for _, seat in ipairs(model:GetChildren()) do
		if (seat.Name == "RearSeat" or seat.Name == "PassengerSeat") and seat:IsA("Seat") and not seat.Occupant
			and not seat:GetAttribute("Reserved") then
			table.insert(list, seat)
		end
	end
	return #list > 0 and list[math.random(1, #list)] or nil
end

-- Senta o NPC no banco (fica soldado no ônibus; quem dirige continua controlando a física).
-- Igual ao táxi: Seat:Sit com o NPC perto; se não sentou (longe, ônibus andando), põe em cima
-- do banco e tenta de novo.
local function seatNpc(player, c, npc, seat)
	local humanoid = npc:FindFirstChildOfClass("Humanoid")
	local root = npc:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or not seat.Parent or seat.Occupant then
		return false
	end
	root.Anchored = false
	setMassless(npc, true)
	NPCKit.sit(npc, true)
	for try = 1, 3 do
		if try > 1 or (root.Position - seat.Position).Magnitude > 8 then
			root.AssemblyLinearVelocity = Vector3.zero
			npc:PivotTo(seat.CFrame * CFrame.new(0, 2.6, 0))
		end
		seat:Sit(humanoid)
		task.wait(0.25)
		if humanoid.SeatPart == seat then
			break
		end
	end
	if humanoid.SeatPart ~= seat then
		warn("[BusService] Passageiro não conseguiu sentar")
		return false
	end
	local _, hum = SecurityService.getLivingCharacter(player)
	local chassis = c.model.PrimaryPart
	if chassis and hum and hum.SeatPart == c.driver then
		pcall(function()
			chassis:SetNetworkOwner(player)
		end)
	end
	return true
end

-- Ônibus trocado ou guardado: passageiros antigos somem
local function checkBus(player, l)
	local c = VehicleService.getCar(player)
	local model = c and c.spec.Service == JOB and c.model or nil
	if l.bus ~= model then
		for _, r in ipairs(l.riders) do
			r.npc:Destroy()
		end
		l.riders = {}
		l.bus = model
	end
	return c, model
end

local function spawnAt(cf, x)
	local spot = cf * CFrame.new(x, 0, 0)
	local ground = NPCKit.groundAt(spot.Position)
	return NPCKit.spawn(CFrame.new(spot.X, ground, spot.Z) * spot.Rotation, {
		name = "Passageiro",
		important = true, -- não entra no limite de NPCs da cidade
		anchored = true,
		speed = 10,
	})
end

local Hooks = {}

-- Etapa começou: passageiros esperando na parada
function Hooks.busArrive(player, state, step)
	local l = lineOf(player)
	for _, npc in ipairs(l.waiting) do
		npc:Destroy()
	end
	l.waiting = {}
	local stop = step.point and sites.points[step.point]
	local curb = stop and stop.part:GetAttribute("Curb")
	if typeof(curb) ~= "CFrame" then
		return
	end
	for i = 1, math.random(1, 3) do
		local npc = spawnAt(curb, (i - 2) * 2.2)
		if npc then
			table.insert(l.waiting, npc)
		end
	end
	-- ônibus vazio (começo da volta): já leva alguns sentados
	local c, model = checkBus(player, l)
	if model and #l.riders == 0 then
		task.spawn(function()
			for _ = 1, math.random(2, 4) do
				local seat = freeSeat(model)
				local npc = seat and model.PrimaryPart and spawnAt(model.PrimaryPart.CFrame * CFrame.new(0, 3, 0), 0)
				if npc and lines[player] == l and seatNpc(player, c, npc, seat) then
					table.insert(l.riders, { npc = npc, seat = seat })
				elseif npc then
					npc:Destroy()
				end
			end
		end)
	end
end

-- Só conclui quem está dirigindo o ônibus e parou
function Hooks.busCheck(player)
	local c = drivingBus(player)
	if not c then
		return "Venha dirigindo o ônibus! Ele fica na garagem da Um Tijo (🚌 no Mapa)."
	end
	local chassis = c.model.PrimaryPart
	if chassis and chassis.AssemblyLinearVelocity.Magnitude > STOP_SPEED then
		return "Pare o ônibus primeiro!"
	end
	return nil
end

-- Porta do ônibus, do lado de fora, no mundo. O ônibus LXR tem as portas à esquerda (atributo
-- DoorSide = -1); quem está na calçada da direita dá a volta pela frente do ônibus.
local function doorPos(c, which)
	local chassis = c.model.PrimaryPart
	local side = c.model:GetAttribute("DoorSide") or 1
	local doorZ = c.spec.DoorZ or {}
	local z = which == "front" and (doorZ.Front or -c.spec.Length / 2 + 2.5) or (doorZ.Middle or 1.5)
	return chassis.CFrame * Vector3.new(side * (c.spec.Width / 2 + 1.5), 0, z)
end

-- Marco 9.8: o passageiro vai até o lado do ônibus que está virado para ele (a calçada), na
-- altura da porta, e entra por ali. Antes ele dava a volta pela frente até a porta do lado da
-- rua (o ônibus LXR é inglês) e não chegava a entrar.
local function pathToDoor(c, which, from)
	local chassis = c.model.PrimaryPart
	local side = math.sign(chassis.CFrame:PointToObjectSpace(from).X)
	local doorZ = c.spec.DoorZ or {}
	local z = which == "front" and (doorZ.Front or -c.spec.Length / 2 + 2.5) or (doorZ.Middle or 1.5)
	return { chassis.CFrame * Vector3.new((side == 0 and 1 or side) * (c.spec.Width / 2 + 1.2), 0, z) }
end

-- Portas abertas: desce gente, sobe gente
function Hooks.busStop(player, state, step)
	local l = lineOf(player)
	local c, model = checkBus(player, l)
	if not model then
		return
	end
	model:SetAttribute("DoorsOpen", true)
	task.delay(3, function()
		if model.Parent then
			model:SetAttribute("DoorsOpen", false)
		end
	end)
	local stop = step.point and sites.points[step.point]
	local curb = stop and stop.part:GetAttribute("Curb")

	-- descem (pela porta do meio) e vão embora pela calçada
	local leaving = math.random(0, math.min(3, #l.riders))
	for _ = 1, leaving do
		local r = table.remove(l.riders, math.random(1, #l.riders))
		local npc = r.npc
		task.spawn(function()
			local weld = r.seat and r.seat:FindFirstChild("SeatWeld")
			if weld then
				weld:Destroy()
			end
			local humanoid = npc:FindFirstChildOfClass("Humanoid")
			if humanoid then
				humanoid.Sit = false
			end
			setMassless(npc, false)
			NPCKit.sit(npc, false)
			-- desce pelo lado da calçada (Marco 9.8), na altura da porta do meio
			local door = typeof(curb) == "CFrame" and pathToDoor(c, "middle", curb.Position)[1] or doorPos(c, "middle")
			local ground = NPCKit.groundAt(door)
			local at = Vector3.new(door.X, ground + 3, door.Z)
			local target = typeof(curb) == "CFrame" and curb.Position or at
			npc:PivotTo(CFrame.lookAt(at, Vector3.new(target.X, at.Y, target.Z)))
			local root = npc:FindFirstChild("HumanoidRootPart")
			if root then
				root.AssemblyLinearVelocity = Vector3.zero
				root.AssemblyAngularVelocity = Vector3.zero
			end
			if humanoid then
				humanoid:ChangeState(Enum.HumanoidStateType.Running)
			end
			task.wait(0.2)
			if not npc.Parent then
				return
			end
			if math.random() < 0.5 then
				NPCKit.say(npc, pick(BYE))
			end
			local away = typeof(curb) == "CFrame" and (curb * CFrame.new(math.random(-8, 8), 0, 8)).Position or at
			NPCKit.walk(npc, { target, away })
			npc:Destroy()
		end)
	end

	-- sobem (pela porta da frente) e sentam. Andam rápido até a porta; se o motorista sair
	-- antes (ou o NPC enroscar), entram direto: ninguém fica para trás na parada.
	local chassis = model.PrimaryPart
	local openedAt = chassis and chassis.Position
	local function busStill()
		return lines[player] == l and model.Parent ~= nil and chassis ~= nil
			and (chassis.Position - openedAt).Magnitude < 4
	end
	local boarding = l.waiting
	l.waiting = {}
	print(("[BusService] %s abriu as portas: %d descem, %d sobem"):format(player.Name, leaving, #boarding))
	for i, npc in ipairs(boarding) do
		task.spawn(function()
			task.wait(0.25 * (i - 1))
			if not npc.Parent or not model.Parent or lines[player] ~= l then
				npc:Destroy()
				return
			end
			if #l.riders >= MAX_RIDERS then
				NPCKit.say(npc, "Vou esperar o próximo!")
				task.wait(3)
				npc:Destroy()
				return
			end
			local humanoid = npc:FindFirstChildOfClass("Humanoid")
			if humanoid then
				humanoid.WalkSpeed = 16
			end
			if i == 1 and math.random() < 0.6 then
				NPCKit.say(npc, pick(HELLO))
			end
			if busStill() then
				NPCKit.walk(npc, pathToDoor(c, "front", npc:GetPivot().Position), nil, busStill)
			end
			local seat = model.Parent and freeSeat(model)
			if lines[player] ~= l or not npc.Parent or not seat then
				npc:Destroy()
				return
			end
			seat:SetAttribute("Reserved", true) -- dois passageiros não disputam o mesmo banco
			local ok = seatNpc(player, c, npc, seat)
			seat:SetAttribute("Reserved", nil)
			if ok then
				table.insert(l.riders, { npc = npc, seat = seat })
			else
				npc:Destroy()
			end
		end)
	end
end

function BusService.init(missionService, jobSites)
	sites = jobSites
	for name, fn in pairs(Hooks) do
		missionService.registerHook(name, fn)
	end
	-- largou o emprego, morreu ou saiu: passageiros somem
	missionService.onStop(clear)
	Players.PlayerRemoving:Connect(clear)
	print(("[BusService] %d paradas de ônibus."):format(#jobSites.busStops))
end

return BusService
