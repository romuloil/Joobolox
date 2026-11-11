-- FireService (ModuleScript)
-- Caminho: ServerScriptService > Services > FireService
-- Marco 10.16: incêndio em EQUIPE (ver JobConfig.Fire): todos os bombeiros em serviço recebem o mesmo
-- incêndio, só eles veem o fogo (FireController), o fogo cresce sozinho e tem tempo para queimar.
-- Marco 9.9: Bombeiro. Os pedidos são normais do MissionService (JobConfig: fireOrder); aqui ficam
-- as ações especiais das etapas:
--   * fireStart: a casa pega fogo (chamas, fumaça, luz laranja) e o morador sai pedindo socorro;
--   * fireTruckCheck: só conclui quem chegou dirigindo o caminhão de bombeiros, parado;
--   * fireOnFoot: para jogar água tem que estar a pé (fora do caminhão);
--   * fireOut: jato de água, o fogo diminui e apaga, a fumaça some e o morador agradece.
-- Também cuida do cano de descida do quartel (aviso "Descer pelo cano").

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

local GameConfig = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("GameConfig"))
local JobConfig = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("JobConfig"))
local NPCKit = require(script.Parent:WaitForChild("NPCKit"))
local VehicleService = require(script.Parent:WaitForChild("VehicleService"))
local SecurityService = require(script.Parent:WaitForChild("SecurityService"))

local FireService = {}

local JOB = "Bombeiro"
local STOP_SPEED = 8
local F -- JobConfig.Fire

local sites
local missionService
local fireFolder

-- Marco 10.16: UM incêndio para a equipe toda. O fogo é desenhado só no cliente dos bombeiros
-- (FireController), a partir dos atributos do objeto "Incendio" em Workspace.Incendios.
-- incident = { entry, front, model, hp, deadline, crew = {[player]=true}, hosed = {[player]=true},
--              lastHose, resident, obj, ended }
local incident

local HELP = { "Socorro! Fogo!", "Ajuda! A casa está pegando fogo!", "Chamem os bombeiros!", "Rápido, vai queimar tudo!" }
local THANKS = { "Obrigado, bombeiros!", "Vocês salvaram a minha casa!", "Ufa! Valeu demais!" }
local SAD = { "Não! Minha casa...", "Chegaram tarde demais...", "Perdi tudo!" }

local function pick(list)
	return list[math.random(1, #list)]
end

local function frontOf(entry)
	local point = entry and sites.points[entry.house]
	return point and point.part
end

local function publish(i)
	local obj = i.obj
	if not obj then
		return
	end
	obj:SetAttribute("Hp", math.floor(i.hp + 0.5))
	obj:SetAttribute("MaxHp", F.MaxHp)
	obj:SetAttribute("Deadline", i.deadlineServer)
	obj:SetAttribute("Crew", (function()
		local n = 0
		for _ in pairs(i.crew) do
			n += 1
		end
		return n
	end)())
end

-- Termina o incêndio: "apagado" ou "queimou"; o objeto fica alguns segundos para o vapor/fumaça
local function finish(i, result)
	if i.ended then
		return
	end
	i.ended = result
	if incident == i then
		incident = nil
	end
	if i.obj then
		i.obj:SetAttribute("Estado", result)
		Debris:AddItem(i.obj, result == "queimou" and 25 or 8)
	end
	local resident = i.resident
	if resident and resident.Parent then
		task.spawn(function()
			NPCKit.say(resident, pick(result == "apagado" and THANKS or SAD), 3)
			NPCKit.emote(resident, result == "apagado" and "cheer" or "wave")
			NPCKit.react(resident, result == "apagado" and "😊" or "😭")
			task.wait(4)
			if resident.Parent then
				resident:Destroy()
			end
		end)
	end
end

local function newIncident()
	local list = sites.fires
	if #list == 0 then
		return nil
	end
	local entry = list[math.random(1, #list)]
	local front = frontOf(entry)
	if not front or not entry.model then
		return nil
	end
	local origin = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild(GameConfig.Places.Bombeiros, true)
	local dist = origin and origin:IsA("Model") and (entry.model:GetPivot().Position - origin:GetPivot().Position).Magnitude or 800
	local burnTime = F.BurnBase + dist * F.BurnPerStud
	local i = {
		entry = entry,
		front = front,
		hp = F.StartHp,
		deadline = os.clock() + burnTime,
		deadlineServer = Workspace:GetServerTimeNow() + burnTime,
		crew = {},
		hosed = {},
		lastHose = 0,
	}
	-- pontos das chamas: telhado, janelas e porta (pelo tamanho da casa)
	local cf, size = entry.model:GetBoundingBox()
	local top = cf.Position.Y + size.Y / 2
	local spots = {
		{ CFrame.new(cf.Position.X, top - 1, cf.Position.Z), 8 },
		{ front.CFrame * CFrame.new(-6, 4, 6), 4 },
		{ front.CFrame * CFrame.new(6, 5, 6), 4 },
		{ front.CFrame * CFrame.new(0, 7, 7), 4 },
		{ CFrame.new(cf.Position.X + size.X * 0.3, top - 2, cf.Position.Z - size.Z * 0.2), 5 },
	}
	local obj = Instance.new("Configuration")
	obj.Name = "Incendio"
	obj:SetAttribute("Estado", "fogo")
	obj:SetAttribute("Endereco", entry.address)
	for n, sp in ipairs(spots) do
		obj:SetAttribute("Spot" .. n, sp[1].Position)
		obj:SetAttribute("Size" .. n, sp[2])
	end
	obj.Parent = fireFolder
	i.obj = obj
	publish(i)
	-- morador na calçada pedindo socorro
	local spot = front.CFrame * CFrame.new(5, -2, -2)
	local ground = NPCKit.groundAt(spot.Position)
	i.resident = NPCKit.spawn(CFrame.new(spot.X, ground, spot.Z) * CFrame.Angles(0, math.rad(180), 0) * front.CFrame.Rotation, {
		name = "Morador",
		important = true,
		anchored = true,
	})
	if i.resident then
		task.spawn(function()
			while not i.ended and i.resident and i.resident.Parent do
				NPCKit.say(i.resident, pick(HELP), 3)
				NPCKit.emote(i.resident, "wave")
				task.wait(6)
			end
		end)
	end
	incident = i
	return i
end

-- Contexto do pedido: todos os bombeiros pegam o mesmo incêndio
local function pickFire()
	local i = incident
	if not i or i.ended then
		i = newIncident()
	end
	return i and i.entry or nil
end

-- Saiu do emprego/renasceu/saiu do jogo: sai da equipe. Sem ninguém, o incêndio some.
local function leaveCrew(player)
	local i = incident
	if not i or not i.crew[player] then
		return
	end
	i.crew[player] = nil
	i.hosed[player] = nil
	publish(i)
	if next(i.crew) == nil and missionService.workers(JOB) == 0 then
		if i.resident and i.resident.Parent then
			i.resident:Destroy()
		end
		i.ended = "cancelado"
		if incident == i then
			incident = nil
		end
		if i.obj then
			i.obj:Destroy()
		end
	end
end

local function truckNear(position)
	local vehicles = Workspace:FindFirstChild("Vehicles")
	if not vehicles then
		return false
	end
	for _, car in ipairs(vehicles:GetChildren()) do
		if car:IsA("Model") and car:GetAttribute("Service") == JOB then
			local ok, pivot = pcall(car.GetPivot, car)
			if ok and (pivot.Position - position).Magnitude <= F.TruckRange then
				return true
			end
		end
	end
	return false
end

local Hooks = {}

-- Etapa 1 começou: entra na equipe do incêndio
function Hooks.fireStart(player, state)
	local i = incident
	local fire = state.order and state.order.fire
	if not i or i.ended or not fire or fire.house ~= i.entry.house then
		return
	end
	i.crew[player] = true
	publish(i)
end

-- Chegou dirigindo o caminhão e parou
function Hooks.fireTruckCheck(player)
	local c = VehicleService.getCar(player)
	local _, humanoid = SecurityService.getLivingCharacter(player)
	if not c or not humanoid or c.spec.Service ~= JOB or humanoid.SeatPart ~= c.driver then
		-- Marco 10.16: em equipe, quem veio de carona no caminhão de outro bombeiro também vale
		local _, _, root = SecurityService.getLivingCharacter(player)
		if not (root and truckNear(root.Position)) then
			return "Venha com o caminhão de bombeiros! Ele fica no quartel (🚒 no Mapa)."
		end
		return nil
	end
	local chassis = c.model.PrimaryPart
	if chassis and chassis.AssemblyLinearVelocity.Magnitude > STOP_SPEED then
		return "Pare o caminhão primeiro!"
	end
	return nil
end

-- Marco 10.16: cada jato tira força do fogo. Apagou = toda a equipe que jogou água conclui.
function Hooks.fireHose(player, state)
	local i = incident
	local fire = state.order and state.order.fire
	if not i or i.ended or not fire or fire.house ~= i.entry.house then
		return nil -- incêndio velho: só conclui
	end
	local _, humanoid, root = SecurityService.getLivingCharacter(player)
	if not humanoid or humanoid.SeatPart then
		return "Desça do caminhão para usar a mangueira!"
	end
	if not truckNear(root.Position) then
		return "A mangueira precisa do caminhão perto (até " .. F.TruckRange .. " studs)!"
	end
	i.crew[player] = true
	i.hosed[player] = true
	i.lastHose = os.clock()
	i.hp = math.max(0, i.hp - F.HoseDamage)
	publish(i)
	if i.hp > 0 then
		return { text = ("💧 Fogo em %d%%. Continue!"):format(math.ceil(i.hp / F.MaxHp * 100)), good = true }
	end
	-- apagou! os outros da equipe que jogaram água concluem também; quem não jogou recomeça
	finish(i, "apagado")
	for other in pairs(i.crew) do
		if other ~= player and other.Parent then
			local step, job = missionService.stepOf(other)
			if job == JOB and step then
				if i.hosed[other] and step == 2 then
					missionService.completeStep(other, 2)
				else
					missionService.restartOrder(other, "🧯 A equipe apagou o fogo sem você. Próximo chamado já vem!", 4)
				end
			end
		end
	end
	return nil
end

-- Fogo apagado (efeito no servidor: nada; o vapor é do cliente)
function Hooks.fireOut()
end

local function tick()
	local i = incident
	if not i or i.ended then
		return
	end
	local now = os.clock()
	if now - i.lastHose > 3 and i.hp < F.MaxHp then
		i.hp = math.min(F.MaxHp, i.hp + F.GrowPerSec)
		publish(i)
	end
	if now >= i.deadline then
		finish(i, "queimou")
		for other in pairs(i.crew) do
			if other.Parent then
				missionService.restartOrder(other, "🔥 A casa queimou! Ninguém ganhou nada. Próximo chamado em breve.", 8)
			end
		end
	end
end

---------------------------------------------------------------------------
-- Cano de descida do quartel
---------------------------------------------------------------------------

local function setupPole()
	local map = Workspace:FindFirstChild("Map")
	local garages = map and map:FindFirstChild("Garages")
	local station = garages and garages:FindFirstChild("QuartelBombeiros")
	local top = station and station:FindFirstChild("CanoTopo")
	local bottom = station and station:FindFirstChild("CanoBase")
	local pole = station and station:FindFirstChild("Cano")
	if not (top and bottom and pole) then
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "CanoPrompt"
	prompt.ActionText = "Descer pelo cano"
	prompt.ObjectText = "Cano dos bombeiros"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.MaxActivationDistance = 8
	prompt.RequiresLineOfSight = false
	prompt.Parent = top
	local sliding = {}
	prompt.Triggered:Connect(function(player)
		local character, humanoid, root = SecurityService.getLivingCharacter(player)
		if not character or sliding[player] or humanoid.SeatPart then
			return
		end
		sliding[player] = true
		-- abraçado no cano, escorrega até o colchão (o personagem fica preso e desce)
		local x, z = pole.Position.X, pole.Position.Z
		local from = top.Position.Y + 1
		local to = bottom.Position.Y + 1
		local look = (bottom.Position - Vector3.new(x, bottom.Position.Y, z))
		local facing = look.Magnitude > 0.1 and look.Unit or Vector3.new(0, 0, -1)
		root.Anchored = true
		for i = 0, 20 do
			local y = from + (to - from) * (i / 20) ^ 1.4
			root.CFrame = CFrame.lookAt(Vector3.new(x - facing.X * 1.2, y, z - facing.Z * 1.2), Vector3.new(x, y, z))
			task.wait(0.04)
		end
		root.CFrame = CFrame.lookAt(bottom.Position + Vector3.new(0, 1, 0), bottom.Position + Vector3.new(0, 1, 0) + facing)
		root.Anchored = false
		sliding[player] = nil
	end)
end

function FireService.init(mission, jobSites)
	missionService = mission
	sites = jobSites
	F = JobConfig.Fire
	fireFolder = Instance.new("Folder")
	fireFolder.Name = "Incendios"
	fireFolder.Parent = Workspace
	for name, fn in pairs(Hooks) do
		missionService.registerHook(name, fn)
	end
	missionService.setContext("pickFire", pickFire)
	missionService.onStop(leaveCrew)
	Players.PlayerRemoving:Connect(leaveCrew)
	task.spawn(function()
		while true do
			task.wait(1)
			tick()
		end
	end)
	setupPole()
	print(("[FireService] %d casas para o Bombeiro."):format(#jobSites.fires))
end

return FireService
