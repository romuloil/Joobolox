-- MarketService (ModuleScript)
-- Caminho: ServerScriptService > Services > MarketService
-- Partes "vivas" do Minas Market, ligadas às etapas do Atendente (JobConfig) pelo MissionService:
--   * cliente NPC: entra pela porta, vai até o caixa do atendente, põe as compras na esteira,
--     recebe a sacola, paga, agradece e vai embora;
--   * prateleiras: ficam meio vazias no começo da reposição e enchem quando o atendente repõe.
-- Tudo roda no servidor (todos veem o mesmo cliente). Cada atendente tem o próprio caixa (lane).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local JobConfig = require(Shared:WaitForChild("JobConfig"))
local NPCKit = require(script.Parent:WaitForChild("NPCKit"))

local MarketService = {}

local market -- JobSiteBuilder.market
local sites -- JobSiteBuilder
local customers = {} -- customers[player] = { npc, humanoid, lane, arriveAt }
local rng = Random.new()

local WALK_SPEED = 12
local GREETINGS = { "Oi! Só isso hoje.", "Boa tarde!", "Olá! Tudo bem?", "Oi, vou levar esses." }
local BEEP = "rbxasset://sounds/electronicpingshort.wav" -- som que já vem com o Roblox
local pick = NPCKit.pick
local say = NPCKit.say

local function now()
	return Workspace:GetServerTimeNow()
end

-- Clientes do caixa são "importantes": sempre aparecem, mesmo com a cidade cheia de NPCs
local function newCustomer(startCf)
	local npc = NPCKit.spawn(startCf, { name = "Cliente", speed = WALK_SPEED, important = true })
	return npc, npc and npc:FindFirstChildOfClass("Humanoid")
end

local function walk(c, points, faceDir)
	if c.npc then
		NPCKit.walk(c.npc, points, faceDir)
	end
end

local function pathLength(points)
	local total = 0
	for i = 2, #points do
		total += (points[i].Position - points[i - 1].Position).Magnitude
	end
	return total
end

local function hideSlots(lane)
	local data = market and market.lanes[lane]
	if not data then
		return
	end
	for _, slot in ipairs(data.slots) do
		slot.Transparency = 1
		if slot:GetAttribute("Home") then
			slot.CFrame = slot:GetAttribute("Home")
		end
	end
end

local function removeCustomer(player)
	local c = customers[player]
	customers[player] = nil
	if c then
		if c.npc then
			c.npc:Destroy()
		end
		hideSlots(c.lane)
	end
end

---------------------------------------------------------------------------
-- Ações das etapas (nomes usados em JobConfig: onBegin / onDone / onCollect)
---------------------------------------------------------------------------

local Hooks = {}

-- Atendente chamou o próximo cliente: ele aparece na porta e anda até o caixa
function Hooks.customerCome(player, state)
	removeCustomer(player)
	local lane = market.lanes[state.lane or 1]
	if not lane then
		return
	end
	local route = { market.door[1], market.door[2], lane.customerSpot }
	local c = { lane = state.lane or 1, arriveAt = now() + 1 + pathLength(route) / WALK_SPEED }
	customers[player] = c
	task.spawn(function()
		local npc, humanoid = newCustomer(route[1])
		if not npc then
			return
		end
		if customers[player] ~= c then
			npc:Destroy() -- o trabalho parou enquanto o cliente era criado
			return
		end
		c.npc, c.humanoid = npc, humanoid
		walk(c, { route[2], route[3] }, -market.base.LookVector) -- de frente para o balcão
		if customers[player] == c then
			say(npc, pick(GREETINGS))
		end
	end)
end

-- Etapa de passar no leitor: as compras aparecem na esteira quando o cliente chega.
-- Devolve quantos segundos faltam para o cliente chegar (a etapa só libera depois disso).
function Hooks.customerArrive(player, state, step)
	local c = customers[player]
	local wait = c and math.max(0, c.arriveAt - now()) or 0
	local options = {}
	for pointName, station in pairs(state.options or {}) do
		table.insert(options, { point = pointName, station = station })
	end
	task.delay(wait, function()
		if customers[player] ~= c then
			return
		end
		for _, entry in ipairs(options) do
			local point = sites.points[entry.point]
			if point then
				local slot = point.part
				if not slot:GetAttribute("Home") then
					slot:SetAttribute("Home", slot.CFrame)
				end
				slot.CFrame = slot:GetAttribute("Home")
				local product = step.products and step.products[entry.station]
				slot.Color = product and product.color or pick(JobConfig.Categories).color
				slot.Transparency = 0
			end
		end
	end)
	return wait
end

-- Um produto passou no leitor: desliza pelo leitor, apita e vai para a ponta das sacolas
function Hooks.scanItem(player, state, step, pointName)
	local c = customers[player]
	local lane = market.lanes[(c and c.lane) or state.lane or 1]
	local point = sites.points[pointName]
	if not lane or not point then
		return
	end
	local slot = point.part
	local beep = Instance.new("Sound")
	beep.SoundId = BEEP
	beep.Volume = 0.5
	beep.Parent = lane.scanner
	beep:Play()
	game:GetService("Debris"):AddItem(beep, 2)
	local overScanner = lane.scanner.CFrame * CFrame.new(0, 0.4, 0)
	local atBag = lane.bag.CFrame * CFrame.new(rng:NextNumber(-0.4, 0.4), 0.45, rng:NextNumber(-0.3, 0.3))
	local t1 = TweenService:Create(slot, TweenInfo.new(0.25), { CFrame = overScanner })
	t1:Play()
	t1.Completed:Connect(function()
		TweenService:Create(slot, TweenInfo.new(0.3), { CFrame = atBag }):Play()
	end)
end

-- Compras embaladas: somem do balcão e o cliente segura a sacola
function Hooks.customerBag(player)
	local c = customers[player]
	if not c then
		return
	end
	hideSlots(c.lane)
	NPCKit.hold(c.npc, "Sacola", Vector3.new(1, 1.3, 0.6), Color3.fromRGB(240, 240, 235), Enum.Material.Fabric)
end

-- Pagou: agradece e vai embora pela porta
function Hooks.customerLeave(player)
	local c = customers[player]
	if not c then
		return
	end
	customers[player] = nil
	local npc = c.npc
	if not npc then
		return
	end
	say(npc, pick({ "Obrigado! Até mais!", "Valeu! Bom trabalho!", "Até a próxima!" }))
	NPCKit.react(npc, "😊")
	NPCKit.emote(npc, "wave")
	task.spawn(function()
		task.wait(1.2)
		walk(c, { market.door[2], market.door[1], market.door[1] * CFrame.new(0, 0, -12) })
		npc:Destroy()
	end)
end

-- Começo da reposição: as prateleiras do pedido ficam meio vazias
function Hooks.shelvesEmpty(player, state, step)
	for _, cat in ipairs(step.cats or {}) do
		for i, product in ipairs(market.shelves[cat] or {}) do
			if i % 2 == 0 or i % 3 == 0 then
				product.Transparency = 1
			end
		end
	end
end

-- Prateleira reposta: os produtos voltam
function Hooks.shelfFill(player, state, step)
	for _, product in ipairs(market.shelves[step.cat] or {}) do
		product.Transparency = 0
	end
end

function MarketService.init(missionService, jobSites)
	sites = jobSites
	market = jobSites.market
	if not market then
		warn("[MarketService] Minas Market não encontrado; clientes NPC desligados.")
		return
	end
	for name, fn in pairs(Hooks) do
		missionService.registerHook(name, fn)
	end
	missionService.onStop(function(player)
		removeCustomer(player)
		-- parou no meio da reposição: as prateleiras não ficam vazias para sempre
		for _, products in pairs(market.shelves) do
			for _, product in ipairs(products) do
				product.Transparency = 0
			end
		end
	end)
end

return MarketService
