-- MissionService (ModuleScript)
-- Caminho: ServerScriptService > Services > MissionService
-- Sistema central de pedidos e pagamentos (documento mestre, seção 7.1), usado por TODAS as profissões:
--   sortear pedido -> mostrar etapa/destino -> interagir -> servidor valida -> paga (+ gorjeta) -> atualiza interface/bônus.
-- Cada profissão só descreve seus pedidos em JobConfig (makeOrder); aqui existe UM motor genérico,
-- com etapas simples, etapas de "coleta" (escolher os itens certos) e entregas em casas.
-- Quem começa e termina o trabalho é o JobService (vagas). Estado do pedido é só da sessão (não salva).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local JobConfig = require(Shared:WaitForChild("JobConfig"))
local SecurityService = require(script.Parent:WaitForChild("SecurityService"))
local EconomyService = require(script.Parent:WaitForChild("EconomyService"))
local DailyBonusService = require(script.Parent:WaitForChild("DailyBonusService"))

local MissionService = {}

local uiUpdate
local sites -- JobSiteBuilder (pontos de interação)
local active = {} -- active[player] = estado do trabalho atual
local rng = Random.new()
local hooks = {} -- ações especiais das etapas (onBegin/onDone/onCollect), registradas por outros serviços
local cleanups = {} -- funções chamadas quando o trabalho para (ex.: tirar o cliente NPC da loja)

local function now()
	return Workspace:GetServerTimeNow()
end

---------------------------------------------------------------------------
-- Objeto segurado nas mãos (visível para todos). As mãos vão até ele no cliente (BikeAnimator).
---------------------------------------------------------------------------

local CARDBOARD = Color3.fromRGB(200, 160, 110)
local CARRY = {
	Dough = { size = Vector3.new(1.1, 1.1, 1.1), color = Color3.fromRGB(245, 230, 200), shape = Enum.PartType.Ball },
	RawPizza = { size = Vector3.new(0.2, 2.4, 2.4), color = Color3.fromRGB(240, 215, 170), shape = Enum.PartType.Cylinder, flat = true },
	CookedPizza = { size = Vector3.new(0.25, 2.4, 2.4), color = Color3.fromRGB(215, 150, 70), shape = Enum.PartType.Cylinder, flat = true },
	BurntPizza = { size = Vector3.new(0.25, 2.4, 2.4), color = Color3.fromRGB(45, 35, 30), shape = Enum.PartType.Cylinder, flat = true },
	PizzaBox = { size = Vector3.new(2.4, 0.45, 2.4), color = Color3.fromRGB(245, 240, 230), stripe = Color3.fromRGB(200, 50, 45) },
	Crate = { size = Vector3.new(1.8, 1.3, 1.4), color = CARDBOARD, material = Enum.Material.Cardboard },
	EmptyBox = { size = Vector3.new(1.8, 0.3, 1.4), color = CARDBOARD, material = Enum.Material.Cardboard },
	Package = { size = Vector3.new(1.5, 1, 1.3), color = CARDBOARD, material = Enum.Material.Cardboard, stripe = Color3.fromRGB(240, 140, 30) },
	Mop = { size = Vector3.new(0.25, 4.2, 0.25), color = Color3.fromRGB(150, 110, 70), material = Enum.Material.Wood },
}

local function clearCarry(player)
	local character = player.Character
	local old = character and character:FindFirstChild("CarriedItem")
	if old then
		old:Destroy()
	end
end

local function weldedPart(parent, root, props)
	local p = Instance.new("Part")
	p.Name = props.name
	p.Size = props.size
	p.Color = props.color
	p.Material = props.material or Enum.Material.SmoothPlastic
	if props.shape then
		p.Shape = props.shape
	end
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CFrame = props.cframe
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = p
	weld.Parent = p
	p.Parent = parent
	return p
end

-- spec = "Dough" ou { kind = "Crate", color = ..., count = ... }; toppings = lista de cores
local function setCarry(player, spec, toppings)
	clearCarry(player)
	if not spec then
		return
	end
	local kind = type(spec) == "table" and spec.kind or spec
	local info = CARRY[kind]
	local character, _, root = SecurityService.getLivingCharacter(player)
	if not info or not root then
		return
	end
	-- Na frente da barriga, sem encostar no corpo
	local depth = info.flat and info.size.Y or info.size.Z
	local base = root.CFrame * CFrame.new(0, 0, -(0.75 + depth / 2))
	local cf = info.flat and base * CFrame.Angles(0, 0, math.rad(90)) or base
	local item = weldedPart(character, root, {
		name = "CarriedItem",
		size = info.size,
		color = type(spec) == "table" and spec.color or info.color,
		material = info.material,
		shape = info.shape,
		cframe = cf,
	})
	if info.stripe then
		weldedPart(item, root, {
			name = "Stripe",
			size = Vector3.new(info.size.X + 0.02, 0.22, 0.4),
			color = info.stripe,
			cframe = base * CFrame.new(0, info.size.Y / 2 - 0.1, 0),
		})
	end
	-- Pilha de pacotes
	local count = type(spec) == "table" and spec.count or 1
	for i = 2, math.min(count or 1, 3) do
		weldedPart(item, root, {
			name = "Extra",
			size = info.size * 0.9,
			color = info.color,
			material = info.material,
			cframe = base * CFrame.new(0, (i - 1) * info.size.Y, 0) * CFrame.Angles(0, 0.2 * i, 0),
		})
	end
	-- Esfregão: cabeça embaixo do cabo
	if kind == "Mop" then
		weldedPart(item, root, { name = "MopHead", size = Vector3.new(1.6, 0.35, 0.8), color = Color3.fromRGB(90, 160, 220), cframe = base * CFrame.new(0, -2, 0) })
	end
	-- Ingredientes por cima da pizza
	if info.flat and toppings and kind ~= "BurntPizza" then
		for i, color in ipairs(toppings) do
			for k = 1, 3 do
				local a = (k / 3) * math.pi * 2 + i
				local r = 0.35 + (i % 3) * 0.25
				weldedPart(item, root, {
					name = "Topping",
					size = Vector3.new(0.35, 0.12, 0.35),
					color = color,
					cframe = base * CFrame.new(math.cos(a) * r, info.size.X / 2 + 0.06 + i * 0.005, math.sin(a) * r),
				})
			end
		end
	end
end

---------------------------------------------------------------------------
-- Pontos de interação
---------------------------------------------------------------------------

local function pointPosition(name)
	local point = name and sites.points[name]
	return point and point.part.Position
end

local function pickPoint(state, jobId, station)
	-- Mesma estação da etapa anterior (ex.: forno) = mesmo ponto
	local current = state.point and sites.points[state.point]
	if current and current.job == jobId and current.station == station then
		return state.point
	end
	local group = sites.groups[jobId] and sites.groups[jobId][station]
	if not group or #group == 0 then
		return nil
	end
	return group[rng:NextInteger(1, #group)]
end

-- Mancha de sujeira só aparece enquanto precisa ser limpa
local function setRevealed(pointName, visible)
	local point = sites.points[pointName]
	if point then
		point.part.Transparency = visible and 0.15 or 1
	end
end

-- Contexto que as profissões recebem para montar o pedido
local function orderContext(jobId, state)
	return {
		lane = state.lane,
		origin = pointPosition(sites.groups[jobId] and sites.groups[jobId].BalcaoPacotes and sites.groups[jobId].BalcaoPacotes[1]) or Vector3.zero,
		pickHouses = function(n)
			local pool = table.clone(sites.houses)
			local picked = {}
			while #picked < n and #pool > 0 do
				local entry = table.remove(pool, rng:NextInteger(1, #pool))
				table.insert(picked, { point = entry.point, address = entry.address, position = pointPosition(entry.point) })
			end
			return picked
		end,
	}
end

local function runHook(name, player, state, step, extra)
	local fn = name and hooks[name]
	if not fn then
		return nil
	end
	local ok, result = pcall(fn, player, state, step, extra)
	if not ok then
		warn(("[MissionService] Erro na ação '%s': %s"):format(name, tostring(result)))
		return nil
	end
	return result
end

local function runCleanups(player)
	for _, fn in ipairs(cleanups) do
		pcall(fn, player)
	end
end

---------------------------------------------------------------------------
-- Pedido
---------------------------------------------------------------------------

local beginStep

local function collectText(step, state)
	if step.count then
		local got, total = 0, 0
		for station, amount in pairs(step.need) do
			total += amount
			got += math.min(state.got[station] or 0, amount)
		end
		return ("%s %d/%d %s"):format(step.text, got, total, step.count)
	end
	local parts = {}
	for station, amount in pairs(step.need) do
		local got = state.got[station] or 0
		if amount > 1 then
			table.insert(parts, ("%s %d/%d"):format(JobConfig.shortLabel(station), got, amount))
		else
			table.insert(parts, (got >= amount and "✓ " or "") .. JobConfig.shortLabel(station))
		end
	end
	table.sort(parts)
	return step.text .. " " .. table.concat(parts, ", ")
end

local function sendStep(player, state)
	local job = JobConfig.Jobs[state.job]
	local step = state.order.steps[state.step]
	local points = {}
	if step.kind == "collect" then
		for pointName, station in pairs(state.options) do
			-- em coletas com contagem (ex.: produtos do cliente), o que já foi feito some
			local done = step.count and (state.got[station] or 0) >= (step.need[station] or 0)
			if not done then
				table.insert(points, { point = pointName, action = JobConfig.optionLabel(station) })
			end
		end
	else
		table.insert(points, { point = state.point, action = step.action })
	end
	local targetPos = step.point and pointPosition(step.point) or nil
	-- Comanda da pizza: desenho do sabor e ingredientes já colocados
	local card
	if state.order.card then
		-- comanda em lista (mercado): cada linha marca ✓ quando a etapa dela termina
		local c = state.order.card
		card = { kind = "list", title = c.title, footer = c.footer, rows = {} }
		for _, row in ipairs(c.rows) do
			local done, current
			if row.station then
				done = state.step > row.step or (state.step == row.step and (state.got[row.station] or 0) >= 1)
				current = state.step == row.step and not done
			else
				done = state.step > row.to
				current = state.step >= row.from and state.step <= row.to
			end
			table.insert(card.rows, { label = row.label, color = row.color, done = done, now = current })
		end
	elseif state.order.flavor then
		card = { flavor = state.order.flavor, title = state.order.title, items = {} }
		for _, id in ipairs(state.order.ingredients) do
			table.insert(card.items, { id = id, done = state.added[id] == true })
		end
	end
	uiUpdate:FireClient(player, "JobStep", {
		job = state.job,
		title = state.order.title,
		step = state.step,
		total = #state.order.steps,
		text = step.kind == "collect" and collectText(step, state) or step.text,
		hold = step.hold or 0,
		points = points,
		place = job.Place,
		targetPos = targetPos,
		readyAt = state.readyAt,
		waitText = step.waitText,
		card = card,
	})
end

function beginStep(player, state)
	local step = state.order.steps[state.step]
	local previousPos = pointPosition(state.point)
	local t = now()
	state.options = nil
	state.got = {}
	if step.kind == "collect" then
		state.options = {}
		for _, station in ipairs(step.options) do
			local pointName = pickPoint({}, state.job, station)
			if pointName then
				state.options[pointName] = station
			end
		end
	else
		local pointName = step.point or pickPoint(state, state.job, step.station)
		if not pointName then
			warn(("[MissionService] Estação '%s' não existe para %s"):format(tostring(step.station), state.job))
			return
		end
		state.point = pointName
		if step.reveal then
			setRevealed(pointName, true)
			state.revealed = pointName
		end
	end
	state.stepStartedAt = t
	state.readyAt = t + (step.waitBefore or 0)
	local wait = runHook(step.onBegin, player, state, step)
	if type(wait) == "number" then
		state.readyAt = math.max(state.readyAt, t + wait)
	end
	state.arriveAt = t
	if step.travel and previousPos then
		-- Não dá para chegar mais rápido que isso sem teleporte
		state.arriveAt = t + (pointPosition(state.point) - previousPos).Magnitude / JobConfig.TravelSpeed
	end
	sendStep(player, state)
end

local function startOrder(player, state)
	local job = JobConfig.Jobs[state.job]
	state.order = job.makeOrder(rng, orderContext(state.job, state))
	state.step = 1
	state.orderStartedAt = now()
	state.tipLost = false
	state.toppings = {}
	state.added = {}
	beginStep(player, state)
end

local function finishOrder(player, state)
	local job = JobConfig.Jobs[state.job]
	local order = state.order
	-- Encerra o pedido ANTES de pagar: um segundo pedido não encontra etapa válida
	state.step = nil
	state.cycles += 1
	local fast = not state.tipLost and order.tip and (now() - state.orderStartedAt) <= order.parTime
	local tip = fast and order.tip or 0
	local paid = EconomyService.add(player, order.pay + tip, ("Emprego: %s (%s)"):format(job.Name, order.title))
	local bonus = paid and DailyBonusService.tryClaim(player) or 0
	uiUpdate:FireClient(player, "JobPaid", {
		job = state.job,
		title = order.title,
		reward = paid and order.pay or 0,
		tip = paid and tip or 0,
		bonus = bonus,
	})

	task.delay(JobConfig.NextOrderDelay, function()
		if active[player] == state and not state.step then
			startOrder(player, state)
		end
	end)
end

local function advance(player, state, step)
	runHook(step.onDone, player, state, step)
	if step.carry ~= nil then
		setCarry(player, step.carry, state.toppings)
	end
	if state.revealed then
		setRevealed(state.revealed, false)
		state.revealed = nil
	end
	if state.step >= #state.order.steps then
		finishOrder(player, state)
	else
		state.step += 1
		beginStep(player, state)
	end
end

-- A pizza passou do ponto: troca o resto do pedido por "jogar fora" + refazer
local function burn(player, state, step)
	local recovery = step.burn
	local steps = {}
	for _, s in ipairs(recovery.steps) do
		table.insert(steps, s)
	end
	for i = recovery.restartAt, #state.order.steps do
		table.insert(steps, state.order.steps[i])
	end
	local old = state.order
	state.order = { title = old.title, flavor = old.flavor, ingredients = old.ingredients, pay = old.pay, tip = old.tip, parTime = old.parTime, steps = steps }
	state.tipLost = true
	state.toppings = {}
	state.added = {}
	state.step = 1
	setCarry(player, recovery.carry)
	uiUpdate:FireClient(player, "JobHint", { text = recovery.text, bad = true })
	beginStep(player, state)
end

local function onPointTriggered(player, pointName)
	if not SecurityService.checkRate(player, "JobPoint", 0.25) then
		return
	end
	local state = active[player]
	if not state or not state.step then
		return
	end
	local step = state.order.steps[state.step]
	local isOption = step.kind == "collect" and state.options and state.options[pointName]
	if not isOption and state.point ~= pointName then
		return -- não é a etapa atual deste jogador
	end
	if step.kind == "collect" and not isOption then
		return
	end
	local _, _, root = SecurityService.getLivingCharacter(player)
	local point = sites.points[pointName]
	if not root or not point then
		return
	end
	if (root.Position - point.part.Position).Magnitude > JobConfig.InteractDistance then
		return
	end
	local t = now()
	if t < state.readyAt or t < state.arriveAt then
		return -- cedo demais (forno ainda assando, ou chegou rápido demais para ser verdade)
	end
	if t - state.stepStartedAt < math.max(JobConfig.MinStepSeconds, (step.hold or 0) * 0.7) then
		return
	end

	if step.kind == "collect" then
		local station = state.options[pointName]
		local need = step.need[station] or 0
		local got = state.got[station] or 0
		state.stepStartedAt = t
		if got >= need then
			if not step.count then
				uiUpdate:FireClient(player, "JobHint", { text = "Esse não vai neste pedido!", bad = true })
			end
			return
		end
		state.got[station] = got + 1
		runHook(step.onCollect, player, state, step, pointName)
		if step.toppings then
			local ing = JobConfig.ingredientById(station:match("^Ing_(.+)$") or "")
			if ing then
				table.insert(state.toppings, ing.color)
				state.added[ing.id] = true
				setCarry(player, "RawPizza", state.toppings)
			end
		end
		for s, amount in pairs(step.need) do
			if (state.got[s] or 0) < amount then
				sendStep(player, state) -- atualiza a lista do que falta
				return
			end
		end
		advance(player, state, step)
		return
	end

	if step.burnAfter and t > state.readyAt + step.burnAfter then
		burn(player, state, step)
		return
	end
	advance(player, state, step)
end

local function watchCharacter(player)
	player.CharacterAdded:Connect(function()
		-- Morreu ou resetou no meio do pedido: começa um pedido novo (o item segurado sumiu junto)
		local state = active[player]
		if state and state.step then
			task.wait(1)
			if active[player] == state and state.step then
				if state.revealed then
					setRevealed(state.revealed, false)
					state.revealed = nil
				end
				runCleanups(player)
				startOrder(player, state)
			end
		end
	end)
end

---------------------------------------------------------------------------
-- API usada pelo JobService
---------------------------------------------------------------------------

function MissionService.startJob(player, jobId)
	MissionService.stopJob(player)
	local state = { job = jobId, cycles = 0 }
	-- Profissões com "Lanes": cada um fica com um posto só seu (ex.: caixa 1 ou caixa 2)
	if JobConfig.Jobs[jobId].Lanes then
		local used = {}
		for other, s in pairs(active) do
			if other ~= player and s.job == jobId and s.lane then
				used[s.lane] = true
			end
		end
		state.lane = 1
		while used[state.lane] do
			state.lane += 1
		end
	end
	active[player] = state
	startOrder(player, state)
end

-- Outros serviços registram ações especiais das etapas (ex.: MarketService cria os clientes NPC)
function MissionService.registerHook(name, fn)
	hooks[name] = fn
end

-- Quantos jogadores estão trabalhando nessa profissão agora
function MissionService.workers(jobId)
	local n = 0
	for _, s in pairs(active) do
		if s.job == jobId then
			n += 1
		end
	end
	return n
end

function MissionService.onStop(fn)
	table.insert(cleanups, fn)
end

function MissionService.stopJob(player)
	local state = active[player]
	if state then
		active[player] = nil
		if state.revealed then
			setRevealed(state.revealed, false)
		end
		clearCarry(player)
		runCleanups(player)
	end
end

function MissionService.init(remotes, jobSites)
	uiUpdate = remotes[GameConfig.Remotes.UIUpdate]
	sites = jobSites
	for name, point in pairs(sites.points) do
		point.prompt.Triggered:Connect(function(player)
			onPointTriggered(player, name)
		end)
	end
	Players.PlayerAdded:Connect(watchCharacter)
	for _, player in ipairs(Players:GetPlayers()) do
		watchCharacter(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		MissionService.stopJob(player)
	end)
end

return MissionService
