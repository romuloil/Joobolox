-- TaxiService (ModuleScript)
-- Caminho: ServerScriptService > Services > TaxiService
-- Marco 9: passageiros do Taxista. As corridas são pedidos normais do MissionService
-- (JobConfig: taxiOrder); aqui ficam as ações especiais das etapas:
--   * taxiCall: o passageiro NPC aparece na calçada do ponto e acena quando o táxi chega perto;
--   * taxiCheck: só conclui a etapa quem está dirigindo o Táxi LXR, parado;
--   * taxiBoard: o passageiro anda até o táxi e senta no banco de trás;
--   * taxiDropoff: o passageiro desce na calçada do destino, agradece e vai embora.

local Players = game:GetService("Players")

local NPCKit = require(script.Parent:WaitForChild("NPCKit"))
local VehicleService = require(script.Parent:WaitForChild("VehicleService"))
local SecurityService = require(script.Parent:WaitForChild("SecurityService"))

local TaxiService = {}

local JOB = "Taxista"
local STOP_SPEED = 8 -- acima disso o táxi ainda está andando
local WAVE_DISTANCE = 70 -- o passageiro acena quando o táxi chega a essa distância

local sites
local riders = {} -- riders[player] = { npc, token }

local CALLS = { "Táxi! Aqui!", "Ei, táxi!", "Aqui, moço!", "Táxi, por favor!" }
local ASKS = { "Para %s, por favor!", "Me leva até %s?", "Vamos para %s!", "%s, por favor. Obrigado!" }
local THANKS = { "Obrigado pela corrida!", "Chegamos! Valeu!", "Que viagem boa!", "Muito obrigada!" }

local function pick(list)
	return list[math.random(1, #list)]
end

-- Táxi que o jogador está dirigindo agora (nil se não estiver)
local function drivingTaxi(player)
	local c = VehicleService.getCar(player)
	local _, humanoid = SecurityService.getLivingCharacter(player)
	if not c or not humanoid or c.spec.Service ~= JOB or humanoid.SeatPart ~= c.driver then
		return nil
	end
	return c
end

local function removeRider(player)
	local r = riders[player]
	riders[player] = nil
	if r and r.npc then
		r.npc:Destroy()
	end
end

local function setMassless(npc, value)
	for _, p in ipairs(npc:GetDescendants()) do
		if p:IsA("BasePart") then
			p.Massless = value -- sentado no táxi não muda o jeito do carro andar
		end
	end
end

local function pointOf(step)
	local point = step.point and sites.points[step.point]
	return point and point.part
end

local Hooks = {}

-- Etapa 1 começou: o passageiro aparece na calçada, de frente para a rua
function Hooks.taxiCall(player, state, step)
	removeRider(player)
	local spot = pointOf(step)
	if not spot then
		return
	end
	local pos = spot.Position
	local ground = NPCKit.groundAt(pos)
	local look = spot.CFrame.LookVector
	local npc = NPCKit.spawn(CFrame.lookAt(Vector3.new(pos.X, ground, pos.Z), Vector3.new(pos.X, ground, pos.Z) + look), {
		name = "Passageiro",
		important = true, -- não entra no limite de NPCs da cidade
		anchored = true,
		speed = 10,
	})
	if not npc then
		return
	end
	local r = { npc = npc, boarding = false, seat = nil }
	riders[player] = r
	-- acena quando o táxi chega perto (uma vez)
	task.spawn(function()
		while riders[player] == r and npc.Parent and not r.boarding do
			local c = VehicleService.getCar(player)
			local chassis = c and c.model.PrimaryPart
			if chassis and (chassis.Position - pos).Magnitude < WAVE_DISTANCE then
				NPCKit.say(npc, pick(CALLS))
				NPCKit.emote(npc, "wave")
				return
			end
			task.wait(1)
		end
	end)
end

-- Só conclui quem está dirigindo o Táxi LXR e parou
function Hooks.taxiCheck(player)
	local c = drivingTaxi(player)
	if not c then
		return "Venha dirigindo o Táxi LXR! Ele fica na garagem da LXR Táxis (🚕 no Mapa)."
	end
	local chassis = c.model.PrimaryPart
	if chassis and chassis.AssemblyLinearVelocity.Magnitude > STOP_SPEED then
		return "Pare o táxi primeiro!"
	end
	return nil
end

-- Banco livre no táxi: atrás primeiro, depois o da frente
local function freeSeat(model)
	local list = {}
	for _, seat in ipairs(model:GetChildren()) do
		if seat.Name == "RearSeat" and seat:IsA("Seat") and not seat.Occupant then
			table.insert(list, seat)
		end
	end
	local front = model:FindFirstChild("PassengerSeat")
	if front and front:IsA("Seat") and not front.Occupant then
		table.insert(list, front)
	end
	return list[1]
end

-- Etapa 1 concluída: o passageiro entra no táxi
function Hooks.taxiBoard(player, state)
	local r = riders[player]
	local c = VehicleService.getCar(player)
	if not r or not r.npc.Parent or not c then
		return
	end
	r.boarding = true
	local npc = r.npc
	local model = c.model
	local destLabel = state.order.destLabel
	task.spawn(function()
		local chassis = model.PrimaryPart
		local seat = freeSeat(model)
		if not chassis or not seat then
			NPCKit.say(npc, "Ih, o táxi está cheio!")
			return
		end
		-- anda até a porta do lado da calçada
		local side = math.sign(chassis.CFrame:PointToObjectSpace(npc:GetPivot().Position).X)
		local door = chassis.CFrame * Vector3.new((side == 0 and 1 or side) * (c.spec.Width / 2 + 1.5), 0, 2)
		NPCKit.walk(npc, { door }, nil, function()
			return riders[player] == r
		end)
		if riders[player] ~= r or not npc.Parent or not seat.Parent or seat.Occupant then
			return
		end
		local humanoid = npc:FindFirstChildOfClass("Humanoid")
		local root = npc:FindFirstChild("HumanoidRootPart")
		if not humanoid or not root then
			return
		end
		root.Anchored = false
		setMassless(npc, true)
		NPCKit.sit(npc, true) -- liga o "sentado" do NPC antes de sentar
		seat:Sit(humanoid)
		-- o carro (com o passageiro soldado) continua sendo controlado por quem dirige
		local _, hum = SecurityService.getLivingCharacter(player)
		if hum and hum.SeatPart == c.driver then
			pcall(function()
				chassis:SetNetworkOwner(player)
			end)
		end
		r.seat = seat
		if destLabel then
			NPCKit.say(npc, pick(ASKS):format(destLabel), 4.5)
		end
	end)
end

-- Etapa 2 concluída: o passageiro desce na calçada, agradece e vai embora
function Hooks.taxiDropoff(player, state, step)
	local r = riders[player]
	riders[player] = nil -- o próximo passageiro não apaga este (ele ainda está descendo)
	local spot = pointOf(step)
	if not r or not r.npc.Parent then
		return
	end
	local npc = r.npc
	task.spawn(function()
		local humanoid = npc:FindFirstChildOfClass("Humanoid")
		local seat = r.seat
		local weld = seat and seat:FindFirstChild("SeatWeld")
		if weld then
			weld:Destroy()
		end
		if humanoid then
			humanoid.Sit = false
		end
		setMassless(npc, false)
		NPCKit.sit(npc, false)
		local c = VehicleService.getCar(player)
		local chassis = c and c.model.PrimaryPart
		local target = spot and spot.Position or npc:GetPivot().Position
		if chassis then
			-- sai pela porta do lado da calçada
			local side = math.sign(chassis.CFrame:PointToObjectSpace(target).X)
			local door = chassis.CFrame * Vector3.new((side == 0 and 1 or side) * (c.spec.Width / 2 + 1.5), 0, 2)
			local ground = NPCKit.groundAt(door)
			local at = Vector3.new(door.X, ground + 3, door.Z)
			npc:PivotTo(CFrame.lookAt(at, Vector3.new(target.X, at.Y, target.Z))) -- em pé, olhando a calçada
		end
		-- Marco 9.4: volta a ficar em pé (antes às vezes caía deitado na grama)
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
		NPCKit.walk(npc, { target })
		if not npc.Parent then
			return
		end
		NPCKit.say(npc, pick(THANKS))
		NPCKit.react(npc, pick({ "😊", "👍", "❤️" }))
		NPCKit.emote(npc, "wave")
		task.wait(2.5)
		if npc.Parent and spot then
			NPCKit.walk(npc, { target - spot.CFrame.LookVector * 6 })
		end
		npc:Destroy()
	end)
end

function TaxiService.init(missionService, jobSites)
	sites = jobSites
	for name, fn in pairs(Hooks) do
		missionService.registerHook(name, fn)
	end
	-- largou o emprego, morreu ou saiu: o passageiro some
	missionService.onStop(removeRider)
	Players.PlayerRemoving:Connect(removeRider)
	print(("[TaxiService] %d pontos de táxi."):format(#jobSites.taxiSpots))
end

return TaxiService
