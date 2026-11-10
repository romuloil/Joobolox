-- JobConfig (ModuleScript)
-- Caminho: ReplicatedStorage > Shared > JobConfig
-- Profissões (documento mestre, seção 7): vagas, pagamento e como cada pedido é montado.
-- Servidor e cliente leem daqui. Pagamentos são PROVISÓRIOS (seção 21).
--
-- Cada profissão tem makeOrder(rng, ctx), que sorteia um pedido e devolve:
--   { title, pay, tip, parTime, steps = { etapa, etapa, ... } }
-- Tipos de etapa:
--   * estação:  { station = "Forno", text, action, hold, carry, waitBefore, burnAfter, burn, reveal }
--   * coleta:   { kind = "collect", options = {estações}, need = {estação = quantidade}, text, hold, carry }
--               várias estações ficam ativas e o jogador precisa escolher as CERTAS
--               (ex.: ingredientes do sabor pedido). Escolha errada não conta.
--   * casa:     { point = ponto de entrega (dado pelo servidor), travel = true, ... }
-- Extras (qualquer etapa): onBegin / onDone / onCollect = nome de uma ação especial do servidor
--   require = ação que confere se pode concluir (devolve um aviso quando não pode; ex.: estar no táxi),
--   reach = distância máxima (studs) dessa etapa (o padrão é InteractDistance),
--   (ex.: "customerCome" faz um cliente NPC entrar na loja), waitText = texto da espera,
--   count = mostra o progresso da coleta como "3/5 produtos".
-- carry = o que o jogador passa a segurar depois da etapa ("Dough", {kind="Crate", color=...}) ou false para largar.
-- tip = gorjeta paga se o pedido terminar em até parTime segundos (e a pizza não queimar).

local JobConfig = {}

JobConfig.Order = { "Pizzaiolo", "Atendente", "Entregador", "Cuidador", "Taxista", "Motorista", "Bombeiro", "Paramedico", "Policial" }

---------------------------------------------------------------------------
-- Pizzaria
---------------------------------------------------------------------------

-- Poucos ingredientes: molho e queijo vão em todas; cada sabor tem só 1 ou 2 coberturas.
-- base = true: fica no grupo "BASE" da bancada (os outros ficam em "COBERTURAS").
JobConfig.Ingredients = {
	{ id = "Molho", label = "Molho", color = Color3.fromRGB(200, 40, 35), base = true },
	{ id = "Queijo", label = "Queijo", color = Color3.fromRGB(250, 215, 100), base = true },
	{ id = "Tomate", label = "Tomate", color = Color3.fromRGB(230, 60, 50) },
	{ id = "Manjericao", label = "Manjericão", color = Color3.fromRGB(60, 150, 60) },
	{ id = "Calabresa", label = "Calabresa", color = Color3.fromRGB(150, 50, 45) },
	{ id = "Presunto", label = "Presunto", color = Color3.fromRGB(240, 160, 160) },
	{ id = "Ovo", label = "Ovo", color = Color3.fromRGB(255, 250, 235) },
}

JobConfig.Flavors = {
	{ id = "Marguerita", label = "Marguerita", ingredients = { "Molho", "Queijo", "Tomate", "Manjericao" }, pay = 180 },
	{ id = "Calabresa", label = "Calabresa", ingredients = { "Molho", "Queijo", "Calabresa" }, pay = 180 },
	{ id = "Portuguesa", label = "Portuguesa", ingredients = { "Molho", "Queijo", "Presunto", "Ovo" }, pay = 200 },
}

local function ingredientById(id)
	for _, ing in ipairs(JobConfig.Ingredients) do
		if ing.id == id then
			return ing
		end
	end
end

local function pizzaOrder(rng)
	local flavor = JobConfig.Flavors[rng:NextInteger(1, #JobConfig.Flavors)]
	local options, need = {}, {}
	for _, ing in ipairs(JobConfig.Ingredients) do
		table.insert(options, "Ing_" .. ing.id)
	end
	for _, id in ipairs(flavor.ingredients) do
		need["Ing_" .. id] = 1
	end
	local name = "Pizza " .. flavor.label
	return {
		title = name,
		flavor = flavor.id, -- a tela mostra a comanda com o desenho e os ingredientes
		ingredients = flavor.ingredients,
		pay = flavor.pay, -- Marco 10.15: economia nova (Revisão 2)
		tip = 30,
		parTime = 45,
		steps = {
			{ station = "BalcaoPizza", text = "Novo pedido: " .. name .. "! Pegue a comanda no balcão", action = "Pegar comanda", hold = 0.5, onDone = "pizzaCustomerCome" },
			{ station = "Massa", text = "Pegue uma massa", action = "Pegar massa", hold = 0.6, carry = "Dough" },
			{ station = "MesaMontagem", text = "Abra a massa na mesa", action = "Abrir massa", hold = 1.5, carry = "RawPizza" },
			{ kind = "collect", options = options, need = need, text = "Monte a " .. flavor.label .. " (veja a comanda):", hold = 0.4, toppings = true },
			{ station = "Forno", text = "Coloque a pizza no forno", action = "Colocar no forno", hold = 0.8, carry = false },
			{
				station = "Forno",
				text = "Tire a pizza do forno antes que queime!",
				action = "Tirar do forno",
				hold = 0.6,
				waitBefore = 8, -- assando
				burnAfter = 15, -- segundos depois de pronta para queimar
				carry = "CookedPizza",
				burn = {
					carry = "BurntPizza",
					text = "A pizza queimou! Jogue no lixo e faça outra",
					steps = { { station = "Lixo", text = "Jogue a pizza queimada no lixo", action = "Jogar fora", hold = 0.5, carry = false } },
					restartAt = 2, -- volta para "pegar massa", com o mesmo sabor
				},
			},
			{ station = "Embalagem", text = "Coloque a pizza na caixa", action = "Embalar pizza", hold = 1, carry = "PizzaBox" },
			{ station = "BalcaoPizza", text = "Entregue a " .. name .. " no balcão", action = "Entregar pizza", hold = 0.6, carry = false, onDone = "pizzaCustomerReceive" },
		},
	}
end

---------------------------------------------------------------------------
-- Mercearia
---------------------------------------------------------------------------

JobConfig.Categories = {
	{ id = "Frutas", label = "Frutas", color = Color3.fromRGB(230, 70, 60), products = { "Maçã", "Banana", "Uva", "Laranja" } },
	{ id = "Bebidas", label = "Bebidas", color = Color3.fromRGB(70, 140, 220), products = { "Suco", "Leite", "Água", "Refri" } },
	{ id = "Limpeza", label = "Limpeza", color = Color3.fromRGB(110, 200, 210), products = { "Sabão", "Detergente", "Esponja" } },
	{ id = "Padaria", label = "Padaria", color = Color3.fromRGB(220, 170, 90), products = { "Pão", "Bolo", "Biscoito" } },
}

-- ctx.lane = número do caixa deste atendente (1 ou 2: cada atendente tem o seu)
local function marketOrder(rng, ctx)
	local lane = ctx.lane or 1
	local roll = rng:NextNumber()
	if roll < 0.45 then
		-- Atender um cliente (NPC) que entra na loja e vem até o seu caixa
		local items = rng:NextInteger(3, 6)
		local total = 0
		local belt, need, products, rows = {}, {}, {}, {}
		for k = 1, items do
			local station = ("Esteira%d_%d"):format(lane, k)
			local cat = JobConfig.Categories[rng:NextInteger(1, #JobConfig.Categories)]
			local name = cat.products[rng:NextInteger(1, #cat.products)]
			local price = rng:NextInteger(3, 12)
			total += price
			table.insert(belt, station)
			need[station] = 1
			products[station] = { color = cat.color, label = name }
			-- cada produto vira uma linha da comanda (✓ quando passa no leitor)
			table.insert(rows, { label = ("%s  $%d"):format(name, price), color = cat.color, station = station, step = 2 })
		end
		table.insert(rows, { label = "Embalar na sacola", color = Color3.fromRGB(240, 240, 235), from = 3, to = 3 })
		table.insert(rows, { label = "Cobrar o cliente", color = Color3.fromRGB(120, 220, 140), from = 4, to = 4 })
		return {
			title = "Cliente no caixa " .. lane,
			card = { title = "Compras do cliente", footer = ("Total: $%d"):format(total), rows = rows },
			pay = 40, -- Marco 10.15: economia nova (Revisão 2)
			tip = 15,
			parTime = 15,
			steps = {
				{ station = "Checkout" .. lane, text = ("Vá para o caixa %d e chame o próximo cliente"):format(lane), action = "Chamar cliente", hold = 0.4, onDone = "customerCome", items = items },
				{ kind = "collect", options = belt, need = need, count = "produtos", products = products, text = "Passe as compras do cliente no leitor:", hold = 0.3, onBegin = "customerArrive", onCollect = "scanItem", waitText = "o cliente chega em" },
				{ station = "Bag" .. lane, text = "Coloque as compras na sacola", action = "Embalar compras", hold = 1.2, onDone = "customerBag" },
				{ station = "Checkout" .. lane, text = ("Cobre %s %d do cliente"):format("$", total), action = "Receber pagamento", hold = 0.8, onDone = "customerLeave" },
			},
		}
	elseif roll < 0.8 then
		-- Repor 2 ou 3 prateleiras: caixa certa do estoque -> prateleira -> caixa vazia na reciclagem
		local pool = table.clone(JobConfig.Categories)
		local count = rng:NextInteger(2, 3)
		local cats = {}
		for _ = 1, count do
			table.insert(cats, table.remove(pool, rng:NextInteger(1, #pool)))
		end
		local options = {}
		for _, c in ipairs(JobConfig.Categories) do
			table.insert(options, "Caixa_" .. c.id)
		end
		local names, ids = {}, {}
		for _, cat in ipairs(cats) do
			table.insert(names, cat.label)
			table.insert(ids, cat.id)
		end
		local steps, rows = {}, {}
		for i, cat in ipairs(cats) do
			local first = #steps + 1
			table.insert(rows, { label = "Repor " .. cat.label, color = cat.color, from = first, to = first + 2 })
			local tag = ("(%d de %d) "):format(i, count)
			table.insert(steps, {
				kind = "collect",
				options = options,
				need = { ["Caixa_" .. cat.id] = 1 },
				text = tag .. "Pegue no estoque a caixa de " .. cat.label .. ":",
				hold = 0.6,
				carry = { kind = "Crate", color = cat.color },
				onBegin = i == 1 and "shelvesEmpty" or nil,
				cats = i == 1 and ids or nil,
			})
			table.insert(steps, { station = "Prateleira_" .. cat.id, text = tag .. "Reponha a prateleira de " .. cat.label, action = "Repor " .. cat.label, hold = 2.5, carry = "EmptyBox", onDone = "shelfFill", cat = cat.id })
			table.insert(steps, { station = "Reciclagem", text = tag .. "Jogue a caixa vazia na reciclagem", action = "Reciclar", hold = 0.5, carry = false })
		end
		return {
			title = "Repor " .. table.concat(names, ", "),
			card = { title = "Reposição", footer = "Caixa certa, prateleira, reciclagem", rows = rows },
			pay = 40 * count, -- Marco 10.15: economia nova (Revisão 2)
			tip = 15,
			parTime = 35,
			steps = steps,
		}
	end
	-- Limpar uma sujeira no chão
	local spill = rng:NextInteger(1, 3)
	return {
		title = "Limpeza",
		card = {
			title = "Limpeza",
			footer = "Procure a mancha laranja",
			rows = {
				{ label = "Pegar o esfregão", color = Color3.fromRGB(240, 200, 40), from = 1, to = 1 },
				{ label = "Limpar a sujeira", color = Color3.fromRGB(240, 150, 40), from = 2, to = 2 },
				{ label = "Guardar o esfregão", color = Color3.fromRGB(90, 160, 220), from = 3, to = 3 },
			},
		},
		pay = 55, -- Marco 10.15: economia nova (Revisão 2)
		tip = 15,
		parTime = 18,
		steps = {
			{ station = "Esfregao", text = "Derrubaram suco no chão! Pegue o esfregão", action = "Pegar esfregão", hold = 0.5, carry = "Mop" },
			{ station = "Sujeira_" .. spill, text = "Limpe a sujeira (procure a mancha laranja no chão)", action = "Limpar", hold = 3, reveal = true },
			{ station = "Esfregao", text = "Guarde o esfregão", action = "Guardar esfregão", hold = 0.5, carry = false },
		},
	}
end

---------------------------------------------------------------------------
-- Entregas
---------------------------------------------------------------------------

JobConfig.FarHouse = 2000 -- Marco 10.15: entrega numa casa mais longe que isso paga +25%

-- ctx.pickHouses(n) devolve n casas diferentes { point, address, position }; ctx.origin = posição do balcão
local function deliveryOrder(rng, ctx)
	local count = rng:NextInteger(1, 3)
	local houses = ctx.pickHouses(count)
	count = #houses
	local steps = {
		{ station = "BalcaoPacotes", text = ("Retire %d pacote%s no balcão"):format(count, count > 1 and "s" or ""), action = "Retirar pacotes", hold = 0.8, carry = { kind = "Package", count = count } },
	}
	local route, last = 0, ctx.origin
	local far = false
	for i, house in ipairs(houses) do
		route += (house.position - last).Magnitude
		if (house.position - ctx.origin).Magnitude > (JobConfig.FarHouse or 2000) then
			far = true
		end
		last = house.position
		local left = count - i
		table.insert(steps, {
			point = house.point,
			text = ("Entregue o pacote %d de %d em %s (veja no Mapa)"):format(i, count, house.address),
			action = "Entregar pacote",
			hold = 0.8,
			travel = true,
			onDone = "deliveryThanks", -- o morador abre a porta e recebe o pacote
			carry = left > 0 and { kind = "Package", count = left } or false,
		})
	end
	return {
		title = count > 1 and ("Rota de %d entregas"):format(count) or "Entrega",
		-- Marco 10.15: $70 por pacote + $0,17 por stud; casa longe (mais de FarHouse studs) +25%
		pay = math.floor((70 * count + route * 0.17) * (far and 1.25 or 1)),
		tip = 0,
		parTime = route / 22 + 15,
		steps = steps,
	}
end

---------------------------------------------------------------------------
-- Taxista (Marco 9): buscar um passageiro NPC na calçada e levar até o destino, de Táxi LXR.
-- ctx.taxiSpots = pontos de táxi na calçada { point, label, position } (JobSiteBuilder).
-- O passageiro, o embarque e o desembarque são feitos pelo TaxiService (ações abaixo).
---------------------------------------------------------------------------

JobConfig.Taxi = {
	Reach = 24, -- distância do ponto para chamar/deixar o passageiro (o táxi para na rua)
	MinTrip = 250, -- corrida mais curta e mais longa (studs)
	MaxTrip = 6000, -- Marco 10.16: corridas no mapa todo (Horizonte, Jardim Progresso, favelas)
	BasePay = 100, -- Marco 10.15: bandeirada + valor por distância (Revisão 2)
	PayPerStud = 0.20,
	LongTrip = 2500, -- corrida longa (mais que isso) paga +30%
	LongBonus = 0.30,
	Tip = 0,
}

local function taxiOrder(rng, ctx)
	local T = JobConfig.Taxi
	local spots = ctx.taxiSpots or {}
	local pickup = spots[rng:NextInteger(1, math.max(#spots, 1))]
	if not pickup then
		error("Sem pontos de táxi no mapa")
	end
	local dest, best
	for _ = 1, 40 do
		local candidate = spots[rng:NextInteger(1, #spots)]
		local d = (candidate.position - pickup.position).Magnitude
		if d >= T.MinTrip and d <= T.MaxTrip then
			dest = candidate
			break
		end
		if candidate ~= pickup and (not best or d > (best.position - pickup.position).Magnitude) then
			best = candidate
		end
	end
	dest = dest or best or pickup
	local trip = (dest.position - pickup.position).Magnitude
	return {
		title = "Corrida",
		pay = math.floor((T.BasePay + trip * T.PayPerStud) * (trip > T.LongTrip and (1 + T.LongBonus) or 1)),
		tip = T.Tip,
		parTime = trip / 30 + 60, -- inclui ir buscar o passageiro
		destLabel = dest.label,
		steps = {
			{
				point = pickup.point,
				text = ("Um passageiro chamou um táxi em %s. Vá buscar (veja no Mapa) e pare do lado dele"):format(pickup.label),
				action = "Chamar passageiro",
				hold = 0,
				travel = true,
				reach = T.Reach,
				require = "taxiCheck",
				onBegin = "taxiCall",
				onDone = "taxiBoard",
			},
			{
				point = dest.point,
				text = ("Leve o passageiro até %s (veja no Mapa)"):format(dest.label),
				action = "Deixar passageiro",
				hold = 0,
				travel = true,
				reach = T.Reach,
				require = "taxiCheck",
				onDone = "taxiDropoff",
			},
		},
	}
end

---------------------------------------------------------------------------
-- Motorista de ônibus (Marco 9): linha circular no anel do meio, com as 8 paradas do mapa
-- (ctx.busStops, em ordem). Cada pedido é uma volta: parar o ônibus na faixa amarela de cada
-- parada, na ordem. Os passageiros NPC (já sentados, descendo e subindo) ficam no BusService.
---------------------------------------------------------------------------

JobConfig.Bus = {
	Reach = 26, -- distância da parada para abrir as portas (o ônibus para na faixa amarela)
	-- Marco 9.10: 3 linhas fixas (paradas 1-8 = anel do meio, 9-16 = anel externo). Cada volta é
	-- uma linha sorteada. Paga por parada + pelo tamanho do caminho (PROVISÓRIO; o Luís pediu
	-- que o ônibus ganhe mais que o táxi, porque trabalha mais).
	Lines = {
		{ Name = "Linha Circular", Stops = { 1, 2, 3, 4, 5, 6, 7, 8 } },
		{ Name = "Linha Contorno", Stops = { 9, 10, 11, 12, 13, 14, 15, 16 } },
		{ Name = "Linha Estrela", Stops = { 1, 10, 3, 12, 5, 14, 7, 16 } }, -- zigue-zague: centro e bairro
	},
	PayPerStop = 50, -- Marco 10.15: economia nova (Revisão 2)
	PayPerStud = 0.20,
	Tip = 170, -- gorjeta se a volta terminar no tempo
}

local function busOrder(rng, ctx)
	local B = JobConfig.Bus
	local byOrder = {}
	for _, stop in ipairs(ctx.busStops or {}) do
		byOrder[stop.order] = stop
	end
	-- só as linhas com todas as paradas no mapa
	local lines = {}
	for _, line in ipairs(B.Lines) do
		local ok = true
		for _, n in ipairs(line.Stops) do
			ok = ok and byOrder[n] ~= nil
		end
		if ok then
			table.insert(lines, line)
		end
	end
	if #lines == 0 then
		error("Sem paradas de ônibus no mapa")
	end
	local line = lines[rng:NextInteger(1, #lines)]
	local stops = {}
	for _, n in ipairs(line.Stops) do
		table.insert(stops, byOrder[n])
	end
	local steps, route = {}, 0
	for i, stop in ipairs(stops) do
		local nextStop = stops[i % #stops + 1]
		route += (nextStop.position - stop.position).Magnitude
		table.insert(steps, {
			point = stop.point,
			text = (i == 1 and ("%s. Pegue o ônibus na Um Tijo (🚌 no Mapa). "):format(line.Name) or "")
				.. ("%s, parada %d de %d (%s): pare na faixa amarela (veja no Mapa)"):format(line.Name, i, #stops, stop.label),
			action = "Abrir as portas",
			hold = 0,
			travel = true,
			reach = B.Reach,
			require = "busCheck",
			onBegin = "busArrive",
			onDone = "busStop",
		})
	end
	return {
		title = line.Name,
		pay = B.PayPerStop * #stops + math.floor(route * B.PayPerStud),
		tip = B.Tip,
		parTime = route / 22 + #stops * 10 + 60, -- inclui sair da garagem
		steps = steps,
	}
end

---------------------------------------------------------------------------
-- Bombeiro (Marco 9.9): alarme de incêndio numa casa da cidade. Vá com o caminhão até a rua
-- da casa (sirene!), desça e jogue água no fogo (segure E). O fogo, a fumaça, o morador pedindo
-- socorro e a água ficam no FireService. Valores PROVISÓRIOS.
---------------------------------------------------------------------------

JobConfig.Fire = {
	Reach = 34, -- o caminhão é grande: para na rua, longe do ponto
	HoseReach = 26, -- a mangueira alcança de longe
	Pay = 1000, -- Marco 10.15: economia nova (Revisão 2) + PayPerStud do quartel até a casa
	PayPerStud = 0.17,
	Tip = 250,
	Hose = 4, -- (antigo) segundos segurando E para apagar
	-- Marco 10.16: incêndio em EQUIPE. Todos os bombeiros em serviço recebem o MESMO incêndio, e só
	-- eles veem o fogo. O fogo tem "força" (0 a 100): começa em StartHp e cresce GrowPerSec até MaxHp
	-- enquanto ninguém joga água. Cada jato (segurar E por HoseHold s, perto do caminhão) tira
	-- HoseDamage. Se não apagar até o tempo acabar (BurnBase + distância do quartel / BurnPerStud
	-- s), a casa QUEIMA e ninguém ganha. Só ganha quem jogou água pelo menos uma vez.
	StartHp = 45,
	MaxHp = 100,
	GrowPerSec = 0.5,
	HoseHold = 1.5,
	HoseDamage = 9,
	TruckRange = 80, -- a mangueira precisa de um caminhão de bombeiros perto
	BurnBase = 120,
	BurnPerStud = 1 / 25, -- +1 s a cada 25 studs do quartel até a casa
}

local function fireOrder(rng, ctx)
	local F = JobConfig.Fire
	local fires = ctx.fires or {}
	if #fires == 0 then
		error("Sem casas para o Bombeiro")
	end
	-- Marco 10.16: incêndio da equipe (o mesmo para todos os bombeiros em serviço)
	local fire = (ctx.pickFire and ctx.pickFire()) or fires[rng:NextInteger(1, #fires)]
	return {
		title = "Incêndio!",
		pay = F.Pay + math.floor((ctx.fireOrigin and fire.model and (fire.model:GetPivot().Position - ctx.fireOrigin).Magnitude or 0) * F.PayPerStud),
		tip = F.Tip,
		parTime = 150,
		fire = { house = fire.house, address = fire.address },
		steps = {
			{
				point = fire.street,
				text = ("🔥 Incêndio na %s! Vá com o caminhão (veja no Mapa) e pare na frente da casa"):format(fire.address),
				action = "Estacionar o caminhão",
				hold = 0,
				travel = true,
				reach = F.Reach,
				require = "fireTruckCheck",
				onBegin = "fireStart",
			},
			{
				point = fire.house,
				text = "Desça e jogue água no fogo (segure E várias vezes, perto do caminhão). Com mais bombeiros apaga mais rápido!",
				action = "Jogar água",
				hold = F.HoseHold,
				reach = F.HoseReach,
				require = "fireHose",
				onDone = "fireOut",
			},
		},
	}
end

---------------------------------------------------------------------------
-- Cuidador de animais (Marco 9): um cliente traz o bichinho (cachorro de várias raças ou gato)
-- ao balcão do Duto Pet Shop. Cada cuidador tem as suas estações (lane 1 ou 2): balcão,
-- banheira, mesa de tosa e comedouro; o saco de ração é de todos. O cliente, o pet andando
-- de uma estação para outra e os efeitos (bolhas, brilho, coração) ficam no PetCareService.
---------------------------------------------------------------------------

local function careOrder(rng, ctx)
	local L = ctx.lane or 1
	local breeds = ctx.petBreeds or {}
	local names = ctx.petNames or { "Thor" }
	local breed = math.max(1, rng:NextInteger(1, math.max(#breeds, 1)))
	local name = names[rng:NextInteger(1, #names)]
	local kind = breeds[breed] and breeds[breed].name or "Cachorro"
	local receive = { station = "Balcao" .. L, text = ("Um cliente trouxe %s (%s). Receba no balcão"):format(name, kind), action = "Receber pet", hold = 1, onBegin = "careArrive", onDone = "careTake" }
	local bath = {
		{ station = "Banheira" .. L, text = ("Leve %s para a banheira e ensaboe"):format(name), action = "Ensaboar", hold = 3, onBegin = "careMove", onDone = "careFx", fx = "Bolhas" },
		{ station = "Banheira" .. L, text = "Agora enxágue bem", action = "Enxaguar", hold = 2, onDone = "careFx", fx = "Agua" },
		{ station = "Mesa" .. L, text = "Na mesa de tosa: seque com o secador", action = "Secar", hold = 2.5, onBegin = "careMove", onDone = "careFx", fx = "Vento" },
		{ station = "Mesa" .. L, text = ("Escove o pelo de %s"):format(name), action = "Escovar", hold = 2.5, onDone = "careFx", fx = "Brilho" },
	}
	local food = {
		{ station = "Saco", text = "Pegue a ração no saco laranja (perto do comedouro)", action = "Pegar ração", hold = 1, carry = { kind = "Crate", color = Color3.fromRGB(150, 95, 50) } },
		{ station = "Comedouro" .. L, text = ("Ponha a ração na tigela de %s"):format(name), action = "Servir ração", hold = 1, carry = false, onBegin = "careMove" },
		{ station = "Comedouro" .. L, text = ("Espere %s comer"):format(name), action = "Recolher tigela", hold = 0.5, waitBefore = 6, waitText = "comendo, pronto em", onDone = "careFx", fx = "Coracao" },
	}
	local back = { station = "Balcao" .. L, text = ("Devolva %s ao dono no balcão"):format(name), action = "Devolver pet", hold = 1, onBegin = "careMove", onDone = "careReturn" }
	local kindRoll = rng:NextNumber()
	local title, middle, pay, tip, parTime
	if kindRoll < 0.4 then
		title, middle, pay, tip, parTime = "Banho e tosa", bath, 520, 90, 75
	elseif kindRoll < 0.75 then
		title, middle, pay, tip, parTime = "Hora da comida", food, 380, 90, 55
	else
		middle = table.clone(bath)
		for _, step in ipairs(food) do
			table.insert(middle, step)
		end
		title, pay, tip, parTime = "Dia de spa", 800, 90, 120
	end
	local steps = { receive }
	for _, step in ipairs(middle) do
		table.insert(steps, step)
	end
	table.insert(steps, back)
	return {
		title = ("%s: %s"):format(title, name),
		pay = pay,
		tip = tip,
		parTime = parTime,
		pet = { breed = breed, name = name },
		steps = steps,
	}
end

---------------------------------------------------------------------------
-- Presidiário (Marco 8.1): tarefas pela prisão. Não pagam dinheiro: a cada algumas
-- tarefas a pena diminui (PrisonService). As estações ficam na Penitenciária.
---------------------------------------------------------------------------

local PRISON_TASKS = {
	function(rng)
		local spot = rng:NextInteger(1, 3)
		return "Limpar o refeitório", {
			{ station = "Limpeza_Armario", text = "Pegue o esfregão no armário do refeitório", action = "Pegar esfregão", hold = 0.5, carry = "Mop" },
			{ station = "Limpeza_Sujeira_" .. spot, text = "Limpe a sujeira no chão do refeitório (mancha laranja)", action = "Limpar", hold = 3, reveal = true },
			{ station = "Limpeza_Armario", text = "Guarde o esfregão no armário", action = "Guardar", hold = 0.5, carry = false },
		}
	end,
	function()
		return "Servir o almoço", {
			{ station = "Cozinha_Panela", text = "Pegue a comida nas panelas da cozinha do refeitório", action = "Pegar comida", hold = 1.5, carry = "Crate" },
			{ station = "Cozinha_Balcao", text = "Leve até o balcão de servir", action = "Servir", hold = 1, carry = false },
		}
	end,
	function()
		return "Lavar a roupa", {
			{ station = "Lav_Cesto", text = "Pegue o cesto de roupa suja na lavanderia", action = "Pegar cesto", hold = 0.5, carry = "Crate" },
			{ station = "Lav_Maquina", text = "Coloque a roupa na máquina de lavar", action = "Colocar roupa", hold = 1, carry = false },
			{ station = "Lav_Maquina", text = "Espere a máquina", action = "Tirar roupa", hold = 0.5, waitBefore = 6, waitText = "lavando, pronto em", carry = "Crate" },
			{ station = "Lav_Varal", text = "Estenda a roupa no varal", action = "Estender", hold = 2, carry = false },
		}
	end,
	function()
		return "Cuidar da horta", {
			{ station = "Horta_Regador", text = "Pegue o regador no pátio da horta", action = "Pegar regador", hold = 0.5 },
			{ station = "Horta_Canteiro", text = "Regue um canteiro da horta", action = "Regar", hold = 2.5 },
			{ station = "Horta_Cesto", text = "Leve o que colheu para o cesto", action = "Guardar", hold = 0.5 },
		}
	end,
	function()
		return "Arrumar a biblioteca", {
			{ station = "Bib_Carrinho", text = "Pegue os livros no carrinho da biblioteca", action = "Pegar livros", hold = 0.5, carry = "Crate" },
			{ station = "Bib_Estante", text = "Guarde os livros na estante", action = "Guardar livros", hold = 1.5, carry = false },
		}
	end,
	function()
		return "Trabalho na oficina", {
			{ station = "Of_Madeira", text = "Pegue madeira na oficina (Escola e Oficinas)", action = "Pegar madeira", hold = 0.5, carry = "Crate" },
			{ station = "Of_Bancada", text = "Monte a peça na bancada", action = "Serrar e lixar", hold = 3, carry = false },
		}
	end,
}

local function prisonOrder(rng)
	local title, steps = PRISON_TASKS[rng:NextInteger(1, #PRISON_TASKS)](rng)
	return { title = title, pay = 0, tip = 0, parTime = 0, steps = steps }
end

---------------------------------------------------------------------------
-- Profissões
---------------------------------------------------------------------------

JobConfig.Jobs = {
	Pizzaiolo = {
		Name = "Pizzaiolo",
		Icon = "🍕", -- Marco 9.14: ícone no quadro de empregos
		Place = "La Paulistana",
		Slots = 2,
		PayText = "Salário + $180 a $200 por pizza",
		Color = Color3.fromRGB(200, 50, 45),
		Description = "Faça Marguerita, Calabresa ou Portuguesa com os ingredientes certos. Não deixe queimar!",
		makeOrder = pizzaOrder,
	},
	Atendente = {
		Name = "Atendente",
		Icon = "🛒", -- Marco 9.14: ícone no quadro de empregos
		Place = "Minas Market",
		Slots = 2,
		Lanes = true, -- cada atendente fica com um caixa (1 ou 2)
		PayText = "Salário + $40 a $120 por tarefa",
		Color = Color3.fromRGB(40, 140, 70),
		Description = "Atenda clientes no caixa, reponha 2 ou 3 prateleiras com as caixas certas e limpe a loja.",
		makeOrder = marketOrder,
	},
	Entregador = {
		Name = "Entregador Sherlex",
		Icon = "📦", -- Marco 9.14: ícone no quadro de empregos
		Place = "Sherlex",
		Slots = 2,
		PayText = "Salário + $70 por pacote, mais longe paga mais",
		Color = Color3.fromRGB(240, 140, 30),
		Description = "Rotas de 1 a 3 pacotes para endereços da cidade (rua e número). Vá de bike ou de carro!",
		makeOrder = deliveryOrder,
	},
	-- Marco 9: cuidador de animais (2 vagas, decidido com o Luís)
	Cuidador = {
		Name = "Cuidador de animais",
		Icon = "🐶", -- Marco 9.14: ícone no quadro de empregos
		Place = "Duto Pet Shop",
		Slots = 2,
		Lanes = true, -- cada cuidador fica com um balcão, uma banheira, uma mesa e uma tigela
		PayText = "Salário + $380 a $800 por pet",
		Color = Color3.fromRGB(130, 80, 200),
		Description = "Banho, tosa e comida para cachorros e gatos dos clientes do Duto Pet Shop.",
		makeOrder = careOrder,
	},
	-- Marco 9: taxista (5 vagas, pedido do Luís). Só trabalha com o Táxi LXR (garagem da LXR Táxis).
	Taxista = {
		Name = "Taxista",
		Icon = "🚕", -- Marco 9.14: ícone no quadro de empregos
		Place = "LXR Táxis",
		Slots = 5,
		PayText = "Salário + $100 e mais por distância",
		Color = Color3.fromRGB(230, 180, 10),
		Description = "Pegue o Táxi LXR na LXR Táxis, busque passageiros pela cidade e leve até o destino.",
		JoinHint = "Taxista: pegue o Táxi LXR na garagem da LXR Táxis (🚕 no Mapa).",
		makeOrder = taxiOrder,
	},
	-- Marco 9: motorista de ônibus. Só trabalha com o Ônibus Um Tijo (garagem da Um Tijo).
	-- Vagas PROVISÓRIAS (o documento mestre fala em 1).
	Motorista = {
		Name = "Motorista de ônibus",
		Icon = "🚌", -- Marco 9.14: ícone no quadro de empregos
		Place = "Um Tijo",
		Slots = 2,
		PayText = "Salário + $1.000 a $3.500 por volta",
		Color = Color3.fromRGB(30, 130, 80),
		Description = "Pegue o ônibus na Um Tijo e faça uma das 3 linhas (Circular, Contorno ou Estrela), parando nas paradas da cidade.",
		JoinHint = "Motorista: pegue o ônibus na garagem da Um Tijo (🚌 no Mapa).",
		makeOrder = busOrder,
	},
	-- Marco 9.9: bombeiro. Vagas e pagamento PROVISÓRIOS.
	Bombeiro = {
		Name = "Bombeiro",
		Icon = "🚒", -- Marco 9.14: ícone no quadro de empregos
		Place = "Corpo de Bombeiros",
		Slots = 4,
		PayText = "Salário + $1.000 e mais por incêndio",
		Color = Color3.fromRGB(200, 22, 30),
		Description = "Pegue o caminhão no quartel dos bombeiros e apague os incêndios nas casas da cidade.",
		JoinHint = "Bombeiro: pegue o caminhão no quartel (🚒 no Mapa).",
		makeOrder = fireOrder,
	},
	-- Marco 10.15: paramédico. Atende quem está caído no chão (aparece no mapa) e reanima (E).
	Paramedico = {
		Name = "Paramédico",
		Icon = "🚑",
		Place = "Hospital Progresso",
		Slots = 4, -- PROVISÓRIO
		PayText = "Salário + $1.500 por pessoa reanimada",
		Color = Color3.fromRGB(220, 60, 70),
		Description = "Quem cai no chão aparece no seu mapa (cruz vermelha). Chegue rápido e segure E para reanimar.",
		JoinHint = "Paramédico: quem cair aparece no seu mapa com uma cruz vermelha. Vá até lá e segure E.",
		NoTasks = true,
	},
	-- Marco 8.1: policial. Por enquanto: cartão de acesso da PM na Penitenciária e viaturas
	-- na garagem da polícia. Tarefas e salário: em breve. Vagas PROVISÓRIAS.
	Policial = {
		Name = "Policial",
		Icon = "👮", -- Marco 9.14: ícone no quadro de empregos
		Place = "Penitenciária",
		Slots = 8, -- Marco 10.1: o Luís achou 4 pouco (servidor de 20 a 30). PROVISÓRIO
		PayText = "Salário + chamados, prisões e patrulha",
		Color = Color3.fromRGB(35, 60, 110),
		Description = "Tem o cartão de acesso da PM na Penitenciária e tira viaturas na garagem da polícia.",
		NoTasks = true,
		Military = true, -- Marco 8.2: quem é preso perde esta profissão (as outras ficam guardadas)
	},
	-- Marco 8.1: quem é preso faz as tarefas de Presidiário (não aparece no quadro de empregos).
	-- Marco 8.2: é um "subgrupo": a profissão da pessoa continua guardada enquanto está presa.
	Presidiario = {
		Name = "Presidiário",
		Icon = "🔒", -- Marco 9.14: ícone no quadro de empregos
		Place = "Penitenciária",
		Slots = 1000,
		PayText = "Tarefas diminuem a pena",
		Color = Color3.fromRGB(235, 120, 30),
		Description = "Faça tarefas pela prisão para diminuir a pena.",
		NoPay = true,
		FinishHook = "prisonTaskDone",
		makeOrder = prisonOrder,
	},
}

-- Nome que aparece no botão de cada estação de coleta
function JobConfig.optionLabel(station)
	local ing = station:match("^Ing_(.+)$")
	if ing then
		local data = ingredientById(ing)
		return "Colocar " .. (data and data.label or ing)
	end
	local cat = station:match("^Caixa_(.+)$")
	if cat then
		return "Pegar caixa de " .. cat
	end
	if station:match("^Esteira") then
		return "Passar no leitor"
	end
	return "Usar"
end

-- Nome curto de uma estação na lista de "precisa" (ex.: "Queijo")
function JobConfig.shortLabel(station)
	local ing = station:match("^Ing_(.+)$")
	if ing then
		local data = ingredientById(ing)
		return data and data.label or ing
	end
	return station:match("^Caixa_(.+)$") or station
end

JobConfig.ingredientById = ingredientById

-- Regras gerais
JobConfig.InteractDistance = 12 -- distância máxima (studs) que o servidor aceita para uma interação
JobConfig.BoardDistance = 14 -- distância máxima do quadro de empregos para pegar um emprego
JobConfig.NextOrderDelay = 2 -- segundos entre terminar um pedido e começar o próximo
JobConfig.MinStepSeconds = 0.3 -- tempo mínimo entre duas ações (evita cliques automáticos)
JobConfig.TravelSpeed = 95 -- velocidade máxima aceita (studs/s) em etapas de viagem; a bike faz 30 e o carro até 80

-- Posição do quadro de empregos na praça (lado oposto ao Seu Bento)
JobConfig.BoardPosition = Vector3.new(-9, 0, 21)

return JobConfig
