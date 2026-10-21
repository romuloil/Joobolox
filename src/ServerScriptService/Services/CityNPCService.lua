-- CityNPCService (ModuleScript)
-- Caminho: ServerScriptService > Services > CityNPCService
-- Marco 5: os NPCs que dão vida à cidade (todos usam o NPCKit).
--   * Funcionários: um em cada loja, atrás do balcão, quando NENHUM jogador está nessa profissão.
--     Cumprimentam quem chega perto e explicam o emprego (E para conversar).
--   * Cliente da pizzaria: entra quando o pizzaiolo pega a comanda, espera no balcão,
--     reclama se demorar, recebe a caixa de pizza, reage (feliz ou nem tanto) e vai embora.
--   * Destinatário da entrega: abre a porta, pega o pacote, agradece, acena e entra.
--   * Pessoas passeando na praça (poucas, para não pesar).
-- As ações do cliente e do destinatário estão ligadas às etapas em JobConfig (onDone).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local JobConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("JobConfig"))
local NPCKit = require(script.Parent:WaitForChild("NPCKit"))
local SecurityService = require(script.Parent:WaitForChild("SecurityService"))

local CityNPCService = {}

local mission -- MissionService
local sites -- JobSiteBuilder
local pick = NPCKit.pick
local rng = Random.new()

local function now()
	return Workspace:GetServerTimeNow()
end

-- Chão de uma posição (cf com a altura do chão de verdade)
local function onGround(cf)
	local y = NPCKit.groundAt(cf.Position)
	return CFrame.new(cf.X, y, cf.Z) * cf.Rotation
end

---------------------------------------------------------------------------
-- Funcionários das lojas
---------------------------------------------------------------------------

local STAFF = {
	Pizzaiolo = {
		name = "Giovanni",
		shirt = Color3.fromRGB(245, 245, 240),
		hello = { "Buonasera! Bem-vindo à La Paulistana!", "Oi! Hoje tem pizza quentinha!" },
		talk = { "Quer ser pizzaiolo? Pegue o emprego no quadro da praça!", "Molho e queijo vão em todas. O resto, veja na comanda!" },
	},
	Atendente = {
		name = "Dona Lúcia",
		shirt = Color3.fromRGB(40, 140, 70),
		hello = { "Bom dia! Tudo fresquinho hoje!", "Olá! Bem-vindo ao Minas Market!" },
		talk = { "Precisamos de gente no caixa! Veja o quadro de empregos.", "Repor prateleira é fácil: caixa certa, prateleira, reciclagem." },
	},
	Entregador = {
		name = "Rafa",
		shirt = Color3.fromRGB(240, 140, 30),
		hello = { "E aí! Sherlex Entregas, rapidinho!", "Opa! Tem muito pacote hoje!" },
		talk = { "Quer entregar pacotes? Pegue o emprego no quadro da praça!", "Dica: o mapa mostra a rua e o número da casa." },
	},
	PetShop = {
		name = "Bia",
		shirt = Color3.fromRGB(130, 80, 200),
		hello = { "Oi! Que bom te ver aqui!", "Bem-vindo ao Duto Pet Shop!" },
		talk = { "O banho e tosa vai abrir em breve. Volte depois!", "Logo logo vamos contratar ajudantes!" },
	},
}

local staffNpc = {} -- staffNpc[jobId] = npc
local greeted = {} -- greeted[jobId][player] = true enquanto o jogador está perto

local function spawnStaff(jobId)
	local shop = sites.shops[jobId]
	local info = STAFF[jobId]
	if not shop or not shop.staff or not info then
		return
	end
	local npc = NPCKit.spawn(onGround(shop.staff), { name = info.name, shirt = info.shirt, anchored = true, important = true, showName = true })
	if not npc then
		return
	end
	staffNpc[jobId] = npc
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Conversar"
	prompt.ObjectText = info.name
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.MaxActivationDistance = 9
	prompt.RequiresLineOfSight = false
	prompt.Parent = npc:FindFirstChild("HumanoidRootPart")
	prompt.Triggered:Connect(function(player)
		if not SecurityService.checkRate(player, "TalkStaff", 1) then
			return
		end
		NPCKit.say(npc, pick(info.talk), 4.5)
		NPCKit.emote(npc, "point")
	end)
end

local function updateStaff()
	for jobId in pairs(STAFF) do
		local hasJob = JobConfig.Jobs[jobId] ~= nil
		local wanted = not hasJob or mission.workers(jobId) == 0
		local npc = staffNpc[jobId]
		if wanted and not (npc and npc.Parent) then
			spawnStaff(jobId)
		elseif not wanted and npc then
			npc:Destroy() -- um jogador assumiu o balcão
			staffNpc[jobId] = nil
		end
		npc = staffNpc[jobId]
		-- cumprimenta quem chega perto (uma vez por visita)
		local root = npc and npc:FindFirstChild("HumanoidRootPart")
		if root then
			greeted[jobId] = greeted[jobId] or {}
			for _, player in ipairs(game:GetService("Players"):GetPlayers()) do
				local character = player.Character
				local proot = character and character:FindFirstChild("HumanoidRootPart")
				local near = proot and (proot.Position - root.Position).Magnitude < 14
				if near and not greeted[jobId][player] then
					greeted[jobId][player] = true
					NPCKit.say(npc, pick(STAFF[jobId].hello))
					NPCKit.emote(npc, "wave")
				elseif not near and greeted[jobId][player] and proot and (proot.Position - root.Position).Magnitude > 22 then
					greeted[jobId][player] = nil
				end
			end
		end
	end
end

---------------------------------------------------------------------------
-- Cliente da pizzaria
---------------------------------------------------------------------------

local pizzaCustomers = {} -- [player] = { npc, spot, warned }

local function removePizzaCustomer(player)
	local c = pizzaCustomers[player]
	pizzaCustomers[player] = nil
	if c and c.npc then
		c.npc:Destroy()
	end
end

local function freeSpot(shop)
	local used = {}
	for _, c in pairs(pizzaCustomers) do
		used[c.spot] = true
	end
	for i = 1, #shop.customers do
		if not used[i] then
			return i
		end
	end
	return 1
end

local Hooks = {}

function Hooks.pizzaCustomerCome(player, state)
	removePizzaCustomer(player)
	local shop = sites.shops.Pizzaiolo
	if not shop or #shop.customers == 0 then
		return
	end
	local c = { spot = freeSpot(shop) }
	pizzaCustomers[player] = c
	local title = state.order and state.order.title or "pizza"
	task.spawn(function()
		local npc = NPCKit.spawn(onGround(shop.door[1]), { name = "Cliente", speed = 11, important = true })
		if not npc then
			return
		end
		if pizzaCustomers[player] ~= c then
			npc:Destroy()
			return
		end
		c.npc = npc
		local target = shop.customers[c.spot]
		NPCKit.walk(npc, { shop.door[2], target }, target.LookVector, function()
			return pizzaCustomers[player] == c
		end)
		if pizzaCustomers[player] ~= c then
			return
		end
		NPCKit.say(npc, pick({ "Uma %s, por favor!", "Oi! Queria uma %s.", "Boa noite! Me vê uma %s?" }):format((title:gsub("^Pizza ", ""))))
		-- esperando: reclama uma vez se passar do tempo ou se a pizza queimar
		while pizzaCustomers[player] == c and npc.Parent do
			task.wait(2)
			local late = state.order and state.orderStartedAt and now() - state.orderStartedAt > (state.order.parTime or 90)
			if (late or state.tipLost) and not c.warned and pizzaCustomers[player] == c then
				c.warned = true
				NPCKit.say(npc, state.tipLost and "Queimou?! Tudo bem, eu espero..." or "Tá demorando, hein...")
				NPCKit.react(npc, "😕")
			end
		end
	end)
end

function Hooks.pizzaCustomerReceive(player, state)
	local c = pizzaCustomers[player]
	pizzaCustomers[player] = nil
	local npc = c and c.npc
	if not npc or not npc.Parent then
		return
	end
	local order = state.order
	local fast = order and not state.tipLost and order.tip and (now() - state.orderStartedAt) <= order.parTime
	NPCKit.hold(npc, "CaixaPizza", Vector3.new(2.2, 0.4, 2.2), Color3.fromRGB(205, 160, 105), Enum.Material.Cardboard)
	if fast then
		NPCKit.say(npc, pick({ "Que cheiro bom! Toma a gorjeta!", "Rapidinho! Obrigado!", "Perfeita! Volto amanhã!" }))
		NPCKit.react(npc, "😍")
		NPCKit.emote(npc, "cheer")
	else
		NPCKit.say(npc, pick({ "Finalmente! Obrigado.", "Demorou, mas chegou." }))
		NPCKit.react(npc, "😐")
	end
	local shop = sites.shops.Pizzaiolo
	task.spawn(function()
		task.wait(1.6)
		if npc.Parent and shop then
			NPCKit.walk(npc, { shop.door[2], shop.door[1], shop.door[1] * CFrame.new(0, 0, -10) })
		end
		npc:Destroy()
	end)
end

---------------------------------------------------------------------------
-- Destinatário da entrega
---------------------------------------------------------------------------

local busyDoors = {}

function Hooks.deliveryThanks(player, state, step)
	local point = step.point and sites.points[step.point]
	local door = point and point.visual
	if not door or not door:IsA("BasePart") or busyDoors[door] then
		return
	end
	busyDoors[door] = true
	task.spawn(function()
		-- porta "abre" (some um instante) e o morador aparece na porta
		local oldT = door.Transparency
		door.Transparency = 0.85
		local groundY = door.Position.Y - door.Size.Y / 2
		local outward = door.CFrame.LookVector
		local startPos = Vector3.new(door.Position.X, groundY, door.Position.Z) + outward * 0.6
		local npc = NPCKit.spawn(CFrame.lookAt(startPos, startPos + outward), { name = "Morador", speed = 8 })
		if npc then
			NPCKit.walk(npc, { startPos + outward * 1.8 }, outward)
			NPCKit.hold(npc, "Pacote", Vector3.new(1.4, 1.2, 1.4), Color3.fromRGB(190, 145, 95), Enum.Material.Cardboard)
			NPCKit.say(npc, pick({ "Chegou! Muito obrigado!", "Oba, meu pacote! Valeu!", "Que rapidez! Obrigada!" }))
			NPCKit.react(npc, pick({ "😊", "🥳", "❤️" }))
			NPCKit.emote(npc, "wave")
			task.wait(2.8)
			if npc.Parent then
				NPCKit.walk(npc, { startPos }, -outward)
			end
			npc:Destroy()
		end
		door.Transparency = oldT
		busyDoors[door] = nil
	end)
end

---------------------------------------------------------------------------
-- Pessoas passeando na praça
---------------------------------------------------------------------------

local WALKERS = 4
local WALK_RING = 18 -- caminho em volta do chafariz (entre as flores e os bancos)
local PLAZA_Y = 0.95
local LINES = { "Que dia lindo!", "Adoro essa praça!", "Já tomou sorvete hoje?", "Olha o chafariz!", "Bom dia!", "Vou ali na pizzaria..." }

local function ringPoint(angleDeg)
	local a = math.rad(angleDeg)
	return Vector3.new(math.cos(a) * WALK_RING, PLAZA_Y, math.sin(a) * WALK_RING)
end

local function walker()
	local angle = rng:NextInteger(0, 15) * 22.5
	local npc = NPCKit.spawn(CFrame.new(ringPoint(angle)), { name = "Morador", speed = rng:NextNumber(6, 9) })
	if not npc then
		return
	end
	local dir = rng:NextInteger(0, 1) == 0 and -1 or 1
	while npc.Parent do
		-- ninguém perto da praça: o NPC fica parado (economiza servidor)
		if not NPCKit.anyPlayerNear(Vector3.zero, 160) then
			task.wait(3)
		else
			local points = {}
			for _ = 1, rng:NextInteger(2, 5) do
				angle += 22.5 * dir
				table.insert(points, ringPoint(angle))
			end
			NPCKit.walk(npc, points)
			local roll = rng:NextNumber()
			if roll < 0.25 then
				NPCKit.say(npc, pick(LINES))
			elseif roll < 0.35 then
				NPCKit.emote(npc, "wave")
			elseif roll < 0.45 then
				NPCKit.face(npc, -npc:GetPivot().Position) -- para e olha o chafariz
			end
			if rng:NextNumber() < 0.3 then
				dir = -dir
			end
			task.wait(rng:NextNumber(2, 6))
		end
	end
end

function CityNPCService.init(missionService, jobSites)
	mission = missionService
	sites = jobSites
	for name, fn in pairs(Hooks) do
		mission.registerHook(name, fn)
	end
	mission.onStop(removePizzaCustomer)
	game:GetService("Players").PlayerRemoving:Connect(function(player)
		for _, list in pairs(greeted) do
			list[player] = nil
		end
	end)

	task.spawn(function()
		while true do
			local ok, err = pcall(updateStaff)
			if not ok then
				warn("[CityNPCService] " .. tostring(err))
			end
			task.wait(1)
		end
	end)
	for i = 1, WALKERS do
		task.delay(i * 0.7, walker)
	end
end

return CityNPCService
