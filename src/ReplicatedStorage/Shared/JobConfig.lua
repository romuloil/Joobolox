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
--   (ex.: "customerCome" faz um cliente NPC entrar na loja), waitText = texto da espera,
--   count = mostra o progresso da coleta como "3/5 produtos".
-- carry = o que o jogador passa a segurar depois da etapa ("Dough", {kind="Crate", color=...}) ou false para largar.
-- tip = gorjeta paga se o pedido terminar em até parTime segundos (e a pizza não queimar).

local JobConfig = {}

JobConfig.Order = { "Pizzaiolo", "Atendente", "Entregador" }

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
	{ id = "Marguerita", label = "Marguerita", ingredients = { "Molho", "Queijo", "Tomate", "Manjericao" }, pay = 30 },
	{ id = "Calabresa", label = "Calabresa", ingredients = { "Molho", "Queijo", "Calabresa" }, pay = 30 },
	{ id = "Portuguesa", label = "Portuguesa", ingredients = { "Molho", "Queijo", "Presunto", "Ovo" }, pay = 35 },
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
		pay = flavor.pay,
		tip = 10,
		parTime = 90,
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
			pay = 8 + 2 * items, -- tarefa mais fácil: paga menos que repor
			tip = 3,
			parTime = 55,
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
			pay = 14 * count,
			tip = 3 * count,
			parTime = 28 * count,
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
		pay = 20,
		tip = 5,
		parTime = 40,
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

-- ctx.pickHouses(n) devolve n casas diferentes { point, address, position }; ctx.origin = posição do balcão
local function deliveryOrder(rng, ctx)
	local count = rng:NextInteger(1, 3)
	local houses = ctx.pickHouses(count)
	count = #houses
	local steps = {
		{ station = "BalcaoPacotes", text = ("Retire %d pacote%s no balcão"):format(count, count > 1 and "s" or ""), action = "Retirar pacotes", hold = 0.8, carry = { kind = "Package", count = count } },
	}
	local route, last = 0, ctx.origin
	for i, house in ipairs(houses) do
		route += (house.position - last).Magnitude
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
		pay = 12 * count + math.floor(route * 0.03),
		tip = 4 * count,
		parTime = route / 22 + 15,
		steps = steps,
	}
end

---------------------------------------------------------------------------
-- Profissões
---------------------------------------------------------------------------

JobConfig.Jobs = {
	Pizzaiolo = {
		Name = "Pizzaiolo",
		Place = "La Paulistana",
		Slots = 2,
		PayText = "$30 a $35 por pizza + gorjeta",
		Color = Color3.fromRGB(200, 50, 45),
		Description = "Faça Marguerita, Calabresa ou Portuguesa com os ingredientes certos. Não deixe queimar!",
		makeOrder = pizzaOrder,
	},
	Atendente = {
		Name = "Atendente",
		Place = "Minas Market",
		Slots = 2,
		Lanes = true, -- cada atendente fica com um caixa (1 ou 2)
		PayText = "$14 a $42 por tarefa + gorjeta",
		Color = Color3.fromRGB(40, 140, 70),
		Description = "Atenda clientes no caixa, reponha 2 ou 3 prateleiras com as caixas certas e limpe a loja.",
		makeOrder = marketOrder,
	},
	Entregador = {
		Name = "Entregador Sherlex",
		Place = "Sherlex",
		Slots = 2,
		PayText = "$15+ por pacote, mais longe paga mais",
		Color = Color3.fromRGB(240, 140, 30),
		Description = "Rotas de 1 a 3 pacotes para endereços da cidade (rua e número). Vá de bike ou de carro!",
		makeOrder = deliveryOrder,
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
