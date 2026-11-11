-- GameConfig (ModuleScript)
-- Caminho: ReplicatedStorage > Shared > GameConfig
-- Configurações centrais do jogo. Servidor e cliente leem daqui.
-- Mude valores aqui em vez de espalhar números pelos scripts.

local GameConfig = {}

GameConfig.GameName = "Little Life: Minha Cidade"
GameConfig.CityName = "Little Little Kinder"
GameConfig.Version = "Marco 10.32"

-- Nomes oficiais (documento mestre, seção 5)
GameConfig.Places = {
	Pizzaria = "La Paulistana",
	Mercearia = "Minas Market",
	Entregas = "Sherlex",
	PetShop = "Duto Pet Shop",
	Onibus = "Um Tijo",
	Bombeiros = "Corpo de Bombeiros de Little Little Kinder",
	Policia = "Centro Policial de Little Little Kinder",
	Banco = "Banco Nacional de Little Little Kinder",
	Taxi = "LXR Táxis",
}

-- Nomes dos RemoteEvents (criados pelo servidor em ReplicatedStorage > Remotes)
GameConfig.Remotes = {
	VehicleRequest = "VehicleRequest", -- cliente pede para montar/desmontar a bicicleta
	UIUpdate = "UIUpdate", -- servidor avisa a interface sobre mudanças
	TutorialRequest = "TutorialRequest", -- cliente avisa que está pronto / terminou o tutorial
	JobRequest = "JobRequest", -- cliente pede para entrar/sair de um emprego
	HomeRequest = "HomeRequest", -- cliente pede algo da casa (decorar, trancar)
	PetRequest = "PetRequest", -- Marco 7: adotar o pet, fazer carinho
	GangRequest = "GangRequest", -- Marco 10.1: entrar ou sair de uma gangue (conversa com o chefe)
	CrimeRequest = "CrimeRequest", -- Marco 10.5: minijogo do caixa eletrônico, taser, algema e chamados da PM
	WeaponRequest = "WeaponRequest", -- Marco 10.5: tiro e recarga (o servidor confere tudo)
	InventoryRequest = "InventoryRequest", -- Marco 10.5: mochila, atalhos e baú
	SettingsRequest = "SettingsRequest", -- Marco 10.8: configurações do jogador (câmera)
	JewelryRequest = "JewelryRequest", -- Marco 10.8: reconhecimento do assalto à joalheria
	DownedRequest = "DownedRequest", -- Marco 10.15: caído no chão (desistir)
	BankRequest = "BankRequest", -- Marco 10.20: assalto ao banco (status)
	LitoralRequest = "LitoralRequest", -- Marco 10.32: surfe (prancha, estado, pontos da onda)
}

-- Marco 10.8: câmera. Sem 1ª pessoa (MinZoom > 0,5) e afastando pouco. A "mira travada" (o boneco
-- vira para onde a câmera olha e o mouse fica no meio, como jogo de tiro) é o padrão no PC;
-- quem quiser a câmera padrão do Roblox troca no seletor do topo (Marco 10.29) ou na tecla L.
GameConfig.Camera = {
	MinZoom = 5, -- Marco 10.21: Luís pediu um pouco mais de zoom (era 7)
	MaxZoom = 22, -- Marco 10.21: e afastar um pouco mais (era 16)
	Shoulder = Vector3.new(1.7, 0.6, 0), -- câmera um pouco à direita do ombro na mira travada
	AimLockDefault = true,
	-- Marco 10.12: mirando com arma (botão direito / "Mirar" no celular), igual GTA
	AimShoulder = Vector3.new(2, 0.8, -1.2), -- câmera mais perto, por cima do ombro
	AimFovRifle = 45, -- zoom do fuzil (70 = normal; menor = mais zoom)
	AimFovPistol = 55,
	AimSensitivity = 0.6, -- mouse mais lento mirando
	Recoil = { pistola = 1.1, fuzil = 0.7 }, -- tranco da câmera por tiro (graus)
}

-- Marco 10.12: vida e stamina (barras embaixo do minimapa). Correr: Shift (PC) ou botão "Correr" (celular).
GameConfig.Stamina = {
	Max = 100,
	RunSpeed = 25, -- correndo (andando = WalkSpeed 16)
	Drain = 16, -- por segundo correndo: 100 dura uns 6 s
	Regen = 14, -- por segundo parado/andando (depois do Delay): enche em uns 7 s
	Delay = 1, -- segundos sem correr até começar a recarregar
	MinToRun = 15, -- se zerar, só volta a correr depois de ter isso
}

-- Marco 10.15: economia nova (Revisão 2 do documento "Economia do Little Life", aprovada pelo Luís).
-- Salário a cada 15 min por estar no emprego + o valor de cada tarefa. Cargos por tarefas feitas
-- em cada profissão (fica salvo; trocar de emprego não perde), +10% nas tarefas a cada promoção.
GameConfig.Career = {
	Interval = 15 * 60, -- salário a cada 15 min
	ActiveWindow = 5 * 60, -- anti-AFK: precisa ter feito 1 tarefa nos 15 min OU ter andado nos últimos 5 min
	RankBonus = 0.10, -- +10% no valor das tarefas por promoção
	Ranks = {
		{ Name = "Estagiário", Tasks = 0 },
		{ Name = "Funcionário", Tasks = 50 },
		{ Name = "Experiente", Tasks = 150 },
		{ Name = "Veterano", Tasks = 400 },
		{ Name = "Chefe", Tasks = 1000 },
	},
	-- nome do cargo 5 em cada profissão
	TopTitle = { Policial = "Delegado", Bombeiro = "Comandante", Atendente = "Gerente", Pizzaiolo = "Chefe de cozinha", Paramedico = "Médico-chefe" },
	Tier = {
		Pizzaiolo = "basica",
		Atendente = "basica",
		Entregador = "rota",
		Taxista = "rota",
		Motorista = "rota",
		Cuidador = "rota",
		Bombeiro = "risco",
		Policial = "risco",
		Paramedico = "risco",
	},
	Salary = {
		basica = { 2500, 3000, 3500, 4000, 4500 },
		rota = { 3000, 3600, 4200, 4800, 5400 },
		risco = { 4000, 4800, 5600, 6400, 7200 },
	},
	ArrestTasks = 5, -- prisão conta 5 tarefas para o cargo do policial
	PatrolPay = 150, -- policial patrulhando: por minuto andando pela cidade (pedido do Luís)
	PatrolDistance = 150, -- precisa ter andado isso (studs) no minuto para contar como patrulha
}

-- Marco 10.15: "morrer" = cair no chão e esperar um paramédico. Valores PROVISÓRIOS.
GameConfig.Downed = {
	Time = 120, -- segundos caído esperando o paramédico (depois renasce na praça sem os itens)
	GiveUpAfter = 5, -- o botão Desistir libera depois disso (para não apertar sem querer)
	ReviveTime = 5, -- paramédico segurando E para reanimar
	ReviveRange = 8,
	ReviveHealth = 50, -- vida depois de reanimado
	RevivePay = 1500, -- paramédico ganha por reanimação (+10% por cargo)
	HospitalFee = 0.02, -- desistir/acabar o tempo: conta do hospital = 2% do dinheiro...
	HospitalMax = 5000, -- ...no máximo isso
}

-- Economia (valores PROVISÓRIOS, ajustar depois de testar)
GameConfig.Economy = {
	CurrencySymbol = "$",
	StartingMoney = 5000, -- dinheiro de quem entra pela primeira vez (Marco 10.15: economia nova)
	MaxMoney = 1000000000, -- limite de segurança
}

-- Bônus diário (regra confirmada: 24h contadas a partir do resgate; o valor é PROVISÓRIO)
GameConfig.DailyBonus = {
	Amount = 2500, -- Marco 10.15: economia nova
	Cooldown = 24 * 60 * 60, -- segundos
}

-- Salvamento (DataStore). Mudar o nome da store APAGA o progresso salvo de todos.
GameConfig.Data = {
	StoreName = "LittleLifePlayerData_v1",
	AutosaveInterval = 120, -- segundos entre salvamentos automáticos
	Retries = 3, -- tentativas antes de desistir de carregar/salvar
}

-- NPC guia da praça
GameConfig.Guide = {
	Name = "Seu Bento",
	Position = Vector3.new(8, 0, 24), -- perto do spawn, na praça (fora do anel de flores)
	TalkDistance = 12, -- distância máxima (studs) para conversar
	SkinColor = Color3.fromRGB(205, 150, 110),
	ShirtColor = Color3.fromRGB(240, 170, 60),
	PantsColor = Color3.fromRGB(60, 80, 120),
}

-- Personagem
GameConfig.WalkSpeed = 16 -- velocidade normal a pé (padrão do Roblox)

-- Bicicleta inicial (gratuita para todos)
GameConfig.Bike = {
	Speed = 30, -- velocidade enquanto pedala
	ToggleCooldown = 1, -- segundos mínimos entre montar e desmontar
	FrameColor = Color3.fromRGB(46, 160, 220), -- quadro
	AccentColor = Color3.fromRGB(60, 45, 35), -- selim e manoplas
	WheelColor = Color3.fromRGB(30, 30, 34), -- pneus e pedais
	MetalColor = Color3.fromRGB(190, 190, 198), -- raios, guidão, pedivela
	WheelRadius = 0.85,
	SeatOffsetY = 0, -- sobe (+) ou desce (-) o selim se o personagem ficar flutuando ou afundado
	PedalSpeed = 0.45, -- voltas do pedal por volta da roda
	Model = "BMX", -- Marco 9.6: modelo 3D em ServerStorage > CarModels (sem ele, a bike de peças de antes)
	MeshLength = 6.2, -- Marco 9.8: comprimento da BMX 3D em studs (era ~5; o Luís achou pequena)
	SeatSink = 0.3, -- quanto o quadril "afunda" no selim (as pernas alcançam melhor os pedais)
}

-- Carros. Cada carro é só dados: o CarBuilder usa o modelo 3D de ServerStorage > CarModels
-- (nome em Model) e, se ele não existir, monta um sedã de peças com as cores daqui.
-- Nomes e marcas próprios (o Roblox não deixa usar marcas reais).
-- Carro melhor = mais rápido e mais controle no drift.
-- Seats: posição dos bancos (X = lado, Y = altura acima do chão, Z = frente(-)/trás(+)).
-- Marco 7.1: Category = "Carros" ou "Motos" (abas da garagem). Moto = true: 2 rodas (Front/Rear)
-- e inclina nas curvas. Fillers com Text = letreiro (texto na face Face da peça; peça invisível
-- se Transparent = true).
GameConfig.Cars = {
	L5 = {
		EngineSound = "M5", -- Marco 9.12: perfil de som (GameConfig.Sounds.Profiles)
		Turbo = true,
		BackfireSound = "Backfire2", -- o outro pipoco
		Name = "LXR L5",
		Price = 280000, -- Marco 10.15: economia nova (Revisão 2)
		Rarity = "Épico",
		Category = "Carros",
		Order = 2,
		Model = "LXR_L5",
		Length = 19,
		Width = 8.1,
		BodyColor = Color3.fromRGB(14, 14, 16), -- preto
		TrimColor = Color3.fromRGB(10, 10, 12),
		AccentColor = Color3.fromRGB(255, 200, 60),
		GlassColor = Color3.fromRGB(8, 9, 11), -- fumê quase total
		GlassTransparency = 0.12,
		RimColor = Color3.fromRGB(175, 150, 95),
		CaliperColor = Color3.fromRGB(200, 30, 35),
		SeatColor = Color3.fromRGB(35, 35, 38),
		Reflectance = 0.08,
		WheelRadius = 1.34,
		Seats = { Driver = Vector3.new(-1.4, 1.3, 0.6), Passenger = Vector3.new(1.4, 1.3, 0.6), Rear = { Vector3.new(-1.3, 1.3, 3.2), Vector3.new(1.3, 1.3, 3.2) } },
		Plates = { Front = Vector3.new(0, 1.6, -9.5), Rear = Vector3.new(0, 2.55, 8.79) }, -- placas (Marco 7.5): centro da placa, mesmo jeito dos bancos
		Roof = 5.24, -- altura do teto por dentro: quem é alto inclina o encosto (Marco 7.5) para a cabeça não sair
		MaxSpeed = 89, -- Marco 10.17: era 85 (+5%)
		ReverseSpeed = 22,
		Acceleration = 33,
		Brake = 70,
		Drag = 14, -- quanto perde de velocidade sem acelerar
		TurnRate = 1.8, -- giro em radianos/s
		Hover = 2.0, -- altura do centro do chassi acima do chão
		-- Aderência e drift (carro melhor = mais controle no drift: gira mais com o freio de mão
		-- e segura o deslize acelerando sem rodar)
		Grip = 9, -- aderência normal (quanto maior, menos o carro escorrega de lado)
		DriftGrip = 1.0, -- aderência com o freio de mão puxado (baixa = traseira solta)
		DriftHoldGrip = 2.4, -- aderência deslizando e acelerando (mantém o drift)
		DriftTurnBoost = 1.7, -- quanto a mais o carro gira durante o drift
		HandbrakeDecel = 20, -- quanto o freio de mão segura a velocidade
		-- Fundo preto com aletas embaixo das 2 entradas de ar do capô (Pos: X lado, Y altura do chão,
		-- Z frente(-)/trás(+); Pitch: inclinação acompanhando o capô)
		Fillers = {
			{ Name = "HoodVentBase", Size = Vector3.new(2.4, 0.4, 1.6), Pos = Vector3.new(0, 2.94, -7.2), Pitch = -7 },
			{ Name = "HoodVentFin", Size = Vector3.new(2.3, 0.1, 0.12), Pos = Vector3.new(0, 3.13, -7.6), Pitch = -7, Color = Color3.fromRGB(45, 45, 50), Material = Enum.Material.Metal },
			{ Name = "HoodVentFin", Size = Vector3.new(2.3, 0.1, 0.12), Pos = Vector3.new(0, 3.18, -7.2), Pitch = -7, Color = Color3.fromRGB(45, 45, 50), Material = Enum.Material.Metal },
			{ Name = "HoodVentFin", Size = Vector3.new(2.3, 0.1, 0.12), Pos = Vector3.new(0, 3.23, -6.8), Pitch = -7, Color = Color3.fromRGB(45, 45, 50), Material = Enum.Material.Metal },
		},
		-- Ponta dos 4 escapamentos (de onde sai o fogo)
		Exhausts = { Vector3.new(-2.29, 1.28, 9.3), Vector3.new(-1.84, 1.28, 9.35), Vector3.new(1.85, 1.28, 9.35), Vector3.new(2.28, 1.28, 9.3) },
	},
	R18 = {
		EngineSound = "R18", -- Marco 9.12: perfil de som (GameConfig.Sounds.Profiles)
		Turbo = true,
		Name = "R18",
		Price = 140000, -- Marco 10.15: economia nova (Revisão 2)
		Rarity = "Raro",
		Category = "Carros",
		Order = 3,
		Model = "R18",
		Length = 17.5,
		Width = 7.5,
		BodyColor = Color3.fromRGB(200, 20, 22), -- vermelho original do modelo
		TrimColor = Color3.fromRGB(12, 12, 14),
		AccentColor = Color3.fromRGB(240, 240, 255),
		GlassColor = Color3.fromRGB(8, 9, 11),
		GlassTransparency = 0.15,
		RimColor = Color3.fromRGB(30, 30, 32),
		CaliperColor = Color3.fromRGB(200, 30, 35),
		SeatColor = Color3.fromRGB(35, 35, 38),
		Reflectance = 0.08,
		WheelRadius = 1.4,
		Seats = { Driver = Vector3.new(-1.4, 1.1, -0.6), Passenger = Vector3.new(1.4, 1.1, -0.6), Rear = {} },
		Plates = { Front = Vector3.new(0, 1.6, -8.65), Rear = Vector3.new(0, 2.1, 8.47) }, -- placas (Marco 7.5): centro da placa, mesmo jeito dos bancos
		Roof = 4.85, -- altura do teto por dentro: quem é alto inclina o encosto (Marco 7.5) para a cabeça não sair
		MaxSpeed = 82, -- Marco 10.17: era 78 (+5%)
		ReverseSpeed = 22,
		Acceleration = 31,
		Brake = 70,
		Drag = 14,
		TurnRate = 1.8,
		Hover = 2.0,
		Grip = 9,
		DriftGrip = 1.1,
		DriftHoldGrip = 2.6,
		DriftTurnBoost = 1.55,
		HandbrakeDecel = 20,
		Exhausts = { Vector3.new(-2.62, 1.56, 8.45), Vector3.new(2.62, 1.56, 8.45) },
	},
	Mengeot = {
		EngineSound = "Engine", -- Marco 9.10: ronco pela força do carro (GameConfig.Sounds)
		Name = "Mengeot",
		Price = 15000, -- Marco 10.15: economia nova (Revisão 2)
		Rarity = "Comum",
		Category = "Carros",
		Order = 6,
		Model = "Mengeot",
		Length = 15,
		Width = 6.8,
		BodyColor = Color3.fromRGB(215, 120, 25), -- laranja original do modelo
		TrimColor = Color3.fromRGB(20, 20, 22),
		AccentColor = Color3.fromRGB(240, 240, 230),
		GlassColor = Color3.fromRGB(10, 11, 13),
		GlassTransparency = 0.2,
		RimColor = Color3.fromRGB(200, 200, 205),
		CaliperColor = Color3.fromRGB(60, 60, 66),
		SeatColor = Color3.fromRGB(45, 45, 48),
		Reflectance = 0.05,
		WheelRadius = 1.2,
		Seats = { Driver = Vector3.new(-1.25, 1.4, -0.2), Passenger = Vector3.new(1.25, 1.4, -0.2), Rear = { Vector3.new(-1.25, 1.4, 3.1), Vector3.new(1.25, 1.4, 3.1) } },
		Plates = { Front = Vector3.new(0, 1.25, -7.59), Rear = Vector3.new(0, 3.15, 7.3) }, -- placas (Marco 7.5): centro da placa; traseira 7.3 (Marco 9.9: em 7.19 a lataria cobria)
		Roof = 5.06, -- altura do teto por dentro: quem é alto inclina o encosto (Marco 7.5) para a cabeça não sair
		MaxSpeed = 63, -- Marco 10.17: era 60 (+5%)
		ReverseSpeed = 18,
		Acceleration = 23,
		Brake = 60,
		Drag = 12,
		TurnRate = 1.7,
		Hover = 2.0,
		Grip = 8,
		DriftGrip = 1.6,
		DriftHoldGrip = 3.6, -- segura menos o drift (carro simples)
		DriftTurnBoost = 1.25,
		HandbrakeDecel = 16,
	},
	-- Marco 7.1: novos modelos 3D (nomes próprios; preços, velocidades e raridades PROVISÓRIOS)
	-- Fúria: o mais rápido do jogo e o mais solto no freio de mão (drift fácil de segurar)
	Furia = {
		EngineSound = "Dodge", -- Marco 9.12: perfil de som (GameConfig.Sounds.Profiles)
		Turbo = true,
		Name = "Fúria",
		Price = 600000, -- Marco 10.15: economia nova (Revisão 2)
		Rarity = "Lendário",
		Category = "Carros",
		Order = 1,
		Model = "Furia",
		Length = 17.5,
		Width = 7.6,
		BodyColor = Color3.fromRGB(15, 15, 18), -- preto
		TrimColor = Color3.fromRGB(10, 10, 12),
		AccentColor = Color3.fromRGB(220, 30, 40),
		GlassColor = Color3.fromRGB(8, 9, 11),
		GlassTransparency = 0.12,
		RimColor = Color3.fromRGB(60, 60, 64),
		CaliperColor = Color3.fromRGB(220, 30, 40),
		SeatColor = Color3.fromRGB(35, 35, 38),
		Reflectance = 0.1,
		WheelRadius = 1.27,
		Seats = { Driver = Vector3.new(-1.45, 1.2, 0.3), Passenger = Vector3.new(1.45, 1.2, 0.3), Rear = { Vector3.new(-1.15, 1.2, 2.3), Vector3.new(1.15, 1.2, 2.3) } },
		Plates = { Front = Vector3.new(0, 1.5, -8.82), Rear = Vector3.new(0, 2.2, 8.82) }, -- placas (Marco 7.5): centro da placa, mesmo jeito dos bancos
		Roof = 4.51, -- altura do teto por dentro: quem é alto inclina o encosto (Marco 7.5) para a cabeça não sair
		MaxSpeed = 100, -- Marco 10.17: era 95 (+5%)
		ReverseSpeed = 24,
		Acceleration = 42,
		Brake = 75,
		Drag = 13,
		TurnRate = 1.9,
		Hover = 2.0,
		Grip = 8.5,
		DriftGrip = 0.7, -- traseira bem solta no freio de mão
		DriftHoldGrip = 1.8, -- segura o drift acelerando
		DriftTurnBoost = 1.95,
		HandbrakeDecel = 13, -- perde pouca velocidade derrapando
		Exhausts = { Vector3.new(-1.6, 0.9, 8.6), Vector3.new(1.6, 0.9, 8.6) }, -- PROVISÓRIO: ponto aproximado
	},
	-- Marco 9.17: a BMW dos admins (Marco 9.16) saiu do jogo a pedido do Luís. A aba "Admin", o
	-- AdminOnly, a física RealDrift do CarController, HeadlightColor e Pops continuam prontos para
	-- um carro futuro (ver REGISTRO_DO_PROJETO.md).
	Polux = {
		EngineSound = "Engine", -- Marco 9.10: ronco pela força do carro (GameConfig.Sounds)
		Name = "Pólux",
		Price = 30000, -- Marco 10.15: economia nova (Revisão 2)
		Rarity = "Comum",
		Category = "Carros",
		Order = 5,
		Model = "Polux",
		Length = 15.5,
		Width = 6.6,
		BodyColor = Color3.fromRGB(90, 184, 219), -- azul-céu
		TrimColor = Color3.fromRGB(20, 20, 22),
		AccentColor = Color3.fromRGB(240, 240, 230),
		GlassColor = Color3.fromRGB(10, 11, 13),
		GlassTransparency = 0.2,
		RimColor = Color3.fromRGB(190, 190, 195),
		CaliperColor = Color3.fromRGB(60, 60, 66),
		SeatColor = Color3.fromRGB(45, 45, 48),
		Reflectance = 0.06,
		WheelRadius = 0.98,
		Seats = { Driver = Vector3.new(-1.3, 1.3, -0.3), Passenger = Vector3.new(1.3, 1.3, -0.3), Rear = { Vector3.new(-1.2, 1.3, 2.3), Vector3.new(1.2, 1.3, 2.3) } },
		Plates = { Front = Vector3.new(0, 1.55, -7.72), Rear = Vector3.new(0, 2.75, 7.63) }, -- placas (Marco 7.5): centro da placa, mesmo jeito dos bancos
		Roof = 4.52, -- altura do teto por dentro: quem é alto inclina o encosto (Marco 7.5) para a cabeça não sair
		MaxSpeed = 67, -- Marco 10.17: era 64 (+5%)
		ReverseSpeed = 18,
		Acceleration = 25,
		Brake = 62,
		Drag = 12,
		TurnRate = 1.75,
		Hover = 2.0,
		Grip = 8.5,
		DriftGrip = 1.5,
		DriftHoldGrip = 3.4,
		DriftTurnBoost = 1.3,
		HandbrakeDecel = 16,
	},
	-- Marco 10.5: modelos do Luís (sedã e picape quadrada). Nomes, preços e velocidades PROVISÓRIOS.
	Virtux = {
		EngineSound = "Engine",
		Name = "Virtux",
		Price = 50000, -- Marco 10.15: economia nova (Revisão 2)
		Rarity = "Comum",
		Category = "Carros",
		Order = 5,
		Model = "Virtus",
		Length = 16,
		Width = 7,
		BodyColor = Color3.fromRGB(190, 26, 30), -- vermelho
		TrimColor = Color3.fromRGB(20, 20, 22),
		AccentColor = Color3.fromRGB(240, 240, 230),
		GlassColor = Color3.fromRGB(10, 11, 13),
		GlassTransparency = 0.2,
		RimColor = Color3.fromRGB(190, 190, 195),
		CaliperColor = Color3.fromRGB(60, 60, 66),
		SeatColor = Color3.fromRGB(45, 45, 48),
		Reflectance = 0.06,
		WheelRadius = 1.08,
		Seats = { Driver = Vector3.new(-1.35, 1.35, -0.4), Passenger = Vector3.new(1.35, 1.35, -0.4), Rear = { Vector3.new(-1.25, 1.35, 2.4), Vector3.new(1.25, 1.35, 2.4) } },
		Plates = { Front = Vector3.new(0, 1.6, -8.0), Rear = Vector3.new(0, 2.6, 7.95) },
		Roof = 4.6,
		MaxSpeed = 69, -- Marco 10.17: era 66 (+5%)
		ReverseSpeed = 18,
		Acceleration = 26,
		Brake = 62,
		Drag = 12,
		TurnRate = 1.75,
		Hover = 2.0,
		Grip = 8.5,
		DriftGrip = 1.5,
		DriftHoldGrip = 3.4,
		DriftTurnBoost = 1.3,
		HandbrakeDecel = 16,
	},
	-- Picape "lotada de som": caixas e luzes na caçamba (SoundRig). Liga e desliga no aviso "Som"
	-- (só o dono). Música: GameConfig.CarSound.MusicId (0 = só as luzes, até o Luís mandar o ID).
	Saveira = {
		EngineSound = "Engine",
		Name = "Saveira Quadrada",
		Price = 45000, -- Marco 10.15: economia nova (Revisão 2)
		Rarity = "Incomum",
		Category = "Carros",
		Order = 4,
		Model = "Saveira",
		Length = 16.45,
		Width = 6.9,
		BodyColor = Color3.fromRGB(242, 242, 242), -- branca
		TrimColor = Color3.fromRGB(20, 20, 22),
		AccentColor = Color3.fromRGB(240, 240, 230),
		GlassColor = Color3.fromRGB(10, 11, 13),
		GlassTransparency = 0.2,
		RimColor = Color3.fromRGB(200, 200, 205),
		CaliperColor = Color3.fromRGB(60, 60, 66),
		SeatColor = Color3.fromRGB(45, 45, 48),
		Reflectance = 0.04,
		WheelRadius = 1.07,
		Seats = { Driver = Vector3.new(-1.3, 1.3, -0.9), Passenger = Vector3.new(1.3, 1.3, -0.9) },
		Plates = { Front = Vector3.new(0, 1.45, -8.2), Rear = Vector3.new(0, 1.85, 8.2) },
		Roof = 4.3,
		-- caçamba (coordenadas do carro): chão em Y, de Z0 a Z1, meia largura HalfX
		SoundRig = { Y = 1.35, Z0 = 2.0, Z1 = 7.6, HalfX = 1.95 },
		MaxSpeed = 63, -- Marco 10.17: era 60 (+5%)
		ReverseSpeed = 18,
		Acceleration = 23,
		Brake = 58,
		Drag = 12,
		TurnRate = 1.7,
		Hover = 2.0,
		Grip = 8,
		DriftGrip = 1.5,
		DriftHoldGrip = 3.4,
		DriftTurnBoost = 1.3,
		HandbrakeDecel = 16,
	},
	-- Marco 10.8: picape média do Luís (modelo da Toro, nome trocado para Coro). PROVISÓRIO: preço e velocidade.
	Coro = {
		EngineSound = "Engine",
		Name = "Coro",
		Price = 90000, -- Marco 10.15: economia nova (Revisão 2)
		Rarity = "Incomum",
		Category = "Carros",
		Order = 4,
		Model = "Coro",
		Length = 18,
		Width = 7.8,
		BodyColor = Color3.fromRGB(214, 214, 216), -- branca (cor do modelo)
		TrimColor = Color3.fromRGB(18, 18, 20),
		AccentColor = Color3.fromRGB(240, 240, 230),
		GlassColor = Color3.fromRGB(10, 11, 13),
		GlassTransparency = 0.2,
		RimColor = Color3.fromRGB(150, 152, 158),
		CaliperColor = Color3.fromRGB(60, 60, 66),
		SeatColor = Color3.fromRGB(40, 40, 44),
		Reflectance = 0.05,
		WheelRadius = 1.29,
		Seats = { Driver = Vector3.new(-1.45, 1.9, -1.8), Passenger = Vector3.new(1.45, 1.9, -1.8), Rear = { Vector3.new(-1.3, 1.9, 1.3), Vector3.new(1.3, 1.9, 1.3) } },
		Plates = { Front = Vector3.new(0, 2.1, -9.05), Rear = Vector3.new(0, 1.35, 8.8) },
		Roof = 5.6,
		MaxSpeed = 71, -- Marco 10.17: era 68 (+5%)
		ReverseSpeed = 18,
		Acceleration = 26,
		Brake = 62,
		Drag = 12,
		TurnRate = 1.65,
		Hover = 2.0,
		Grip = 9,
		DriftGrip = 1.6,
		DriftHoldGrip = 3.4,
		DriftTurnBoost = 1.3,
		HandbrakeDecel = 16,
	},
	-- Marco 10.8: carro dos admins (modelo do Tiguan, nome Miguan). All black, rodas pretas com pinça
	-- vermelha e mais rápido que o Fúria. Marco 10.10: modelo refeito (tools/carros/miguan.json + carvis.py):
	-- altura original (rebaixado o pneu entrava no paralama), lataria lisa, placas no lugar delas.
	-- Só aparece na aba "Admin" da garagem (AdminOnly; quem é admin: GameConfig.Admins).
	Miguan = {
		EngineSound = "E36",
		Turbo = true,
		AdminOnly = true,
		Name = "Miguan",
		Price = 0,
		Rarity = "Admin",
		Category = "Carros",
		Order = 0,
		Model = "Miguan",
		Length = 17,
		Width = 7.8,
		BodyColor = Color3.fromRGB(8, 8, 10), -- all black
		TrimColor = Color3.fromRGB(10, 10, 12),
		AccentColor = Color3.fromRGB(200, 20, 30),
		GlassColor = Color3.fromRGB(5, 6, 7), -- insulfilm bem escuro
		GlassTransparency = 0.08,
		RimColor = Color3.fromRGB(16, 16, 18),
		CaliperColor = Color3.fromRGB(200, 24, 30),
		SeatColor = Color3.fromRGB(25, 25, 28),
		Reflectance = 0.04, -- 0.12 refletia o céu e o preto ficava azulado
		HeadlightColor = Color3.fromRGB(215, 230, 255), -- farol de LED branco-azulado
		Pops = { Time = 1.1, Chance = 0.7, Burst = { 5, 9 } },
		WheelRadius = 1.31,
		Seats = { Driver = Vector3.new(-1.35, 1.95, -1.3), Passenger = Vector3.new(1.35, 1.95, -1.3), Rear = { Vector3.new(-1.25, 1.95, 2.6), Vector3.new(1.25, 1.95, 2.6) } },
		-- placas no rebaixo da grade e da tampa traseira (medido no modelo)
		Plates = { Front = Vector3.new(0, 2.03, -8.52), Rear = Vector3.new(0, 3.08, 8.16) },
		PlateSize = Vector3.new(1.08, 0.46, 0.06),
		Roof = 5.55,
		MaxSpeed = 125, -- Fúria = 95: o mais rápido do jogo
		ReverseSpeed = 28,
		Acceleration = 55,
		Brake = 90,
		Drag = 13,
		TurnRate = 2.0,
		Hover = 2.0,
		Grip = 10,
		DriftGrip = 0.9,
		DriftHoldGrip = 2.2,
		DriftTurnBoost = 1.8,
		HandbrakeDecel = 14,
		Exhausts = { Vector3.new(-1.33, 1.15, 8.05), Vector3.new(1.33, 1.15, 8.05) }, -- as duas ponteiras embaixo do para-choque
	},
	Ranchera = {
		EngineSound = "Engine", -- Marco 9.10: ronco pela força do carro (GameConfig.Sounds)
		Name = "Ranchera",
		Price = 70000, -- Marco 10.15: economia nova (Revisão 2)
		Rarity = "Incomum",
		Category = "Carros",
		Order = 4,
		Model = "Ranchera",
		ArchLiner = 0.25, -- Marco 8.1: caixa de roda escura (o arco da lataria fica bem acima do pneu)
		Length = 18.5,
		Width = 7.3,
		BodyColor = Color3.fromRGB(219, 107, 31), -- laranja-queimado
		TrimColor = Color3.fromRGB(15, 15, 17),
		AccentColor = Color3.fromRGB(240, 240, 230),
		GlassColor = Color3.fromRGB(10, 11, 13),
		GlassTransparency = 0.2,
		RimColor = Color3.fromRGB(190, 190, 190),
		CaliperColor = Color3.fromRGB(60, 60, 66),
		SeatColor = Color3.fromRGB(40, 40, 44),
		Reflectance = 0.05,
		WheelRadius = 1.36,
		Seats = { Driver = Vector3.new(-1.45, 2.3, -1.2), Passenger = Vector3.new(1.45, 2.3, -1.2), Rear = { Vector3.new(-1.3, 2.3, 1.4), Vector3.new(1.3, 2.3, 1.4) } },
		Plates = { Front = Vector3.new(0, 2.0, -9.32), Rear = Vector3.new(0, 2.85, 9.04) }, -- placas (Marco 7.5): centro da placa, mesmo jeito dos bancos
		Roof = 5.87, -- altura do teto por dentro: quem é alto inclina o encosto (Marco 7.5) para a cabeça não sair
		MaxSpeed = 69, -- Marco 10.17: era 66 (+5%)
		ReverseSpeed = 18,
		Acceleration = 25,
		Brake = 60,
		Drag = 12,
		TurnRate = 1.6,
		Hover = 2.0,
		Grip = 9,
		DriftGrip = 1.8,
		DriftHoldGrip = 3.8,
		DriftTurnBoost = 1.25,
		HandbrakeDecel = 17,
	},
	-- Motos (Marco 7.1): 2 rodas, inclinam nas curvas. Só o piloto e um garupa.
	ShinobiH2 = {
		EngineSound = "Moto", -- Marco 9.12: perfil de som (GameConfig.Sounds.Profiles)
		Name = "Shinobi H2",
		Price = 350000, -- Marco 10.15: economia nova (Revisão 2)
		Rarity = "Épico",
		Category = "Motos",
		Moto = true,
		Order = 10,
		Model = "ShinobiH2",
		Length = 8.5,
		Width = 2.8,
		BodyColor = Color3.fromRGB(40, 40, 46), -- grafite (o quadro verde fica)
		TrimColor = Color3.fromRGB(15, 15, 17),
		AccentColor = Color3.fromRGB(57, 230, 0),
		GlassColor = Color3.fromRGB(20, 22, 26),
		GlassTransparency = 0.3,
		RimColor = Color3.fromRGB(30, 30, 32),
		CaliperColor = Color3.fromRGB(200, 30, 35),
		SeatColor = Color3.fromRGB(30, 30, 32),
		Reflectance = 0.12,
		WheelRadius = 1.3,
		Seats = { Driver = Vector3.new(0, 2.6, 0.6), Passenger = Vector3.new(0, 2.9, 2.1), Rear = {} },
		Plates = { Rear = Vector3.new(0, 2.9, 3.97) }, -- placas (Marco 7.5): centro da placa, mesmo jeito dos bancos
		-- mãos no guidom e pés nas pedaleiras (Marco 7.4), em relação ao chão no centro da moto
		Grips = { Left = Vector3.new(-1.15, 3.3, -1.45), Right = Vector3.new(1.15, 3.3, -1.45) },
		Pegs = { Left = Vector3.new(-0.75, 1.9, 1.3), Right = Vector3.new(0.75, 1.9, 1.3) },
		MaxSpeed = 97, -- Marco 10.17: era 92 (+5%)
		ReverseSpeed = 10,
		Acceleration = 44,
		Brake = 80,
		Drag = 14,
		TurnRate = 2.1,
		Hover = 2.0,
		Grip = 10,
		DriftGrip = 2.2,
		DriftHoldGrip = 4,
		DriftTurnBoost = 1.3,
		HandbrakeDecel = 22,
		LeanAngle = 30, -- quanto inclina na curva (graus)
		WheelieAngle = 34, -- grau (Marco 7.2): quanto empina segurando Q / botão Grau (graus)
	},
	RaioRR = {
		EngineSound = "Moto", -- Marco 9.12: perfil de som (GameConfig.Sounds.Profiles)
		Name = "Raio RR",
		Price = 200000, -- Marco 10.15: economia nova (Revisão 2)
		Rarity = "Raro",
		Category = "Motos",
		Moto = true,
		Order = 11,
		Model = "RaioRR",
		Length = 8,
		Width = 2.7,
		BodyColor = Color3.fromRGB(217, 15, 20), -- vermelha
		TrimColor = Color3.fromRGB(15, 15, 17),
		AccentColor = Color3.fromRGB(240, 240, 240),
		GlassColor = Color3.fromRGB(20, 22, 26),
		GlassTransparency = 0.3,
		RimColor = Color3.fromRGB(30, 30, 32),
		CaliperColor = Color3.fromRGB(200, 30, 35),
		SeatColor = Color3.fromRGB(30, 30, 32),
		Reflectance = 0.1,
		WheelRadius = 1.17,
		Seats = { Driver = Vector3.new(0, 2.5, 0.5), Passenger = Vector3.new(0, 2.8, 1.9), Rear = {} },
		Plates = { Rear = Vector3.new(0, 2.9, 2.85) }, -- placas (Marco 7.5): centro da placa, mesmo jeito dos bancos
		Grips = { Left = Vector3.new(-1.15, 3.3, -1.75), Right = Vector3.new(1.15, 3.3, -1.75) },
		Pegs = { Left = Vector3.new(-0.7, 1.9, 1.0), Right = Vector3.new(0.7, 1.9, 1.0) },
		MaxSpeed = 92, -- Marco 10.17: era 88 (+5%)
		ReverseSpeed = 10,
		Acceleration = 39,
		Brake = 80,
		Drag = 14,
		TurnRate = 2.1,
		Hover = 2.0,
		Grip = 10,
		DriftGrip = 2.2,
		DriftHoldGrip = 4,
		DriftTurnBoost = 1.3,
		HandbrakeDecel = 22,
		LeanAngle = 28,
		WheelieAngle = 30,
	},
	-- Veículos de serviço: só para quem tem o emprego (Service). Não aparecem na garagem do
	-- jogo publicado; no Studio aparecem na aba "Serviço" para testar (Garage.ServiceInStudio).
	-- Têm as cores da empresa (não podem ser pintados).
	-- Van da Sherlex (Marco 7; modelo 3D no 7.1): sai na placa "Pegar van" da Sherlex.
	Van = {
		EngineSound = "Engine", -- Marco 9.10: ronco pela força do carro (GameConfig.Sounds)
		Name = "Van Sherlex",
		Order = 90,
		Category = "Serviço",
		Service = "Entregador", -- emprego que libera a van
		Model = "SherlexVan",
		Length = 20,
		Width = 7.8,
		BodyColor = Color3.fromRGB(245, 245, 242), -- branca com faixa laranja
		TrimColor = Color3.fromRGB(240, 140, 30),
		AccentColor = Color3.fromRGB(240, 140, 30),
		GlassColor = Color3.fromRGB(20, 24, 30),
		GlassTransparency = 0.3,
		RimColor = Color3.fromRGB(190, 190, 195),
		CaliperColor = Color3.fromRGB(60, 60, 66),
		SeatColor = Color3.fromRGB(45, 45, 48),
		Reflectance = 0.03,
		WheelRadius = 1.41,
		Seats = { Driver = Vector3.new(-1.6, 2.6, -5.6), Passenger = Vector3.new(1.6, 2.6, -5.6), Rear = {} },
		Plates = { Front = Vector3.new(0, 2.3, -10.02), Rear = Vector3.new(0, 2.8, 9.87) }, -- placas (Marco 7.5): centro da placa, mesmo jeito dos bancos
		Roof = 7.9, -- altura do teto por dentro: quem é alto inclina o encosto (Marco 7.5) para a cabeça não sair
		MaxSpeed = 105, -- Marco 10.17: era 55
		ReverseSpeed = 16,
		Acceleration = 34,
		Brake = 55,
		Drag = 12,
		TurnRate = 1.5,
		Hover = 2.0,
		Grip = 10,
		DriftGrip = 3.5, -- van quase não derrapa
		DriftHoldGrip = 5,
		DriftTurnBoost = 1.1,
		HandbrakeDecel = 18,
		-- Marco 7.3: faixas, letreiros e vidros agora vêm desenhados no próprio modelo 3D (tools/carros)
	},
	-- Caminhão do Correio: amarelo e azul. Emprego "Carteiro" ainda não existe (só no Studio).
	Correio = {
		Name = "Caminhão do Correio",
		Order = 91,
		Category = "Serviço",
		Service = "Carteiro", -- PROVISÓRIO: emprego futuro
		Model = "CorreioTruck",
		EngineSound = "TruckEngine", -- Marco 9.9: som de motor de caminhão (GameConfig.Sounds)
		Length = 26,
		Width = 7.4,
		BodyColor = Color3.fromRGB(250, 199, 13), -- amarelo
		TrimColor = Color3.fromRGB(30, 60, 140),
		AccentColor = Color3.fromRGB(30, 60, 140),
		GlassColor = Color3.fromRGB(20, 26, 34),
		GlassTransparency = 0.2,
		RimColor = Color3.fromRGB(150, 150, 150),
		CaliperColor = Color3.fromRGB(60, 60, 66),
		SeatColor = Color3.fromRGB(45, 45, 48),
		Reflectance = 0.03,
		WheelRadius = 1.47,
		Seats = { Driver = Vector3.new(-1.7, 4.8, -10.5), Passenger = Vector3.new(1.7, 4.8, -10.5), Rear = {} },
		Plates = { Front = Vector3.new(0, 2.9, -13.12), Rear = Vector3.new(0, 1.9, 12.13) }, -- placas (Marco 7.5): centro da placa, mesmo jeito dos bancos
		Roof = 9.45, -- altura do teto por dentro: quem é alto inclina o encosto (Marco 7.5) para a cabeça não sair
		MaxSpeed = 105, -- Marco 10.17: era 48
		ReverseSpeed = 14,
		Acceleration = 30,
		Brake = 50,
		Drag = 11,
		TurnRate = 1.25,
		Hover = 2.0,
		Grip = 11,
		DriftGrip = 4.5,
		DriftHoldGrip = 6,
		DriftTurnBoost = 1.05,
		HandbrakeDecel = 18,
		-- Marco 7.3: faixas, letreiros e vidros agora vêm desenhados no próprio modelo 3D (tools/carros)
	},
	-- Viatura: branca com faixa azul-escura, POLÍCIA nas portas e giroflex piscando.
	-- Emprego "Policial" chega no Marco 8 (só no Studio por enquanto).
	Viatura = {
		EngineSound = "Viatura", -- Marco 9.12: perfil de som (GameConfig.Sounds.Profiles)
		Name = "Viatura",
		Order = 92,
		Category = "Serviço",
		Service = "Policial", -- PROVISÓRIO: emprego do Marco 8
		Model = "Viatura",
		ArchLiner = 0.25, -- Marco 8.1: caixa de roda escura (o arco da lataria fica bem acima do pneu)
		Length = 18,
		Width = 7.6,
		BodyColor = Color3.fromRGB(242, 242, 245),
		TrimColor = Color3.fromRGB(15, 30, 70),
		AccentColor = Color3.fromRGB(15, 30, 70),
		GlassColor = Color3.fromRGB(10, 11, 13),
		GlassTransparency = 0.15,
		RimColor = Color3.fromRGB(30, 30, 32),
		CaliperColor = Color3.fromRGB(60, 60, 66),
		SeatColor = Color3.fromRGB(35, 35, 38),
		Reflectance = 0.06,
		WheelRadius = 1.35,
		Seats = { Driver = Vector3.new(-1.45, 2.0, -0.8), Passenger = Vector3.new(1.45, 2.0, -0.8), Rear = { Vector3.new(-1.4, 2.0, 2.4), Vector3.new(1.4, 2.0, 2.4) } },
		Plates = { Front = Vector3.new(0, 1.8, -8.84), Rear = Vector3.new(0, 2.75, 8.95) }, -- placas (Marco 7.5): centro da placa, mesmo jeito dos bancos
		Roof = 5.55, -- altura do teto por dentro: quem é alto inclina o encosto (Marco 7.5) para a cabeça não sair
		MaxSpeed = 115, -- Marco 10.17: era 80
		ReverseSpeed = 20,
		Acceleration = 43,
		Brake = 70,
		Drag = 13,
		TurnRate = 1.75,
		Hover = 2.0,
		Grip = 9.5,
		DriftGrip = 1.4,
		DriftHoldGrip = 3,
		DriftTurnBoost = 1.4,
		HandbrakeDecel = 18,
		Siren = true, -- luzes vermelha e azul piscam com o carro andando
		-- Marco 7.3: faixas, letreiros e vidros agora vêm desenhados no próprio modelo 3D (tools/carros)
	},
	-- Táxi da LXR Táxis: amarelo com placa TÁXI no teto. Marco 9: sai na garagem da LXR Táxis, só para o Taxista.
	Taxi = {
		EngineSound = "Engine", -- Marco 9.10: ronco pela força do carro (GameConfig.Sounds)
		Name = "Táxi LXR",
		Order = 93,
		Category = "Serviço",
		Service = "Taxista", -- Marco 9: emprego Taxista
		Model = "Taxi",
		Length = 17,
		Width = 6.9,
		BodyColor = Color3.fromRGB(250, 204, 20),
		TrimColor = Color3.fromRGB(20, 20, 22),
		AccentColor = Color3.fromRGB(20, 20, 22),
		GlassColor = Color3.fromRGB(10, 11, 13),
		GlassTransparency = 0.2,
		RimColor = Color3.fromRGB(185, 188, 192),
		CaliperColor = Color3.fromRGB(60, 60, 66),
		SeatColor = Color3.fromRGB(35, 35, 38),
		Reflectance = 0.05,
		WheelRadius = 1.1,
		Seats = { Driver = Vector3.new(-1.35, 1.3, -0.6), Passenger = Vector3.new(1.35, 1.3, -0.6), Rear = { Vector3.new(-1.15, 1.3, 2.0), Vector3.new(1.15, 1.3, 2.0) } },
		Plates = { Front = Vector3.new(0, 1.8, -8.34), Rear = Vector3.new(0, 2.55, 8.06) }, -- placas (Marco 7.5): centro da placa, mesmo jeito dos bancos
		Roof = 4.74, -- altura do teto por dentro: quem é alto inclina o encosto (Marco 7.5) para a cabeça não sair
		MaxSpeed = 80, -- Marco 10.17: era 62 (108); 10.19b: o Luís achou rápido demais
		ReverseSpeed = 18,
		Acceleration = 37,
		Brake = 60,
		Drag = 12,
		TurnRate = 1.7,
		Hover = 2.0,
		Grip = 9,
		DriftGrip = 1.8,
		DriftHoldGrip = 3.8,
		DriftTurnBoost = 1.2,
		HandbrakeDecel = 17,
		-- Marco 7.3: faixas, letreiros e vidros agora vêm desenhados no próprio modelo 3D (tools/carros)
	},
	-- Marco 9: ônibus do Motorista de ônibus. Marco 9.7: modelo LXR do Luís (tools/busprep.py ->
	-- ServerStorage > CarModels > OnibusLXR, com a textura dele; bancos tirados do modelo). Sem o
	-- modelo, é montado de peças (CarBuilder, Shape = "Bus"). Lento e pesado de propósito.
	-- O modelo é "mão inglesa": motorista à direita e portas à esquerda (DoorSide = -1).
	Onibus = {
		Name = "Ônibus LXR",
		Model = "OnibusLXR",
		EngineSound = "TruckEngine", -- Marco 9.9: som de motor de caminhão (GameConfig.Sounds)
		KeepTextures = true, -- a pintura vem da textura do modelo
		ShowArms = true, -- janelas grandes: os braços de quem senta aparecem
		NoFloor = true, -- o modelo já tem piso por dentro
		DoorSide = -1, -- portas do lado esquerdo (BusService); o ônibus de peças tem as portas à direita
		DoorZ = { Front = -13.9, Middle = 2.1 }, -- centro das portas (frente = -Z)
		PartsWidth = 9.6, -- largura do ônibus de peças
		Roof = 7.6,
		Order = 94,
		Category = "Serviço",
		Service = "Motorista",
		Shape = "Bus",
		SignText = "UM TIJO • CIRCULAR", -- letreiro da frente
		SideText = GameConfig.Places.Onibus,
		Length = 34,
		Width = 7.8,
		BodyColor = Color3.fromRGB(245, 245, 240),
		TrimColor = Color3.fromRGB(28, 28, 32),
		AccentColor = Color3.fromRGB(30, 130, 80), -- faixa verde
		GlassColor = Color3.fromRGB(35, 45, 55),
		RimColor = Color3.fromRGB(200, 200, 205),
		SeatColor = Color3.fromRGB(30, 80, 140),
		Reflectance = 0.03,
		WheelRadius = 1.38,
		Seats = {
			Driver = Vector3.new(1.6, 2.5, -13.62), -- Marco 9.8: mais para dentro (a mão saía pela janela)
			Passenger = Vector3.new(2.54, 1.97, -2.71),
			Rear = {
				Vector3.new(-2.73, 1.97, -2.71), Vector3.new(-1.41, 1.97, -2.71), Vector3.new(1.23, 1.97, -2.71), Vector3.new(-2.73, 1.97, -0.61),
				Vector3.new(-1.41, 1.97, -0.61), Vector3.new(1.23, 1.97, -0.61), Vector3.new(2.54, 1.97, -0.61), Vector3.new(1.23, 1.97, 1.34),
				Vector3.new(2.54, 1.97, 1.34), Vector3.new(1.23, 1.97, 3.45), Vector3.new(2.54, 1.97, 3.45), Vector3.new(-2.73, 2.61, 5.51),
				Vector3.new(-1.41, 2.61, 5.51), Vector3.new(1.23, 2.61, 5.51), Vector3.new(2.54, 2.61, 5.51), Vector3.new(-2.73, 3.15, 7.35),
				Vector3.new(-1.41, 3.15, 7.35), Vector3.new(1.23, 3.15, 7.35), Vector3.new(2.54, 3.15, 7.35), Vector3.new(-2.73, 3.15, 9.56),
				Vector3.new(-1.41, 3.15, 9.56), Vector3.new(1.23, 3.15, 9.56), Vector3.new(2.54, 3.15, 9.56), Vector3.new(-2.73, 3.88, 11.57),
				Vector3.new(-1.41, 3.88, 11.57), Vector3.new(1.23, 3.88, 11.57), Vector3.new(2.54, 3.88, 11.57), Vector3.new(-2.73, 3.88, 13.78),
				Vector3.new(-1.41, 3.88, 13.78), Vector3.new(1.23, 3.88, 13.78), Vector3.new(2.54, 3.88, 13.78), Vector3.new(-2.73, 3.87, 15.7),
				Vector3.new(-1.41, 3.87, 15.7), Vector3.new(-0.09, 3.87, 15.7), Vector3.new(1.23, 3.87, 15.7), Vector3.new(2.54, 3.87, 15.7),
			},
		},
		Plates = { Front = Vector3.new(0, 1.4, -17.05), Rear = Vector3.new(0, 1.6, 17.05) },
		MaxSpeed = 101, -- Marco 10.17: era 46
		ReverseSpeed = 12,
		Acceleration = 22,
		Brake = 36,
		Drag = 9,
		TurnRate = 1.1,
		Hover = 2.0,
		Grip = 12,
		DriftGrip = 8,
		DriftHoldGrip = 9,
		DriftTurnBoost = 0.3,
		HandbrakeDecel = 14,
	},
	-- Marco 9.9: caminhão de bombeiros (modelo do Luís, tools/firetruckprep.py; cores do Scania que
	-- ele mandou: vermelho, faixa amarela, frente preta, portas de enrolar prateadas). Sai no quartel,
	-- só para o Bombeiro. Giroflex piscando e sirene.
	CaminhaoBombeiros = {
		-- Marco 9.11: modelo "fire_truck" de codexito (CC BY; crédito na lateral de trás, a pedido do
		-- Luís), repintado no estilo do Scania (tools/firetruck2prep.py). Mantém a textura.
		Name = "Caminhão de Bombeiros",
		Model = "CaminhaoBombeiros",
		SirenSound = "FireSiren",
		EngineSound = "TruckEngine", -- Marco 9.9: som de motor de caminhão (GameConfig.Sounds)
		KeepTextures = true,
		NoFloor = true, -- o modelo é fechado (janelas escuras na textura)
		Roof = 6.9,
		Order = 95,
		Category = "Serviço",
		Service = "Bombeiro",
		Length = 26,
		Width = 8.66,
		BodyColor = Color3.fromRGB(200, 16, 46),
		TrimColor = Color3.fromRGB(29, 29, 32),
		AccentColor = Color3.fromRGB(242, 183, 5),
		GlassColor = Color3.fromRGB(12, 14, 18),
		GlassTransparency = 0.1,
		RimColor = Color3.fromRGB(212, 212, 216),
		SeatColor = Color3.fromRGB(35, 35, 38),
		Reflectance = 0.06,
		WheelRadius = 1.37,
		Seats = {
			Driver = Vector3.new(-1.8, 2.6, -9.6),
			Passenger = Vector3.new(1.8, 2.6, -9.6),
			Rear = { Vector3.new(-2.0, 2.6, -6.3), Vector3.new(0, 2.6, -6.3), Vector3.new(2.0, 2.6, -6.3) },
		},
		Plates = { Front = Vector3.new(0, 1.5, -13.05), Rear = Vector3.new(0, 1.6, 11.8) },
		Fillers = {
			-- giroflex em cima da cabine (o do modelo é só desenho na textura)
			{ Name = "GiroflexE", Size = Vector3.new(2.6, 0.35, 0.6), Pos = Vector3.new(-1.5, 7.3, -10.7), Color = Color3.fromRGB(255, 32, 24), Material = Enum.Material.Neon, Siren = "Red" },
			{ Name = "GiroflexD", Size = Vector3.new(2.6, 0.35, 0.6), Pos = Vector3.new(1.5, 7.3, -10.7), Color = Color3.fromRGB(255, 32, 24), Material = Enum.Material.Neon, Siren = "Blue" },
		},
		MaxSpeed = 104, -- Marco 10.17: era 58
		ReverseSpeed = 14,
		Acceleration = 26,
		Brake = 40,
		Drag = 10,
		TurnRate = 1.2,
		Hover = 2.0,
		Grip = 12,
		DriftGrip = 8,
		DriftHoldGrip = 9,
		DriftTurnBoost = 0.3,
		HandbrakeDecel = 16,
		Siren = true,
	},
	-- Marco 10.19: ambulância do SAMU (Sprinter feita pelo Luís; tools/samuprep.py -> modelos/Ambulancia.glb,
	-- importada em ServerStorage > CarModels com o nome "Ambulancia"). Mantém a textura. Sai na
	-- garagem do pronto-socorro do Hospital Progresso, só para o Paramédico. Giroflex e sirene.
	-- Dentro da parte de trás: maca, banco lateral, armários, oxigênio e luz (peças em Fillers).
	Ambulancia = {
		Name = "Ambulância SAMU",
		Model = "Ambulancia",
		SirenSound = "AmbulanceSiren",
		EngineSound = "Engine",
		KeepTextures = true,
		NoFloor = true, -- o modelo já tem o piso da cabine e do baú
		Roof = 7.6,
		Order = 96,
		Category = "Serviço",
		Service = "Paramedico",
		Length = 21,
		Width = 7.5,
		BodyColor = Color3.fromRGB(240, 240, 242),
		TrimColor = Color3.fromRGB(29, 29, 32),
		AccentColor = Color3.fromRGB(200, 20, 30),
		GlassColor = Color3.fromRGB(16, 20, 24),
		GlassTransparency = 0.25,
		RimColor = Color3.fromRGB(190, 192, 196),
		SeatColor = Color3.fromRGB(35, 35, 38),
		Reflectance = 0.05,
		WheelRadius = 1.37,
		Seats = {
			Driver = Vector3.new(-1.6, 3.0, -3.9),
			Passenger = Vector3.new(1.6, 3.0, -3.9),
			-- banco lateral (2 lugares) e a maca
			Rear = { Vector3.new(2.3, 3.9, 3.6), Vector3.new(2.3, 3.9, 6.6), Vector3.new(-1.0, 3.4, 5.2) },
		},
		Fillers = {
			{ Name = "PisoBau", Size = Vector3.new(5.9, 0.1, 12), Pos = Vector3.new(0, 1.66, 3.55), Color = Color3.fromRGB(185, 190, 196) },
			-- maca (lado esquerdo)
			{ Name = "MacaBase", Size = Vector3.new(2.2, 1.0, 6.8), Pos = Vector3.new(-1.0, 2.2, 4.6), Color = Color3.fromRGB(150, 155, 162), Material = Enum.Material.Metal },
			{ Name = "MacaColchao", Size = Vector3.new(2.0, 0.4, 6.6), Pos = Vector3.new(-1.0, 2.9, 4.6), Color = Color3.fromRGB(235, 120, 30) },
			{ Name = "MacaTravesseiro", Size = Vector3.new(1.6, 0.3, 1.2), Pos = Vector3.new(-1.0, 3.25, 7.3), Color = Color3.fromRGB(236, 238, 240) },
			-- banco lateral em cima da caixa de roda (lado direito), com encosto na parede
			{ Name = "BancoBase", Size = Vector3.new(1.4, 1.8, 5.6), Pos = Vector3.new(2.3, 2.5, 5.2), Color = Color3.fromRGB(236, 238, 240) },
			{ Name = "BancoAssento", Size = Vector3.new(1.4, 0.35, 5.6), Pos = Vector3.new(2.3, 3.55, 5.2), Color = Color3.fromRGB(235, 120, 30) },
			{ Name = "BancoEncosto", Size = Vector3.new(0.3, 2.2, 5.6), Pos = Vector3.new(2.85, 4.8, 5.2), Color = Color3.fromRGB(235, 120, 30) },
			-- armários no alto das paredes
			{ Name = "ArmarioAltoE", Size = Vector3.new(0.8, 1.6, 7), Pos = Vector3.new(-2.6, 7.1, 4.8), Color = Color3.fromRGB(236, 238, 240) },
			{ Name = "ArmarioAltoD", Size = Vector3.new(0.8, 1.6, 5.6), Pos = Vector3.new(2.6, 7.1, 5.2), Color = Color3.fromRGB(236, 238, 240) },
			-- armário de remédios encostado na cabine, com a cruz vermelha e o desfibrilador em cima
			{ Name = "ArmarioRemedios", Size = Vector3.new(2.2, 4.8, 1.6), Pos = Vector3.new(1.9, 4.0, -1.6), Color = Color3.fromRGB(236, 238, 240) },
			{ Name = "Cruz", Size = Vector3.new(0.9, 0.3, 0.05), Pos = Vector3.new(1.9, 5.2, -0.78), Color = Color3.fromRGB(210, 25, 35) },
			{ Name = "Cruz", Size = Vector3.new(0.3, 0.9, 0.05), Pos = Vector3.new(1.9, 5.2, -0.78), Color = Color3.fromRGB(210, 25, 35) },
			{ Name = "Desfibrilador", Size = Vector3.new(1.0, 0.6, 0.6), Pos = Vector3.new(1.9, 6.7, -1.6), Color = Color3.fromRGB(240, 190, 20) },
			{ Name = "Oxigenio", Size = Vector3.new(0.6, 3.2, 0.6), Pos = Vector3.new(-2.5, 3.3, -1.7), Color = Color3.fromRGB(40, 150, 70), Material = Enum.Material.Metal },
			{ Name = "LuzBau", Size = Vector3.new(2.0, 0.1, 6), Pos = Vector3.new(0, 8.0, 4), Color = Color3.fromRGB(245, 248, 255), Material = Enum.Material.Neon },
		},
		MaxSpeed = 110, -- Marco 10.19: entre o táxi (108) e a viatura (115); só o Miguan (125) é mais rápido
		ReverseSpeed = 18,
		Acceleration = 36,
		Brake = 55,
		Drag = 11,
		TurnRate = 1.9, -- Marco 10.28: era 1.45, abria demais em alta velocidade
		Hover = 2.0,
		Grip = 11,
		DriftGrip = 8,
		DriftHoldGrip = 9,
		DriftTurnBoost = 0.3,
		HandbrakeDecel = 16,
		Siren = true,
	},
}
-- Garagens (Marco 6.3): guaritas no mapa onde o jogador retira carro ou bike.
-- Marco 7: carros comprados com o dinheiro do jogo (salvos no perfil, data.ownedCars).
-- FreeInStudio = no Studio todos os carros ficam liberados para testar (no jogo publicado, não).
-- Para testar a compra no Studio, mude para false.
GameConfig.Garage = {
	FreeInStudio = true,
	-- Marco 7.1: no Studio a garagem também mostra os veículos de serviço (aba "Serviço") para
	-- testar viatura, táxi e caminhão antes dos empregos existirem. No jogo publicado, não.
	ServiceInStudio = true,
	UseDistance = 16, -- distância máxima da guarita para usar o menu
}
-- Loja de pintura (Marco 6.4): fica longe da cidade, no fim de uma estradinha depois do anel
-- externo. PROVISÓRIO: de graça para testar (depois vai ser paga; preço a decidir).
-- Marco 9.7: garagem da Um Tijo (ônibus) numa área nova, fora da cidade: avenida que sai do anel
-- externo na direção da rua Dir e o terminal no fim dela (o Luís quer a cidade crescendo para fora)
-- Marco 9.9: quartel do Corpo de Bombeiros (FireStationBuilder), no fim da sua avenida, fora da cidade
-- Marco 9.9: sons dos veículos. Áudios públicos da Creator Store (PROVISÓRIOS: para trocar, cole
-- outro número aqui; aceita 123456 ou "rbxassetid://123456"). Volume e distância ficam embaixo.
GameConfig.Sounds = {
	-- Marco 9.10: cada carro usa o ronco da sua força (EngineSound no carro). O tom sobe com a
	-- velocidade; EnginePitch muda o tom de base de cada tipo.
	Engine = 143509179, -- carro comum (Mengeot, Polux, Ranchera, táxi, van)
	SportEngine = 338224404, -- esportivo V8, mais forte (L5, R18, Fúria, viatura)
	MotoEngine = 338224404, -- motos: o mesmo V8, mais agudo (EnginePitch)
	TruckEngine = 138696135, -- caminhão/ônibus
	-- Marco 9.12: sons que o Luís escolheu. Cada perfil tem o motor parado (Idle) e acelerando
	-- (Accel); o jogo mistura os dois. O carro usa o perfil pelo EngineSound dele.
	Profiles = {
		Dodge = { Idle = 126560668123605, Accel = 133233759728167, Volume = 0.22, Pitch = 0.92 }, -- Fúria
		Viatura = { Idle = 18987334731, Accel = 111337899640001, Volume = 0.25 }, -- viatura da PM
		M5 = { Idle = 3875244806, Accel = 3875246402, Volume = 0.25 }, -- LXR L5
		R18 = { Idle = 134438723401054, Accel = 78314592776592, Volume = 0.25 },
		Moto = { Idle = 131390517646051, Accel = 82915762361351, Volume = 0.22 }, -- Shinobi e Raio
		E36 = { Idle = 76422393168466, Accel = 105516298760152, Volume = 0.22 }, -- Marco 9.16: BMW dos admins (E34)
	},
	EngineMaster = 0.8, -- volume geral dos motores (0.5 = metade)
	Turbo = 91287040710006, -- "psssh" do turbo (carros com Turbo = true)
	TurboVolume = 0.35,
	EnginePitch = { Engine = 1, SportEngine = 0.9, MotoEngine = 1.45, TruckEngine = 0.85 },
	EngineVolume = { Engine = 0.35, SportEngine = 0.6, MotoEngine = 0.5, TruckEngine = 0.5 },
	Siren = 4832422661, -- sirene da viatura (yelp)
	AmbulanceSiren = 1101154144, -- Marco 10.19: sirene da ambulância. PROVISÓRIO: mesma do bombeiro até o Luís escolher
	FireSiren = 1101154144, -- sirene do caminhão de bombeiros (wail). PROVISÓRIO: o Luís pode escolher
	Backfire = 1618282056, -- pipoco (pops and bangs) que o Luís escolheu: Fúria e R18
	Backfire2 = 110871999631951, -- outro pipoco: LXR L5 (BackfireSound = "Backfire2")
	Backfire3 = 82620995969774, -- Marco 9.16: pops and bangs da BMW dos admins (giro alto)
	SirenVolume = 0.6,
	BackfireVolume = 0.18,
	MaxDistance = 140, -- até onde os outros jogadores escutam
	SirenKey = Enum.KeyCode.G, -- liga/desliga a sirene (viatura e bombeiros)
}
-- Marco 9.16: quem é admin (carros da aba "Admin"). O dono do jogo (ou do grupo) já é admin; põe
-- aqui o UserId de mais alguém. InStudio = true: no Studio todo mundo é admin (para testar).
GameConfig.Admins = {
	UserIds = {},
	InStudio = true,
	GroupRank = 255,
}
-- Marco 9.12: sons de ambiente da cidade (AmbienceController). Id = 0: sem som. Volume baixinho
-- de propósito (0 a 1); Master muda todos juntos. Every = de quanto em quanto tempo (segundos,
-- sorteado entre os dois números) toca um latido ou barulho de obra ao longe.
GameConfig.Ambience = {
	Master = 1,
	Trafego = { Id = 0, Volume = 0.12 }, -- trânsito de fundo (mais forte no centro)
	Passaros = { Id = 0, Volume = 0.12 }, -- passarinhos (mais forte longe do centro e no parque)
	Parque = { Id = 0, Volume = 0.15 }, -- crianças brincando perto da MigueLândia
	Chafariz = { Id = 0, Volume = 0.2 }, -- água dos chafarizes (som 3D)
	Cachorros = { Id = 0, Volume = 0.2, Every = { 25, 70 }, MaxSeconds = 6 }, -- latidos ao longe
	Obra = { Id = 0, Volume = 0.12, Every = { 45, 100 }, MaxSeconds = 12 }, -- obra ao longe
}
GameConfig.FireStation = {
	Dir = 7, -- rua (comercial) de onde sai a avenida
	RoadLength = 240,
	RoadName = "Avenida dos Bombeiros", -- PROVISÓRIO
	UnitName = "Little Little Kinder", -- "UNIDADE ..." na marquise
}
GameConfig.BusTerminal = {
	Dir = 3, -- rua (comercial) de onde sai a avenida
	RoadLength = 420, -- Marco 9.8: bem mais longe da cidade (era 160)
	RoadName = "Avenida do Terminal", -- PROVISÓRIO
}

-- Marco 10: expansão da cidade. O desenho das estradas fica no CityRoads (Shared), que o
-- MapBuilder, o mapa (M) e o GPS leem: mudar aqui muda os três juntos.
-- Rodovia LK-101: pista dupla que continua a Avenida das Palmeiras (rua 1) para o norte até o
-- Trevo Norte. Rodoanel LK-100: anel em volta do mapa inteiro; nesta versão só o trecho norte
-- (Arc graus para cada lado do Trevo Norte), o resto vem nos próximos marcos.
GameConfig.Rodovia = {
	Name = "Rodovia do Horizonte",
	Code = "LK-101",
	RingName = "Rodoanel",
	RingCode = "LK-100",
	RingRadius = 4200, -- raio do Rodoanel (centro = praça)
	RingArc = 60, -- trecho pronto: 60° para cada lado do norte
	CarriageWidth = 26, -- cada pista (2 faixas + acostamento)
	Median = 10, -- canteiro do meio
	TrevoName = "Trevo Norte",
	TrevoRadius = 58,
	ExitZ = -1150, -- cruzamento das saídas (Vale e Serra)
	ExitLength = 1400,
	ValeName = "Estrada do Vale",
	ValeSoon = "Distrito Industrial: em breve",
	SerraName = "Estrada da Serra",
	SerraSoon = "Serra: em breve",
	PostoName = "Posto Estrela", -- posto de gasolina (enfeite) na beira da rodovia
	PostoZ = -2600,
}

-- Marco 10: Avenida do Progresso (sai da rua 5, para o sul) até uma rotatória com 3 estradas
-- para áreas futuras.
GameConfig.Progresso = {
	Name = "Avenida do Progresso",
	EndZ = 1500,
	RoundaboutName = "Rotatória do Progresso",
	RoundaboutRadius = 40,
	BranchLength = 1300,
	Branches = {
		{ Name = "Estrada Leste", Dir = Vector3.new(1, 0, 0), Soon = "Bairro Leste: em breve" },
		{ Name = "Estrada Oeste", Dir = Vector3.new(-1, 0, 0), Soon = "Bairro Oeste: em breve" },
		{ Name = "Estrada Sul", Dir = Vector3.new(0, 0, 1), Soon = nil }, -- Marco 10.31: leva à Costa do Sol
	},
	-- Marco 10.4: Jardim Progresso, bairro residencial dos dois lados da avenida, entre a cidade e
	-- a rotatória (ProgressoBuilder). Hospital, praça, escola, casas variadas, 4 casas modernas e
	-- 2 prédios. Nomes PROVISÓRIOS. Ruas: From -> To (Y = 0).
	District = {
		Name = "Jardim Progresso",
		Seed = 2024, -- sorteio próprio (não mexe no resto da cidade)
		Streets = {
			{ Name = "Rua das Acácias", From = Vector3.new(-300, 0, 860), To = Vector3.new(900, 0, 860) },
			{ Name = "Rua dos Ipês", From = Vector3.new(-900, 0, 1100), To = Vector3.new(900, 0, 1100) },
			{ Name = "Rua das Paineiras", From = Vector3.new(-900, 0, 1320), To = Vector3.new(900, 0, 1320) },
			{ Name = "Rua da Saúde", From = Vector3.new(450, 0, 860), To = Vector3.new(450, 0, 1540) },
			{ Name = "Rua Bela Vista", From = Vector3.new(900, 0, 860), To = Vector3.new(900, 0, 1540) },
			{ Name = "Rua do Sabiá", From = Vector3.new(-450, 0, 1100), To = Vector3.new(-450, 0, 1540) },
			{ Name = "Rua do Bem-te-vi", From = Vector3.new(-900, 0, 1100), To = Vector3.new(-900, 0, 1540) },
		},
		HospitalName = "Hospital Progresso",
		SchoolName = "Escola Municipal Progresso",
		PlazaName = "Praça do Progresso",
		Towers = {
			{ Name = "Residencial Ipê", Floors = 9, Style = "sacadas", Wall = Color3.fromRGB(236, 214, 190), Accent = Color3.fromRGB(255, 170, 90) },
			{ Name = "Edifício Paineiras", Floors = 11, Style = "sacadas", Wall = Color3.fromRGB(214, 226, 232), Accent = Color3.fromRGB(110, 190, 255) },
		},
	},
}

-- Marco 10: Bairro Horizonte, a região de luxo no fim da Rodovia, depois do Trevo Norte
-- (HorizonteBuilder). Nomes e preços PROVISÓRIOS (preços das moradias ficam no HomeConfig).
GameConfig.Horizonte = {
	Name = "Bairro Horizonte",
	BoulevardName = "Boulevard do Horizonte",
	Streets = { "Rua das Orquídeas", "Rua das Magnólias", "Rua das Hortênsias" },
	WestName = "Rua do Poente",
	EastName = "Rua do Nascente",
	LoopName = "Alameda dos Jardins",
	CondoName = "Jardins do Horizonte",
	PlazaName = "Praça do Horizonte",
	ParkName = "Parque dos Jardins",
	Seed = 1010, -- sorteio próprio do bairro (não mexe nas casas e árvores do resto da cidade)
	-- Prédios do boulevard (12 lotes: repete a lista). Style "vidro" = fachada espelhada;
	-- "sacadas" = janelas com varandas de vidro.
	Towers = {
		{ Name = "Edifício Aurora", Floors = 12, Style = "sacadas", Wall = Color3.fromRGB(238, 232, 220), Accent = Color3.fromRGB(255, 180, 90) },
		{ Name = "Torre Safira", Floors = 18, Style = "vidro", Glass = Color3.fromRGB(55, 95, 150), Accent = Color3.fromRGB(80, 170, 255), Helipad = true },
		{ Name = "Residencial Mirante", Floors = 11, Style = "sacadas", Wall = Color3.fromRGB(205, 210, 215), Accent = Color3.fromRGB(120, 230, 170) },
		{ Name = "Edifício Atlântico", Floors = 15, Style = "vidro", Glass = Color3.fromRGB(60, 120, 125), Accent = Color3.fromRGB(240, 240, 255) },
		{ Name = "Torre Esmeralda", Floors = 20, Style = "vidro", Glass = Color3.fromRGB(50, 110, 85), Accent = Color3.fromRGB(110, 240, 160), Helipad = true },
		{ Name = "Edifício Solar", Floors = 10, Style = "sacadas", Wall = Color3.fromRGB(240, 222, 196), Accent = Color3.fromRGB(255, 210, 90) },
		{ Name = "Residencial Brisa", Floors = 13, Style = "sacadas", Wall = Color3.fromRGB(226, 236, 240), Accent = Color3.fromRGB(120, 200, 255) },
		{ Name = "Torre Ônix", Floors = 22, Style = "vidro", Glass = Color3.fromRGB(35, 38, 48), Accent = Color3.fromRGB(255, 120, 200), Helipad = true },
		{ Name = "Edifício Coral", Floors = 12, Style = "sacadas", Wall = Color3.fromRGB(245, 215, 200), Accent = Color3.fromRGB(255, 140, 120) },
		{ Name = "Torre Cristal", Floors = 17, Style = "vidro", Glass = Color3.fromRGB(110, 160, 200), Accent = Color3.fromRGB(200, 240, 255) },
		{ Name = "Residencial Aurora Boreal", Floors = 14, Style = "sacadas", Wall = Color3.fromRGB(215, 220, 235), Accent = Color3.fromRGB(170, 140, 255) },
		{ Name = "Torre Horizonte", Floors = 24, Style = "vidro", Glass = Color3.fromRGB(70, 90, 120), Accent = Color3.fromRGB(255, 200, 120), Helipad = true },
	},
	ApartmentsPerTower = 6, -- elevadores no fundo do saguão (mais o da cobertura, na lateral)
}

-- Marco 10.1: as 3 comunidades (favelas) e as gangues. Nomes, chefes e lugares decididos pelo
-- Luís (2026-10-28); cores, tamanhos e o resto escolhidos pelo Claude (PROVISÓRIOS).
-- Center = meio da favela (Y = 0); Size = largura (X) e fundo (Z). Road = estrada de acesso
-- (vai no CityRoads: mapa e GPS mostram). Cada favela tem sorteio próprio (Seed).
-- Entrar numa gangue: conversar com o chefe (escondido na favela). Quem entra ganha um barraco
-- lá e perde só a casinha da Vila Esperança. Policial não pode ser de gangue.
GameConfig.Gangs = {
	Order = { "CDA", "TDE", "CDS" },
	Title = "Chefe da gangue", -- subtítulo embaixo do nome do chefe
	TalkDistance = 12,
	ShacksPerFavela = 30, -- barracos que dá para morar (os outros são só de enfeite)
	List = {
		CDA = {
			Name = "Comando Andrômeda", Short = "CDA", Chief = "Kauã Nébula",
			Community = "Morro da Nebulosa", Style = "morro",
			Color = Color3.fromRGB(135, 75, 210), Accent = Color3.fromRGB(240, 130, 225),
			-- o morro fica no lado leste (HillOffset); a oeste, a baixada com o campinho
			Center = Vector3.new(-950, 0, -1420), Size = Vector2.new(560, 380), Seed = 3101, HillOffset = 60,
			Road = { Name = "Ladeira da Nebulosa", Points = { Vector3.new(-890, 0, -1150), Vector3.new(-890, 0, -1214) } },
		},
		TDE = {
			Name = "Tropa do Eclipse", Short = "TDE", Chief = "Ryan Eclipse",
			Community = "Complexo da Lua Negra", Style = "complexo",
			Color = Color3.fromRGB(40, 40, 48), Accent = Color3.fromRGB(250, 140, 40),
			Center = Vector3.new(800, 0, 1840), Size = Vector2.new(560, 440), Seed = 3202,
			Road = { Name = "Rua da Lua Negra", Points = { Vector3.new(800, 0, 1540), Vector3.new(800, 0, 1604) } },
		},
		CDS = {
			Name = "Cartel Solaris", Short = "CDS", Chief = "Davi Sol Negro",
			Community = "Favela Horizonte Solar", Style = "solar",
			Color = Color3.fromRGB(245, 190, 30), Accent = Color3.fromRGB(220, 60, 40),
			Center = Vector3.new(2450, 0, -2650), Size = Vector2.new(520, 460), Seed = 3303,
			Road = { Name = "Estrada do Sol", Points = { Vector3.new(1150, 0, -1150), Vector3.new(1150, 0, -1700), Vector3.new(2450, 0, -2250), Vector3.new(2450, 0, -2404) } },
		},
	},
	MusicId = 0, -- som do paredão (0 = sem música; o botão só acende as luzes)
	DrinkPrice = 20, -- refri no bar da favela
}

-- Marco 10.5: crimes do Ladrão (quem é de gangue) e o trabalho do Policial.
-- Decidido pelo Luís: assaltar lojinhas e caixas eletrônicos espalhados, alarme que chama a polícia,
-- estrelas de procurado, lista de procurados na Base da PM, chamados de NPC só para o policial não
-- ficar parado, algema e taser até chegarem as armas dele. TODOS os números são PROVISÓRIOS.
-- Marco 10.5: som da Saveira (cole aqui o ID da música; 0 = só as luzes piscam). Volume baixo.
GameConfig.CarSound = { MusicId = 0, Volume = 0.35, MaxDistance = 90 }

GameConfig.Crime = {
	-- Lojas de conveniência: o térreo do prédio mais perto de cada ponto vira uma loja (dá para entrar)
	StoreNames = { "Conveniência 24h", "Mercadinho Kinder", "Conveniência Lua", "Empório da Esquina", "Mini Mercado Sol", "Conveniência Progresso" },
	StoreTargets = {
		Vector3.new(250, 0, 37), Vector3.new(-37, 0, 250), Vector3.new(-37, 0, -250),
		Vector3.new(-250, 0, 37), Vector3.new(121, 0, 238), Vector3.new(-37, 0, 1015),
	},
	-- Caixas eletrônicos: na frente do prédio mais perto de cada ponto (e um no Posto Estrela)
	AtmTargets = {
		Vector3.new(156, 0, -37), Vector3.new(-37, 0, 460), Vector3.new(37, 0, -500), Vector3.new(-450, 0, -37),
		Vector3.new(547, 0, 37), Vector3.new(-303, 0, 162), Vector3.new(111, 0, 324), Vector3.new(-37, 0, 734),
		Vector3.new(-37, 0, 1450), Vector3.new(82, 0, -255),
	},
	AtmBrand = "LLC", -- marca no caixa eletrônico (pedido do Luís)
	AtmHeight = 5.8, -- altura do caixa eletrônico (studs)
	AtmColors = { -- cores do caixa (as mesmas que o Banco Nacional vai usar)
		Corpo = Color3.fromRGB(30, 45, 90),
		Detalhe = Color3.fromRGB(230, 180, 40),
		Metal = Color3.fromRGB(190, 195, 200),
		Tela = Color3.fromRGB(15, 20, 30),
		Painel = Color3.fromRGB(20, 30, 60),
	},

	-- Assalto à loja: segurar E no caixa e ficar perto até acabar
	StoreTime = 40, -- segundos (Marco 10.15: era 20)
	StoreAlarmDelay = 10, -- o alarme toca 10 s depois de começar
	StoreReward = { 3000, 8500 }, -- Marco 10.15: economia nova
	StorePoints = 12, -- pontos de procurado
	StoreRange = 16, -- distância máxima do caixa durante o assalto
	-- Caixa eletrônico: minijogo de 3 etapas; o alarme toca na hora
	AtmSteps = 3,
	AtmStepMin = 6, -- segundos mínimos entre uma etapa e outra (o servidor confere)
	AtmReward = { 6000, 10000 },
	AtmPoints = 15,
	AtmRange = 10,
	Cooldown = 300, -- a loja/o caixa fica fechado 5 min depois de roubado

	-- Procurado: pontos -> estrelas (1 a 5). Sem crime por DecayAfter segundos, perde 1 ponto a cada DecayEvery.
	StarPoints = { 10, 25, 45, 70, 100 },
	DecayAfter = 120,
	DecayEvery = 8,
	ListStars = 3, -- a partir de 3 estrelas o nome vai para a Lista de Procurados
	BountyPerStar = 1300, -- recompensa para quem prende
	ShowStarsToPolice = true, -- estrelinhas em cima da cabeça do procurado, só o Policial vê

	-- Polícia
	CallLife = 240, -- um chamado some depois de 4 min
	CallArrive = 45, -- chegou no chamado (studs)
	CallPay = 700, -- primeiro policial que chega no alarme
	ArrestPay = 2000, -- por prender (mais a recompensa por estrela)
	KillPoints = 20, -- matar alguém dá pontos de procurado (matar policial: o dobro)
	TaserRange = 30,
	TaserCooldown = 3,
	TaserStun = 4, -- segundos atordoado
	CuffRange = 8,
	-- Marco 10.6: revista (pedido do Luís). O policial segura G perto da pessoa; leva de 7 a 10 s
	-- (se a pessoa se afastar, cancela). Depois ele vê a mochila, a munição e o dinheiro sujo e pode
	-- apreender o que é proibido (armas que não são do emprego e o que estiver em Illegal).
	FriskTime = { 7, 10 },
	FriskRange = 8,
	FriskOpen = 90, -- segundos que o painel da revista vale para apreender
	Illegal = {}, -- itens proibidos que não são armas (ex.: Illegal.Droga = true), para o futuro
	SentenceBase = 60, -- pena = base + por estrela (segundos)
	SentencePerStar = 60,
	-- Chamados de NPC: só quando não tem crime de jogador há NpcQuiet segundos
	NpcQuiet = 180,
	NpcPay = { 500, 850 },
	NpcCalls = {
		{ title = "Furto de bicicleta", say = "Foi mal, foi mal! Eu devolvo a bike!" },
		{ title = "Pichação no muro", say = "Era só um desenho, seu guarda..." },
		{ title = "Briga na rua", say = "Ele que começou!" },
		{ title = "Suspeito em atitude estranha", say = "Eu só tava esperando o ônibus!" },
		{ title = "Barulho alto na rua", say = "Já vou abaixar o som!" },
	},
}

-- Marco 10.8 + 10.9: joalheria do Bairro Horizonte (no lote "novidade" da Rua das Magnólias) e o
-- assalto (regras nossas, nada copiado de jogo). Tudo PROVISÓRIO. Marco 10.9: loja maior (área
-- restrita com sala de segurança, escritório do gerente, estoque e o COFRE), assalto mais difícil e
-- fuga de verdade:
--   1. Reconhecimento (precisa para o plano silencioso): no catálogo da entrada, achar com o olhar
--      as 3 câmeras, o leitor de cartão da porta dos funcionários, o quadro de energia (beco) e o
--      duto do telhado. Vale para a gangue toda por ReconValid segundos.
--   2. SILENCIOSO: gás do sono no duto do telhado. Os funcionários dormem por GasDuration segundos
--      (quando acordam, o alarme toca). O medidor de ALERTA sobe com barulho (vitrine quebrada, erro
--      no minigame, câmera vendo a gangue, arrombar porta); cheio = alarme.
--      BARULHENTO: arma na mão + "Anunciar o assalto": alarme na hora. Renda o segurança mirando nele
--      (AimTime s) em até GuardReact s, senão ele aperta o botão de pânico (a porta de aço fecha em
--      PanicLockdown s e todo mundo ganha PanicPoints de procurado).
--   3. Vitrines e gavetas: minigame de mira (aperte E / clique / toque no AGORA quando o ponteiro
--      estiver na faixa verde). Vitrine blindada e o cofre são mais difíceis.
--   4. Área restrita: o cartão está com o gerente (dormindo ou rendido). Sem cartão dá para arrombar
--      a porta (DoorForceTime s, barulho). O código do cofre: na gaveta do escritório (OfficeTime s)
--      ou hackeando o terminal da sala de segurança (que também desliga câmeras e lasers por
--      HackTime s e segura a trava da saída por ExitOverride s). Sem código: furadeira (VaultDrill s,
--      alarme na hora). Lá dentro, cortinas de laser piscando: encostar = alarme.
--   5. Alarme: chamado da PM; Lockdown s depois a porta de aço fecha a frente E a saída de emergência
--      tranca (trava magnética). Forçar a trava: ExitForceTime s segurando E (a PM é avisada).
--   6. Fuga: a bolsa pesa (anda mais devagar) e tem RASTREADOR: por TrackerTime s depois de sair da
--      loja a PM vê você piscando no mapa. Depois disso, venda as joias ao chefe da sua gangue
--      (receptador): ele não compra com rastreador ligado nem com polícia perto. Preso ou morto: perde.
GameConfig.Jewelry = {
	Name = "Opala Joias",
	Slogan = "ALTA JOALHERIA",
	MinPolice = 0, -- policiais online para poder assaltar (0 = dá para testar sozinho)
	Cooldown = 1500, -- a loja fica fechada 25 min depois de assaltada
	ReconTime = 240, -- segundos para achar os pontos do reconhecimento
	ReconValid = 1200, -- o reconhecimento vale 20 min para a gangue
	GasTime = 4, -- segurar E no duto
	FuseTime = 5, -- segurar E no quadro de energia
	GasDuration = 150, -- plano silencioso: os funcionários dormem 2,5 min; quando acordam, alarme
	Lockdown = 60, -- as grades e a trava da saída fecham 60 s depois do alarme
	GuardReact = 6, -- plano barulhento: segundos para render o segurança antes do botão de pânico
	AimTime = 1.5, -- segundos mirando num funcionário para ele se render
	PanicLockdown = 25, -- botão de pânico: a porta de aço fecha em 25 s
	PanicPoints = 15, -- pontos de procurado a mais pelo botão de pânico
	CardTime = 1.5, -- segurar E para pegar o cartão do gerente
	DoorForceTime = 8, -- arrombar a porta dos funcionários sem cartão
	OfficeTime = 5, -- procurar o código na gaveta do escritório
	VaultOpenTime = 5, -- digitar o código na porta do cofre
	VaultDrill = 40, -- furadeira no cofre (sem código): segundos até abrir
	HackTime = 90, -- terminal hackeado: câmeras e lasers desligados por 90 s
	ExitOverride = 40, -- terminal hackeado: a saída fica destravada 40 s depois do lockdown
	ExitForceTime = 12, -- forçar a trava magnética da saída de emergência
	TrackerTime = 150, -- rastreador da bolsa (depois de sair da loja)
	SellDistance = 12, -- perto do chefe para vender
	BagSlots = 8, -- espaço da bolsa (cada vitrine 1; colar 2; ouro 2; diamante 3)
	SlowPerSlot = 0.55, -- cada espaço ocupado tira isso da velocidade de andar
	-- medidor de alerta (plano silencioso): 100 = alarme
	Noise = { Glass = 7, Armored = 11, Miss = 12, HackFail = 25, CamPerSec = 1.2, ForcePerSec = 4, Decay = 0.5 },
	-- minigame: hits = acertos, zone = largura da faixa verde (0-1), speed = idas e voltas por segundo
	Minigame = {
		vitrine = { Hits = 2, Zone = 0.24, Speed = 0.9 },
		blindada = { Hits = 3, Zone = 0.16, Speed = 1.15 },
		-- Marco 10.27: Type escolhe o jogo (sem Type é a barra). setas: Hits fileiras de Len setas em Time s;
		-- memoria: Hits rodadas, começando em Len botões; fios: Hits fios entre Len, em Time s;
		-- segurar: Hits etapas de Time s com o ponteiro na faixa (Zone e Speed)
		gaveta = { Type = "segurar", Hits = 2, Zone = 0.18, Speed = 1.05, Drill = true }, -- Drill = parafusadeira na mão (Marco 10.21)
		colar = { Type = "setas", Hits = 2, Len = 5, Time = 5 },
		diamante = { Type = "fios", Hits = 3, Len = 6, Time = 9 },
		terminal = { Type = "setas", Hits = 3, Len = 5, Time = 6 },
		MaxMiss = 3, -- errou 3 vezes: trava e precisa começar de novo
		NoGunHits = 1, -- sem arma na mão: 1 acerto a mais nas vitrines
	},
	-- valor de cada peça (dinheiro limpo, pago pelo receptador): sorteado entre os dois números
	Loot = {
		aneis = { Name = "Anéis", Value = { 1750, 2750 } },
		relogios = { Name = "Relógios", Value = { 2250, 3500 } },
		colares = { Name = "Colares", Value = { 2750, 4250 } },
		blindada = { Name = "Peças raras", Value = { 4500, 6500 } },
		colar = { Name = "Colar Imperial", Value = { 9000, 12000 }, Slots = 2 },
		ouro = { Name = "Barras de ouro", Value = { 6500, 8500 }, Slots = 2 },
		diamante = { Name = "Diamante Estrela", Value = { 22500, 30000 }, Slots = 3 },
	},
	CasePoints = 4, -- pontos de procurado por peça (câmeras cortadas: metade)
	StartPoints = 20, -- pontos ao tocar o alarme (câmeras cortadas: metade)
	EscapePoliceRadius = 70, -- com policial mais perto que isso, o receptador não compra
	PoliceDoorTime = 0.6, -- Marco 10.15: policial abre as portas com o acesso da PM (não arromba)
	PoliceRecoverPay = 1500, -- policial que prende alguém com joias na bolsa ganha isso a mais
	Sounds = { Glass = 0, Alarm = 0, Gas = 0, Drill = 0 }, -- IDs de som (0 = sem som; o Luís escolhe)
	-- Marco 10.11: animação de pegar joias (feita pelo Luís: JewelGrab_R15 / JewelGrab_R6).
	-- Cole aqui o ID de cada uma depois de publicar no Roblox (aceita 123456 ou "rbxassetid://123456").
	-- 0 = sem ID: no Studio ela ainda toca se o KeyframeSequence estiver em ReplicatedStorage > Animacoes.
	-- SmashAt/GrabAt = segundos do golpe no vidro e da mão pegando (marcadores Smash e Grab1).
	GrabAnim = { R15 = 129971159003502, R6 = 116318792648019, Length = 3.5, SmashAt = 0.77, GrabAt = 1.73, Lock = true },
}

-- Marco 10.20: assalto ao BANCO CENTRAL (BankBuilder monta o prédio na Estrada do Vale; regras no
-- BankService; eventos em HeistEvents). Valores em dinheiro limpo pago pelo chefe da gangue
-- (receptador). Números PROVISÓRIOS: o Luís ajusta depois de testar.
GameConfig.Bank = {
	Name = "Banco Central LLC",
	Short = "Banco Central",
	Road = { T = 430, Side = 1 }, -- lote na Estrada do Vale: t = distância da saída da rodovia, lado +1 = sul
	LotW = 236, LotD = 250,
	MinCrew = 1, -- TESTE (Luís pediu 2026-11-04): 1 = dá para assaltar sozinho. Voltar para 2 depois. Jogadores da MESMA gangue perto do ponto de anúncio para começar (conferido no servidor)
	StartRadius = 45,
	MinPolice = 0, -- policiais online para poder assaltar (0 = dá para testar sem PM)
	Cooldown = 2700, -- o banco fica fechado 45 min depois do assalto
	-- preparação (F1, antes do anúncio; vale para a gangue toda)
	PrepValid = 900, -- cada preparação vale 15 min
	BadgeTime = 2.5, -- segurar E para "pegar emprestado" o crachá do funcionário que fuma no beco
	PowerTime = 6, -- segurar E no transformador do beco (câmeras e telefone mudos)
	PowerAlarmDelay = 45, -- com a energia cortada, o alarme só chega na PM 45 s depois do anúncio
	-- início (F2)
	GuardReact = 8, -- segundos para render o segurança antes do botão de pânico
	AimTime = 1.4, -- segundos mirando num NPC para ele se render
	-- Marco 10.25: rendido sem amarrar volta a reagir; reféns agitados; lasers do subsolo; túnel
	TieTime = 35, -- segundos até o segurança rendido reagir, se ninguém amarrar
	Tension = { Start = 20, Alone = 0.6, Watched = 0.25, Shout = 35, Shot = 12, ShoutCooldown = 5, Penalty = 25 },
	LaserPenalty = 20, -- encostar no laser: o cerco chega estes segundos mais cedo
	TunnelFuse = 6, -- segundos do C4 até abrir o túnel
	PanicSiege = 90, -- botão de pânico: o cerco chega 90 s mais cedo
	-- Marco 10.21: seguranças armados. O do salão saca a arma quando aperta o pânico; o vigilante da
	-- galeria começa a atirar GalleryDelay s depois do anúncio. Mirar neles (AimTime) rende os dois.
	Guards = { FireRate = 1.3, Range = 75, Hit = 0.5, Damage = 9, AimRange = 70, GalleryDelay = 8 },
	-- interno (F3)
	CardTime = 1.5,
	DoorForceTime = 12, -- arrombar a porta de segurança sem crachá
	DualWindow = 2.5, -- as 2 chaves do controle duplo precisam girar com até 2,5 s de diferença
	SoloDualWindow = 12, -- se só sobrou 1 da equipe (caiu, foi preso ou saiu): 12 s (trava temporária)
	KeyTime = 2, -- segurar cada chave
	DrillSetTime = 3, -- montar a furadeira térmica na porta do cofre
	DrillTime = 75, -- segundos furando (a obra e a tempestade abafam: mais rápido)
	WheelTime = 3, -- girar o volante para abrir a porta
	DoorOpenTime = 7, -- animação da porta abrindo (segundos)
	DoorAngle = 72.5, -- graus que a porta abre
	-- alarme e cerco (pressão sem depender de policial de verdade)
	SiegeTime = 480, -- 8 min depois do alarme o Batalhão de Choque cerca o banco: a porta da frente tranca
	SiegeFinal = 210, -- e 3,5 min depois disso a polícia toma o prédio (o assalto acaba)
	SiegePoints = 4, -- pontos de procurado a cada 10 s para quem está dentro durante o cerco
	ExitForceTime = 10, -- forçar a saída de serviço durante o cerco
	StartPoints = 25, -- pontos de procurado ao tocar o alarme
	LootPoints = 3, -- por item pego
	-- bolsa (malote)
	BagSlots = 14,
	SlowPerSlot = 0.4,
	TrackerTime = 150, -- dinheiro marcado (Cofre-Isca): rastreador depois de sair do banco
	EscapeRadius = 150, -- longe assim do banco = saiu (fase fuga)
	EscapePoliceRadius = 70, -- com policial mais perto que isso, o receptador não compra
	SellDistance = 12,
	PoliceRecoverPay = 2500, -- policial que prende alguém com malote do banco ganha isso a mais
	PoliceBagPay = 1200, -- policial que recolhe um malote largado no chão
	ReconnectGrace = 120, -- quem caiu do jogo volta para a equipe se entrar em até 2 min
	AbandonTime = 150, -- ninguém da equipe no banco por 2,5 min (antes de abrir o cofre) = fim
	DropLife = 120, -- malote largado no chão some depois de 2 min
	-- minigames (mesmo da joalheria): Hits = acertos, Zone = faixa verde, Speed = velocidade
	Minigame = {
		gaveta = { Type = "segurar", Hits = 2, Zone = 0.22, Speed = 1, Drill = true },
		terminal = { Type = "setas", Hits = 3, Len = 5, Time = 6 },
		laser = { Type = "fios", Hits = 3, Len = 5, Time = 10 }, -- Marco 10.27: quadro dos lasers
		cofrinho = { Type = "segurar", Hits = 2, Zone = 0.18, Speed = 1.1, Drill = true },
		retro = { Type = "memoria", Hits = 3, Len = 3, Speed = 1.1 },
		furadeira = { Type = "segurar", Hits = 3, Zone = 0.16, Speed = 1.2, Drill = true },
		sacola = { Hits = 4, Zone = 0.14, Speed = 1.25 },
		negociador = { Hits = 4, Zone = 0.15, Speed = 1.2 }, -- Marco 10.21: enrolar o negociador
	},
	-- valor de cada pegada (sorteado entre os dois números); Slots = espaço na bolsa
	Loot = {
		caixa = { Name = "Gaveta do caixa", Value = { 1500, 2500 }, Slots = 1 },
		dinheiro = { Name = "Maços de dinheiro", Value = { 5000, 6500 }, Slots = 1 },
		ouro = { Name = "Barras de ouro", Value = { 11000, 13000 }, Slots = 2 },
		cofrinho = { Name = "Cofrinho de aluguel", Value = { 1500, 6000 }, Slots = 1, Rare = { Chance = 0.12, Name = "Relíquia de família", Value = { 14000, 17000 } } },
		diretor = { Name = "Cofre do Diretor", Value = { 18000, 22000 }, Slots = 2 },
		maleta = { Name = "Maleta executiva", Value = { 12000, 16000 }, Slots = 2 },
		malote = { Name = "Malote", Value = { 1500, 3000 }, Slots = 1 },
	},
	MoneyGrabs = 3, -- cada pilha de dinheiro dá 3 pegadas (6 pilhas)
	GoldGrabs = 4, -- cada palete de ouro dá 4 pegadas (2 paletes)
	-- sons (0 = sem som; o Luís pode trocar)
	-- Marco 10.26: sons da Creator Store (troque os IDs quando quiser)
	Sounds = { Alarm = 4530741431, Drill = 9125450626, VaultDoor = 9117908810, Explosion = 138533090376585, Money = 9113726249, Thunder = 0, Helicopter = 0, Bell = 0 },
	-- Eventos (HeistEvents): Chance = sorteio quando a fase começa; Cooldown = segundos até poder
	-- acontecer de novo no servidor. Desligar um evento: Chance = 0.
	Events = {
		VIP = { Chance = 0.35, Cooldown = 1800 }, -- B01 Visita da Gerência Regional
		Corajoso = { Chance = 0.45, Cooldown = 900 }, -- B04 Cliente Corajoso
		Rompe = { Chance = 0.3, Cooldown = 900 }, -- B05 Malote se Rompe
		Reforma = { Chance = 0.4, Cooldown = 3600 }, -- B07 Reforma no Prédio (sorteado quando o banco abre)
		Retro = { Chance = 0.6, Cooldown = 600 }, -- Terminal Nostálgico
		Teimosa = { Chance = 0.4, Cooldown = 900 }, -- B09 Porta que Não Para de Fechar
		AoVivo = { Chance = 0.35, Cooldown = 1800 }, -- B14 Transmissão ao Vivo
		Tempestade = { Chance = 0.25, Cooldown = 3600 }, -- B17 Tempestade
		Isca = { Chance = 0.45, Cooldown = 900 }, -- B19 Cofre-Isca
		Rival = { Chance = 0.3, Cooldown = 1800 }, -- B20 Equipe Rival Oportunista
		Avalanche = { Chance = 0.4, Cooldown = 900 }, -- Avalanche de Malotes
		Furadeira = { Chance = 0.55, Cooldown = 300 }, -- furadeira superaquecida
		-- Marco 10.21
		Negociador = { Chance = 0.4, Cooldown = 900, Ring = 25, Bonus = 60, Penalty = 20, Ignore = 30 }, -- telefone do negociador da PM
		CarroForte = { Chance = 0.3, Cooldown = 1800, Stay = 90, Radio = 25, RadioPenalty = 30, Value = { 9000, 13000 }, Slots = 2 }, -- carro-forte na doca
		AlarmeSilencioso = { Chance = 0.35, Cooldown = 900, Time = 15, Penalty = 45 }, -- caixa com o pé no alarme silencioso
		Sprinkler = { Chance = 0.35, Cooldown = 900 }, -- sprinklers: furadeira na metade da velocidade
		Gas = { Chance = 0.5, Cooldown = 900, Duration = 70, Damage = 4 }, -- gás lacrimogêneo no cerco (máscaras no armário)
	},
	MaxEvents = 4, -- eventos ao mesmo tempo (a Reforma, sorteada na abertura, ocupa 1)
	TestAllEvents = false, -- TESTE: true = todo evento acontece sempre que puder (sem sorteio nem espera)
}

-- Marco 10.20: eventos da joalheria (mesmo motor: HeistEvents). Valem para 1 jogador ou para a gangue.
GameConfig.Jewelry.Events = {
	Apagao = { Chance = 0.25, Cooldown = 1200, Duration = 45 }, -- queda de energia: câmeras e lasers apagam
	Tiara = { Chance = 0.35, Cooldown = 1200, Value = { 14000, 18000 }, Slots = 2 }, -- lançamento da coleção (sensor de peso)
	Malote = { Chance = 0.3, Cooldown = 1200, Value = { 10000, 14000 }, Slots = 2, Stay = 40 }, -- entregador do carro-forte
	Corajoso = { Chance = 0.4, Cooldown = 900 }, -- cliente escondido no provador corre para chamar a PM
	-- Marco 10.21
	Leilao = { Chance = 0.35, Cooldown = 1200, Colar = { 16000, 22000 }, Guest = { 2500, 4000 }, Lances = { 6000, 9000 }, BreakNoise = 45 }, -- leilão VIP: redoma, convidados, caixa dos lances
	JoiaFalsa = { Chance = 0.3, Cooldown = 900, Duration = 150, Factor = 0.08 }, -- uma vitrine só tem réplicas (lupa)
	Pedido = { Chance = 0.3, Cooldown = 1200, Duration = 50, Value = { 7000, 10000 }, Bonus = 20 }, -- pedido de casamento no meio do assalto
	Live = { Chance = 0.3, Cooldown = 900, Duration = 40, Range = 24, Phone = { 1500, 2500 } }, -- influencer fazendo live
}
GameConfig.Jewelry.EventMinigame = { sacola = { Hits = 4, Zone = 0.14, Speed = 1.25 } }
GameConfig.Jewelry.MaxEvents = 3 -- eventos ao mesmo tempo na joalheria
GameConfig.Jewelry.TestAllEvents = false -- TESTE: true = todo evento acontece sempre que puder

-- Marco 10.5: armas (modelos do Luís em ServerStorage > WeaponModels, nomes = Model).
-- Tiro acerta qualquer jogador, MENOS em zona segura (praça, dentro das casas e dos locais de
-- trabalho): quem está numa zona segura não leva nem dá tiro. Punição para quem atira à toa: depois.
-- Dano, cadência, pente e preços PROVISÓRIOS.
GameConfig.Weapons = {
	SafePlazaRadius = 74, -- praça central (a rotatória inteira) é zona segura
	SafePlazaCenter = Vector3.new(0, 0, 0),
	Length = { pistola = 1.4, fuzil = 3.2 }, -- tamanho da arma na mão (studs)
	CarArmor = 0.5, -- quem está dentro de um carro leva só metade do dano (pedido do Luís)
	CarHitRadius = 7, -- a bala que entra no carro pega quem está a até essa distância da linha do tiro
	PoliceArmor = 0.75, -- colete: policial leva 75% do dano de tiro de outros jogadores
	KillMemory = 10, -- segundos: quem acertou por último leva a culpa da morte
	Range = 300,
	ReloadTime = 1.8,
	-- Kind: "pistola" segura com uma mão, "fuzil" com as duas. Auto = segura o botão para atirar.
	List = {
		Pistola9mm = { Name = "Pistola 9mm", Model = "Pistola9mm", Kind = "pistola", Damage = 18, Rate = 0.28, Mag = 15, Icon = "🔫" },
		Colt1911 = { Name = "Colt 1911", Model = "Colt1911", Kind = "pistola", Damage = 24, Rate = 0.4, Mag = 8, Price = 25000, Icon = "🔫" },
		Vityaz = { Name = "Vityaz", Model = "Vityaz", Kind = "fuzil", Damage = 12, Rate = 0.09, Mag = 30, Auto = true, Price = 90000, Icon = "🔫" },
		ColtM5 = { Name = "Colt M5", Model = "ColtM5", Kind = "fuzil", Damage = 20, Rate = 0.13, Mag = 30, Auto = true, Icon = "🔫" },
		AK47 = { Name = "AK-47", Model = "AK47", Kind = "fuzil", Damage = 24, Rate = 0.12, Mag = 30, Auto = true, Price = 180000, Icon = "🔫" },
		ScarH = { Name = "SCAR-H", Model = "ScarH", Kind = "fuzil", Damage = 30, Rate = 0.16, Mag = 20, Auto = true, Price = 250000, Icon = "🔫" },
	},
	-- Marco 10.6: munição comprada (pedido do Luís): pistola por kit de 12 balas, fuzil e
	-- submetralhadora por pente de 30. Fica guardada (reserva) e o R recarrega tirando dela.
	-- As armas do emprego (Policial) têm munição à vontade. Preço na escala de hoje: com a
	-- Revisão 2 da economia (tudo x10) vira $300 e $1.200.
	Ammo = {
		pistola = { Name = "Kit de balas (pistola)", Short = "Kit pistola", Per = 12, Price = 300, Icon = "🟨" },
		fuzil = { Name = "Pente de 30 (fuzil)", Short = "Pente fuzil", Per = 30, Price = 1200, Icon = "🟧" },
	},
	MaxAmmo = 240, -- reserva máxima de cada tipo
	PoliceKit = { "Pistola9mm" }, -- o Policial ganha ao pegar o emprego (some ao sair)
	PoliceRifle = "ColtM5", -- no armário da PM ("Pegar fuzil")
	GangShop = { "Colt1911", "Vityaz", "AK47", "ScarH" }, -- o chefe da gangue vende (fica salvo na mochila)
	ShotSoundId = 0, -- som do tiro (0 = sem som até escolher um ID; volume baixo)
}

-- Marco 10.5: mochila (inventário). 2 atalhos no HUD + 12 espaços na mochila (pedido do Luís:
-- uns 10 a 15). Baú: ver Chests abaixo.
GameConfig.Inventory = {
	Hotbar = 2,
	Backpack = 12,
	Chest = 70, -- o maior baú (a tela do baú é montada com esse tanto de espaços). Marco 10.17: 70
	-- Marco 10.7 (pedido do Luís): nas casas padrão o baú é o baú medieval (20 espaços, já vem na
	-- casa); da casa moderna para cima é o guarda-roupa (50). O que fica guardado é um só
	-- (data.chest): o baú pequeno só usa os 20 primeiros espaços.
	Chests = {
		-- Marco 10.17 (pedido do Luís): o guarda-roupa/armário já vem em todas as casas grandes (Give).
		-- Cobertura e mansão: "Armário" de 70 (o modelo 3D do Luís vem depois; até lá usa o desenho
		-- do guarda-roupa). Quem já tinha guarda-roupa nessas duas, ele vira o Armário de 70.
		Armario = { Size = 50, Label = "Guarda-roupa", Give = true, Tiers = { casamoderna = true } },
		Closet = { Size = 70, Label = "Armário", Give = true, Tiers = { cobertura = true, mansao = true } },
		Bau = { Size = 20, Label = "Baú", Give = true, Tiers = { barraco = true, basica = true, media = true, sobrado = true, apartamento = true } },
	},
}

GameConfig.PaintShop = {
	Name = "Pintura Arco-Íris",
	Dir = 8, -- rua (diagonal) de onde sai a estradinha
	RoadLength = 80,
	Price = 0,
	UseDistance = 14, -- o carro precisa estar a menos disso do centro da cabine
	Cooldown = 1.5,
	-- Cores prontas da paleta (o jogador também pode escolher qualquer cor no seletor)
	Palette = {
		{ 14, 14, 16 }, { 245, 245, 245 }, { 150, 155, 160 }, { 70, 72, 78 },
		{ 200, 20, 22 }, { 120, 10, 20 }, { 240, 110, 20 }, { 250, 200, 30 },
		{ 30, 150, 60 }, { 20, 80, 45 }, { 120, 200, 40 }, { 30, 170, 170 },
		{ 30, 90, 200 }, { 15, 30, 90 }, { 90, 180, 240 }, { 120, 50, 180 },
		{ 230, 80, 160 }, { 255, 160, 190 }, { 120, 80, 50 }, { 210, 190, 150 },
	},
}

-- Pets (Marco 7). Primeiro pet: cachorro, em 3 cores. Adoção no Duto Pet Shop.
-- PROVISÓRIO: adoção de graça; nome, cores e tamanho escolhidos pelo Claude.
GameConfig.Pets = {
	Dog = {
		Name = "Cachorro",
		Model = "Dog", -- modelo 3D em ServerStorage > PetModels (sem ele: cachorro de peças)
		Price = 0,
		Length = 3.2, -- do focinho ao rabo, em studs
		Colors = {
			{ Name = "Caramelo", Color = Color3.fromRGB(200, 140, 70) },
			{ Name = "Preto", Color = Color3.fromRGB(35, 33, 33) },
			{ Name = "Branco", Color = Color3.fromRGB(240, 236, 228) },
		},
	},
	-- Marco 9.9: cachorros 3D do Luís (tools/dogprep.py). A cor escolhida pinta a pelagem principal
	-- (o branco do husky, as pintas do dálmata e a sela do pastor ficam fixos). Preços PROVISÓRIOS.
	Husky = {
		Name = "Husky",
		Model = "DogHusky",
		Price = 0,
		Length = 3.0,
		Colors = {
			{ Name = "Cinza", Color = Color3.fromRGB(110, 112, 120) },
			{ Name = "Preto", Color = Color3.fromRGB(42, 42, 46) },
			{ Name = "Ruivo", Color = Color3.fromRGB(150, 88, 52) },
			{ Name = "Areia", Color = Color3.fromRGB(196, 168, 128) },
		},
	},
	Dalmata = {
		Name = "Dálmata",
		Model = "DogDalmata",
		Price = 0,
		Length = 3.6,
		Colors = {
			{ Name = "Branco", Color = Color3.fromRGB(242, 240, 235) },
			{ Name = "Creme", Color = Color3.fromRGB(238, 226, 205) },
		},
	},
	Pastor = {
		Name = "Pastor alemão",
		Model = "DogPastor",
		Price = 0,
		Length = 3.6,
		Colors = {
			{ Name = "Caramelo", Color = Color3.fromRGB(176, 122, 62) },
			{ Name = "Avermelhado", Color = Color3.fromRGB(160, 88, 45) },
			{ Name = "Dourado", Color = Color3.fromRGB(200, 150, 80) },
		},
	},
	-- Marco 10.7: o dragão virou o Dragão de Cristal do Luís (tools/cristalprep.py). A cor vem da
	-- textura do modelo (verde com cristais azuis), então é uma cor só. Preço PROVISÓRIO.
	Dragao = {
		Name = "Dragão de Cristal",
		Model = "PetDragao",
		-- Marco 10.7: modelo com esqueleto (CrystalDragon.fbx importado com esse nome em PetModels) e as
		-- animações dele publicadas pelo Luís. Enquanto Walk = 0, usa o PetDragao que mexe por script.
		Rig = "PetDragaoRig",
		ScriptAnims = "DragaoAnims", -- animações do .fbx (Shared/DragaoAnims, feito por tools/dragaoanims.py)
		Price = 250000,
		Length = 6, -- da cabeça à ponta do rabo
		FollowBack = 5, -- é grande: anda mais longe do dono
		FollowSide = 3,
		Aura = { Color3.fromRGB(90, 170, 255), Color3.fromRGB(150, 220, 255), Color3.fromRGB(110, 200, 120) },
		Colors = {
			{ Name = "Verde e azul", Color = Color3.fromRGB(70, 110, 60) },
		},
	},
}
-- Parque de diversões MigueLândia (Marco 7.2): no fim de uma avenida que sai da rua 2 (diagonal)
-- depois do anel externo. Roda gigante e carrossel dá para andar (sentar com E); os outros
-- brinquedos se mexem só de enfeite (cada jogador vê a animação no próprio aparelho).
GameConfig.Park = {
	Name = "MigueLândia",
	Dir = 2, -- rua (diagonal) de onde sai a avenida do parque
	RoadLength = 120, -- avenida do anel externo até o estacionamento
	RoadName = "Avenida da Alegria", -- PROVISÓRIO
	Size = 440, -- o parque é um quadrado de 440 x 440 studs (estacionamento incluído)
	WheelSpeed = 0.12, -- roda gigante (radianos por segundo)
	CarouselSpeed = 0.5, -- carrossel (radianos por segundo)
}

-- Penitenciária (Marco 8): no fim de uma estrada que sai da rua 4 (diagonal) depois do anel externo.
-- Por enquanto é só o lugar (tudo aberto para visitar); regras de prisão ainda vamos decidir.
GameConfig.Prison = {
	Name = "Penitenciária de Little Little Kinder", -- PROVISÓRIO
	Dir = 4, -- rua (diagonal) de onde sai a estrada
	RoadLength = 100, -- estrada do anel externo até o portão
	RoadName = "Estrada da Penitenciária", -- PROVISÓRIO
	Width = 520, -- largura (studs)
	Depth = 560, -- profundidade, da entrada até o fundo (studs)
	-- Marco 8.1: presidiário. Tudo PROVISÓRIO até decidirmos as regras juntos.
	Sentence = 300, -- pena padrão em segundos (5 min). Só conta enquanto a pessoa está no jogo.
	TasksMin = 2, -- a cada N tarefas (sorteado entre TasksMin e TasksMax)...
	TasksMax = 4,
	TaskReduction = 60, -- ...a pena diminui esses segundos
	TestInStudio = true, -- placa "Testar prisão" na recepção, só no Studio
	PoliceDoorOpenTime = 5, -- segundos que uma porta com cartão fica aberta
	DoorOpenTime = 1.6, -- segundos para uma porta girar (abrir ou fechar)
	-- altura das cercas (studs). Mais altas que o pulo; a rota de fuga vem depois.
	OuterFence = 22,
	SecureFence = 24,
	YardFence = 16,
}

-- Marco 8.4: farda da PM (camisa com colete e calça), vestida no armário do arsenal da Base da PM.
-- Cole aqui o número (ID) das imagens que você importou no Studio (Janela > Gerenciador de ativos > Imagens >
-- clique com o botão direito > Copiar ID do ativo). 0 = ainda não configurada.
GameConfig.PoliceUniform = {
	Job = "Policial",
	Shirt = 111238928778312, -- camisa_pm_colete.png (ID do Luís)
	Pants = 73575715494010, -- calca_pm.png (ID do Luís)
	Locker = "Armário da PM",
	Wear = "Você vestiu a farda da PM!",
	UseDistance = 10,
}

-- Marco 9.11: farda do bombeiro (feita no Claude Design). Camisa e calça clássicas
-- (modelos/farda_bombeiro/*.png: o Luís sobe no Roblox e cola os IDs aqui; com 0 fica a roupa
-- normal) + o equipamento 3D (capacete, balaclava, mochila, cinto, luvas e botas) do modelo
-- ServerStorage > UniformModels > FardaBombeiro (tools/fardaprep.py). Armários no vestiário do quartel.
GameConfig.FireUniform = {
	Job = "Bombeiro",
	Shirt = 126801700478251, -- FardaBombeiro_camisa.png (ID do Luís)
	Pants = 139528188668513, -- FardaBombeiro_calca.png (ID do Luís)
	Model = "FardaBombeiro",
	HideHair = true, -- o capacete e a balaclava cobrem o cabelo
	GearFlip = true, -- Marco 9.14: desvira o equipamento 3D (saía de costas). Se ficar de costas de novo, ponha false
	Locker = "Armário dos Bombeiros",
	Wear = "Você vestiu a farda de bombeiro!",
	UseDistance = 10,
}

-- Marco 10.8: macacão laranja do preso (pedido do Luís, referência com "D.O.C" nas costas).
-- Veste sozinho quando a pessoa é presa e sai quando ela é solta.
-- Sem os IDs (0): o corpo fica laranja (a roupa do jogador sai) + "L.L.K" e o número nas costas.
-- Com os IDs: modelos/farda_presidiario/Presidiario_camisa.png e _calca.png (o Luís sobe no Roblox
-- como imagem e cola os IDs aqui), que já têm os bolsos, as costuras e o "L.L.K" desenhados.
GameConfig.PrisonUniform = {
	Job = "Presidiario",
	Prison = true,
	Shirt = 0, -- Presidiario_camisa.png
	Pants = 0, -- Presidiario_calca.png
	BodyColor = Color3.fromRGB(240, 110, 25), -- laranja do macacão (usado quando falta o ID)
	BackText = "L.L.K",
	Wear = "Você vestiu o macacão laranja da Penitenciária.",
}

GameConfig.PetShop = {
	UseDistance = 12, -- distância máxima da placa de adoção
}

-- Marco 9: bichinhos dos clientes do Cuidador de animais (feitos de peças; Marco 9.9: model = modelo
-- 3D em ServerStorage > PetModels, se estiver lá). Raças e nomes escolhidos pelo Claude (PROVISÓRIO).
GameConfig.PetCare = {
	Breeds = {
		{ name = "Vira-lata caramelo", kind = "Dog", color = Color3.fromRGB(200, 140, 70) },
		{ name = "Dálmata", kind = "Dog", model = "DogDalmata", length = 3.6, color = Color3.fromRGB(242, 240, 235), light = Color3.fromRGB(250, 250, 248), dark = Color3.fromRGB(30, 30, 32), spots = Color3.fromRGB(25, 25, 28), collar = Color3.fromRGB(40, 110, 220) },
		{ name = "Salsicha", kind = "Dog", color = Color3.fromRGB(125, 65, 30), body = 2.9, legs = 0.5, longEars = true },
		{ name = "Pastor alemão", kind = "Dog", model = "DogPastor", length = 3.6, color = Color3.fromRGB(176, 122, 62), ears = "pointy" },
		-- Marco 9.9: o husky de cliente sai com uma pelagem sorteada (coats)
		{ name = "Husky", kind = "Dog", model = "DogHusky", length = 3.0, coats = { Color3.fromRGB(110, 112, 120), Color3.fromRGB(42, 42, 46), Color3.fromRGB(150, 88, 52), Color3.fromRGB(196, 168, 128) }, color = Color3.fromRGB(120, 125, 135), light = Color3.fromRGB(245, 245, 245), ears = "pointy", collar = Color3.fromRGB(240, 170, 30) },
		{ name = "Poodle", kind = "Dog", color = Color3.fromRGB(245, 235, 225), light = Color3.fromRGB(250, 245, 240), fluffy = true, legs = 1.1, size = 0.9, collar = Color3.fromRGB(230, 90, 160) },
		{ name = "Gato laranja", kind = "Cat", color = Color3.fromRGB(235, 140, 50), size = 0.85 },
		{ name = "Gato preto", kind = "Cat", color = Color3.fromRGB(32, 32, 36), light = Color3.fromRGB(60, 60, 66), dark = Color3.fromRGB(20, 20, 22), size = 0.85 },
		{ name = "Gato cinza", kind = "Cat", color = Color3.fromRGB(150, 152, 160), size = 0.85 },
		{ name = "Siamês", kind = "Cat", color = Color3.fromRGB(235, 222, 200), dark = Color3.fromRGB(70, 50, 40), face = Color3.fromRGB(150, 110, 85), tail = Color3.fromRGB(80, 60, 45), size = 0.85 },
	},
	Names = { "Thor", "Mel", "Bob", "Luna", "Pipoca", "Nina", "Max", "Bolinha", "Amora", "Fred", "Mia", "Toddy", "Paçoca", "Lili", "Rex", "Frida" },
}

GameConfig.CarCooldown = 2 -- segundos entre pedidos de chamar/sair do carro

-- Mapa do bairro inicial (medidas em studs; 1 stud ≈ 28 cm)
GameConfig.Map = {
	GroundSize = 12000, -- Marco 10: chão do tamanho do Rodoanel (era 3600) para a cidade crescer
	TreeArea = 3600, -- árvores soltas só em volta da cidade antiga
	MapView = 2600, -- quantos studs o mapa (tecla M) mostra de lado a lado sem zoom
	RoundaboutOuterRadius = 74, -- borda externa do asfalto da rotatória
	RoundaboutIslandRadius = 50, -- praça no meio (primeiro lugar que o jogador vê)
	RoadWidth = 24,
	RoadLength = 560, -- comprimento de cada rua que sai da rotatória (até o anel externo)
	InnerRingRadius = 330, -- anel de rua do meio (forma os quarteirões)
	SidewalkWidth = 6,
	-- Vila Esperança (Marco 6.1): bairro humilde onde todo jogador começa com uma casinha grátis.
	-- Fica no fim da rua 6 (diagonal), depois do anel externo.
	Vila = { Name = "Vila Esperança", StreetName = "Rua da Esperança", Dir = 6, Length = 300 },
	NobreRadius = 250, -- casas mais perto da praça que isso valem como "Sobrado" (mais caras)
	TreeSeed = 2026, -- muda a posição das árvores aleatórias
	RandomTrees = 320,
	-- Nomes das ruas (1 a 8 = ruas que saem da praça; ímpares comerciais, pares residenciais)
	StreetNames = {
		"Avenida das Palmeiras", "Rua das Flores", "Avenida do Comércio", "Rua dos Ipês",
		"Avenida Central", "Rua das Acácias", "Avenida da Paz", "Rua do Sol",
	},
	InnerRingName = "Avenida Circular",
	OuterRingName = "Rua do Contorno",
}

-- Paleta (documento mestre, seção 3)
GameConfig.Colors = {
	Grass = Color3.fromRGB(106, 170, 74),
	GrassDark = Color3.fromRGB(84, 145, 60),
	Asphalt = Color3.fromRGB(70, 72, 78),
	Sidewalk = Color3.fromRGB(200, 196, 186),
	RoadLine = Color3.fromRGB(245, 245, 240),
	Trunk = Color3.fromRGB(110, 78, 50),
	Leaves = { Color3.fromRGB(70, 150, 60), Color3.fromRGB(90, 170, 70), Color3.fromRGB(60, 130, 55) },
	Walls = {
		Color3.fromRGB(245, 235, 215),
		Color3.fromRGB(240, 220, 190),
		Color3.fromRGB(215, 230, 240),
		Color3.fromRGB(240, 210, 200),
		Color3.fromRGB(225, 235, 210),
	},
	Roofs = {
		Color3.fromRGB(180, 70, 55),
		Color3.fromRGB(150, 90, 60),
		Color3.fromRGB(80, 90, 110),
		Color3.fromRGB(170, 110, 70),
	},
	Door = Color3.fromRGB(120, 80, 50),
	Window = Color3.fromRGB(160, 210, 240),
	Water = Color3.fromRGB(90, 170, 230),
	Flowers = { Color3.fromRGB(240, 90, 110), Color3.fromRGB(250, 210, 70), Color3.fromRGB(180, 110, 220) },
}

-- Marco 10.31: Costa do Sol, o litoral no fim da Estrada Sul (LitoralBuilder + LitoralService).
-- Inspirado nas orlas da Califórnia (calçadão, palmeiras altas, píer com parque, academia na areia)
-- com um toque brasileiro (calçadão de ondas, água de coco, açaí). Mar ao sul (+Z) até a borda do
-- mapa. Nomes e preços PROVISÓRIOS (decidir com o Luís).
GameConfig.Litoral = {
	Name = "Costa do Sol",
	Seed = 31031, -- sorteio próprio (não mexe no resto da cidade)
	EntryZ = 2840, -- fim da Estrada Sul: Rotatória da Costa
	RoundaboutName = "Rotatória da Costa",
	RoundaboutRadius = 40,
	AvenueName = "Avenida Costa do Sol", -- boulevard da rotatória até a orla (x = 0)
	BeiraMarName = "Avenida Beira-Mar",
	BeiraMarZ = 3400,
	BeiraMarHalf = 1800, -- x de -1800 a 1800
	TownZ = 3080, -- rua de trás do bairro
	TownName = "Rua das Gaivotas",
	TownHalf = 1200,
	CrossStreets = {
		{ Name = "Rua da Enseada", X = -1200 },
		{ Name = "Rua dos Surfistas", X = -600 },
		{ Name = "Rua das Conchas", X = 600 },
		{ Name = "Rua do Farol", X = 1200 },
	},
	-- faixas da orla (z, de norte para sul)
	FrontZ0 = 3440, -- casinhas coloridas viradas para o calçadão
	WalkZ0 = 3500, -- calçadão (ondas)
	WalkZ1 = 3540,
	GreenZ1 = 3560, -- gramado com palmeiras
	BikeZ1 = 3572, -- ciclovia
	SandFlatZ = 3770, -- areia plana até aqui, depois desce até o mar
	SeaZ = 3860, -- daqui para o sul é mar (água de Terrain)
	SandStartZ = 3446, -- Marco 10.32: o chão de grama termina aqui; daqui para o sul é areia (Terrain)
	BeachHalf = 2600, -- largura da areia (x); depois é costão de pedra
	SeaLevel = -6, -- superfície da água
	SeaBottom = -18,
	Pier = { Name = "Píer Costa do Sol", Width = 44, Z0 = 3540, Z1 = 4022 },
	-- MigueLândia em cima do píer (centro da plataforma; frente virada para a praia)
	ParkCenter = Vector3.new(0, 0, 4250),
	-- lanches da orla (E na barraca). Preço em dinheiro limpo. Mão: mesmo lanche da MigueLândia.
	Snacks = {
		Coco = { Name = "Água de coco", Price = 8, Heal = 8 },
		Acai = { Name = "Açaí", Price = 15, Heal = 15 },
		Picole = { Name = "Picolé", Price = 6, Heal = 6 },
		Milho = { Name = "Milho verde", Price = 7, Heal = 8 },
		Churros = { Name = "Churros", Price = 9, Heal = 8 },
		-- Marco 10.32: lanchonetes da orla (dá para entrar e comprar no balcão)
		Sorvete = { Name = "Sorvete", Price = 7, Heal = 7 },
		CachorroQuente = { Name = "Cachorro-quente", Price = 10, Heal = 12 },
		Refri = { Name = "Refrigerante", Price = 5, Heal = 4 },
	},
	GymCooldown = 0.6,
	WavesSoundId = 0, -- som do mar (cole um ID da Creator Store; 0 = sem som)
	WavesVolume = 0.35,
	Tourists = 14, -- NPCs passeando no calçadão
	Beachgoers = 12, -- Marco 10.32: banhistas andando na areia (homens e mulheres, com conversa)
}

-- Marco 10.32: surfe na Costa do Sol. Área marcada por boias a leste do píer. As ondas são as
-- mesmas para todo mundo (contadas pelo relógio do servidor) e cada aparelho desenha as suas.
GameConfig.Surf = {
	X0 = 520, X1 = 1500, -- boias dos lados
	ZShore = 3880, -- daqui para a areia não dá mais para remar (fica raso)
	ZOut = 4170, -- boias do fundo: as ondas nascem aqui
	ZPeak = 3990, -- onde a onda fica mais alta
	ZBreak = 3905, -- onde ela quebra e acaba
	WaveSpeed = 13, -- studs por segundo, em direção à areia
	WavePeriod = 10, -- uma onda nova a cada 10 s
	WaveHeight = 3.4, -- altura máxima (studs acima do mar)
	PaddleSpeed = 11,
	RideSpeed = 26, -- velocidade de lado na onda (carvando)
	RentPrice = 10, -- aluguel da prancha (dinheiro limpo)
	MoneyPerPoints = 25, -- $1 a cada 25 pontos
	MaxMoneyPerWave = 80,
	ShopX = 960, ShopZ = 3712, -- escolinha de surfe (na areia, de frente para a área)
	-- modelo 3D opcional: ServerStorage > SurfModels > Prancha (MeshPart; o jogo pinta as cores)
}

-- Marco 10.31: concessionária (modelo achado pelo Romin, ServerStorage > DealershipTemplate),
-- no lugar antigo da MigueLândia, no fim da Avenida da Alegria (perto da cidade).
GameConfig.Dealership = {
	Name = "Prestige Motors", -- PROVISÓRIO
	RoadName = "Avenida dos Motores", -- era "Avenida da Alegria" (o parque foi para o píer)
	Display = { "Furia", "ShinobiH2", "L5", "RaioRR", "R18", "Coro" }, -- carros girando na frente
	TurntableSpeed = 0.25, -- radianos por segundo
}

return GameConfig
