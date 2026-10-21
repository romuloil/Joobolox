-- Moradores de rua usam o mesmo NPCKit dos clientes e das pessoas da praça.
-- As distâncias são medidas ao longo das avenidas; a posição final vem da calçada real.
local StreetNPCConfig = {}

StreetNPCConfig.TalkDistance = 10
StreetNPCConfig.TalkCooldown = 1.5
StreetNPCConfig.NPCSpeechCooldown = 1
StreetNPCConfig.MinSpacing = 22
StreetNPCConfig.Clearance = Vector3.new(2.6, 5.6, 2.6)
StreetNPCConfig.DistanceOffsets = { 0, 16, -16, 32, -32, 48, -48 }
StreetNPCConfig.Residents = {
	{ id = "Morador01", name = "Helena", street = 1, distance = 265, side = -1, topic = "police" },
	{ id = "Morador02", name = "Davi", street = 2, distance = 410, side = 1, topic = "neighborhood" },
	{ id = "Morador03", name = "Camila", street = 3, distance = 260, side = -1, topic = "jobs" },
	{ id = "Morador04", name = "Joaquim", street = 4, distance = 485, side = 1, topic = "delivery" },
	{ id = "Morador05", name = "Nina", street = 5, distance = 245, side = -1, topic = "transport" },
	{ id = "Morador06", name = "André", street = 6, distance = 410, side = 1, topic = "market" },
	{ id = "Morador07", name = "Marina", street = 7, distance = 235, side = -1, topic = "map" },
	{ id = "Morador08", name = "Otávio", street = 8, distance = 485, side = 1, topic = "city" },
}

StreetNPCConfig.Lines = {
	police = {
		"Você está na {street}. A delegacia fica mais ao norte da Avenida das Palmeiras, de frente para a avenida.",
		"Quer trabalhar como policial? Procure o balcão de plantão na delegacia e depois retire o uniforme no local.",
		"O mapa mostra a delegacia e os demais serviços. Toque no ícone no alto da tela ou aperte M.",
	},
	neighborhood = {
		"Bem-vindo à {street}! Eu gosto de ficar por aqui vendo o movimento do bairro.",
		"As casas têm endereço e número. Nas entregas, confira a rua no mapa antes de sair.",
		"Se quiser chegar à praça, siga a sua rua em direção ao centro da cidade.",
	},
	jobs = {
		"Tem trabalho na {pizza}, no {market} e na {delivery}. O quadro de empregos fica na praça.",
		"O uniforme é retirado no local de trabalho e fica disponível enquanto você está no emprego.",
		"A {taxi} também está contratando. Procure o balcão da empresa para começar o plantão.",
	},
	delivery = {
		"Quem entrega encomendas pela {delivery} passa bastante pela {street}.",
		"O destino da tarefa aparece no mapa. Parar e conferir o endereço evita uma volta enorme!",
		"A bicicleta ajuda nos trajetos curtos. Os veículos de trabalho são retirados nas garagens da profissão.",
	},
	transport = {
		"A sede da {taxi} fica ao sul da Avenida Central. É o prédio amarelo com o nome azul.",
		"O taxista começa na empresa, retira o uniforme e busca o carro amarelo na garagem.",
		"Uma corrida passa por buscar o passageiro e levá-lo ao destino. Dirija com calma nas esquinas!",
	},
	market = {
		"O {market} tem atendimento e reposição. Você pode escolher esse emprego na praça.",
		"Quando mudar de profissão, devolva o material da anterior. O uniforme e o carro acompanham o emprego.",
		"Você está na {street}. A praça fica em direção ao centro, seguindo a avenida.",
	},
	map = {
		"Perdeu o caminho? Abra o mapa pelo ícone no alto da tela ou pela tecla M.",
		"A delegacia e a {taxi} agora ficam em terrenos abertos, com acesso direto pelas avenidas.",
		"As avenidas saem da praça e se ligam pelos anéis de rua. Dá para dar a volta pelo bairro.",
	},
	city = {
		"Eu sou um dos moradores da {street}. Por aqui sempre tem alguém para conversar.",
		"A Parada da Serra fica fora da cidade. A garagem de lá serve para retirar seu carro pessoal.",
		"Para começar um trabalho, procure o quadro da praça ou o balcão da empresa. Depois vá buscar seu uniforme.",
	},
}

return StreetNPCConfig
